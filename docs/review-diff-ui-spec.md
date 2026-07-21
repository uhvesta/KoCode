# Review Diff UI Rewrite Specification

Status: proposed  
Scope: Unified, Split, and Full File rendering inside a workspace Review tab

## 1. Outcome

Review should feel like a focused pull-request review rather than three unrelated text previews. All three modes must render the same comparison, preserve the selected file and change while switching modes, support inline annotations, and remain responsive on PR-sized changes.

The rewrite will use one canonical diff document and one shared code-row renderer. Unified, Split, and Full File become presentations of that document, not separate implementations of diff semantics.

## 2. Problems in the current implementation

### Unified

- Rows size themselves around their contents inside a two-axis SwiftUI `ScrollView`, producing the narrow, centered column shown in the screenshot.
- Line-number gutters, change markers, and code do not form stable columns.
- Change backgrounds cover only the intrinsic row width instead of the review pane.
- Hunk headers float in the code stream and do not act as full-width change separators.
- There is no syntax highlighting.

### Split

- Split mode does not render the parsed diff. It labels every line of `oldContent` as removed and every line of `newContent` as added.
- Unchanged lines are therefore red on the left and green on the right.
- The two files are not aligned by diff hunks; insertions and deletions shift every later line.
- The independent columns do not have a single authoritative vertical row model.
- There is no syntax highlighting.

### Full File

- Its overall information architecture is the strongest of the three modes.
- It needs syntax highlighting and a clearer gutter/background treatment.
- `changedNewLineNumbers` is recomputed while building individual rows. This must become precomputed presentation data.
- Deleted files need an explicit baseline-file presentation instead of an empty after-file.

### Shared correctness gaps

- Snapshot-to-snapshot comparisons currently fall back to “all old lines removed, all new lines added” because no patch/hunks are produced for those comparisons.
- “Previous Change” and “Next Change” currently select adjacent files. The labels and behavior disagree.
- Highlighting exists only as a Swift-specific prototype and is not connected to the review renderers.
- Work such as line splitting, annotation counting, changed-line set construction, and syntax parsing can be repeated during SwiftUI body evaluation.

## 3. Product behavior

### Shared review chrome

- Keep the repository filter, baseline controls, refresh, mode selector, totals, and Finish Review in the top toolbar.
- Keep a resizable file navigator on the left. Default width: 280 points; minimum: 220; maximum: 420.
- Each file row shows status, path, `+N −N`, and annotation count. The selected row has an unambiguous selection background.
- The content header shows repository, path, status, per-file totals, and the active change position, for example `Change 2 of 7`.
- “Previous Change” and “Next Change” navigate hunks. At a file boundary they continue to the preceding or following changed file.
- File navigation remains available by clicking the file list and through separate previous/next-file keyboard commands.
- Changing mode preserves repository filter, file, active hunk, selected annotation range, and the nearest visible line.
- Refresh keeps the last successful result visible with a small progress indicator. It does not replace the content with an indefinite spinner.
- Repository-specific errors appear in a dismissible banner without hiding successful repositories.

### Code viewport rules

- Code begins at the leading edge after fixed gutters; it is never centered in unused space.
- Default row height is 20 points with a 12–13 point user-monospace font.
- Lines do not wrap by default. Long lines use horizontal scrolling and retain text selection.
- Tabs render using a configurable tab width, defaulting to 4.
- Line-number gutters remain visible while horizontally scrolling.
- The viewport is virtualized. Only visible rows and a small overscan region create views.
- Diff color is a background layer; syntax color remains readable above it.
- Added and removed states are conveyed by `+`/`−`, accessibility labels, and color. Color is never the sole signal.

## 4. Canonical presentation model

Introduce derived, non-durable presentation types in `AvestaCore` or a dedicated review presentation module:

```swift
struct ReviewDiffDocument {
    let file: WorkspaceFileDiff
    let hunks: [ReviewDiffHunk]
    let oldLines: [SourceLine]
    let newLines: [SourceLine]
    let changedOldLines: IndexSet
    let changedNewLines: IndexSet
}

struct ReviewDiffHunk {
    let id: StableHunkID
    let header: HunkHeader
    let unifiedRows: [UnifiedDiffRow]
    let splitRows: [SplitDiffRow]
}

struct SplitDiffRow {
    let changeGroupID: StableChangeGroupID?
    let old: DiffCell?
    let new: DiffCell?
}

struct DiffCell {
    let side: DiffSide
    let lineNumber: Int
    let kind: DiffLineKind
    let sourceLineIndex: Int
}
```

The exact names may change, but these invariants may not:

- Diff parsing and alignment happen once per file/fingerprint, never in a view body.
- Row identity is stable across mode switches and refreshes when the hunk still matches.
- Every rendered code cell carries its diff side and real source line number.
- Annotation anchors are derived from those identities, not screen row indices.
- The presentation document is cached by repository ID, file fingerprint, and comparison identity.

## 5. Diff semantics

### Unified row construction

- Preserve Git hunk order.
- A context line has both old and new line numbers.
- A removal has only an old line number.
- An addition has only a new line number.
- Each hunk begins with a full-width header row showing both ranges and optional function context.
- Separate hunks with a visible separator; omitted context must not look like adjacent source.

### Split alignment

Construct split rows from each parsed hunk:

1. Pair each context line with itself on both sides.
2. Collect each contiguous change group into removed and added lines.
3. Zip removed and added lines by index up to the larger count.
4. Use an empty cell on the shorter side.
5. Continue with the next context line.

For one removed line replaced by two added lines, the first removed and first added line share a row; the second added line has an empty left cell. Unchanged context is neutral on both sides. Added-only and deleted-only files naturally produce blank opposite cells.

Split uses one shared vertical row sequence, guaranteeing alignment. Each side may have an independent horizontal offset, but vertical scrolling is synchronized and driven by the shared row index.

### Historical comparisons

For snapshot-to-snapshot, activity-session, and last-review comparisons, generate real line edits and hunks from `oldContent` and `newContent`. Use a deterministic Myers-style line diff with configurable context (default: 3 lines), or another proven algorithm with equivalent output. Do not synthesize a hunk containing every old line followed by every new line.

The algorithm must handle:

- empty, added, and deleted files;
- replacements with unequal line counts;
- repeated lines without unstable alignment;
- files without a trailing newline;
- renames and path changes;
- mode-only and binary changes with a non-text placeholder.

## 6. Unified mode

- Render a single full-width code table.
- Gutters: old line number, new line number, change marker, annotation indicator, then code.
- Context rows use the normal surface background.
- Removed rows use a subtle red content background with a stronger red gutter accent.
- Added rows use a subtle green content background with a stronger green gutter accent.
- Hunk headers use a subdued blue/secondary surface and remain readable across the full viewport.
- Clicking a changed line selects it; shift-click and drag extend a same-side range.
- Clicking the annotation gutter opens the composer for the selected range.
- The active hunk gets a restrained focus outline used by previous/next navigation.

## 7. Split mode

- Render Before and After headers above equal-width panes with a central divider.
- Each side has a fixed line-number gutter, change marker, annotation indicator, and code cell.
- Context rows are neutral on both sides.
- Removed cells are red only where a removed line exists.
- Added cells are green only where an added line exists.
- Empty alignment cells use a faint striped or secondary background so intentional padding is distinguishable from a blank source line.
- Hunk separators span both panes and show old/new ranges.
- Selecting lines cannot cross sides. An annotation records `.old` or `.new` explicitly.
- Resizing the review pane preserves the 50/50 division unless the user drags the divider; the chosen ratio persists per Review tab.

## 8. Full File mode

- Show the complete current file with changed new-side lines highlighted.
- For a deleted file, show the complete baseline file with removed lines highlighted and a “Deleted file — showing baseline” banner.
- For a renamed file, show both old and new paths in the header.
- Use one line-number gutter and an annotation gutter. A `+` or `−` marker appears only on changed lines.
- Previous/next change scrolls to the first line of the preceding/following hunk.
- Preserve the current full-file density and general layout; the rewrite should polish it rather than redesign it.

## 9. Syntax highlighting

Replace the Swift-only entry point with a language-neutral `SyntaxHighlightingService`.

### Required behavior

- Highlight the complete old and new source before extracting attributed lines. Parsing isolated diff rows is forbidden because multiline strings/comments require surrounding syntax.
- Unified removals use highlighted old-source lines. Unified additions and context use highlighted new-source lines.
- Split Before uses the old-source result; After uses the new-source result.
- Full File uses the displayed side’s complete-source result.
- Diff backgrounds do not overwrite token foreground colors.
- Unknown languages fall back to plain monospaced text without delaying the diff.
- Highlighting runs off the main actor and is cancellable when the selected file changes.
- Cache by file fingerprint, side, language, and color theme.
- Publish plain rows immediately, then atomically apply highlighting without changing row heights or scroll position.

### Language registry

The registry identifies languages by file name and extension, not extension alone. Initial support should cover the files prominent in AvestaCode workspaces:

- Swift
- Rust
- Starlark/Bazel (`BUILD`, `BUILD.bazel`, `MODULE.bazel`, `.bzl`)
- TOML, including `Cargo.lock`
- JSON
- YAML
- Markdown
- shell
- Python
- JavaScript/TypeScript

Tree-sitter grammars and queries must be pinned and packaged for both SwiftPM/Xcode and Bazel builds. A missing grammar or query is a recoverable plain-text fallback and must be covered by diagnostics/tests.

### Large-file policy

- Files up to 2 MB or 50,000 lines highlight automatically in the background.
- Larger files render plain text immediately and offer “Enable syntax highlighting,” with cancellation and progress.
- Highlight cache entries are bounded by total attributed-text cost and evicted least-recently-used.

## 10. Rendering architecture

Use one AppKit-backed virtualized code table embedded through `NSViewRepresentable`, while keeping the surrounding Review tab in SwiftUI.

Recommended implementation:

- `NSTableView`/`NSScrollView` or an equivalent reusable-row AppKit view for Unified and Full File.
- A shared-row split table, or two synchronized clip views driven by the same `SplitDiffRow` collection, for Split.
- Reusable cells with fixed gutters and an attributed, non-editable selectable text field.
- A sticky overlay/header for column labels and hunk navigation.

This boundary is intentional: precise gutters, synchronized scrolling, attributed text, line-range hit testing, and very large virtualized documents are a poor fit for the current nested SwiftUI `ScrollView`/`LazyVStack` implementation. The AppKit adapter owns only review-code presentation and interaction; durable review state remains in the model/SQLite repositories.

## 11. Interaction and accessibility

- Keyboard:
  - `[` / `]` with the application’s chosen modifiers: previous/next changed file.
  - `⌥↑` / `⌥↓`: previous/next hunk.
  - `⌘1`, `⌘2`, `⌘3`: Unified, Split, Full File when these do not conflict with tab shortcuts; otherwise use documented alternatives.
  - `Escape`: clear line selection or dismiss the composer.
- Copy copies source text only by default; a context menu can copy with line numbers or copy the patch.
- VoiceOver announces side, line number, change kind, annotation count, and source text.
- Focus order is toolbar, file navigator, content header, code viewport, annotations.
- Light and dark themes meet WCAG AA contrast for text; selected and changed states remain distinguishable together.

## 12. Performance requirements

- Building presentation rows is linear in patch/source size and occurs outside SwiftUI body evaluation.
- Selecting a typical file after review capture shows plain rows within 100 ms on the development machine.
- A 2 MB patch and a 50,000-line file remain scrollable without constructing all platform row views.
- Scrolling targets 60 fps with no repeated source splitting, annotation filtering, changed-line-set construction, or syntax parsing per visible row.
- Mode switching reuses the cached document and highlighted sources; it must not rerun Git or reload snapshot blobs.
- Refresh cancellation terminates obsolete presentation/highlighting work.

## 13. Testing plan

### Core unit tests

- Unified line numbers and kinds for context, additions, removals, and replacements.
- Split alignment for 1:1, 1:N, N:1, addition-only, deletion-only, and separated change groups.
- Snapshot-to-snapshot Myers diff with repeated lines and missing final newline.
- Stable row/hunk identity across equivalent refreshes.
- Added, deleted, renamed, binary, mode-only, and paths containing spaces.

### Syntax tests

- Language resolution for exact names and extensions.
- Token colors for every initially supported language.
- Correct old/new line lookup in Unified and Split.
- Multiline syntax proves whole-file parsing.
- Missing resources and oversized files fall back safely.
- Cache hit, eviction, cancellation, and theme invalidation.

### Renderer and interaction tests

- Golden screenshots in light and dark mode at narrow, normal, and wide window sizes.
- Unified rows fill the viewport and gutters remain aligned.
- Split context is neutral and both sides stay vertically aligned while scrolling.
- Full File highlights only changed lines and shows deleted files correctly.
- Long-line horizontal scrolling keeps gutters fixed.
- Mode switches preserve file and active hunk.
- Previous/next change scrolls to hunks and crosses file boundaries.
- Line-range selection produces the correct repository, path, side, and line range for annotations.

### Performance tests

- A generated 2 MB, multi-hunk PR fixture.
- A 50,000-line full file with sparse changes.
- A workspace fixture with at least 100 changed files.
- Tests assert bounded presentation time and row-view reuse; they also guard against per-row reparsing/re-highlighting.

## 14. Delivery plan

### Phase 1 — Correct data and lock regressions

1. Add failing fixtures demonstrating the current Unified width and Split “everything changed” bugs.
2. Add the canonical review document and split-alignment builder.
3. Implement real snapshot-to-snapshot line diffs.
4. Expand parser edge-case coverage.

Exit condition: all modes receive correct, side-aware rows for every baseline type.

### Phase 2 — Shared virtualized renderer

1. Build the AppKit code table and shared row cells.
2. Replace Unified with full-width table rendering.
3. Replace Split with hunk-aligned paired rows and synchronized scrolling.
4. Move Full File onto the same table infrastructure.

Exit condition: screenshot and interaction tests pass without syntax highlighting.

### Phase 3 — Syntax highlighting

1. Generalize the existing Swift prototype into the highlighting service and cache.
2. Add and pin the initial language grammars and queries.
3. Connect old/new attributed lines to every mode.
4. Add background cancellation and the large-file policy.

Exit condition: all supported languages highlight consistently in all three modes without blocking file selection.

### Phase 4 — PR-review interaction polish

1. Implement hunk navigation, persistent active hunk, and clear file-navigation commands.
2. Implement side-aware range selection and annotation gutters.
3. Add copy actions, accessibility, themes, and error/loading states.

Exit condition: a user can conduct the full comment/question/terminal-handoff workflow from every mode.

### Phase 5 — Performance and release gate

1. Profile the real `mono` comparison and generated stress fixtures.
2. Remove remaining repeated derived work from view evaluation.
3. Run SwiftPM, Xcode, and Bazel test/build matrices.
4. Capture final golden screenshots for the three modes.

Exit condition: all acceptance criteria below pass on the packaged application.

## 15. Acceptance criteria

- Unified occupies the full content width with stable gutters and conventional hunk rendering.
- Split displays only actual removals/additions as changed and keeps unchanged lines aligned and neutral.
- Full File retains its useful complete-file view and adds non-blocking syntax highlighting.
- The same file, hunk, line identity, and annotation anchors are used in all modes.
- Every baseline type produces real hunks rather than whole-file replacement output.
- Previous/next change navigates hunks, not merely files.
- Switching modes never reruns Git and preserves review position.
- PR-sized fixtures and the real workspace remain responsive.
- Syntax highlighting supports the initial language registry in SwiftPM/Xcode and Bazel builds.
- UI, core, performance, and accessibility tests cover the behaviors above.

## 16. Explicit non-goals for the first rewrite

- Editable source code inside Review.
- Merge-conflict resolution.
- More than two comparison panes.
- Semantic/AST-aware diffing.
- Intraline word-diff highlighting. This can follow once line alignment is correct and stable.
