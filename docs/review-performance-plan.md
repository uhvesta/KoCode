# Review Performance Plan

The Review tab has two distinct latency budgets: capture the workspace Git comparison, then present and scroll the selected file. These paths must be measured independently so a fast Git capture cannot hide an expensive renderer.

## Current benchmark

The checked-in real-workspace harness is run with:

```sh
AVESTACODE_REVIEW_BENCHMARK_WORKTREE=/path/to/worktree \
AVESTACODE_REVIEW_BENCHMARK_BASELINE=origin/main \
swift test --filter GitServiceTests/testConfiguredRealWorkspaceReviewCapture
```

On the `checkleft-starlark/mono` fixture on July 21, 2026, Git capture produced 63 files and a 1,856,801-byte patch in 0.291 seconds. That makes presentation and rendering the primary target for the reported delay on this fixture.

## Phase 1: remove repeated and invisible work

Status: implemented.

- Capture independent workspace repositories concurrently while preserving repository order and per-repository errors.
- Build only the active Unified, Split, or Full File representation for the selected file.
- Index annotations once by side and line instead of filtering every annotation for every rendered row.
- Index file-level annotation counts once for the navigator.
- Perform syntax highlighting off the main actor; retain plain row rendering for files larger than 512 KB or 10,000 lines.
- Keep explicit regression tests for mode-specific derivation, annotation lookup, and large-document construction.

## Phase 2: instrument the interactive path

- Add signposts around Git capture, patch parsing, document derivation, highlighting, first visible row, and scroll updates.
- Add generated fixtures for a 2 MB multi-hunk patch, a 50,000-line file with sparse changes, and 100 changed files across multiple repositories.
- Record p50/p95 file-open latency, time to first visible row, peak resident memory, main-thread stalls, and scroll hitch ratio in CI artifacts.
- Add cancellation and generation IDs so an obsolete refresh, file selection, or highlight result cannot replace newer state.

Targets on the development machine:

- Existing captured results show their first plain rows within 100 ms of file selection.
- Review remains interactive during refresh and highlighting.
- Sustained scrolling has no main-thread stalls over 16 ms caused by row derivation, annotation lookup, or syntax parsing.

## Phase 3: virtualize the code viewport

The current combined-axis SwiftUI `ScrollView`/`LazyVStack` remains the main architectural risk for very large files. Replace it with the AppKit-backed virtualized table described in `review-diff-ui-spec.md`:

- Reuse a bounded number of row views with fixed gutters.
- Use one row model for Unified and Full File and paired cells for Split.
- Keep horizontal scrolling inside the code region and vertical scrolling row-based.
- Preserve line selection, inline comment expansion, hunk anchors, accessibility, and copy behavior.
- Cache derived documents and highlighted lines by snapshot fingerprint, file, and mode.

## Release gate

- Run SwiftPM and Bazel test suites plus the packaged-app smoke harness.
- Compare Instruments/signpost traces before and after virtualization.
- Validate the real `mono` workspace and generated stress fixtures.
- Do not consider the renderer complete until row-view reuse and scroll-hitch targets are covered by automated performance tests.
