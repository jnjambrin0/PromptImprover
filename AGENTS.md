# PromptImprover Agent Knowledge Base

Last updated: 2026-02-21

## 1) Purpose
Use this file as the first read for any agent run in this repository. It summarizes the implementation context, non-negotiable constraints, current status, and next required validation.

## 1.1) Debug-First Change Protocol (Mandatory)
- For regressions or user-reported failures, do not implement fixes immediately.
- First pass must be diagnosis only:
  - reproduce,
  - gather concrete evidence (logs, command outputs, runtime env),
  - isolate root cause and affected code path,
  - propose the smallest viable fix.
- Do not introduce architecture-level complexity unless diagnosis proves a minimal fix is insufficient.
- Before coding, document:
  - root cause,
  - why previous behavior failed,
  - why chosen fix is minimal and sufficient,
  - what tests will prove it.
- After fixing, verify with targeted tests first, then broader smoke/build checks.

## 2) Source of Truth
- Product requirements: `PRD.md`
- Technical design: `ARCHITECTURE.md`
- Active execution state, checklist, and handoff: `TASKS.md`

If this file conflicts with `PRD.md`/`ARCHITECTURE.md`, follow those documents and then update this file.

## 3) Non-Negotiable Product Constraints
- App is macOS SwiftUI and orchestrates local CLIs only: `codex` and `claude`.
- No direct API integrations from the app.
- No history, no RAG/vector DB, no user-repo reads/writes outside per-run temp workspace.
- Per-run workspace is under `/tmp/PromptImprover/run-<uuid>/`.
- Codex must run with read-only CLI sandbox flag.
- Final user-visible output must be only the optimized prompt text.

## 4) Current Architecture Snapshot
- App/UI: `PromptImprover/App`, `PromptImprover/UI`
- Domain/contracts/errors: `PromptImprover/Core`
- Process execution and streaming buffers: `PromptImprover/Execution`
- CLI discovery/health: `PromptImprover/CLI`
- Providers/parsers: `PromptImprover/Providers`, `PromptImprover/Providers/Parsers`
- Workspace/templates: `PromptImprover/Workspace`, `PromptImprover/Resources/templates`
- Tests: `Tests/Unit`, fixtures in `Tests/Fixtures`

## 5) Current Project Status
- Current phase from `TASKS.md`: `Phase 4 - UI Integration + Run Lifecycle (in_progress)`.
- Implemented and verified:
  - Single-screen UI with input, tool/model pickers, Improve/Stop, output, Copy, status.
  - `PromptImproverViewModel` lifecycle with discovery gating, streaming, cancel/error handling.
  - Workspace + process runner + parsers + providers (Codex and Claude with fallback JSON path).
  - Codex provider hotfix: hybrid auth strategy (isolated `CODEX_HOME` first, automatic retry with inherited user environment when auth-like failure is detected).
  - Codex discovery hotfix: fallback now scans `~/.nvm/versions/node/<version>/bin/codex` to support `nvm` installs without relying on `current` symlink or GUI PATH.
  - Codex runtime env hotfix: provider prepends Codex executable directory to `PATH` so `#!/usr/bin/env node` wrappers can resolve `node` in GUI app environments.
  - Codex UX hotfix: intermediate stream deltas are suppressed; output field is populated only with final validated `optimized_prompt`.
  - UI editor fix: both `Input Prompt` and `Optimized Prompt` fields are scrollable; optimized output remains read-only via no-op binding (not disabled).
  - Claude provider hotfix: final extraction ignores stream `tool_use.input` payloads and validates only final result candidates before fallback JSON-schema run.
  - Claude streaming cleanup: parser tolerates `input_json_delta` but does not emit it as user-facing delta text.
  - Smoke test hardening: no silent pass on `schemaMismatch`/`toolExecutionFailed`; skip only for missing binary or explicit unauthenticated precondition.
  - Output contract hardening: accept only JSON object with exactly one key `optimized_prompt`; reject empty/fenced/prefixed outputs.
  - Added tests for parser chunk-splits, process timeout/cancel/stdout+stderr, contract strictness.
- Verified commands:
  - `xcodebuild` app build succeeds.
  - `swift test` passes.
  - `PROMPT_IMPROVER_RUN_CLI_SMOKE=1 swift test --filter CLISmokeTests` passed in this environment.

## 6) Pending Gate (Blocking Completion of Phase 4)
Manual Xcode UI smoke evidence is still required:
- Confirm streaming output updates while running (Claude flow; Codex is intentionally final-only in output field).
- Confirm Stop transitions to Cancelled and leaves no orphan process.
- Confirm Copy copies exact final prompt text.
- Confirm Improve is disabled with clear install message when selected tool is unavailable.

Do not mark Phase 4 done until these checks are confirmed and recorded in `TASKS.md`.

## 7) Decisions and Known Caveats
- App-level macOS sandbox is disabled by design to execute user-installed binaries.
- Timeout default is 120 seconds.
- `Process.terminationHandler` ordering caveat is accounted for.
- `NSPasteboard.clearContents()` then `setString(_:forType: .string)` is used for copy.
- Known pitfall (Codex): forcing `CODEX_HOME` to a temp workspace can hide valid auth cache and cause false unauthenticated runs.
- Decision (Codex): keep run isolation attempt, but auto-retry without overriding `CODEX_HOME` when auth failure is detected.
- Known pitfall (Codex discovery): when Codex is installed via `nvm`, GUI/non-interactive PATH may miss `nvm` bin paths; fallback now scans versioned `nvm` directories as mitigation.
- Known pitfall (Codex runtime): even with binary discovery, execution can fail with `env: node: No such file or directory` for node-based wrappers when GUI PATH lacks node. Provider now prepends executable directory to `PATH`.
- Known pitfall (Codex streaming UX): JSONL event text can contain intermediate reasoning-like content. Current behavior intentionally does not surface Codex deltas in the output field.
- Decision (UI output editor): avoid disabling `TextEditor` for read-only output because it can block scrolling on macOS; use read-only binding instead.
- Known pitfall (Claude): stream may include `assistant.tool_use.input` JSON fragments (`file_path`, etc.); these are not final output candidates.
- Decision (Claude): only accept final candidates from `structured_output`, `result` JSON payload, or JSON fallback run.
- Decision (Claude parser): do not surface `input_json_delta` in UI output.
- SwiftPM emits deprecation warnings for `swift-testing` on Swift 6 toolchains.
- Attempting to remove `swift-testing` currently fails in this environment with `missing required module '_TestingInternals'`, so dependency remains.
- Xcode warns that `Copy Templates` script has no declared outputs and runs every build (non-blocking).

## 8) Runbook for Next Agent
1. Read `PRD.md`, `ARCHITECTURE.md`, and `TASKS.md`.
2. Complete pending manual UI smoke checks (human-in-the-loop via Xcode).
3. Update `TASKS.md`:
   - mark Phase 4 done only if manual checks pass,
   - advance to Phase 5 checklist and acceptance validation.
4. Re-run:
   - `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build`
   - `swift test`
   - `PROMPT_IMPROVER_RUN_CLI_SMOKE=1 swift test --filter CLISmokeTests`
