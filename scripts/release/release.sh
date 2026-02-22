#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
reset_release_state

"$SCRIPT_DIR/00_validate_invariants.sh"
"$SCRIPT_DIR/10_archive_export.sh"
"$SCRIPT_DIR/20_package_dmg_notarize_staple.sh"
"$SCRIPT_DIR/30_generate_signed_appcast.sh"

if [[ "${SKIP_PUBLISH:-0}" != "1" ]]; then
  "$SCRIPT_DIR/40_publish_github.sh"
else
  log "SKIP_PUBLISH=1, skipping GitHub publication."
fi

log "Release pipeline completed successfully."
