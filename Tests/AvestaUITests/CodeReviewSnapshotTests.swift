import AppKit
import ComposableArchitecture
import SnapshotTesting
import SwiftUI
import XCTest
@testable import AvestaCore
@testable import AvestaUI

@MainActor
final class CodeReviewSnapshotTests: XCTestCase {
    func testCodeReviewFileMode() throws {
        let repoURL = try makeFixtureRepository()
        let file = makeFixtureFile()
        let session = CodeReviewFlowFeature.CodeReviewSessionState(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            diffSpec: "origin/main...HEAD",
            repoPath: repoURL,
            files: [file],
            activeFileIndex: 0
        )

        let view = SideBySideDiffView(
            session: session,
            navigation: CodeReviewNavigationState(changes: CodeReviewChangeNavigation.changes(in: file)),
            previousChange: {},
            nextChange: {}
        )
            .environment(\.colorScheme, .dark)
            .frame(width: 920, height: 620)
        let controller = NSHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 920, height: 620)
        controller.view.appearance = NSAppearance(named: .darkAqua)

        assertSnapshot(
            of: controller,
            as: .image(size: CGSize(width: 920, height: 620)),
            named: "file-mode",
            record: snapshotRecordMode
        )
    }

    func testCodeReviewBoardFlow() throws {
        let repoURL = try makeFixtureRepository()
        let file = makeFixtureFile()
        var session = CodeReviewFlowFeature.CodeReviewSessionState(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            diffSpec: "origin/main...HEAD",
            repoPath: repoURL,
            files: [file],
            activeFileIndex: 0
        )
        session.comments = [
            ReviewComment(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
                fileID: file.id,
                startLine: 2,
                endLine: 2,
                highlightedText: "let title = \"New\"",
                text: "Prefer a localized title here.",
                createdAt: Date(timeIntervalSince1970: 1_750_000_000)
            )
        ]
        let codeReview = AppFeature.CodeReviewTabState(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            flow: CodeReviewFlowFeature.State(session: session)
        )
        let boardItem = BoardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
            content: """
            # Code Review: origin/main...HEAD @ 2026-06-30T18:00:00Z

            ## `Sources/App.swift`

            ### Line 2
            ```swift
            let title = "New"
            ```
            Prefer a localized title here.
            """,
            source: "Code Review: \(session.diffSpec)",
            createdAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let workspace = AppFeature.WorkspaceState(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            name: "Review Flow",
            path: repoURL,
            tabs: [.codeReview(codeReview)],
            activeTabID: codeReview.id,
            boardItems: [boardItem]
        )
        let store = Store(initialState: AppFeature.State(
            workspaces: [workspace],
            activeWorkspaceID: workspace.id,
            isBoardVisible: true
        )) {
            AppFeature()
        }

        let view = HStack(spacing: 0) {
            CodeReviewView(store: store, tab: codeReview)
                .frame(width: 820, height: 720)
            BoardPanel(store: store, items: workspace.boardItems)
                .frame(width: 360, height: 720)
        }
        .environment(\.colorScheme, .dark)
        .frame(width: 1180, height: 720)
        let controller = NSHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 1180, height: 720)
        controller.view.appearance = NSAppearance(named: .darkAqua)

        assertSnapshot(
            of: controller,
            as: .image(size: CGSize(width: 1180, height: 720)),
            named: "board-flow",
            record: snapshotRecordMode
        )
    }

    private func makeFixtureFile() -> FileDiff {
        FileDiff(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            path: "Sources/App.swift",
            status: .modified,
            hunks: [
                DiffHunk(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    oldStart: 1,
                    oldCount: 7,
                    newStart: 1,
                    newCount: 9,
                    lines: [
                        DiffLine(kind: .context, oldLineNumber: 1, newLineNumber: 1, content: "import SwiftUI"),
                        DiffLine(kind: .removed, oldLineNumber: 2, newLineNumber: nil, content: "let title = \"Old\""),
                        DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 2, content: "let title = \"New\""),
                        DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 3, content: "let subtitle = \"Workbench\""),
                        DiffLine(kind: .context, oldLineNumber: 3, newLineNumber: 4, content: ""),
                        DiffLine(kind: .context, oldLineNumber: 4, newLineNumber: 5, content: "struct AppView: View {"),
                        DiffLine(kind: .context, oldLineNumber: 5, newLineNumber: 6, content: "    var body: some View {"),
                        DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 7, content: "        Text(subtitle)"),
                        DiffLine(kind: .context, oldLineNumber: 6, newLineNumber: 8, content: "        Text(title)"),
                        DiffLine(kind: .context, oldLineNumber: 7, newLineNumber: 9, content: "    }"),
                        DiffLine(kind: .context, oldLineNumber: 8, newLineNumber: 10, content: "}")
                    ]
                )
            ]
        )
    }

    private var snapshotRecordMode: SnapshotTestingConfiguration.Record {
        let rawValue = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] ?? "never"
        return SnapshotTestingConfiguration.Record(rawValue: rawValue) ?? .never
    }

    private func makeFixtureRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AvestaCodeSnapshotTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try """
        import SwiftUI
        let title = "New"
        let subtitle = "Workbench"

        struct AppView: View {
            var body: some View {
                Text(subtitle)
                Text(title)
            }
        }
        """.write(
            to: sourceDirectory.appendingPathComponent("App.swift"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }
}
