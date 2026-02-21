# Task Plan

Use this file to track the current task with checkable items.

## Task 1B Checklist
- [x] Extend run-time request payload with optional engine model/effort fields
- [x] Resolve effective engine model + effort in `PromptImproverViewModel.improve()`
- [x] Wire Codex invocation args for `--model` and effort config (`-c model_reasoning_effort=...`)
- [x] Wire Claude invocation args for `--model` across stream + fallback runs
- [x] Apply Claude effort via ephemeral workspace `.claude/settings.json` (`effortLevel`)
- [x] Add regression tests for provider args and workspace effort file behavior
- [x] Verify targeted tests, full unit suite, and app build
- [x] Update maintenance documentation

## Review
- Result: Task 1B implemented. Engine model and effort are now resolved at run start and carried into provider execution without changing streaming parsers or output-contract validation. Target model remains independent and still drives prompt-guide selection only.
- Verification:
  - `swift test --filter "ProviderBehaviorTests|WorkspaceManagerTests|EffortGatingTests"` (19 tests passed)
  - `swift test` (48 tests passed)
  - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (build succeeded)
- Risks/Follow-ups:
  - Model/effort configuration controls in UI are still pending by design; Task 1B uses resolved defaults from Task 1A settings.
  - Capability detection remains local help/version parsing and may need updates if CLI help formats change.
