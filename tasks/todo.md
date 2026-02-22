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

## Runtime Hardening Checklist
- [x] Add local CLI command runner with timeout + stdout/stderr capture
- [x] Wire timeout-backed runner into `CLIDiscovery`, `CLIHealthCheck`, and `ToolCapabilityDetector`
- [x] Patch Claude runtime `PATH` with executable-directory prefix (parity with Codex)
- [x] Refactor Codex runtime `PATH` construction to reuse shared helper
- [x] Extend discovery to include `nvm` versioned candidates for Claude
- [x] Add regression tests for discovery fallback, timeout handling, and Claude PATH patching
- [x] Re-run full unit suite and app build
- [ ] Manual Finder-launched smoke for Codex/Claude wrapper execution

## Review (Runtime Hardening)
- Result: Improved local runtime robustness without changing product UX. Local discovery/diagnostic processes now use bounded execution with timeout handling, Claude execution now receives the same executable-directory PATH patch strategy as Codex, and Claude discovery can resolve `~/.nvm/versions/node/<version>/bin/claude` fallbacks when shell lookup is unavailable.
- Verification:
  - `swift test` (59 tests passed, including new `CLIDiagnosticsHardeningTests` and new Claude PATH provider coverage)
  - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (build succeeded)
- Risks/Follow-ups:
  - Manual smoke from Finder launch context is still recommended to validate real host environment behavior with installed wrappers.
  - Timeouts are defensive best-effort guards; pathological binaries may still produce degraded capability detail (safe fallback behavior is preserved).

## Task 3A Checklist
- [x] Replace hardcoded target model enum run-path usage with persisted output model slug/display + ordered guide snapshot in `RunRequest`
- [x] Add guides domain model (`OutputModel`, `GuideDoc`, `GuidesCatalog`) with normalization/reconciliation helpers
- [x] Add versioned `GuidesCatalogStore` persistence under Application Support
- [x] Add `GuideDocumentManager` import/resolve/delete support with `.md` + size + UTF-8 validation
- [x] Add Gemini built-in guide template and seed default output models/mappings (`claude-4-6`, `gpt-5-2`, `gemini-3-0`)
- [x] Update workspace builder to copy only mapped guides in strict order and write structured `RUN_CONFIG.json`
- [x] Update provider prompt instructions to read ordered guides from `RUN_CONFIG.json`
- [x] Drive main-screen target picker from persisted output models
- [x] Implement full Settings → Guides UI (output model CRUD, guide import/delete, ordered mapping + reorder, reset built-ins)
- [x] Add tests for catalog mutations, catalog store, guide import validation, and workspace copy/run-config semantics
- [x] Re-run full unit suite and macOS app build
- [ ] Manual in-app smoke of Guides settings flows (import dialogs + CRUD UX) in running app

## Review (Task 3A)
- Result: Implemented end-to-end Guides mapping with persisted output models and ordered multi-guide assignments, independent from execution tool selection. Main run selection now uses persisted output-model slugs/display names; workspace assembly now includes only mapped guides in defined order and emits deterministic `RUN_CONFIG.json` (`targetSlug`, ordered filenames).
- Verification:
  - `swift test` (74 tests passed; includes new `GuidesCatalogMutationTests`, `GuidesCatalogStoreTests`, `GuideDocumentManagerTests`, updated workspace/provider/smoke coverage)
  - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (build succeeded)
- Risks/Follow-ups:
  - Manual UI smoke is still recommended for file importer UX and confirmation dialogs in Settings → Guides.
  - In-app guide content editing remains intentionally out of scope; Task 3A covers import/mapping/persistence/runtime integration only.

## Task 3B Checklist
- [x] Extend `GuideDoc` with optional `forkStoragePath` and preserve backward-compatible decoding
- [x] Extend `GuideDocumentManaging` with editor lifecycle APIs (`loadText`, `ensureEditableGuide`, `saveText`, `revertBuiltInFork`, `hasFork`)
- [x] Switch guide file writes to atomic temp+replace logic via `AtomicJSONStore`
- [x] Add built-in fork resolution precedence (fork if present, template otherwise) without changing guide IDs
- [x] Add `PromptImproverViewModel` guide editor methods and synchronous catalog persistence for save/revert
- [x] Add Settings → Guides in-app markdown editor UI with monospaced `TextEditor`
- [x] Implement built-in read-only mode + `Edit` (fork-on-edit) + `Save` + `Discard` + `Revert to built-in`
- [x] Implement dirty-state confirmation on guide switch and explicit editor close
- [x] Verify run integration still file-based and fork content flows into workspace via existing mapped-guide copy path
- [x] Add tests for fork creation/save/revert/resolution, atomic save cleanup, catalog fork-path persistence, and workspace fork-preference
- [x] Re-run full unit suite and macOS app build
- [ ] Manual in-app smoke of new guide editor interactions in Settings window

## Review (Task 3B)
- Result: Implemented in-app markdown guide editing with safe built-in forking and revert flow. Built-in guides remain bundle read-only until `Edit` creates a user-local fork; saves are atomic and update metadata (`updatedAt`, `hash`), and runtime workspace guide copying now automatically uses forked content when present.
- Verification:
  - `swift test` (80 tests passed; includes expanded `GuideDocumentManagerTests`, `GuidesCatalogStoreTests`, and `WorkspaceManagerTests` coverage for Task 3B behavior)
  - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (build succeeded)
- Risks/Follow-ups:
  - Manual UI smoke remains recommended for editor flow details in Settings (dirty-state dialogs, fork/revert UX transitions).
  - Dirty-state confirmation is intentionally scoped to guide switch and explicit editor close, not Settings-window close interception.

## Task 3B Layout Stabilization Checklist
- [x] Diagnose Guides tab overflow after editor integration
- [x] Lower right-pane minimum height guardrail to avoid aggregate overflow
- [x] Split Guide Library pane into nested vertical resizable panes (library list/actions + editor)
- [x] Reduce editor minimum text area height while keeping monospaced editor behavior
- [x] Rebuild macOS app target to confirm no SwiftUI regressions
- [ ] Manual visual smoke in short/tall Settings windows

## Review (Task 3B Layout Stabilization)
- Result: Stabilized Guides tab vertical layout by replacing the single stacked Guide Library content block with a nested `VSplitView`, and by rebalancing minimum heights (`mappingPane: 260`, `guideLibraryPane: 220`) so the right column no longer over-constrains short windows.
- Verification:
  - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (build succeeded)
- Risks/Follow-ups:
  - Manual UI smoke is still recommended to validate usability across different Settings window sizes and splitter positions.

## Task 3B UX Comfort Redesign Checklist
- [x] Keep root `Guides` tab architecture as `HSplitView` (left output models, right workspace with segmented mode)
- [x] Keep editor-first workspace mode (`Guides`) with persisted mode via `@AppStorage`
- [x] Keep dedicated mapping workspace (`Mapping`) with `Open in Editor` handoff action
- [x] Keep editor workspace as horizontal library/editor split with searchable guide library and monospaced markdown editor
- [x] Extend dirty-state guard coverage to workspace switching using existing discard/keep dialog flow
- [x] Increase global Settings minimum window size for practical markdown editing ergonomics
- [x] Update maintenance documentation (`AGENTS.md`) and lessons (`tasks/lessons.md`)
- [x] Re-run full unit suite and macOS app build
- [ ] Manual in-app UX smoke across resizing and editor/mapping transitions

## Review (Task 3B UX Comfort Redesign)
- Result: Completed. Guides settings now prioritizes real markdown editing space by separating workflows into explicit `Guides` and `Mapping` modes, preserving dirty-state protections, and enforcing a larger minimum Settings window footprint so editor + library panes stay usable.
- Verification:
  - `swift test` (80 tests passed)
  - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (build succeeded)
- Risks/Follow-ups:
  - Manual Settings-window UX smoke remains required to validate real-world comfort across resize ranges.

## Task 3B Horizontal Overflow Tuning Checklist
- [x] Diagnose horizontal clipping in `Guides` editor workspace after comfort redesign
- [x] Rebalance split width constraints (`outputModels`, library/editor split mins/maxes)
- [x] Remove conflicting rigid right-workspace minimum width constraint
- [x] Re-run full unit suite and macOS app build
- [ ] Manual in-app smoke focused on horizontal resizing/splitter extremes

## Review (Task 3B Horizontal Overflow Tuning)
- Result: Completed. Editor workspace no longer forces horizontal overflow under tight split/window combinations because split minima were reduced and conflicting parent minimum width was removed.
- Verification:
  - `swift test` (80 tests passed)
  - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (build succeeded)
- Risks/Follow-ups:
  - Manual resize smoke is still recommended for edge-case splitter positions in Settings.
