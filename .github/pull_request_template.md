## Summary

Describe the change and why it is needed.

## Related Issues

Link related issues (for example, `Closes #123`).

## Current Behavior

Describe current behavior before this PR (if relevant).

## New Behavior

Describe behavior after this PR.

## Verification

Provide verification evidence (commands and key results):

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

Optional smoke tests:

```bash
PROMPT_IMPROVER_RUN_CLI_SMOKE=1 swift test --filter CLISmokeTests
```

## Checklist

- [ ] Scope is focused and avoids unrelated refactors.
- [ ] Tests were added/updated when behavior changed.
- [ ] Documentation was updated when user-visible behavior changed.
- [ ] UI changes include screenshots or short recordings.
- [ ] Security-sensitive changes considered [SECURITY.md](https://github.com/jnjambrin0/PromptImprover/blob/main/SECURITY.md) implications.

## Reviewer Notes

Add context that will help maintainers review quickly (tradeoffs, follow-ups, known limits).
