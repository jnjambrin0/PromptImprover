#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
load_release_state

require_var SPARKLE_BIN
require_var RELEASE_BUILD_VERSION
require_var RELEASE_SHORT_VERSION

appcast_generator="$SPARKLE_BIN/generate_appcast"
[[ -x "$appcast_generator" ]] || die "Missing executable Sparkle generator at $appcast_generator"

mkdir -p "$UPDATES_DIR"
"$appcast_generator" "$UPDATES_DIR"

appcast_path="$UPDATES_DIR/appcast.xml"
[[ -f "$appcast_path" ]] || die "Expected appcast at $appcast_path"

"$SCRIPT_DIR/00_validate_invariants.sh" --require-current-in-appcast

write_release_state RELEASE_APPCAST_PATH "$appcast_path"
log "Signed appcast generated: $appcast_path"
