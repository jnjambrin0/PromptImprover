#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
load_release_state

require_cmd hdiutil
require_cmd codesign
require_cmd spctl
require_cmd xcrun

require_var RELEASE_EXPORTED_APP_PATH
require_var RELEASE_BUILD_VERSION
require_var DEVELOPER_ID_APPLICATION
require_var NOTARY_PROFILE

app_path="$RELEASE_EXPORTED_APP_PATH"
[[ -d "$app_path" ]] || die "Missing exported app: $app_path"

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

codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$dmg_path"

xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"

codesign --deep --strict --verify --verbose=2 "$app_path"
spctl --assess --type execute -vv "$app_path"

write_release_state RELEASE_DMG_PATH "$dmg_path"
log "DMG packaged, notarized, and stapled: $dmg_path"
