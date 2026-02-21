# PromptImprover Agent Guide

Last updated: 2026-02-21

## Purpose
This file is the single shared reference for code agents working in this repository. Keep it current, concise, and practical.

## Project Snapshot
- Product: macOS SwiftUI app that improves prompts using local CLIs.
- Supported tools: `codex`, `claude`.
- UX: single screen with input editor, tool/model pickers, `Improve` / `Stop`, read-only output, `Copy`, status/error text.
- Status: MVP complete and validated (automated + manual smoke).
- Current phase: Task 2 settings UX + runtime hardening shipped. Task 3 guide CRUD is pending.

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
- Engine model/effort are runtime execution settings (provider invocation), distinct from target model selection (prompt-guide selection).
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
    - `Guides`: `NavigationSplitView` placeholder scaffold with tool-scoped sidebar/detail state for upcoming Task 3 guide management.
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
