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

## Storage Layout
- `Application Support/PromptImprover/`
  - `settings.json`
  - `model-mapping.json`
  - `guides/builtin/`, `guides/user/`, `guides/user/forks/`
  - `diagnostics/`
- `Caches/PromptImprover/`
  - `cli-discovery-cache.json`
  - `rag-index/`, `thumbnails/`
- `tmp/PromptImprover/`
  - per-run workspaces and transient files

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

## Sparkle Auto-Updates (Non-App-Store)
Prompt Improver now uses Sparkle 2 for "download once, update forever" updates outside the Mac App Store.

Implemented defaults:
- Sparkle keys are configured in `Config/Info.plist` (`SUFeedURL`, `SUPublicEDKey`).
- `SUFeedURL` and `SUPublicEDKey` are injected from target build settings:
  - `SPARKLE_FEED_URL`
  - `SPARKLE_PUBLIC_ED_KEY`
- Automatic checks are enabled (`SUEnableAutomaticChecks=YES`).
- Automatic downloads/installs are user-controllable (`SUAllowsAutomaticUpdates=YES`, `SUAutomaticallyUpdate=NO`).
- Signed feed enforcement is enabled (`SURequireSignedFeed=YES`, `SUVerifyUpdateBeforeExtraction=YES`).

### App UX
- App menu includes `Check for Updates…` wired to Sparkle.
- Settings now includes an `Updates` tab:
  - automatic check toggle,
  - automatic download/install toggle,
  - manual `Check for Updates…` button,
  - current version/build display.
- First-run reliability flow prompts users to move the app to `/Applications` (or fallback `~/Applications`) when launched from non-updatable locations.

### Important setup before first production release
1. Generate Sparkle keys:
```bash
<sparkle-bin>/generate_keys
```
2. Copy the printed public key into target build setting `SPARKLE_PUBLIC_ED_KEY` (Debug/Release).
3. Set your feed URL in target build setting `SPARKLE_FEED_URL` (Debug/Release), for example:
   - `https://jnjambrin0.github.io/PromptImprover/updates/stable/appcast.xml`
4. Keep your Sparkle private key off web hosts and only in trusted signing/release environments.
5. Run invariant validation before shipping:
```bash
scripts/release/00_validate_invariants.sh
```

### Local DMG + smoke (outside Xcode)
`Move and Relaunch` intentionally terminates the current process, so do not validate this flow from an Xcode-attached run.

1. Build a local test DMG:
```bash
scripts/dev/make_local_dmg.sh
```
2. Mount the DMG and copy `PromptImprover.app` out to `Downloads` (or any non-Applications path).
3. Launch that copied app from Finder/Terminal (not from Xcode) and validate:
   - move prompt appears,
   - `Move and Relaunch` relaunches from `/Applications` or `~/Applications`.
4. After relaunch, use `Check for Updates…`:
   - if `SPARKLE_FEED_URL` points to a non-existing appcast you will get a network/feed error (expected),
   - if `SPARKLE_PUBLIC_ED_KEY` is empty/invalid, release validation will fail before shipping (expected).

### What is "real Sparkle staging smoke"
It means testing updates against a real hosted staging feed and signed artifacts, not local placeholders:
1. Create a staging appcast URL (eg. GitHub Pages `updates/staging/appcast.xml`).
2. Set staging `SPARKLE_FEED_URL` in a staging build.
3. Publish two real signed/notarized DMGs to staging and run `generate_appcast`.
4. Install v1, run app from Applications, then update to v2 via Sparkle UI and verify release notes/delta behavior.

### Debug signing note (Library Validation / Hardened Runtime)
If you run local Debug builds with ad-hoc signing and Hardened Runtime, macOS may block loading Sparkle due library validation constraints. Use an Apple Development signing identity for local runs (recommended), or disable library validation for Debug only if strictly necessary.

## Release Pipeline (Local + CI)
Release scripts live in `scripts/release`:
- `00_validate_invariants.sh`
- `10_archive_export.sh`
- `20_package_dmg_notarize_staple.sh`
- `30_generate_signed_appcast.sh`
- `40_publish_github.sh`
- `release.sh`

Configuration lives in `scripts/release/release-config.env`.

Run full release pipeline:
```bash
scripts/release/release.sh
```

Dry run up to appcast generation (skip publishing):
```bash
SKIP_PUBLISH=1 scripts/release/release.sh
```

### Release invariants enforced
- `CFBundleVersion` must be numeric dotted (`x`, `x.y`, `x.y.z`) and strictly greater than highest published `sparkle:version`.
- `CFBundleIdentifier` must remain `com.jnjambrin0.PromptImprover`.
- `CFBundleShortVersionString` must be numeric dotted.
- Generated appcast item must match current build/short-version values.

### Distribution flow
1. Archive/export app (Developer ID).
2. Build signed DMG with `/Applications` symlink.
3. Notarize + staple DMG.
4. Verify signatures (`codesign`, `spctl`).
5. Generate signed appcast + deltas via `generate_appcast`.
6. Upload DMG to GitHub release and publish feed artifacts to GitHub Pages.

## Project Layout
- `PromptImprover/App`: app entry + view model + root view.
- `PromptImprover/UI`: SwiftUI components.
- `PromptImprover/Core`: models, errors, output contract.
- `PromptImprover/Execution`: process runner, streaming buffer, logging.
- `PromptImprover/Providers`: codex/claude providers + parsers.
- `PromptImprover/Workspace`: temp workspace creation + template loading.
- `PromptImprover/CLI`: CLI discovery + health checks.
- `PromptImprover/Updates`: Sparkle updater bridge/manager + install-location move flow.
- `PromptImprover/Resources/templates`: agent templates, guides, schema.
- `Tests/Unit`, `Tests/Fixtures`: test suite and parser fixtures.
- `scripts/release`: release scripts for invariants, notarized DMG packaging, appcast, and publishing.
- `TASKS.md`: mandatory run-state continuity and handoff file.

## License
Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
