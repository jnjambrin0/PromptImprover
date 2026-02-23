#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_CONFIG_FILE="${RELEASE_CONFIG_FILE:-$SCRIPT_DIR/release-config.env}"
RELEASE_STATE_FILE="${RELEASE_STATE_FILE:-$SCRIPT_DIR/.release-state.env}"

log() {
  printf '[release] %s\n' "$*"
}

die() {
  printf '[release] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_var() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    die "Missing required variable: $var_name"
  fi
}

resolve_sparkle_bin() {
  local candidate=""

  if [[ -n "${SPARKLE_BIN:-}" ]]; then
    candidate="$SPARKLE_BIN"
    if [[ "$candidate" != /* ]]; then
      candidate="$REPO_ROOT/$candidate"
    fi
  else
    candidate="$REPO_ROOT/build/local/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
    if [[ ! -x "$candidate/generate_appcast" ]]; then
      candidate="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
        -type d \
        -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin' \
        2>/dev/null | head -n 1 || true)"
    fi
  fi

  [[ -n "$candidate" ]] || die "Could not resolve SPARKLE_BIN. Set SPARKLE_BIN or run an Xcode build with Sparkle package dependencies first."
  [[ -x "$candidate/generate_appcast" ]] || die "Resolved SPARKLE_BIN does not contain generate_appcast: $candidate"

  SPARKLE_BIN="$candidate"
  export SPARKLE_BIN
}

load_release_config() {
  [[ -f "$RELEASE_CONFIG_FILE" ]] || die "Missing release config: $RELEASE_CONFIG_FILE"
  # shellcheck disable=SC1090
  source "$RELEASE_CONFIG_FILE"
  export PROJECT_FILE SCHEME_NAME CONFIGURATION APP_NAME EXPECTED_BUNDLE_IDENTIFIER
  export SPARKLE_FEED_URL UPDATES_DIR SPARKLE_BIN DEVELOPER_ID_APPLICATION
  export NOTARY_PROFILE GITHUB_REPOSITORY GITHUB_PAGES_BRANCH GITHUB_PAGES_PATH
  export XCODEBUILD_BIN LOCAL_DERIVED_DATA LOCAL_STAGE_ROOT
  export LOCAL_MACOSX_DEPLOYMENT_TARGET LOCAL_DISABLE_CODE_SIGNING LOCAL_ADHOC_SIGN_APP

  PROJECT_FILE="${PROJECT_FILE:-PromptImprover.xcodeproj}"
  SCHEME_NAME="${SCHEME_NAME:-PromptImprover}"
  CONFIGURATION="${CONFIGURATION:-Release}"
  APP_NAME="${APP_NAME:-PromptImprover}"
  EXPECTED_BUNDLE_IDENTIFIER="${EXPECTED_BUNDLE_IDENTIFIER:-com.jnjambrin0.PromptImprover}"
  SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://jnjambrin0.github.io/PromptImprover/updates/stable/appcast.xml}"
  UPDATES_DIR="${UPDATES_DIR:-$REPO_ROOT/updates/stable}"
  SPARKLE_BIN="${SPARKLE_BIN:-}"
  DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
  NOTARY_PROFILE="${NOTARY_PROFILE:-}"
  GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-jnjambrin0/PromptImprover}"
  GITHUB_PAGES_BRANCH="${GITHUB_PAGES_BRANCH:-gh-pages}"
  GITHUB_PAGES_PATH="${GITHUB_PAGES_PATH:-updates/stable}"
  XCODEBUILD_BIN="${XCODEBUILD_BIN:-/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild}"
  LOCAL_DERIVED_DATA="${LOCAL_DERIVED_DATA:-$REPO_ROOT/build/local/DerivedData}"
  LOCAL_STAGE_ROOT="${LOCAL_STAGE_ROOT:-$REPO_ROOT/build/local/dmg-root-release-local}"
  LOCAL_MACOSX_DEPLOYMENT_TARGET="${LOCAL_MACOSX_DEPLOYMENT_TARGET:-15.0}"
  LOCAL_DISABLE_CODE_SIGNING="${LOCAL_DISABLE_CODE_SIGNING:-1}"
  LOCAL_ADHOC_SIGN_APP="${LOCAL_ADHOC_SIGN_APP:-1}"
  DMG_ASSETS_DIR="${DMG_ASSETS_DIR:-$SCRIPT_DIR/dmg-assets}"
  export DMG_ASSETS_DIR

  if [[ "$PROJECT_FILE" != /* ]]; then
    PROJECT_FILE="$REPO_ROOT/$PROJECT_FILE"
  fi
  if [[ "$UPDATES_DIR" != /* ]]; then
    UPDATES_DIR="$REPO_ROOT/$UPDATES_DIR"
  fi

  export PROJECT_FILE SCHEME_NAME CONFIGURATION APP_NAME EXPECTED_BUNDLE_IDENTIFIER
  export SPARKLE_FEED_URL UPDATES_DIR SPARKLE_BIN DEVELOPER_ID_APPLICATION
  export NOTARY_PROFILE GITHUB_REPOSITORY GITHUB_PAGES_BRANCH GITHUB_PAGES_PATH
  export XCODEBUILD_BIN LOCAL_DERIVED_DATA LOCAL_STAGE_ROOT
  export LOCAL_MACOSX_DEPLOYMENT_TARGET LOCAL_DISABLE_CODE_SIGNING LOCAL_ADHOC_SIGN_APP

  mkdir -p "$UPDATES_DIR"
}

load_release_state() {
  if [[ -f "$RELEASE_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$RELEASE_STATE_FILE"
  fi
}

reset_release_state() {
  : >"$RELEASE_STATE_FILE"
}

write_release_state() {
  local key="$1"
  local value="$2"
  printf '%s=%q\n' "$key" "$value" >>"$RELEASE_STATE_FILE"
}

build_setting() {
  local key="$1"
  local settings="$2"
  awk -v target="$key" -F ' = ' '$1 ~ "[[:space:]]"target"$" { print $2; exit }' <<<"$settings"
}

ensure_dmgbuild() {
  local venv_dir="${DMGBUILD_VENV:-$REPO_ROOT/build/.dmgbuild-venv}"
  if [[ ! -x "$venv_dir/bin/dmgbuild" ]]; then
    log "Creating dmgbuild virtual environment at $venv_dir..."
    python3 -m venv "$venv_dir"
    "$venv_dir/bin/pip" install --quiet dmgbuild
  fi
  DMGBUILD="$venv_dir/bin/dmgbuild"
  export DMGBUILD
}

build_xcode_version_override_args() {
  XCODE_VERSION_OVERRIDE_ARGS=()
  if [[ -n "${RELEASE_BUILD_VERSION_OVERRIDE:-}" ]]; then
    XCODE_VERSION_OVERRIDE_ARGS+=(CURRENT_PROJECT_VERSION="$RELEASE_BUILD_VERSION_OVERRIDE")
  fi
  if [[ -n "${RELEASE_SHORT_VERSION_OVERRIDE:-}" ]]; then
    XCODE_VERSION_OVERRIDE_ARGS+=(MARKETING_VERSION="$RELEASE_SHORT_VERSION_OVERRIDE")
  fi
}
