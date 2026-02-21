# Lessons Learned

Capture user corrections and prevention rules.

## Template
- Date:
- Context:
- Mistake pattern:
- Prevention rule:
- Verification:

## 2026-02-21
- Date: 2026-02-21
- Context: Task 2 Settings implementation shipped with user-reported regressions in CLI diagnostics, Models reactivity, and Guides layout.
- Mistake pattern: Assumed Settings bindings were sufficient without publishing the underlying settings state, and patched PATH only in provider runtime but not in local diagnostics/capability checks.
- Prevention rule: For any new settings editor, explicitly verify state publication/reactivity paths; for any local CLI invocation path (providers, health checks, capability detection), centralize env construction and run wrapper-based tests that require executable-directory PATH prepending.
- Verification: Added `CLIEnvironmentIntegrationTests`, reran `swift test` (55 passed), and reran macOS app build via `xcodebuild` (succeeded).
