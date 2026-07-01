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

    func testCreateWorktreeCreatesMissingBranchFromDefaultBranch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AvestaCodeGitNewBranchWorktreeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = root.appending(path: "source", directoryHint: .isDirectory)
        let cache = root.appending(path: "cache", directoryHint: .isDirectory)
        let worktree = root.appending(path: "worktree", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try run(["git", "init", "-b", "main"], cwd: source)
        try "from main\n".write(to: source.appending(path: "file.txt"), atomically: true, encoding: .utf8)
        try run(["git", "add", "file.txt"], cwd: source)
        try run(["git", "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", "initial"], cwd: source)

        let service = GitService(cacheRoot: cache)
        let bare = try await service.ensureBareClone(remoteURL: source.path, name: "source")
        try await service.createWorktree(bareRepo: bare, branch: "main2", destination: worktree)

        let currentBranch = try await service.currentBranch(repoPath: worktree)
        let content = try String(contentsOf: worktree.appending(path: "file.txt"), encoding: .utf8)
        let branches = try await service.branches(repoPath: bare)

        XCTAssertEqual(currentBranch, "main2")
        XCTAssertEqual(content, "from main\n")
        XCTAssertTrue(branches.contains("main2"))
    }

    func testCreateWorktreeCreatesMissingBranchFromExplicitBaseBranch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AvestaCodeGitExplicitBaseWorktreeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = root.appending(path: "source", directoryHint: .isDirectory)
        let cache = root.appending(path: "cache", directoryHint: .isDirectory)
        let worktree = root.appending(path: "worktree", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try run(["git", "init", "-b", "main"], cwd: source)
        try "from main\n".write(to: source.appending(path: "file.txt"), atomically: true, encoding: .utf8)
        try run(["git", "add", "file.txt"], cwd: source)
        try run(["git", "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", "initial"], cwd: source)
        try run(["git", "switch", "-c", "review-base"], cwd: source)
        try "from review-base\n".write(to: source.appending(path: "file.txt"), atomically: true, encoding: .utf8)
        try run(["git", "add", "file.txt"], cwd: source)
        try run(["git", "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", "base change"], cwd: source)

        let service = GitService(cacheRoot: cache)
        let bare = try await service.ensureBareClone(remoteURL: source.path, name: "source")
        try await service.createWorktree(
            bareRepo: bare,
            branch: "review-child",
            destination: worktree,
            baseBranch: "review-base"
        )

        let currentBranch = try await service.currentBranch(repoPath: worktree)
        let content = try String(contentsOf: worktree.appending(path: "file.txt"), encoding: .utf8)

        XCTAssertEqual(currentBranch, "review-child")
        XCTAssertEqual(content, "from review-base\n")
    }

    func testWorkingTreeAndCheckpointDiffsIncludeLastTurnOnly() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AvestaCodeGitCheckpointTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try run(["git", "init", "-b", "main"], cwd: root)
        try "one\n".write(to: root.appending(path: "file.txt"), atomically: true, encoding: .utf8)
        try run(["git", "add", "file.txt"], cwd: root)
        try run(["git", "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", "initial"], cwd: root)

        try "one\ntwo\n".write(to: root.appending(path: "file.txt"), atomically: true, encoding: .utf8)
        try "first draft\n".write(to: root.appending(path: "notes.txt"), atomically: true, encoding: .utf8)

        let service = GitService()
        let gitChanges = try await service.workingTreeDiff(repoPath: root)
        XCTAssertEqual(gitChanges.map(\.path).sorted(), ["file.txt", "notes.txt"])

        let checkpointDate = Date(timeIntervalSince1970: 1_782_835_200)
        let checkpoint = try await service.reviewCheckpoint(repoPath: root, createdAt: checkpointDate)
        XCTAssertEqual(checkpoint.createdAt, checkpointDate)

        try "one\ntwo\nthree\n".write(to: root.appending(path: "file.txt"), atomically: true, encoding: .utf8)
        try "after checkpoint\n".write(to: root.appending(path: "later.txt"), atomically: true, encoding: .utf8)

        let lastTurn = try await service.diff(repoPath: root, since: checkpoint)
        XCTAssertEqual(lastTurn.map(\.path).sorted(), ["file.txt", "later.txt"])
        XCTAssertFalse(lastTurn.contains { $0.path == "notes.txt" })
        XCTAssertEqual(lastTurn.first { $0.path == "file.txt" }?.addedLineCount, 1)
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
