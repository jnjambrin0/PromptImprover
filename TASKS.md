# Current Phase: Phase 4 - UI Integration + Run Lifecycle (in_progress)

## Phase 4 Checklist
- [x] Build single-screen UI with input editor, tool/model pickers, Improve/Stop buttons, read-only output, Copy button, and status indicator.
- [x] Implement `PromptImproverViewModel` run lifecycle: discovery, availability gating, streaming updates, completion/error/cancel transitions.
- [x] Enforce Improve disabled states: running, empty input, unavailable selected tool.
- [x] Map runtime errors to PRD-aligned user messages.
- [x] Implement clipboard copy using `NSPasteboard.general.clearContents()` + `setString(_:forType: .string)`.
- [x] Fix Codex auth regression: add hybrid execution strategy (`CODEX_HOME` isolated first, automatic retry with inherited user environment on auth failure).
- [x] Fix Claude false `schemaMismatch`: ignore `tool_use.input` as final output candidate and validate only final result candidates.
- [x] Remove streaming UI noise from Claude: tolerate `input_json_delta` without emitting it as user-visible delta.
- [x] Add provider behavior tests for Codex fallback/auth classification and Claude stream/fallback extraction.
- [x] Harden `CLISmokeTests` policy: do not silently pass on `schemaMismatch`/`toolExecutionFailed`; skip only for missing binary or explicit not-authenticated precondition.
- [x] Fix Codex discovery for `nvm` installs without `current` symlink by scanning `~/.nvm/versions/node/<version>/bin/codex` as fallback.
- [x] Fix Codex runtime env for node-based CLI wrappers: prepend Codex executable directory to `PATH` in provider runs.
- [x] Hide Codex intermediate stream deltas in UI output; show only final contract-validated prompt on completion.
- [ ] Run manual UI smoke in Xcode for AC3/AC4/AC5 evidence (streaming, stop/cancel, copy, disabled improve when tool missing).

## Testing (Action Required from You)
1. Run app in Xcode.
2. Select `Codex + GPT-5.2`, click `Improve`, and confirm output updates incrementally while running (AC4).
3. Start another run and click `Stop`; confirm status changes to `Cancelled` and no orphan process remains in debug console (AC5).
4. Complete one run, click `Copy`, paste in any text field, and confirm pasted text matches final optimized prompt exactly.
5. Force unavailable tool case (for example, remove `codex` from PATH in scheme env or test on machine without that binary) and confirm `Improve` is disabled with install message (AC3).
6. Paste back a pass/fail line for each check above.
7. Paste relevant Xcode console lines if any check fails.

## Project Phase Status
- Phase 1 - Project Foundation + Task Continuity: done
- Phase 2 - Workspace + Process Execution Core: done
- Phase 3 - Providers + Streaming Parsers: done
- Phase 4 - UI Integration + Run Lifecycle: in_progress
- Phase 5 - Testing, Docs, and Acceptance Validation: pending

## Notes / Decisions
- Locked decisions implemented: app-level sandbox disabled; CLI-only orchestration; no direct API integrations; no history/RAG; timeout default 120s.
- Output contract hardened to strict object shape: accept only JSON object with exactly one key `optimized_prompt` (string), then normalize/reject empty/fenced/prefixed output.
- Parser robustness implemented and tested for partial lines across chunks and malformed lines mixed with valid lines.
- `ProcessRunner` implements timeout and cancellation with terminate + kill fallback; tests cover timeout, cancellation, and stdout/stderr dual stream consumption.
- Root cause recorded (Codex): forcing `CODEX_HOME` to workspace can hide valid user credentials; fix is hybrid retry strategy (isolated first, then inherited home on auth failures).
- Codex discovery fix applied: fallback now scans versioned `nvm` directories (`~/.nvm/versions/node/<version>/bin/codex`) and no longer depends on `current` symlink.
- New diagnosis (Codex runtime): binary is a `#!/usr/bin/env node` wrapper; app runtime PATH may omit node location. Fix applied by prepending Codex executable directory to `PATH` when launching provider runs.
- UX decision applied (Codex): suppress `RunEvent.delta` emission to avoid showing model intermediate thinking; output field is now finalized only with `RunEvent.completed`.
- Root cause recorded (Claude): stream can include `tool_use.input` JSON (`file_path`, etc.); parsing that as final output caused premature `schemaMismatch` before fallback.
- `ClaudeStreamJSONParser` now emits only `text_delta` to UI; `input_json_delta` is tolerated but hidden.
- CLI smoke tests are env-gated via `PROMPT_IMPROVER_RUN_CLI_SMOKE=1`; current run passed for both Codex and Claude after smoke policy hardening.
- Additional targeted verification passed: `PROMPT_IMPROVER_RUN_CLI_SMOKE=1 swift test --filter CLISmokeTests.codexSmokeRun`.
- Apple docs findings (via MCP):
  - `Process.terminationHandler` is not guaranteed to be fully executed before `waitUntilExit()` returns.
  - `NSPasteboard.setString(_:forType:)` is the correct API for clipboard write after claiming/clearing pasteboard contents.
- Current non-blocking warnings:
  - SwiftPM warning: `swift-testing` deprecation on Swift 6 toolchains.
  - In this environment, removing `swift-testing` breaks tests with `missing required module '_TestingInternals'`, so dependency remains.
  - Xcode warning: `Copy Templates` run script has no declared outputs and runs every build.

## Phase History (Detailed)

### Phase 1 - Project Foundation + Task Continuity (done)
- [x] Create `TASKS.md` with phase structure and handoff format.
- [x] Scaffold architecture-aligned folders under `PromptImprover/` and `Tests/`.
- [x] Implement core domain files (`Models.swift`, `Errors.swift`, `Contracts.swift`).
- [x] Add bundled template files and schema under `PromptImprover/Resources/templates/`.
- [x] Add CLI discovery + health check skeleton (`CLIDiscovery`, `CLIHealthCheck`).
- [x] Wire app entry/root view away from scaffold `ContentView`.
- [x] Verification gate passed: app builds and template files present in app bundle resources.
- Phase 1 completed successfully; proceed to Phase 2.

### Phase 2 - Workspace + Process Execution Core (done)
- [x] Implement `WorkspaceManager` with per-run `/tmp/PromptImprover/run-<uuid>/` workspace.
- [x] Write runtime files: `INPUT_PROMPT.txt`, `TARGET_MODEL.txt`, `RUN_CONFIG.json`.
- [x] Copy templates + schema into each run workspace.
- [x] Implement `StreamLineBuffer` with `maxLineBytes` and `maxBufferedBytes` guards.
- [x] Implement `ProcessRunner` streaming stdout/stderr + timeout + cancel semantics.
- [x] Verification gate passed: unit tests for buffering/workspace behavior and app build.
- Phase 2 completed successfully; proceed to Phase 3.

### Phase 3 - Providers + Streaming Parsers (done)
- [x] Implement `CodexJSONLParser` with malformed-line tolerance.
- [x] Implement `ClaudeStreamJSONParser` for `text_delta` and tolerant `input_json_delta` handling.
- [x] Implement `CodexProvider` with `codex exec --json --ephemeral --sandbox read-only --skip-git-repo-check --output-schema --output-last-message -C ... -`.
- [x] Implement `ClaudeProvider` streaming run and fallback JSON-schema run path.
- [x] Enforce schema-based final extraction and contract normalization.
- [x] Verification gate passed: parser/provider tests and smoke runs (env-gated) executed.
- Phase 3 completed successfully; proceed to Phase 4.

### Phase 4 - UI Integration + Run Lifecycle (in_progress)
- [x] Main UI and run lifecycle integrated.
- [x] Error mapping and disabled state logic integrated.
- [x] Codex provider auth fallback fix implemented and covered by tests.
- [x] Claude provider final extraction fix implemented and covered by tests.
- [x] Claude parser UI-noise suppression implemented and covered by tests.
- [x] Smoke tests tightened to fail on real regressions.
- [x] Codex discovery updated for `nvm` versioned install path fallback.
- [x] Codex provider environment updated to include executable directory in `PATH` (fixes `env: node: No such file or directory`).
- [x] Codex provider no longer streams intermediate deltas into output field.
- [ ] Pending manual UI smoke evidence from Xcode for AC3/AC4/AC5.

### Phase 5 - Testing, Docs, and Acceptance Validation (pending)
- [x] SwiftPM tests target created and active (`Package.swift`).
- [x] Add `StreamLineBufferTests`.
- [x] Add `CodexJSONLParserTests`.
- [x] Add `ClaudeStreamJSONParserTests`.
- [x] Add `WorkspaceManagerTests`.
- [x] Add `OutputContractTests`.
- [x] Add `ProcessRunnerTests`.
- [x] Add `CLISmokeTests` (env-gated).
- [x] Fixtures added under `Tests/Fixtures`.
- [x] Docs added: `README.md`, `LICENSE`.
- [ ] Final acceptance validation AC1-AC6 requires completing Phase 4 manual UI smoke first.

## Handoff (Next Agent Run)
1. Next goal: collect manual UI smoke evidence from the user and close Phase 4; then move to Phase 5 acceptance closure.
2. Exact files to touch next: `TASKS.md`; `PromptImprover/App/RootView.swift` (only if UI smoke reveals issues); `PromptImprover/App/PromptImproverViewModel.swift` (only if UI smoke reveals lifecycle issues).
3. Exact commands:
- `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration Debug -sdk macosx build`
- `swift test`
- `PROMPT_IMPROVER_RUN_CLI_SMOKE=1 swift test --filter CLISmokeTests`
4. Success condition: manual smoke checks pass and are recorded in `TASKS.md`, then set `Phase 4 completed successfully; proceed to Phase 5.`
