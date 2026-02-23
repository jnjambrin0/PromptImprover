#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
load_release_state

require_cmd "$XCODEBUILD_BIN"
require_cmd codesign

mkdir -p "$LOCAL_DERIVED_DATA"

build_xcode_version_override_args
settings="$($XCODEBUILD_BIN -project "$PROJECT_FILE" -scheme "$SCHEME_NAME" -configuration "$CONFIGURATION" "${XCODE_VERSION_OVERRIDE_ARGS[@]}" -showBuildSettings)"
current_build="$(build_setting "CURRENT_PROJECT_VERSION" "$settings")"
short_version="$(build_setting "MARKETING_VERSION" "$settings")"

[[ -n "$current_build" ]] || die "Could not resolve CURRENT_PROJECT_VERSION"
[[ -n "$short_version" ]] || die "Could not resolve MARKETING_VERSION"

build_args=(
  -project "$PROJECT_FILE"
  -scheme "$SCHEME_NAME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$LOCAL_DERIVED_DATA"
)

if [[ -n "${LOCAL_MACOSX_DEPLOYMENT_TARGET:-}" ]]; then
  build_args+=(MACOSX_DEPLOYMENT_TARGET="$LOCAL_MACOSX_DEPLOYMENT_TARGET")
fi

build_args+=("${XCODE_VERSION_OVERRIDE_ARGS[@]}")

if [[ "${LOCAL_DISABLE_CODE_SIGNING:-1}" == "1" ]]; then
  build_args+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=
    DEVELOPMENT_TEAM=
  )
  log "Local release build: code signing disabled (LOCAL_DISABLE_CODE_SIGNING=1)."
fi

"$XCODEBUILD_BIN" "${build_args[@]}" build

app_path="$LOCAL_DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
[[ -d "$app_path" ]] || die "Local release app not found at $app_path"

if [[ "${LOCAL_ADHOC_SIGN_APP:-1}" == "1" ]]; then
  log "Applying ad-hoc code signature to local release app (LOCAL_ADHOC_SIGN_APP=1)."
  codesign --force --deep --sign - "$app_path"
  codesign --verify --deep --strict --verbose=2 "$app_path"
fi

write_release_state RELEASE_BUILD_VERSION "$current_build"
write_release_state RELEASE_SHORT_VERSION "$short_version"
write_release_state RELEASE_EXPORTED_APP_PATH "$app_path"

log "Local release build completed: $app_path"
