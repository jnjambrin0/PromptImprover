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

load_release_config() {
  [[ -f "$RELEASE_CONFIG_FILE" ]] || die "Missing release config: $RELEASE_CONFIG_FILE"
  # shellcheck disable=SC1090
  source "$RELEASE_CONFIG_FILE"
  export PROJECT_FILE SCHEME_NAME CONFIGURATION APP_NAME EXPECTED_BUNDLE_IDENTIFIER
  export SPARKLE_FEED_URL UPDATES_DIR SPARKLE_BIN DEVELOPER_ID_APPLICATION
  export NOTARY_PROFILE GITHUB_REPOSITORY GITHUB_PAGES_BRANCH GITHUB_PAGES_PATH
  export XCODEBUILD_BIN

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

  if [[ "$PROJECT_FILE" != /* ]]; then
    PROJECT_FILE="$REPO_ROOT/$PROJECT_FILE"
  fi
  if [[ "$UPDATES_DIR" != /* ]]; then
    UPDATES_DIR="$REPO_ROOT/$UPDATES_DIR"
  fi

  export PROJECT_FILE SCHEME_NAME CONFIGURATION APP_NAME EXPECTED_BUNDLE_IDENTIFIER
  export SPARKLE_FEED_URL UPDATES_DIR SPARKLE_BIN DEVELOPER_ID_APPLICATION
  export NOTARY_PROFILE GITHUB_REPOSITORY GITHUB_PAGES_BRANCH GITHUB_PAGES_PATH
  export XCODEBUILD_BIN

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
