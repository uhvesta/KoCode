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
        let output = try await run(["git", "-C", repoPath.path, "diff", "--find-renames", spec], cwd: nil)
        return try GitDiffParser().parse(output)
    }

    public func branches(repoPath: URL) async throws -> [String] {
        let output = try await run(["git", "-C", repoPath.path, "branch", "--format=%(refname:short)"], cwd: nil)
        return output.split(separator: "\n").map(String.init)
    }

    public func currentBranch(repoPath: URL) async throws -> String {
        try await run(["git", "-C", repoPath.path, "branch", "--show-current"], cwd: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ args: [String], cwd: URL?) async throws -> String {
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
