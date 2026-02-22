# PromptImprover Agent Guide

Last updated: 2026-02-22

## Purpose
This file is the single shared reference for code agents working in this repository. Keep it current, concise, and practical.

## Project Snapshot
- Product: macOS SwiftUI app that improves prompts using local CLIs.
- Supported tools: `codex`, `claude`.
- UX: single screen with input editor, tool picker, target output-model picker, `Improve` / `Stop`, read-only output, `Copy`, status/error text.
- Status: MVP complete and validated (automated + manual smoke).
- Current phase: Task 3A guides CRUD + output-model mapping shipped, including Guides settings layout stabilization. Task 3 follow-on UX refinements are pending.

## Core Rules
- CLI orchestration only. No direct API integrations from the app.
- No chat history, no RAG/vector DB, no user-repo access outside the run workspace.
- Per-run workspace under `/tmp/PromptImprover/run-<uuid>/` with best-effort cleanup.
- Final user-visible output must be contract-validated prompt text only.
- Contract: accept only JSON object with exactly one key: `optimized_prompt` (non-empty string).
- Reject fenced output, prefixed wrappers, empty content, or schema-mismatched payloads.

## Architecture Map
- App/UI: `PromptImprover/App`, `PromptImprover/UI`
- Domain/contracts/errors: `PromptImprover/Core`
- Execution/buffers/process: `PromptImprover/Execution`
- Providers/parsers: `PromptImprover/Providers`, `PromptImprover/Providers/Parsers`
- CLI discovery/health: `PromptImprover/CLI`
- Settings/capability persistence: `PromptImprover/Core` (settings stores), `PromptImprover/CLI` (capability detector/cache)
- Workspace/templates: `PromptImprover/Workspace`, `PromptImprover/Resources/templates`
- Tests/fixtures: `Tests/Unit`, `Tests/Fixtures`

## Build and Test
- Build app:
  - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build`
- Run unit tests:
  - `swift test`
- Run live CLI smoke tests (env-gated):
  - `PROMPT_IMPROVER_RUN_CLI_SMOKE=1 swift test --filter CLISmokeTests`

## Research Tooling
- MCP `apple-docs` is available and should be preferred for Apple framework APIs (SwiftUI/AppKit/Foundation), platform compatibility, WWDC references, and modern API alternatives.
- MCP `Context7` is available and should be preferred for third-party library/framework documentation and up-to-date usage patterns.
- For new libraries or complex features, use these tooling sources first before relying on memory-only implementation details.

## Workflow Orchestration
### 1) Plan Mode by Default
- Use plan mode for any non-trivial task (3+ steps, cross-file changes, or design decisions).
- If execution deviates from plan, stop and re-plan before continuing.
- Include verification in the plan, not only implementation.
- Write explicit specs up front when requirements are ambiguous.

### 2) Subagent Strategy
- Use subagents liberally to keep main context focused.
- Offload research, exploration, and parallel analysis to subagents.
- For complex issues, parallelize independent investigations.
- Keep one clear objective per subagent.

### 3) Self-Improvement Loop
- After any user correction, update `tasks/lessons.md` with the mistake pattern and prevention rule.
- Turn repeated mistakes into explicit guardrails.
- Review relevant lessons at the start of each new session.

### 4) Verification Before Done
- Never mark work complete without evidence.
- Compare behavior before/after when regression risk exists.
- Run tests, inspect logs, and demonstrate correctness.
- Apply a staff-level quality bar before handoff.

### 5) Demand Elegance (Balanced)
- For non-trivial changes, pause and evaluate whether a cleaner design exists.
- Replace hacky patches with the most maintainable solution that fits scope.
- Avoid over-engineering simple fixes.

### 6) Autonomous Bug Fixing
- For bug reports, diagnose and fix end-to-end without unnecessary user context switching.
- Use logs, failing tests, and reproduction evidence to drive fixes.
- Resolve failing CI-equivalent checks when possible.

## Task Management
1. Plan first: write a checklist in `tasks/todo.md`.
2. Verify plan: confirm approach before implementation.
3. Track progress: mark checklist items as completed as you execute.
4. Explain changes: keep high-level rationale visible during execution.
5. Document results: add a short review/outcome section to `tasks/todo.md`.
6. Capture lessons: update `tasks/lessons.md` after corrections.

## Key Implementation Decisions
- App-level sandbox remains disabled to execute user-installed CLIs reliably.
- Default run timeout: 120 seconds.
- Clipboard copy uses `NSPasteboard.clearContents()` + `setString(_:forType: .string)`.
- Output editor is read-only via no-op binding (not `.disabled`) to preserve scroll behavior.
- `TextEditor` fields use `writingToolsBehavior(.disabled)` to reduce macOS Writing Tools noise.
- Engine settings and capability cache persist separately under `~/Library/Application Support/PromptImprover/`:
  - `engine_settings.json`
  - `tool_capabilities.json`
  - `guides_catalog.json`
  - `guides/` (imported user markdown guides)
- Engine model/effort are runtime execution settings (provider invocation), distinct from target output-model selection (guide mapping selection).
- Branding/UI defaults:
  - Accent color is amber with light/dark variants from `AccentColor.colorset`.
  - Improve CTA uses `.borderedProminent` + SF Symbol `wand.and.stars` (avoids prior custom-icon rendering issues).
  - Stop button uses `.bordered`.
  - Input/output editor borders use subtle accent stroke when non-empty.
  - Streaming indicator uses accented `ProgressView`.

## Provider Pitfalls and Fixes
- Codex auth:
  - Running with isolated `CODEX_HOME` can hide valid credentials.
  - Implemented strategy: isolated attempt first, retry with inherited environment on auth-like failure.
- Codex discovery/runtime:
  - Added fallback scan for `~/.nvm/versions/node/<version>/bin/codex`.
  - Prepend codex executable directory to `PATH` for node-based wrappers (`env: node: No such file or directory` case).
- Codex output UX:
  - Do not show intermediate Codex deltas in output field; only final validated result.
- Claude stream parsing:
  - Ignore `tool_use.input` payloads as final candidates.
  - Accept final candidates from structured result paths only; fallback schema run when needed.
  - Tolerate `input_json_delta` but do not surface it to UI.

## Known Console Noise (Non-blocking)
These logs have been observed and are treated as system/framework noise unless paired with functional breakage:
- `NSViewBridgeErrorCanceled`
- `Unable to obtain a task name port right ... (0x5)`
- `AFIsDeviceGreymatterEligible Missing entitlements for os_eligibility lookup`
- `Unable to create bundle at URL ((null))`
- `IconRendering.framework ... binary.metallib invalid format`

## Expected Debug Logs
- `[PromptImprover] Run config ...` is expected in `DEBUG` builds (from `Logging.debug`) and is not an error by itself.

## Debug-First Protocol (Mandatory)
For regressions or user-reported failures:
1. Reproduce first.
2. Gather concrete evidence (app logs, command output, runtime env).
3. Isolate root cause and affected path.
4. Propose minimal fix.
5. Verify with targeted tests, then broader smoke/build checks.

Do not add architecture-level complexity unless evidence proves minimal fixes are insufficient.

## Core Principles
- Simplicity first: keep changes as small and local as possible.
- No laziness: find root causes; avoid temporary or cosmetic fixes.
- Minimal impact: modify only what is required and protect adjacent behavior.

## Maintenance Rule
When behavior changes, update this file in the same change:
- What changed
- Why it changed
- How it was verified
- Any durable caveats for future agents

## Maintenance Update (2026-02-21)
- What changed:
  - Added persisted per-tool engine settings (`defaultEngineModel`, `defaultEffort`, ordered `customEngineModels`, `perModelEffortAllowlist`) with schema-versioned JSON storage.
  - Added local-only capability detection + cache keyed by binary signature (`path`, `versionString`, `mtime`, `size`; with `lastCheckedAt` metadata) and invalidation on signature change.
  - Added reusable effort gating logic in the model layer and non-visual hooks in `PromptImproverViewModel` for resolved engine models/defaults/effective efforts.
- Why it changed:
  - Implement Task 1A requirements for configurable engine model/effort settings and deterministic local capability handling without remote probing.
- How it was verified:
  - `swift test` (42 tests passed, including new settings/cache/gating coverage).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Capability detection intentionally only executes local `--version`/`--help` commands.
  - Codex effort support falls back to a local version map (`>= 0.104.0`) when explicit help evidence is absent.
  - Capability cache invalidation never mutates or clears user engine settings (separate persistence files).
  - Task 1A keeps model/effort configuration controls out of the UI; those editors are expected in a later UI-focused task.

## Maintenance Update (2026-02-21, Visual Branding)
- What changed:
  - App icon set populated with generated PNGs for required macOS icon slots in `AppIcon.appiconset`.
  - `AccentColor.colorset` updated to amber brand palette with explicit light/dark values.
  - Added `ToolbarIcon.imageset` with template rendering intent.
  - Updated UI styling:
    - Improve button switched to `Label("Improve", systemImage: "wand.and.stars")` + `.borderedProminent`.
    - Stop button now explicitly `.bordered`.
    - Input/output editor borders now accent when content exists.
    - Streaming indicator uses a `ProgressView` in the output panel.
- Why it changed:
  - Improve visual consistency and make key actions/state transitions more visible while preserving existing workflow and behavior.
- How it was verified:
  - `swift test` (42 tests passed).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - `ToolbarIcon.imageset` exists as an asset but is not yet wired to a toolbar item in code.

## Maintenance Update (2026-02-21, Task 1B Runtime Engine Wiring)
- What changed:
  - `RunRequest` now carries optional `engineModel` and `engineEffort` values resolved at run start.
  - `PromptImproverViewModel.improve()` now resolves effective engine model/effort from persisted settings plus cached capabilities and logs effective run config in debug builds.
  - `CodexProvider` now appends `--model <engineModel>` and `-c model_reasoning_effort=<effort>` when present.
  - `ClaudeProvider` now appends `--model <engineModel>` for both stream and fallback JSON runs.
  - `WorkspaceManager` now conditionally writes `.claude/settings.json` `effortLevel` inside each ephemeral run workspace for Claude runs with an effective effort.
  - Added regression tests covering Codex/Claude effective args and workspace effort file behavior.
- Why it changed:
  - Implement Task 1B so engine settings influence real CLI invocation while preserving streaming behavior and strict final-output contract validation.
- How it was verified:
  - `swift test --filter "ProviderBehaviorTests|WorkspaceManagerTests|EffortGatingTests"` (19 tests passed).
  - `swift test` (48 tests passed).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Target model selection remains a separate concept from engine model and continues to drive prompt-guide selection.
  - Effort is only passed when pre-resolved/gated by settings allowlist and capability support.
  - Claude effort is applied via project-scoped `.claude/settings.json` with key `effortLevel`; invalid/missing workspace settings are safely replaced with a minimal JSON object for the run.

## Maintenance Update (2026-02-21, Task 2 Settings Window)
- What changed:
  - Added native macOS `Settings` scene in `PromptImproverApp` with two tabs:
    - `Models`: per-tool ordered engine model list CRUD/reorder, default model picker, default effort picker, per-model effort allowlist toggles, capability status (binary path/version/last-checked), local `Recheck`, and per-tool `Reset to defaults`.
    - `Guides`: placeholder scaffold with tool-scoped sidebar/detail state for upcoming Task 3 guide management (later stabilized to `HSplitView` in regression fixes).
  - Moved app-wide `PromptImproverViewModel` ownership to `PromptImproverApp` (`@StateObject`) and injected into both root window and settings to keep settings/main-run state synchronized.
  - Extended engine settings model with additive `orderedEngineModels` override plus deterministic mutators/reset helpers; existing `customEngineModels` remains for backward compatibility.
  - Extended capability cache API with cached-entry retrieval (`CachedToolCapabilities`) and `forceRefresh` support while preserving existing `capabilities(...)` wrapper.
  - Added background queue execution for settings persistence and CLI diagnostics/capability recheck to avoid blocking main thread.
  - Added tests:
    - `EngineSettingsMutationTests` for ordered override precedence, pruning invariants, and per-tool reset behavior.
    - `EngineSettingsStoreTests` coverage for ordered override round-trip.
    - `ToolCapabilityCacheTests` coverage for forced refresh + refreshed `lastCheckedAt`.
- Why it changed:
  - Implement Task 2 requirements for native settings UX, persisted engine configuration controls, and local capability visibility/recheck without changing active-run behavior.
- How it was verified:
  - `swift test` (53 tests passed).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Settings edits apply to new runs only; in-flight runs continue using the `RunRequest` snapshot resolved at run start.
  - Capability recheck remains strictly local (`--version`/`--help`) and does not use network probing.
  - `orderedEngineModels` is authoritative when set; legacy files without it still resolve via `seed + custom`.
  - Guides tab is a placeholder scaffold and intentionally omits guide CRUD/editing.

## Maintenance Update (2026-02-21, Task 2 Regression Stabilization)
- What changed:
  - Added `CLIExecutionEnvironment` helper and applied it to `CLIHealthCheck` and `ToolCapabilityDetector` so diagnostics/capability checks always prepend the selected executable directory to `PATH`.
  - Marked `PromptImproverViewModel.engineSettings` as `@Published` to restore immediate Settings UI refresh for model picker, effort picker, allowlist toggles, and model list mutations.
  - Replaced `GuidesSettingsView` `NavigationSplitView` with `HSplitView` scaffold to avoid Settings-tab layout/chrome conflicts.
  - Added `CLIEnvironmentIntegrationTests` to verify env-wrapped executables work for both version health checks and help-based capability detection.
- Why it changed:
  - Fix user-reported Task 2 regressions: `env: node: No such file or directory` in capability status, non-reactive Models controls, and unstable Guides tab layout in native Settings.
- How it was verified:
  - `swift test` (55 tests passed, including new CLI env integration tests).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Framework-private console logs (`AFIsDeviceGreymatterEligible...`, `IconRendering...binary.metallib...`) are still treated as non-blocking noise unless accompanied by functional issues.
  - Settings edits continue to apply only to new runs, never to in-flight runs.

## Maintenance Update (2026-02-21, Runtime Hardening Pass)
- What changed:
  - Added timeout-bounded local command execution for CLI diagnostics/discovery via `CLILocalCommandRunner` (`stdout`/`stderr`/status + timeout result).
  - Updated `CLIDiscovery`, `CLIHealthCheck`, and `ToolCapabilityDetector` to use the new local runner instead of unbounded `waitUntilExit()` calls.
  - Extended discovery fallback candidates to include `nvm` versioned Claude binaries (`~/.nvm/versions/node/<version>/bin/claude`).
  - Added PATH patching parity for Claude runtime execution by prepending the executable directory (same strategy already used by Codex); Codex now uses shared PATH helper directly.
  - Added regression coverage:
    - `CLIDiagnosticsHardeningTests` (discovery timeout fallback, health-check timeout behavior, capability timeout fallback behavior).
    - `ProviderBehaviorTests` coverage for Claude PATH patching.
- Why it changed:
  - Reduce operational risk from local process hangs and environment discrepancies (especially Node-wrapper CLIs) while preserving existing app UX and run semantics.
- How it was verified:
  - `swift test` (59 tests passed).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Timeout handling is defensive and returns safe degraded capability metadata when local help/version commands do not complete.
  - Manual Finder-context smoke is still recommended for host-specific shell/env differences.

## Maintenance Update (2026-02-21, Concurrency Warning Cleanup)
- What changed:
  - Fixed Swift concurrency warnings in `PromptImproverViewModel.refreshAvailability(...)` by avoiding direct capture of non-Sendable `CLIDiscovery` and `CLIHealthCheck` instances inside `diagnosticsQueue.async` closures.
  - Wrapped those values in existing `UncheckedSendableBox` before capture, matching the same local pattern already used for capability store capture.
- Why it changed:
  - Remove compile-time warning noise and keep diagnostics path compliant with stricter `@Sendable` closure checks without changing runtime behavior.
- How it was verified:
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (warning removed from `PromptImproverViewModel.swift`).
  - `swift test` (59 tests passed).
- Durable caveats:
  - When dispatching work to concurrent queues, avoid capturing new non-Sendable types directly; use value snapshots or explicit sendable wrappers.

## Maintenance Update (2026-02-21, Task 3A Guides Mapping + Persistence)
- What changed:
  - Added guides domain and persistence:
    - `OutputModel { displayName, slug, guideIds[] }`
    - `GuideDoc { id, title, storagePath, isBuiltIn, updatedAt, hash? }`
    - `GuidesCatalog` reconciliation helpers and `GuidesCatalogStore` (`guides_catalog.json`, schema versioned).
  - Added `GuideDocumentManager` for local guide import/resolve/delete with strict import validation:
    - markdown-only (`.md`)
    - max size 1 MiB
    - UTF-8 required
    - user guides stored under Application Support `guides/`.
  - Replaced hardcoded target model run path with persisted output model selection:
    - main picker now uses persisted output models (built-in + user-defined),
    - `RunRequest` now carries `targetSlug`, `targetDisplayName`, ordered `mappedGuides` snapshot.
  - Upgraded workspace assembly:
    - static templates remain (`AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, schema),
    - only mapped guides are copied into `guides/` in deterministic order,
    - `RUN_CONFIG.json` now records `{ targetSlug, guideFilenamesInOrder }`.
  - Updated provider run prompt instructions to consume `RUN_CONFIG.json` ordered guide filenames.
  - Implemented full Settings → Guides UI:
    - output model CRUD (display name + slug),
    - guide import/delete (built-ins read-only),
    - ordered multi-guide assignment + reorder per output model,
    - reset built-in output models and built-in mappings while preserving user entries.
  - Added Gemini built-in guide template: `GEMINI3_PROMPT_GUIDE.md` and wired Xcode template-copy script paths.
  - Added/updated tests:
    - `GuidesCatalogMutationTests`
    - `GuidesCatalogStoreTests`
    - `GuideDocumentManagerTests`
    - updated `WorkspaceManagerTests`, `ProviderBehaviorTests`, and `CLISmokeTests` for new run request/mapping behavior.
- Why it changed:
  - Implement Task 3A end-to-end: persistent guides management, ordered output-model mappings, and runtime workspace integration that is independent from execution tool selection.
- How it was verified:
  - `swift test` (74 tests passed).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Guides content editing remains out of scope; Task 3A supports import/mapping/persistence/runtime copy only.
  - Settings edits continue to apply only to new runs, never in-flight runs.
  - Guide deletion auto-unassigns mapping references (chosen policy), while built-in guides remain non-deletable.

## Maintenance Update (2026-02-22, Guides Settings Layout Stabilization)
- What changed:
  - Reworked the right column of `Settings → Guides` to avoid clipped content in shorter windows.
  - Replaced the fixed stacked right panel with a vertical split:
    - container now uses `VSplitView` (top `Guide Mapping`, bottom `Guide Library`),
    - both panes are resizable by the user.
  - Reduced rigid list minimum heights and allowed each list to expand/contract within its pane (`maxHeight: .infinity`).
- Why it changed:
  - Fix user-reported UI regression where right-pane content exceeded available vertical space and became partially inaccessible.
- How it was verified:
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Pane minimum heights (`260` for mapping, `220` for library) are intentional guardrails for control usability; adjust together if the pane contents change materially.

## Maintenance Update (2026-02-22, Task 3B In-App Guide Editor + Built-In Forking)
- What changed:
  - Extended guides model/storage with built-in fork support:
    - `GuideDoc` now includes optional `forkStoragePath`.
    - `GuideDocumentManaging` now supports `loadText`, `ensureEditableGuide`, `saveText`, `revertBuiltInFork`, and `hasFork`.
  - Updated `GuideDocumentManager` behavior:
    - guide file writes now use `AtomicJSONStore.write(...)` (temp + replace) for atomic persistence.
    - built-in guides now resolve content from fork file when `forkStoragePath` exists and the file is present, otherwise from bundled template.
    - built-in `Edit` now creates deterministic local forks under `guides/forks/<guide-id>.md`.
    - save updates `updatedAt` and SHA-256 `hash`; revert removes fork file and clears `forkStoragePath`.
  - Added guide editor APIs in `PromptImproverViewModel`:
    - `loadGuideText(id:)`
    - `beginGuideEdit(id:)`
    - `saveGuideText(id:text:)`
    - `revertGuideToBuiltIn(id:)`
    - `guideHasFork(id:)`
    - save/revert use synchronous catalog persistence to reduce metadata-loss risk.
  - Implemented Settings → Guides markdown editor UX:
    - selecting a guide opens editor content in a monospaced `TextEditor`.
    - built-in guides are read-only until `Edit` forks locally.
    - actions: `Save`, `Discard`, `Revert to built-in` (when fork exists), and explicit `Close Editor`.
    - dirty-state confirmation added for guide switch and close-editor transitions.
  - Added tests for Task 3B scenarios:
    - `GuideDocumentManagerTests`: fork creation, save metadata updates, revert behavior, fork resolution precedence, atomic-save temp cleanup.
    - `WorkspaceManagerTests`: mapped built-in guide copies fork content when fork exists.
    - `GuidesCatalogStoreTests`: `forkStoragePath` round-trip and backward-compatible decode when absent.
- Why it changed:
  - Implement Task 3B requirements for in-app guide editing while preserving bundle immutability for built-in guides and maintaining reliable, file-based runtime guide handoff.
- How it was verified:
  - `swift test` (80 tests passed).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Unsaved-change confirmation is scoped to guide switch and explicit editor close, not Settings-window close interception.
  - Runtime prompt contract remains unchanged: guide content is still consumed from workspace files (`RUN_CONFIG.json` + copied `guides/*`), never inlined into provider prompt text.

## Maintenance Update (2026-02-22, Task 3B Guides Height Regression Stabilization)
- What changed:
  - Refined `Settings → Guides` right-column layout to prevent vertical clipping after adding the in-app editor:
    - kept top-level right side as `VSplitView` with `mappingPane` min height `260` and `guideLibraryPane` min height `220`.
    - changed `guideLibraryPane` from one stacked `VStack` into a nested `VSplitView` with two resizable panes:
      - library list/actions pane
      - editor pane
    - reduced editor `TextEditor` minimum height from `170` to `120` and kept list sizing flexible (`minHeight: 120`, `maxHeight: .infinity`).
- Why it changed:
  - User-reported regression: right-side content could exceed available window height, clipping library/editor content and hiding controls.
- How it was verified:
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - The nested split is intentional to preserve access to both list and editor in short windows; avoid returning to a single fixed vertical stack for these sections.

## Maintenance Update (2026-02-22, Task 3B UX Comfort Redesign)
- What changed:
  - Reoriented `Settings → Guides` around an editor-first workflow with explicit workspace modes:
    - right workspace now uses a persisted segmented mode (`Guides` / `Mapping`) and defaults to `Guides`.
    - `Guides` mode uses a horizontal split between `Guide Library` and `Guide Editor` to prioritize markdown editing space.
    - `Mapping` mode is isolated from editing and includes `Open in Editor` handoff.
  - Preserved and extended unsaved-change guardrails:
    - existing discard/keep dialog now also gates `Guides -> Mapping` workspace switches when editor content is dirty.
  - Improved practical editing ergonomics:
    - raised global Settings minimum size to `1100x700` in `SettingsRootView`.
    - rebalanced split width constraints to keep a comfortably sized editor pane and avoid output-model controls starving editor width.
- Why it changed:
  - User-reported UX issue after height stabilization: content was no longer clipped, but working areas remained too compressed for continuous markdown editing.
- How it was verified:
  - `swift test` (80 tests passed).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - The dominant workflow is intentionally editor-first; mapping is now a dedicated mode instead of a simultaneous stacked pane.
  - Workspace mode persistence uses `@AppStorage("settings.guides.workspace.mode")`; if mode taxonomy changes later, include migration handling.

## Maintenance Update (2026-02-22, Task 3B Horizontal Overflow Tuning)
- What changed:
  - Rebalanced horizontal width constraints in `GuidesSettingsView` to prevent editor content from clipping when split panes approach minimum sizes:
    - narrowed output-models pane bounds (`min: 250`, `ideal: 280`, `max: 340`).
    - removed rigid `minWidth` from right workspace container so child split can adapt without forcing overflow.
    - reduced editor-workspace split minimums (`library min: 250`, `editor min: 400`) and tightened library max width (`360`).
- Why it changed:
  - User-reported regression after comfort redesign: editor area could extend past visible bounds horizontally, clipping right-side controls/content.
- How it was verified:
  - `swift test` (80 tests passed).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Keep split-pane minimums internally consistent; avoid parent min-width constraints that are smaller than child aggregate minimums.

## Maintenance Update (2026-02-22, Task 3B Guides View Modularization)
- What changed:
  - Refactored the large `GuidesSettingsView` implementation into a dedicated feature folder:
    - `UI/Settings/Guides/GuidesSettingsView.swift` (root view + lifecycle/dialog wiring + stored state),
    - `UI/Settings/Guides/GuidesSettingsView+State.swift` (derived bindings/computed UI state),
    - `UI/Settings/Guides/GuidesSettingsView+Panes.swift` (layout and pane composition),
    - `UI/Settings/Guides/GuidesSettingsView+Actions.swift` (catalog/library CRUD actions),
    - `UI/Settings/Guides/GuidesSettingsView+EditorFlow.swift` (editor transitions, dirty guards, load/save/revert flow),
    - `UI/Settings/Guides/GuidesSettingsTypes.swift` (supporting UI types/enums).
  - Removed legacy monolithic file `UI/Settings/GuidesSettingsView.swift`.
- Why it changed:
  - Reduce maintenance risk and review complexity after Task 3B UX growth; the previous single-file view exceeded 1k lines and mixed layout/state/flow concerns.
- How it was verified:
  - `swift test` (80 tests passed).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - The refactor is intentionally behavior-preserving; keep new Guides-related edits within the `UI/Settings/Guides/` slice to avoid recreating a monolithic view file.

## Maintenance Update (2026-02-22, Main Window Dead-Space Auto Sizing)
- What changed:
  - Removed the idle-state `Spacer` from `RootView` composer layout; this was the direct source of synthesized dead vertical space between input and bottom bar in compact mode.
  - Moved main-window sizing control to SwiftUI scene/content constraints instead of manual `NSWindow` orchestration:
    - main scene now uses `windowResizability(.contentSize)`,
    - `RootView` now declares state-bound height limits:
      - idle (`showOutput == false`): `minHeight 220`, `maxHeight 250`
      - output/running (`showOutput == true`): `minHeight 320`, `maxHeight 560`
  - Kept compact launch default size at `520x250` for new windows.
- Why it changed:
  - User-reported dead space persisted and prior manual window-control approach added unnecessary complexity. The root cause was layout elasticity in idle mode plus unconstrained scene sizing under restoration.
- How it was verified:
  - `swift test` (80 tests passed).
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Compact/expanded behavior is now defined by `RootView` height bounds and scene `contentSize` resizability; if future UX changes alter editor/panel heights, these bounds should be reviewed together.
  - This fix intentionally avoids direct `NSWindow` frame mutations to reduce maintenance complexity and animation-related regressions.

## Maintenance Update (2026-02-22, Main Screen Vertical Spacing Rebalance)
- What changed:
  - Rebalanced `composerArea` vertical padding in `RootView`:
    - top padding reduced from `16` to `8`,
    - bottom padding increased from `12` to `20`.
  - This shifts visual spacing from above the input editor to the area between the editor block and the bottom configuration bar.
- Why it changed:
  - User feedback indicated excess empty space from the top edge to the input field and insufficient separation between the input area and bottom controls.
- How it was verified:
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Keep top/bottom composer paddings tuned as a pair; adjusting only one side can reintroduce perceived imbalance in compact mode.

## Maintenance Update (2026-02-22, Output Model Picker Arrow/Cursor UX)
- What changed:
  - Updated `BottomBarView` output-model selector (`modelPicker`) interaction styling:
    - removed explicit chevron icon from the custom label content,
    - applied `.menuIndicator(.hidden)` to suppress native menu arrow affordance,
    - added hover pointer behavior (`NSCursor.pointingHand`) while selector is enabled.
- Why it changed:
  - User requested cleaner selector presentation (no right-side arrow) and explicit pointer cursor feedback on hover.
- How it was verified:
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Hover cursor uses push/pop semantics; if additional hover states are introduced nearby, keep cursor stack balance in mind.

## Maintenance Update (2026-02-22, Input Placeholder/Caret Alignment)
- What changed:
  - Adjusted empty-state placeholder in `InputEditorView` to align with `TextEditor` insertion caret:
    - replaced generic placeholder vertical inset (`.padding(.vertical, 16)`) with explicit top inset (`.padding(.top, 8)`),
    - kept leading inset at `13` to preserve horizontal text start alignment.
- Why it changed:
  - User-reported UI quality issue: caret and placeholder were visually misaligned in the empty input state.
- How it was verified:
  - `xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build` (succeeds).
- Durable caveats:
  - Placeholder/caret alignment depends on effective `TextEditor` content insets; if editor padding or font metrics change, revisit both placeholder top and leading insets together.
