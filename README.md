# Prompt Improver (macOS)

Prompt Improver is a native macOS SwiftUI app that improves prompts using local CLIs (`codex` and `claude`) in headless mode.

## MVP Features
- Single-screen UX.
- Input prompt editor.
- Tool picker (`Codex CLI`, `Claude Code`).
- Target output model picker driven by Settings → Guides (built-in + user-defined).
- Streaming output while running.
- Strict final output contract:
  - JSON schema `{ "optimized_prompt": "..." }`
  - rendered output is plain optimized prompt only.
- `Stop` cancellation and `Copy` output button.
- Guides settings:
  - import Markdown guides (`.md`) into local Application Support storage,
  - create/edit/delete output models (`displayName`, `slug`),
  - map ordered guide lists per output model.

## Safety Model
- No direct API integrations from the app.
- No user file-system reads/writes outside temporary run workspaces.
- Per-run temporary workspace under `/tmp/PromptImprover/run-<uuid>`.
- Codex runs with CLI read-only sandbox flag.

## Prerequisites
- macOS with Xcode installed.
- `codex` and/or `claude` installed and authenticated in Terminal.

## Build
```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project PromptImprover.xcodeproj \
  -scheme PromptImprover \
  -configuration Debug \
  -sdk macosx build
```

## Test
Unit tests and parser/workspace contract checks run via SwiftPM target:
```bash
swift test
```

Optional live smoke tests (executes real CLIs):
```bash
PROMPT_IMPROVER_RUN_CLI_SMOKE=1 swift test --filter CLISmokeTests
```

## Project Layout
- `PromptImprover/App`: app entry + view model + root view.
- `PromptImprover/UI`: SwiftUI components.
- `PromptImprover/Core`: models, errors, output contract.
- `PromptImprover/Execution`: process runner, streaming buffer, logging.
- `PromptImprover/Providers`: codex/claude providers + parsers.
- `PromptImprover/Workspace`: temp workspace creation + template loading.
- `PromptImprover/CLI`: CLI discovery + health checks.
- `PromptImprover/Resources/templates`: agent templates, guides, schema.
- `Tests/Unit`, `Tests/Fixtures`: test suite and parser fixtures.
- `TASKS.md`: mandatory run-state continuity and handoff file.
