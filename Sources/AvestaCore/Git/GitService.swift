import Foundation

public actor GitService {
    private let cacheRoot: URL
    private let fileManager: FileManager

    public init(cacheRoot: URL = AppConfig.default.cacheRoot, fileManager: FileManager = .default) {
        self.cacheRoot = cacheRoot
        self.fileManager = fileManager
    }

    public func ensureBareClone(remoteURL: String, name: String) async throws -> URL {
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let bareRepo = cacheRoot.appending(path: "\(name).git", directoryHint: .isDirectory)

        if fileManager.fileExists(atPath: bareRepo.path) {
            _ = try await run(["git", "-C", bareRepo.path, "fetch", "--all", "--prune"], cwd: nil)
        } else {
            _ = try await run(["git", "clone", "--bare", remoteURL, bareRepo.path], cwd: nil)
        }

        return bareRepo
    }

    public func createWorktree(bareRepo: URL, branch: String, destination: URL) async throws {
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try await run(["git", "-C", bareRepo.path, "worktree", "add", destination.path, branch], cwd: nil)
    }

    public func removeWorktree(bareRepo: URL, worktreePath: URL) async throws {
        _ = try await run(["git", "-C", bareRepo.path, "worktree", "remove", worktreePath.path], cwd: nil)
    }

    public func listWorktrees(bareRepo: URL) async throws -> [String] {
        let output = try await run(["git", "-C", bareRepo.path, "worktree", "list", "--porcelain"], cwd: nil)
        return output
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("worktree ") else { return nil }
                return String(line.dropFirst("worktree ".count))
            }
    }

    public func diff(repoPath: URL, spec: String) async throws -> [FileDiff] {
        let output = try await run(["git", "-C", repoPath.path, "diff", "--no-ext-diff", "--find-renames", spec], cwd: nil)
        return try GitDiffParser().parse(output)
    }

    public func workingTreeDiff(repoPath: URL) async throws -> [FileDiff] {
        let baseFiles = try await headSnapshot(repoPath: repoPath)
        let currentFiles = try workingTreeSnapshot(repoPath: repoPath)
        return try await diffSnapshots(old: baseFiles, new: currentFiles)
    }

    public func reviewCheckpoint(repoPath: URL, createdAt: Date) async throws -> ReviewCheckpoint {
        ReviewCheckpoint(createdAt: createdAt, files: try workingTreeSnapshot(repoPath: repoPath))
    }

    public func diff(repoPath: URL, since checkpoint: ReviewCheckpoint) async throws -> [FileDiff] {
        try await diffSnapshots(old: checkpoint.files, new: workingTreeSnapshot(repoPath: repoPath))
    }

    public func branches(repoPath: URL) async throws -> [String] {
        let output = try await run(["git", "-C", repoPath.path, "branch", "--format=%(refname:short)"], cwd: nil)
        return output.split(separator: "\n").map(String.init)
    }

    public func currentBranch(repoPath: URL) async throws -> String {
        try await run(["git", "-C", repoPath.path, "branch", "--show-current"], cwd: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func workingTreeSnapshot(repoPath: URL) throws -> [ReviewCheckpointFile] {
        let output = try runSync(["git", "-C", repoPath.path, "ls-files", "-co", "--exclude-standard", "-z"], cwd: nil)
        let paths = output
            .split(separator: "\0")
            .map(String.init)
            .filter { !$0.isEmpty }
            .sorted()

        return try paths.compactMap { path in
            let url = safeFileURL(for: path, under: repoPath)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else { return nil }

            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) else { return nil }
            return ReviewCheckpointFile(path: path, content: content)
        }
    }

    private func headSnapshot(repoPath: URL) async throws -> [ReviewCheckpointFile] {
        do {
            _ = try await run(["git", "-C", repoPath.path, "rev-parse", "--verify", "HEAD"], cwd: nil)
        } catch {
            return []
        }

        let output = try await run(["git", "-C", repoPath.path, "ls-tree", "-r", "-z", "--name-only", "HEAD"], cwd: nil)
        let paths = output
            .split(separator: "\0")
            .map(String.init)
            .filter { !$0.isEmpty }
            .sorted()

        var files: [ReviewCheckpointFile] = []
        for path in paths {
            let content = try await run(["git", "-C", repoPath.path, "show", "HEAD:\(path)"], cwd: nil)
            files.append(ReviewCheckpointFile(path: path, content: content))
        }
        return files
    }

    private func diffSnapshots(
        old oldFiles: [ReviewCheckpointFile],
        new newFiles: [ReviewCheckpointFile]
    ) async throws -> [FileDiff] {
        let root = fileManager.temporaryDirectory
            .appending(path: "AvestaCodeReview-\(UUID().uuidString)", directoryHint: .isDirectory)
        let oldRoot = root.appending(path: "base", directoryHint: .isDirectory)
        let newRoot = root.appending(path: "current", directoryHint: .isDirectory)

        try fileManager.createDirectory(at: oldRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: newRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try writeSnapshot(oldFiles, to: oldRoot)
        try writeSnapshot(newFiles, to: newRoot)

        let output = try await run(
            ["git", "diff", "--no-index", "--no-ext-diff", "--find-renames", "base", "current"],
            cwd: root,
            allowedStatuses: [0, 1]
        )
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try GitDiffParser().parse(output)
            .map { $0.normalized(oldRoot: "base", newRoot: "current") }
    }

    private func writeSnapshot(_ files: [ReviewCheckpointFile], to root: URL) throws {
        for file in files {
            let url = safeFileURL(for: file.path, under: root)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func safeFileURL(for path: String, under root: URL) -> URL {
        path
            .split(separator: "/")
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .reduce(root) { partial, component in
                partial.appending(path: String(component), directoryHint: .notDirectory)
            }
    }

    private func run(_ args: [String], cwd: URL?, allowedStatuses: Set<Int32> = [0]) async throws -> String {
        guard let executable = args.first else { return "" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = cwd

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard allowedStatuses.contains(process.terminationStatus) else {
            throw GitServiceError.commandFailed(
                executable: executable,
                arguments: Array(args.dropFirst()),
                status: process.terminationStatus,
                stderr: error
            )
        }

        return output
    }

    private func runSync(_ args: [String], cwd: URL?) throws -> String {
        guard let executable = args.first else { return "" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = cwd

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw GitServiceError.commandFailed(
                executable: executable,
                arguments: Array(args.dropFirst()),
                status: process.terminationStatus,
                stderr: error
            )
        }

        return output
    }
}

public enum GitServiceError: Error, Equatable, LocalizedError {
    case commandFailed(executable: String, arguments: [String], status: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let executable, let arguments, let status, let stderr):
            return "Command failed (\(status)): \(([executable] + arguments).joined(separator: " "))\n\(stderr)"
        }
    }
}
