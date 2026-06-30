import XCTest
@testable import AvestaCore

final class GitServiceTests: XCTestCase {
    func testLocalBareCloneWorktreeAndDiff() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AvestaCodeGitServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = root.appending(path: "source", directoryHint: .isDirectory)
        let cache = root.appending(path: "cache", directoryHint: .isDirectory)
        let worktree = root.appending(path: "worktree", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try run(["git", "init", "-b", "main"], cwd: source)
        try "one\n".write(to: source.appending(path: "file.txt"), atomically: true, encoding: .utf8)
        try run(["git", "add", "file.txt"], cwd: source)
        try run(["git", "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", "initial"], cwd: source)

        let service = GitService(cacheRoot: cache)
        let bare = try await service.ensureBareClone(remoteURL: source.path, name: "source")
        try await service.createWorktree(bareRepo: bare, branch: "main", destination: worktree)

        try "one\ntwo\n".write(to: worktree.appending(path: "file.txt"), atomically: true, encoding: .utf8)
        let files = try await service.diff(repoPath: worktree, spec: "HEAD")

        let currentBranch = try await service.currentBranch(repoPath: worktree)
        let worktrees = try await service.listWorktrees(bareRepo: bare)

        XCTAssertEqual(currentBranch, "main")
        XCTAssertTrue(worktrees.contains { URL(fileURLWithPath: $0).standardizedFileURL.path == worktree.standardizedFileURL.path })
        XCTAssertEqual(files.first?.path, "file.txt")
        XCTAssertEqual(files.first?.hunks.first?.lines.last?.kind, .added)

        try run(["git", "checkout", "--", "file.txt"], cwd: worktree)
        try await service.removeWorktree(bareRepo: bare, worktreePath: worktree)
    }

    private func run(_ args: [String], cwd: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = cwd
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("Command failed: \(args.joined(separator: " ")) \(error)")
        }
    }
}
