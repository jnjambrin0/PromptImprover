#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
load_release_state

require_cmd "$XCODEBUILD_BIN"

archive_path="${ARCHIVE_PATH:-$REPO_ROOT/build/release/$APP_NAME.xcarchive}"
export_path="${EXPORT_PATH:-$REPO_ROOT/build/release/export}"
export_options_plist="${EXPORT_OPTIONS_PLIST:-$SCRIPT_DIR/export-options-developer-id.plist}"

mkdir -p "$(dirname "$archive_path")" "$export_path"

if [[ ! -f "$export_options_plist" ]]; then
  cat >"$export_options_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST
fi

"$XCODEBUILD_BIN" \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$archive_path" \
  archive

"$XCODEBUILD_BIN" \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options_plist"

app_path="$export_path/$APP_NAME.app"
[[ -d "$app_path" ]] || die "Exported app not found at $app_path"

write_release_state RELEASE_ARCHIVE_PATH "$archive_path"
write_release_state RELEASE_EXPORT_PATH "$export_path"
write_release_state RELEASE_EXPORTED_APP_PATH "$app_path"

log "Archive/export completed: $app_path"
