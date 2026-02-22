# Lessons Learned

Capture user corrections and prevention rules.

## Template
- Date:
- Context:
- Mistake pattern:
- Prevention rule:
- Verification:

## 2026-02-21
- Date: 2026-02-21
- Context: Task 2 Settings implementation shipped with user-reported regressions in CLI diagnostics, Models reactivity, and Guides layout.
- Mistake pattern: Assumed Settings bindings were sufficient without publishing the underlying settings state, and patched PATH only in provider runtime but not in local diagnostics/capability checks.
- Prevention rule: For any new settings editor, explicitly verify state publication/reactivity paths; for any local CLI invocation path (providers, health checks, capability detection), centralize env construction and run wrapper-based tests that require executable-directory PATH prepending.
- Verification: Added `CLIEnvironmentIntegrationTests`, reran `swift test` (55 passed), and reran macOS app build via `xcodebuild` (succeeded).

## 2026-02-22
- Date: 2026-02-22
- Context: Task 3B introduced a richer Guides editor panel; user reported vertical overflow/clipping in Settings → Guides.
- Mistake pattern: Kept aggregate minimum heights too high for the Settings window (`mappingPane + guideLibraryPane`) and embedded multiple vertically heavy sections in one pane without internal resizing.
- Prevention rule: For split-based Settings layouts, validate that combined min heights fit the root min window size, and use nested split panes (or equivalent flexible layout) when list/editor stacks coexist in one column.
- Verification: Updated `GuidesSettingsView` to lower right-pane minimum height and add a nested `VSplitView` for library vs editor sections; reran `xcodebuild` (succeeded).

## 2026-02-22 (UX Comfort Follow-up)
- Date: 2026-02-22
- Context: After the overflow fix, user reported that the Guides tab was still uncomfortable for real markdown editing because usable panes were too compressed.
- Mistake pattern: Solved clipping technically, but did not rebalance the full interaction model (workspace separation + minimum window ergonomics) around the dominant editing workflow.
- Prevention rule: For editor-heavy settings screens, validate ergonomic minimums end-to-end: separate competing workflows into modes, then ensure root window minimum size supports the combined split minimum widths used by those modes.
- Verification: Updated Settings minimum size and rebalanced Guides split width constraints around the editor-first workflow; validated with `swift test` and `xcodebuild`.

## 2026-02-22 (Horizontal Overflow Follow-up)
- Date: 2026-02-22
- Context: After the editor-first redesign, user reported horizontal clipping in the Guide Editor pane.
- Mistake pattern: Set child split minimum widths (`library + editor`) that could exceed parent workspace constraints, causing right-edge content clipping under some splitter positions/window widths.
- Prevention rule: In split-based layouts, enforce `sum(child mins) <= practical parent min` and avoid rigid parent min-width constraints that can conflict with child minima.
- Verification: Rebalanced pane minima/maxima in `GuidesSettingsView`, removed rigid right-workspace minimum width, and validated with `swift test` and `xcodebuild`.

## 2026-02-22 (Main Window Dead-Space Follow-up)
- Date: 2026-02-22
- Context: User rejected an initial main-window dead-space fix that introduced manual `NSWindow` sizing orchestration.
- Mistake pattern: Jumped to imperative window-frame control before proving the layout root cause, increasing complexity without first exhausting SwiftUI-native constraint fixes.
- Prevention rule: For UI spacing regressions, first isolate whether the issue is layout elasticity (`Spacer`, min/max frames) or scene sizing/restoration behavior, and prefer declarative SwiftUI scene/content constraints before AppKit window mutation.
- Verification: Replaced manual window controller with `windowResizability(.contentSize)`, state-bounded root heights, and removal of idle spacer; reran `swift test` and `xcodebuild` successfully.
