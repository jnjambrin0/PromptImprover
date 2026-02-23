#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
load_release_state

require_var RELEASE_BUILD_VERSION
require_var RELEASE_SHORT_VERSION

resolve_sparkle_bin

appcast_generator="$SPARKLE_BIN/generate_appcast"
[[ -x "$appcast_generator" ]] || die "Missing executable Sparkle generator at $appcast_generator"

mkdir -p "$UPDATES_DIR"
timeout_seconds="${APPCAST_TIMEOUT_SECONDS:-900}"
start_ts="$(date +%s)"

if [[ -n "${SPARKLE_PRIVATE_KEY_BASE64:-}" ]]; then
  log "Generating signed appcast using SPARKLE_PRIVATE_KEY_BASE64 (timeout ${timeout_seconds}s)."
  (
    echo "$SPARKLE_PRIVATE_KEY_BASE64" | base64 --decode | "$appcast_generator" --ed-key-file - "$UPDATES_DIR"
  ) &
else
  log "Generating signed appcast using Sparkle key from Keychain (timeout ${timeout_seconds}s)."
  (
    "$appcast_generator" "$UPDATES_DIR"
  ) &
fi
generator_pid="$!"

while kill -0 "$generator_pid" >/dev/null 2>&1; do
  elapsed="$(( $(date +%s) - start_ts ))"
  if (( elapsed > timeout_seconds )); then
    log "generate_appcast exceeded timeout (${timeout_seconds}s). Sending SIGTERM."
    kill "$generator_pid" >/dev/null 2>&1 || true
    sleep 2
    kill -9 "$generator_pid" >/dev/null 2>&1 || true
    wait "$generator_pid" 2>/dev/null || true
    die "generate_appcast timed out after ${timeout_seconds}s"
  fi
  sleep 1
done
set +e
wait "$generator_pid"
generator_status="$?"
set -e
if [[ "$generator_status" -ne 0 ]]; then
  die "generate_appcast failed with exit code $generator_status"
fi

elapsed_total="$(( $(date +%s) - start_ts ))"
log "generate_appcast completed in ${elapsed_total}s."

appcast_path="$UPDATES_DIR/appcast.xml"
[[ -f "$appcast_path" ]] || die "Expected appcast at $appcast_path"

"$SCRIPT_DIR/00_validate_invariants.sh" --require-current-in-appcast

write_release_state RELEASE_APPCAST_PATH "$appcast_path"
log "Signed appcast generated: $appcast_path"
