#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
reset_release_state

run_stage() {
  local label="$1"
  local start_ts end_ts elapsed
  shift
  start_ts="$(date +%s)"
  log "Starting stage: $label"
  "$@"
  end_ts="$(date +%s)"
  elapsed="$((end_ts - start_ts))"
  log "Completed stage: $label (${elapsed}s)"
}

run_stage "sync_feed_state" "$SCRIPT_DIR/05_sync_feed_state.sh"
run_stage "resolve_release_versions" "$SCRIPT_DIR/06_resolve_release_versions.sh"
run_stage "validate_invariants" "$SCRIPT_DIR/00_validate_invariants.sh"
run_stage "build_local_release" "$SCRIPT_DIR/11_build_local_release.sh"
run_stage "package_dmg_local" "$SCRIPT_DIR/21_package_dmg_local.sh"
run_stage "generate_signed_appcast" "$SCRIPT_DIR/30_generate_signed_appcast.sh"

if [[ "${SKIP_PUBLISH:-0}" != "1" ]]; then
  run_stage "publish_github" "$SCRIPT_DIR/40_publish_github.sh"
else
  log "SKIP_PUBLISH=1, skipping GitHub publication."
fi

log "Local release pipeline completed successfully."
