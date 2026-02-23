# Runtime Guide Sources in PromptImprover

This document defines the canonical files and runtime data flow for prompt-guides and workspace inputs.

## Canonical files to maintain

Update these files when you want behavior changes to ship in the app bundle:

- `PromptImprover/Resources/templates/claude-4-6-prompt-guide.md`
- `PromptImprover/Resources/templates/gpt-5-2-prompt-guide.md`
- `PromptImprover/Resources/templates/gemini-3-0-prompt-guide.md`
- `PromptImprover/Resources/templates/AGENTS.md`
- `PromptImprover/Resources/templates/CLAUDE.md`

Notes:
- Runtime workspace copies only the template for the selected tool:
  - Codex runs: `AGENTS.md`
  - Claude runs: `CLAUDE.md` + `.claude/settings.json`
- Built-in guide content is resolved from bundle templates at runtime unless a fork exists.

## Canonical mapping source

Built-in output-model and guide mapping is defined in:

- `PromptImprover/Core/GuidesModels.swift`

Key sections:
- `GuidesDefaults.builtInTemplateByGuideID`
- `GuidesDefaults.builtInGuides`
- `GuidesDefaults.builtInOutputModels`

## Packaging reminder

Templates are copied into app resources by the Xcode project build script:

- `PromptImprover.xcodeproj/project.pbxproj` (shell script uses `rsync` from `PromptImprover/Resources/templates` to app `templates/` resources)

## Runtime guide resolution rules

At run time (`GuideDocumentManager.data(for:)`):

1. If guide is built-in and has a valid fork file, read fork content (`guides/user/forks/...` in Application Support).
2. If guide is built-in and has no fork, read directly from bundled template (`PromptImprover/Resources/templates/...` packaged into app bundle).
3. If guide is user-created, read from Application Support path in `GuideDoc.storagePath`.

This means built-in non-fork guide behavior tracks bundled templates directly on shipped builds.

## Model-facing runtime prompt (exact responsibility)

Prompt runtime text passed to CLI:
- always tells the model to read `INPUT_PROMPT.txt`,
- includes target output model explicitly (`targetDisplayName` + `targetSlug`),
- includes explicit ordered guide filenames (or states no guides are provided),
- does not reference `TARGET_MODEL.txt` or `RUN_CONFIG.json`.

## Workspace runtime files (exact responsibility)

Workspace is created under `/tmp/PromptImprover/run-<uuid>/`.

- `INPUT_PROMPT.txt`:
  - source: user prompt only
  - normalization: `\r\n` and `\r` converted to `\n`, then outer whitespace/newlines trimmed
  - no metadata mixed in
- `RUN_CONFIG.json`:
  - source: internal run metadata for local tracing/audit
  - not a model-facing dependency
  - fields:
    - `targetSlug`
    - `guideFilenamesInOrder`
- `guides/*.md`:
  - copied in strict order from `mappedGuides`
  - filenames: `guides/%03d-<sanitized-guide-id>.md`

## Operational implications

- To change built-in guide behavior in shipped app runs, edit canonical template files and rebuild/package.
- If a built-in guide is forked in Settings, fork content overrides bundled built-in content until reverted.
- Tool selection (`codex` vs `claude`) and output model selection are independent axes.
