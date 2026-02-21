# Task Plan

Use this file to track the current task with checkable items.

## Checklist
- [x] Define scope
- [x] Implement settings model + persistence for per-tool engine models/effort defaults/allowlists
- [x] Implement local-only capability detection and signature-based capability cache invalidation
- [x] Wire non-visual view-model hooks for resolved models/defaults/effective effort gating
- [x] Add unit tests for persistence compatibility, cache invalidation, and effort gating
- [x] Verify with `swift test` and app build
- [x] Summarize outcome

## Review
- Result: Task 1A implemented with new engine settings persistence, local capability detection, and signature-keyed capability cache. `RootView` remains unchanged; hooks are available via `PromptImproverViewModel`.
- Verification:
  - `swift test` (42 tests passed)
  - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (build succeeded)
- Risks/Follow-ups:
  - Task 1B must wire model/effort runtime args in providers using the new hooks.
  - Current detector intentionally uses local help/version parsing only and may need parser updates if CLI help text formats change.
