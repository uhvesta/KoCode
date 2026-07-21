import CryptoKit
import Foundation

public actor GitService {
    private let cacheRoot: URL
    private let fileManager: FileManager

    public init(cacheRoot: URL = AppConfig.default.cacheRoot, fileManager: FileManager = .default) {
        self.cacheRoot = cacheRoot
        self.fileManager = fileManager
    }

    public func sharedClonePath(remoteURL: String) -> URL {
        let canonical = SQLiteStateRepository.canonicalRemoteURL(remoteURL)
        let hash = SHA256.hash(data: Data(canonical.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let name = Self.repositoryName(remoteURL)
        return cacheRoot.appending(path: "\(name)-\(hash).git", directoryHint: .isDirectory)
    }

    public func ensureSharedClone(remoteURL: String, at path: URL) async throws {
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: path.path) {
            try ensureOriginFetchRefspec(sharedClone: path)
            _ = try run(["git", "-C", path.path, "fetch", "--all", "--prune"])
        } else {
            _ = try run(["git", "clone", "--bare", remoteURL, path.path])
            try ensureOriginFetchRefspec(sharedClone: path)
            _ = try run(["git", "-C", path.path, "fetch", "--all", "--prune"])
        }
    }

    public func fetch(sharedClone: URL) async throws {
        try ensureOriginFetchRefspec(sharedClone: sharedClone)
        _ = try run(["git", "-C", sharedClone.path, "fetch", "--all", "--prune"])
    }

    public func branches(sharedClone: URL) async throws -> [String] {
        let output = try run(["git", "-C", sharedClone.path, "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes/origin"])
        return output.split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/HEAD") }.sorted()
    }

    public func createWorktree(sharedClone: URL, branch: String, destination: URL, baseBranch: String?) async throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let exists = (try? run(["git", "-C", sharedClone.path, "show-ref", "--verify", "--quiet", "refs/heads/\(branch)"])) != nil
        if exists {
            _ = try run(["git", "-C", sharedClone.path, "worktree", "add", destination.path, branch])
        } else {
            let base = try resolvedBase(sharedClone: sharedClone, requested: baseBranch)
            _ = try run(["git", "-C", sharedClone.path, "worktree", "add", "-b", branch, destination.path, base])
        }
        // Worktrees created from a bare shared clone must retain the normal
        // remote-tracking refspec so `git fetch origin <branch>` updates
        // origin/<branch> instead of only FETCH_HEAD.
        try ensureOriginFetchRefspec(sharedClone: destination)
    }

    public func removeWorktree(sharedClone: URL, path: URL) async throws {
        _ = try run(["git", "-C", sharedClone.path, "worktree", "remove", "--force", path.path])
        _ = try? run(["git", "-C", sharedClone.path, "worktree", "prune"])
    }

    public func removeSharedClone(at path: URL) throws {
        let root = cacheRoot.standardizedFileURL.path
        let candidate = path.standardizedFileURL.path
        guard candidate.hasPrefix(root + "/") else {
            throw GitServiceError.invalidCachePath(candidate)
        }
        if fileManager.fileExists(atPath: candidate) { try fileManager.removeItem(at: path) }
    }

    public func dirtyChangeCount(repository: URL) async throws -> Int {
        let output = try run(["git", "-C", repository.path, "status", "--porcelain=v1", "--untracked-files=all"])
        return output.split(separator: "\n").count
    }

    public func capture(repository: WorkspaceRepositoryRecord, relativeTo reference: String? = nil) async throws -> ReviewSnapshotRepository {
        if let reference, !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try captureRelative(repository: repository, reference: reference)
        }
        let branch = try run(["git", "-C", repository.worktreePath.path, "branch", "--show-current"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let head = try? run(["git", "-C", repository.worktreePath.path, "rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let statusOutput = try run(["git", "-C", repository.worktreePath.path, "status", "--porcelain=v1", "--untracked-files=all", "-z"])
        let entries = Self.parseStatus(statusOutput)
        var files: [SnapshotFile] = []
        for entry in entries {
            let path = entry.path
            let status = entry.status
            let oldPath = entry.oldPath
            let oldLookup = oldPath ?? path
            let oldContent = (try? run(["git", "-C", repository.worktreePath.path, "show", "HEAD:\(oldLookup)"])) ?? ""
            let fileURL = repository.worktreePath.appending(path: path, directoryHint: .notDirectory)
            let newContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            var patch = (try? run(["git", "-C", repository.worktreePath.path, "diff", "--no-ext-diff", "--find-renames", "HEAD", "--", path])) ?? ""
            if patch.isEmpty && status == .added { patch = Self.addedPatch(path: path, content: newContent) }
            let fingerprint = Self.hash([path, status.rawValue, oldContent, newContent, patch].joined(separator: "\u{0}"))
            files.append(SnapshotFile(path: path, status: status, oldPath: oldPath, oldContent: oldContent, newContent: newContent, patch: patch, fingerprint: fingerprint))
        }
        return ReviewSnapshotRepository(repositoryID: repository.id, headOID: head, branch: branch, files: files.sorted { $0.path < $1.path })
    }

    private func captureRelative(repository: WorkspaceRepositoryRecord, reference: String) throws -> ReviewSnapshotRepository {
        let root = repository.worktreePath.path
        let resolvedReference = try run(["git", "-C", root, "rev-parse", "--verify", "\(reference)^{commit}"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = try run(["git", "-C", root, "branch", "--show-current"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let head = try? run(["git", "-C", root, "rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let aggregatePatch = try run(["git", "-C", root, "diff", "--no-ext-diff", "--find-renames", reference, "--"])
        let parsed = aggregatePatch.isEmpty ? [] : (try GitDiffParser().parse(aggregatePatch))
        let patches = Self.filePatches(from: aggregatePatch)
        let oldContents = try batchFileContents(
            root: root,
            reference: reference,
            paths: parsed.map { $0.oldPath ?? $0.path }
        )
        var files: [SnapshotFile] = []
        var seenPaths: Set<String> = []
        for diff in parsed {
            let oldLookup = diff.oldPath ?? diff.path
            let oldContent = oldContents[oldLookup] ?? ""
            let newContent = (try? String(contentsOf: repository.worktreePath.appending(path: diff.path), encoding: .utf8)) ?? ""
            let patch = patches[diff.path] ?? ""
            let fingerprint = Self.hash([resolvedReference, diff.path, diff.status.rawValue, oldContent, newContent, patch].joined(separator: "\u{0}"))
            files.append(SnapshotFile(path: diff.path, status: diff.status, oldPath: diff.oldPath, oldContent: oldContent, newContent: newContent, patch: patch, fingerprint: fingerprint))
            seenPaths.insert(diff.path)
        }

        let statusOutput = try run(["git", "-C", root, "status", "--porcelain=v1", "--untracked-files=all", "-z"])
        for entry in Self.parseStatus(statusOutput) where entry.status == .added && !seenPaths.contains(entry.path) {
            let content = (try? String(contentsOf: repository.worktreePath.appending(path: entry.path), encoding: .utf8)) ?? ""
            let patch = Self.addedPatch(path: entry.path, content: content)
            files.append(SnapshotFile(path: entry.path, status: .added, oldContent: "", newContent: content, patch: patch, fingerprint: Self.hash([resolvedReference, entry.path, content].joined(separator: "\u{0}"))))
        }
        return ReviewSnapshotRepository(repositoryID: repository.id, headOID: head, branch: "\(branch) vs \(reference)", files: files.sorted { $0.path < $1.path })
    }

    /// Splits the already-loaded aggregate diff into its per-file patches.
    /// This avoids launching another `git diff` process for every changed file.
    private static func filePatches(from aggregatePatch: String) -> [String: String] {
        guard !aggregatePatch.isEmpty else { return [:] }
        var chunks: [String] = []
        var current = ""
        for line in aggregatePatch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git "), !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += line
            current += "\n"
        }
        if !current.isEmpty { chunks.append(current) }

        var result: [String: String] = [:]
        for chunk in chunks {
            guard let file = try? GitDiffParser().parse(chunk).first else { continue }
            result[file.path] = chunk
        }
        return result
    }

    /// Reads every baseline file through one `git cat-file --batch` process
    /// instead of spawning `git show` once per changed path.
    private func batchFileContents(root: String, reference: String, paths: [String]) throws -> [String: String] {
        guard !paths.isEmpty else { return [:] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", root, "cat-file", "--batch"]
        let stdin = Pipe()
        let capture = try ProcessFileCapture()
        process.standardInput = stdin
        process.standardOutput = capture.stdout
        process.standardError = capture.stderr
        try process.run()
        let requests = paths.map { "\(reference):\($0)" }.joined(separator: "\n") + "\n"
        stdin.fileHandleForWriting.write(Data(requests.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let output = try capture.outputData()
        let error = try capture.errorData()
        guard process.terminationStatus == 0 else {
            throw GitServiceError.commandFailed(
                arguments: process.arguments ?? [],
                status: process.terminationStatus,
                stderr: String(decoding: error, as: UTF8.self)
            )
        }

        var result: [String: String] = [:]
        var cursor = output.startIndex
        for path in paths {
            guard let newline = output[cursor...].firstIndex(of: 0x0A) else { break }
            let header = String(decoding: output[cursor..<newline], as: UTF8.self)
            cursor = output.index(after: newline)
            if header.hasSuffix(" missing") {
                result[path] = ""
                continue
            }
            guard let size = Int(header.split(separator: " ").last ?? ""),
                  size >= 0,
                  let end = output.index(cursor, offsetBy: size, limitedBy: output.endIndex) else { break }
            result[path] = String(decoding: output[cursor..<end], as: UTF8.self)
            cursor = end
            if cursor < output.endIndex, output[cursor] == 0x0A { cursor = output.index(after: cursor) }
        }
        return result
    }

    public static func workspaceFingerprint(_ repositories: [ReviewSnapshotRepository]) -> String {
        hash(repositories.sorted { $0.repositoryID.uuidString < $1.repositoryID.uuidString }.flatMap { repository in
            [repository.repositoryID.uuidString, repository.headOID ?? "", repository.branch] + repository.files.flatMap { [$0.path, $0.fingerprint] }
        }.joined(separator: "\u{0}"))
    }

    public static func fileDiff(from file: SnapshotFile) -> FileDiff {
        if !file.patch.isEmpty, let parsed = try? GitDiffParser().parse(file.patch), let first = parsed.first { return first }
        return LineDiffBuilder.build(
            path: file.path,
            oldPath: file.oldPath,
            status: file.status,
            oldContent: file.oldContent,
            newContent: file.newContent
        )
    }

    public static func compare(old: ReviewSnapshotRecord, new: ReviewSnapshotRecord, repositoryNames: [UUID: String]) -> [WorkspaceFileDiff] {
        let oldFiles = Dictionary(uniqueKeysWithValues: old.repositories.flatMap { repository in repository.files.map { ("\(repository.repositoryID):\($0.path)", (repository.repositoryID, $0)) } })
        let newFiles = Dictionary(uniqueKeysWithValues: new.repositories.flatMap { repository in repository.files.map { ("\(repository.repositoryID):\($0.path)", (repository.repositoryID, $0)) } })
        return Set(oldFiles.keys).union(newFiles.keys).sorted().compactMap { key in
            let oldEntry = oldFiles[key]
            let newEntry = newFiles[key]
            let repositoryID = newEntry?.0 ?? oldEntry!.0
            let oldContent = oldEntry?.1.newContent ?? ""
            let newContent = newEntry?.1.newContent ?? ""
            guard oldContent != newContent else { return nil }
            let source = newEntry?.1 ?? oldEntry!.1
            let status: FileStatus = oldEntry == nil ? .added : (newEntry == nil ? .deleted : .modified)
            let comparison = SnapshotFile(path: source.path, status: status, oldPath: source.oldPath, oldContent: oldContent, newContent: newContent, patch: "", fingerprint: hash(oldContent + "\u{0}" + newContent))
            return WorkspaceFileDiff(repositoryID: repositoryID, repositoryName: repositoryNames[repositoryID] ?? "Repository", diff: fileDiff(from: comparison), oldContent: oldContent, newContent: newContent)
        }
    }

    private func resolvedBase(sharedClone: URL, requested: String?) throws -> String {
        let candidates = [requested, "main", "master", "origin/main", "origin/master"].compactMap { $0 }.filter { !$0.isEmpty }
        for candidate in candidates where (try? run(["git", "-C", sharedClone.path, "rev-parse", "--verify", candidate])) != nil { return candidate }
        return "HEAD"
    }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        // A PR-sized diff can exceed a pipe's kernel buffer. File-backed
        // capture lets git keep writing even when this call originates on the
        // main actor and no dispatch worker is available to drain a Pipe.
        let capture = try ProcessFileCapture()
        process.standardOutput = capture.stdout
        process.standardError = capture.stderr
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: try capture.outputData(), as: UTF8.self)
        let error = String(decoding: try capture.errorData(), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw GitServiceError.commandFailed(arguments: arguments, status: process.terminationStatus, stderr: error) }
        return output
    }

    private func ensureOriginFetchRefspec(sharedClone: URL) throws {
        let expected = "+refs/heads/*:refs/remotes/origin/*"
        let configured = try? run(["git", "-C", sharedClone.path, "config", "--get-all", "remote.origin.fetch"])
        guard !(configured?.split(separator: "\n").contains { String($0) == expected } ?? false) else { return }
        _ = try run(["git", "-C", sharedClone.path, "config", "--add", "remote.origin.fetch", expected])
    }

    private static func parseStatus(_ output: String) -> [(status: FileStatus, path: String, oldPath: String?)] {
        let fields = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var result: [(FileStatus, String, String?)] = []
        var index = 0
        while index < fields.count {
            let field = fields[index]
            guard field.count >= 4 else { index += 1; continue }
            let code = String(field.prefix(2))
            let path = String(field.dropFirst(3))
            if code.contains("R"), index + 1 < fields.count {
                result.append((.renamed, fields[index + 1], path))
                index += 2
            } else {
                let status: FileStatus = code == "??" || code.contains("A") ? .added : (code.contains("D") ? .deleted : .modified)
                result.append((status, path, nil))
                index += 1
            }
        }
        return result
    }

    private static func addedPatch(path: String, content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        return "diff --git a/\(path) b/\(path)\nnew file mode 100644\n--- /dev/null\n+++ b/\(path)\n@@ -0,0 +1,\(lines.count) @@\n" + lines.map { "+\($0)" }.joined(separator: "\n") + "\n"
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func repositoryName(_ remoteURL: String) -> String {
        let trimmed = remoteURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return (trimmed.split(separator: "/").last.map(String.init) ?? "repository").replacingOccurrences(of: ".git", with: "")
    }
}

private final class ProcessFileCapture {
    let stdout: FileHandle
    let stderr: FileHandle

    private let stdoutURL: URL
    private let stderrURL: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("avestacode-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        stdoutURL = directory.appendingPathComponent("stdout")
        stderrURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        stdout = try FileHandle(forWritingTo: stdoutURL)
        stderr = try FileHandle(forWritingTo: stderrURL)
    }

    deinit {
        try? stdout.close()
        try? stderr.close()
        try? FileManager.default.removeItem(at: stdoutURL.deletingLastPathComponent())
    }

    func outputData() throws -> Data {
        try stdout.synchronize()
        return try Data(contentsOf: stdoutURL)
    }

    func errorData() throws -> Data {
        try stderr.synchronize()
        return try Data(contentsOf: stderrURL)
    }
}

public enum GitServiceError: Error, LocalizedError, Equatable {
    case commandFailed(arguments: [String], status: Int32, stderr: String)
    case invalidCachePath(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let arguments, let status, let stderr):
            return "Git failed (\(status)): \(arguments.joined(separator: " "))\n\(stderr)"
        case .invalidCachePath(let path):
            return "Refusing to remove a path outside the shared repository cache: \(path)"
        }
    }
}
