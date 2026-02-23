#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
load_release_state

require_cmd hdiutil

require_var RELEASE_EXPORTED_APP_PATH
require_var RELEASE_BUILD_VERSION

app_path="$RELEASE_EXPORTED_APP_PATH"
[[ -d "$app_path" ]] || die "Missing local release app: $app_path"

ensure_dmgbuild

mkdir -p "$UPDATES_DIR"
dmg_path="$UPDATES_DIR/$APP_NAME-$RELEASE_BUILD_VERSION.dmg"

"$DMGBUILD" \
  -s "$DMG_ASSETS_DIR/dmg-settings.py" \
  -D app="$app_path" \
  -D background="$DMG_ASSETS_DIR/dmg-background.png" \
  "$APP_NAME" \
  "$dmg_path"

hdiutil verify "$dmg_path"

[[ -f "$dmg_path" ]] || die "Local release DMG was not generated: $dmg_path"

write_release_state RELEASE_DMG_PATH "$dmg_path"
log "Local release DMG packaged: $dmg_path"
