import XCTest
@testable import AvestaCore

final class GitServiceTests: XCTestCase {
    func testRepositoryBankIdentityStripsRemotePrefixAndGitSuffix() {
        XCTAssertEqual(RepositorySourceRecord.identity(from: "https://github.com/spinyfin/mono.git"), "spinyfin/mono")
        XCTAssertEqual(RepositorySourceRecord.identity(from: "git@github.com:uhvesta/bazel-gazelle.git"), "uhvesta/bazel-gazelle")
        XCTAssertEqual(RepositorySourceRecord.identity(from: "ssh://git@github.com/owner/repo.git"), "owner/repo")
    }

    func testSharedCloneWorktreeAndWorkspaceCaptureIncludeTrackedAndUntrackedChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "AvestaGit-\(UUID())", directoryHint: .isDirectory)
        let source = root.appending(path: "source", directoryHint: .isDirectory)
        let cache = root.appending(path: "cache", directoryHint: .isDirectory)
        let worktree = root.appending(path: "worktree", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try run(["git", "init", "-b", "main"], at: source)
        try "one\n".write(to: source.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)
        try run(["git", "add", "."], at: source)
        try run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "initial"], at: source)

        let service = GitService(cacheRoot: cache)
        let shared = await service.sharedClonePath(remoteURL: source.path)
        try await service.ensureSharedClone(remoteURL: source.path, at: shared)
        let sharedBranches = try await service.branches(sharedClone: shared)
        XCTAssertTrue(sharedBranches.contains("origin/main"))
        try await service.createWorktree(sharedClone: shared, branch: "feature", destination: worktree, baseBranch: "main")
        try "one\ntwo\n".write(to: worktree.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: worktree.appending(path: "untracked.txt"), atomically: true, encoding: .utf8)

        let workspaceID = UUID()
        let item = WorkspaceRepositoryRecord(workspaceID: workspaceID, sourceID: UUID(), name: "source", worktreePath: worktree, branch: "feature")
        let capture = try await service.capture(repository: item)
        let branchCapture = try await service.capture(repository: item, relativeTo: "main")

        XCTAssertEqual(capture.branch, "feature")
        XCTAssertEqual(capture.files.map(\.path), ["tracked.txt", "untracked.txt"])
        XCTAssertEqual(capture.files.first { $0.path == "untracked.txt" }?.status, .added)
        XCTAssertGreaterThan(GitService.fileDiff(from: capture.files[0]).addedLineCount, 0)
        XCTAssertEqual(branchCapture.files.map(\.path), ["tracked.txt", "untracked.txt"])
        XCTAssertTrue(branchCapture.branch.contains("vs main"))
        XCTAssertEqual(branchCapture.files.first { $0.path == "tracked.txt" }?.oldContent, "one\n")
        XCTAssertTrue(branchCapture.files.first { $0.path == "tracked.txt" }?.patch.contains("diff --git") == true)
    }

    func testCanonicalRemoteDeduplicatesHTTPSAndSSHSpelling() {
        XCTAssertEqual(SQLiteStateRepository.canonicalRemoteURL("HTTPS://GitHub.com/org/repo.git/"), "https://github.com/org/repo")
        XCTAssertEqual(SQLiteStateRepository.canonicalRemoteURL("git@github.com:org/repo.git"), "ssh://git@github.com/org/repo")
    }

    func testPRStyleCaptureDrainsDiffLargerThanProcessPipeCapacity() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "AvestaLargeDiff-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try run(["git", "init", "-b", "main"], at: root)
        let oldContent = (0..<12_000).map { "old line \($0)" }.joined(separator: "\n") + "\n"
        try oldContent.write(to: root.appending(path: "large.txt"), atomically: true, encoding: .utf8)
        try run(["git", "add", "large.txt"], at: root)
        try run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "baseline"], at: root)
        let newContent = (0..<12_000).map { "new line \($0) with enough content to exceed a process pipe" }.joined(separator: "\n") + "\n"
        try newContent.write(to: root.appending(path: "large.txt"), atomically: true, encoding: .utf8)

        let item = WorkspaceRepositoryRecord(
            workspaceID: UUID(),
            sourceID: UUID(),
            name: "large",
            worktreePath: root,
            branch: "main"
        )
        let capture = try await GitService(cacheRoot: root.appending(path: "cache")).capture(
            repository: item,
            relativeTo: "HEAD"
        )

        let file = try XCTUnwrap(capture.files.first)
        XCTAssertEqual(file.path, "large.txt")
        XCTAssertGreaterThan(file.patch.utf8.count, 512 * 1_024)
        XCTAssertEqual(file.oldContent, oldContent)
        XCTAssertEqual(file.newContent, newContent)
    }

    func testConfiguredRealWorkspaceReviewCapture() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["AVESTACODE_REVIEW_BENCHMARK_WORKTREE"] else {
            throw XCTSkip("Set AVESTACODE_REVIEW_BENCHMARK_WORKTREE to benchmark a real workspace")
        }
        let baseline = environment["AVESTACODE_REVIEW_BENCHMARK_BASELINE"] ?? "origin/main"
        let item = WorkspaceRepositoryRecord(
            workspaceID: UUID(),
            sourceID: UUID(),
            name: URL(fileURLWithPath: path).lastPathComponent,
            worktreePath: URL(fileURLWithPath: path),
            branch: "benchmark"
        )
        let started = ContinuousClock.now
        let capture = try await GitService().capture(repository: item, relativeTo: baseline)
        let elapsed = started.duration(to: .now)
        let bytes = capture.files.reduce(0) { $0 + $1.patch.utf8.count }
        print("AvestaCode review benchmark: \(capture.files.count) files, \(bytes) patch bytes in \(elapsed)")
        XCTAssertFalse(capture.branch.isEmpty)
    }

    func testSnapshotComparisonBuildsContextLimitedHunksInsteadOfWholeFileReplacement() {
        let old = (1...14).map { "line \($0)" }.joined(separator: "\n") + "\n"
        var newLines = (1...14).map { "line \($0)" }
        newLines[6] = "changed seven"
        let new = newLines.joined(separator: "\n") + "\n"
        let snapshot = SnapshotFile(path: "file.txt", status: .modified, oldContent: old, newContent: new, patch: "", fingerprint: "f")

        let diff = GitService.fileDiff(from: snapshot)

        XCTAssertEqual(diff.hunks.count, 1)
        XCTAssertEqual(diff.removedLineCount, 1)
        XCTAssertEqual(diff.addedLineCount, 1)
        XCTAssertTrue(diff.hunks[0].lines.contains { $0.kind == .context })
        XCTAssertLessThan(diff.hunks[0].lines.count, 14)
    }

    func testSnapshotComparisonHandlesRepeatedLinesAndMissingFinalNewline() {
        let snapshot = SnapshotFile(
            path: "repeat.txt",
            status: .modified,
            oldContent: "same\nold\nsame",
            newContent: "same\nnew\nsame",
            patch: "",
            fingerprint: "f"
        )
        let diff = GitService.fileDiff(from: snapshot)
        XCTAssertEqual(diff.hunks.flatMap(\.lines).filter { $0.kind == .removed }.map(\.content), ["old"])
        XCTAssertEqual(diff.hunks.flatMap(\.lines).filter { $0.kind == .added }.map(\.content), ["new"])
        XCTAssertEqual(diff.hunks.flatMap(\.lines).filter { $0.kind == .context }.map(\.content), ["same", "same"])
    }

    func testSnapshotComparisonAddedAndDeletedFilesHaveNoPhantomBlankLine() {
        let added = GitService.fileDiff(from: SnapshotFile(path: "new", status: .added, oldContent: "", newContent: "one\n", patch: "", fingerprint: "a"))
        let deleted = GitService.fileDiff(from: SnapshotFile(path: "old", status: .deleted, oldContent: "one\n", newContent: "", patch: "", fingerprint: "d"))
        XCTAssertEqual(added.addedLineCount, 1)
        XCTAssertEqual(added.removedLineCount, 0)
        XCTAssertEqual(deleted.removedLineCount, 1)
        XCTAssertEqual(deleted.addedLineCount, 0)
    }

    private func run(_ arguments: [String], at directory: URL) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = arguments; process.currentDirectoryURL = directory
        let error = Pipe(); process.standardError = error; try process.run(); process.waitUntilExit()
        if process.terminationStatus != 0 { XCTFail(String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)) }
    }
}
