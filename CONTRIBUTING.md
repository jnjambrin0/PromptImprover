# Contributing to PromptImprover

Thanks for investing time in PromptImprover. This project is Open Source and welcomes contributions across code, docs, UX polish, testing, and release quality.

## Code of Conduct

All participation is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). Please read it before contributing.

## Ways to Contribute

- Fix reproducible bugs.
- Improve documentation and onboarding.
- Add or strengthen automated tests.
- Propose and implement focused UX or reliability improvements.

## Before You Start

1. Search existing [issues](https://github.com/jnjambrin0/PromptImprover/issues) and open pull requests.
2. For non-trivial work, open an issue (or comment on an existing one) before starting implementation.
3. Keep each change scoped to one problem statement.

## Development Setup

PromptImprover is a macOS SwiftUI app.

Prerequisites:
- macOS
- Xcode
- Optional for live smoke tests: locally installed/authenticated `codex` and/or `claude`

Core verification commands:

```bash
swift test
```

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project PromptImprover.xcodeproj \
  -scheme PromptImprover \
  -configuration Debug \
  -sdk macosx build
```

Optional live CLI smoke tests:

```bash
PROMPT_IMPROVER_RUN_CLI_SMOKE=1 swift test --filter CLISmokeTests
```

## Branching and Pull Request Process

1. Fork the repository and create a branch from `main`.
2. Implement a focused change set.
3. Run the verification commands above.
4. Update tests and documentation when behavior changes.
5. Open a pull request using the repository PR template.
6. Link the related issue (for example, `Closes #123`) when applicable.

## Quality Expectations

- Keep changes minimal and intentional.
- Avoid unrelated refactors in the same pull request.
- Include evidence for behavioral changes (tests, logs, screenshots for UI changes).
- Keep user-facing wording clear and professional.

## Review and Merge

- Maintainers review contributions on a best-effort basis.
- Feedback and change requests are part of normal review.
- PRs are merged when scope, quality, and verification are acceptable.

## Contributor License

By submitting a contribution, you agree that your contributions are provided under the same license as this repository: [Apache License 2.0](LICENSE).

PromptImprover currently does not require CLA or DCO sign-off.

