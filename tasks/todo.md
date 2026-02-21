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

## Task 2 Checklist
- [x] Add native SwiftUI `Settings` scene with shared `PromptImproverViewModel`
- [x] Add Settings root with two tabs: `Models` and `Guides`
- [x] Implement Models tab with per-tool ordered model list CRUD + reorder + default model picker
- [x] Implement default effort + per-model effort allowlist editing UI with persistence
- [x] Show capability diagnostics (path/version/last checked) and add local-only `Recheck`
- [x] Add per-tool `Reset to defaults` preserving unrelated persisted data
- [x] Add Guides tab sidebar/detail placeholder scaffold for Task 3
- [x] Extend engine settings model with additive `orderedEngineModels` override and mutating helpers
- [x] Extend capability cache API to return cached entries and support forced refresh
- [x] Move settings persistence + diagnostics/recheck execution off main thread
- [x] Add/extend unit tests for settings mutations/store behavior and capability forced refresh
- [x] Verify full test suite and app build
- [x] Update maintenance documentation

## Review (Task 2)
- Result: Task 2 implemented. App now has a native macOS Settings window (Cmd+,) with `Models` and `Guides` tabs. Models tab supports full ordered model list editing, default model/effort configuration, per-model allowlist editing, capability status with recheck, and per-tool reset. Guides tab provides a NavigationSplitView scaffold for Task 3.
- Verification:
  - `swift test` (53 tests passed, including new `EngineSettingsMutationTests` and cache refresh coverage)
  - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (build succeeded)
- Risks/Follow-ups:
  - Capability refresh and settings persistence rely on guarded background queues with unchecked sendable boxes; safe for current usage but worth revisiting if diagnostics/persistence ownership broadens.
  - Guides tab is intentionally placeholder-only and does not yet provide CRUD/editing.

## Task 2 Regression Fixes Checklist
- [x] Patch local CLI diagnostics/capability checks to prepend executable directory into `PATH`
- [x] Add reusable CLI environment helper to avoid duplicate env patch logic
- [x] Restore Settings reactivity by publishing `engineSettings` in `PromptImproverViewModel`
- [x] Replace `Guides` tab `NavigationSplitView` with stable `HSplitView` scaffold
- [x] Add regression tests for env-wrapped local executables in health check and capability detector
- [x] Re-run full unit suite and app build
- [ ] Manual smoke of Settings UI interactions (pending in-app verification)

## Review (Task 2 Regression Fixes)
- Result: Fixed confirmed regressions from the first Task 2 pass. `CLIHealthCheck` and `ToolCapabilityDetector` now run with executable-directory-prefixed `PATH`, so local wrappers depending on sibling runtimes (e.g. nvm-style node wrappers) no longer fail diagnostics with `env: node: No such file or directory`. Models controls now refresh immediately because `engineSettings` is published. Guides tab now uses an `HSplitView` placeholder scaffold to avoid `NavigationSplitView` chrome conflicts in Settings tabs.
- Verification:
  - `swift test` (55 tests passed, including new `CLIEnvironmentIntegrationTests`)
  - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (build succeeded)
- Risks/Follow-ups:
  - Console logs from private frameworks listed in `AGENTS.md` remain non-blocking noise unless paired with functional breakage.
  - Manual in-app smoke validation is still recommended for final UX confirmation of Settings interactions.
