#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
load_release_state

require_cmd gh
require_cmd git
require_cmd rsync

require_var RELEASE_DMG_PATH
require_var RELEASE_APPCAST_PATH

resolve_release_file_path() {
  local requested_path="$1"
  local label="$2"
  local search_root
  local basename_path
  local resolved
  local candidates

  if [[ -f "$requested_path" ]]; then
    printf '%s\n' "$requested_path"
    return 0
  fi

  search_root="$REPO_ROOT/updates"
  basename_path="$(basename "$requested_path")"
  mapfile -t candidates < <(find "$search_root" -type f -name "$basename_path" 2>/dev/null | sort)

  if [[ "${#candidates[@]}" -eq 1 ]]; then
    resolved="${candidates[0]}"
    if [[ "$resolved" == "$REPO_ROOT/"* ]]; then
      resolved="${resolved#"$REPO_ROOT"/}"
    fi
    log "Resolved $label path '$requested_path' to '$resolved'."
    printf '%s\n' "$resolved"
    return 0
  fi

  if [[ "${#candidates[@]}" -gt 1 ]]; then
    printf '[release] ERROR: Ambiguous %s path. Requested: %s\n' "$label" "$requested_path" >&2
    printf '[release] ERROR: Matching candidates under updates/:\n' >&2
    printf '  %s\n' "${candidates[@]}" >&2
    exit 1
  fi

  printf '[release] ERROR: %s file not found: %s\n' "$label" "$requested_path" >&2
  if [[ -d "$search_root" ]]; then
    printf '[release] Available files under updates/:\n' >&2
    find "$search_root" -maxdepth 4 -type f | sort >&2 || true
  fi
  exit 1
}

RELEASE_DMG_PATH="$(resolve_release_file_path "$RELEASE_DMG_PATH" "Release DMG")"
RELEASE_APPCAST_PATH="$(resolve_release_file_path "$RELEASE_APPCAST_PATH" "Release appcast")"

publish_updates_dir="$UPDATES_DIR"
if [[ ! -f "$publish_updates_dir/appcast.xml" ]]; then
  publish_updates_dir="$(dirname "$RELEASE_APPCAST_PATH")"
fi

timeout_seconds="${PUBLISH_TIMEOUT_SECONDS:-900}"

run_with_timeout() {
  local label="$1"
  shift
  local start_ts cmd_pid elapsed cmd_status
  start_ts="$(date +%s)"
  log "$label: started"

  "$@" &
  cmd_pid="$!"

  while kill -0 "$cmd_pid" >/dev/null 2>&1; do
    elapsed="$(( $(date +%s) - start_ts ))"
    if (( elapsed > timeout_seconds )); then
      log "$label: exceeded timeout (${timeout_seconds}s). Sending SIGTERM."
      kill "$cmd_pid" >/dev/null 2>&1 || true
      sleep 2
      kill -9 "$cmd_pid" >/dev/null 2>&1 || true
      wait "$cmd_pid" 2>/dev/null || true
      die "$label timed out after ${timeout_seconds}s"
    fi
    sleep 1
  done

  set +e
  wait "$cmd_pid"
  cmd_status="$?"
  set -e
  if [[ "$cmd_status" -ne 0 ]]; then
    die "$label failed with exit code $cmd_status"
  fi
  elapsed="$(( $(date +%s) - start_ts ))"
  log "$label: completed in ${elapsed}s"
}

public_dmg_temp_dir=""
worktree_dir=""
cleanup() {
  if [[ -n "${worktree_dir:-}" ]]; then
    git -C "$REPO_ROOT" worktree remove "$worktree_dir" --force >/dev/null 2>&1 || true
    rm -rf "$worktree_dir"
  fi
  if [[ -n "${public_dmg_temp_dir:-}" ]]; then
    rm -rf "$public_dmg_temp_dir"
  fi
}
trap cleanup EXIT

list_release_asset_names() {
  gh release view "$release_tag" --repo "$GITHUB_REPOSITORY" --json assets --jq '.assets[].name'
}

is_legacy_numbered_dmg_asset() {
  local asset_name="$1"
  local numeric_suffix

  [[ "$asset_name" == "${APP_NAME}-"*.dmg ]] || return 1
  numeric_suffix="${asset_name#${APP_NAME}-}"
  numeric_suffix="${numeric_suffix%.dmg}"

  [[ "$numeric_suffix" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]
}

cleanup_legacy_numbered_dmg_assets() {
  local asset_name
  local cleaned_count=0

  while IFS= read -r asset_name; do
    [[ -n "$asset_name" ]] || continue
    if is_legacy_numbered_dmg_asset "$asset_name"; then
      run_with_timeout "Delete legacy release asset ($asset_name)" \
        gh release delete-asset "$release_tag" "$asset_name" --repo "$GITHUB_REPOSITORY" --yes
      cleaned_count="$((cleaned_count + 1))"
    fi
  done < <(list_release_asset_names || true)

  if [[ "$cleaned_count" -gt 0 ]]; then
    log "Deleted $cleaned_count legacy numbered DMG asset(s) from release $release_tag."
  else
    log "No legacy numbered DMG assets found for release $release_tag."
  fi
}

validate_release_assets() {
  local asset_name
  local has_public_dmg=0
  local legacy_assets=()

  while IFS= read -r asset_name; do
    [[ -n "$asset_name" ]] || continue
    if [[ "$asset_name" == "$public_dmg_name" ]]; then
      has_public_dmg=1
    fi
    if is_legacy_numbered_dmg_asset "$asset_name"; then
      legacy_assets+=("$asset_name")
    fi
  done < <(list_release_asset_names || true)

  [[ "$has_public_dmg" -eq 1 ]] || die "Expected canonical GitHub release DMG asset is missing: $public_dmg_name"
  if [[ "${#legacy_assets[@]}" -gt 0 ]]; then
    printf '[release] ERROR: Legacy numbered DMG assets remain in release %s:\n' "$release_tag" >&2
    printf '  %s\n' "${legacy_assets[@]}" >&2
    die "Canonical release asset validation failed."
  fi
}

release_tag="${RELEASE_TAG:-}"
if [[ -z "$release_tag" ]]; then
  release_tag="$(git -C "$REPO_ROOT" describe --tags --exact-match 2>/dev/null || true)"
fi
[[ -n "$release_tag" ]] || die "RELEASE_TAG is required (or run from an exact release tag checkout)."

public_dmg_name="${APP_NAME}-${release_tag}.dmg"
public_dmg_temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/promptimprover-release-assets.XXXXXX")"
public_dmg_path="$public_dmg_temp_dir/$public_dmg_name"
cp "$RELEASE_DMG_PATH" "$public_dmg_path"

cleanup_legacy_numbered_dmg_assets
run_with_timeout "GitHub release asset upload ($public_dmg_name)" \
  gh release upload "$release_tag" "$public_dmg_path" --repo "$GITHUB_REPOSITORY" --clobber
validate_release_assets
log "Canonical GitHub release asset published: $public_dmg_name"

worktree_dir="$(mktemp -d "${TMPDIR:-/tmp}/promptimprover-pages.XXXXXX")"

if git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$GITHUB_PAGES_BRANCH" >/dev/null 2>&1; then
  run_with_timeout "Fetch GitHub Pages branch" git -C "$REPO_ROOT" fetch origin "$GITHUB_PAGES_BRANCH"
  git -C "$REPO_ROOT" worktree add "$worktree_dir" "origin/$GITHUB_PAGES_BRANCH"
else
  git -C "$REPO_ROOT" worktree add --detach "$worktree_dir"
  git -C "$worktree_dir" checkout --orphan "$GITHUB_PAGES_BRANCH"
  git -C "$worktree_dir" rm -rf . >/dev/null 2>&1 || true
fi

mkdir -p "$worktree_dir/$GITHUB_PAGES_PATH"
rsync -a --delete "$publish_updates_dir/" "$worktree_dir/$GITHUB_PAGES_PATH/"

if [[ -n "$(git -C "$worktree_dir" status --porcelain)" ]]; then
  # updates/ is ignored in the main branch .gitignore; force-add in gh-pages worktree.
  git -C "$worktree_dir" add -A -f -- "$GITHUB_PAGES_PATH"
  git -C "$worktree_dir" commit -m "Publish updates for $release_tag"
  run_with_timeout "Push GitHub Pages updates" git -C "$worktree_dir" push origin HEAD:"$GITHUB_PAGES_BRANCH"
else
  log "No GitHub Pages changes to publish."
fi

log "GitHub release asset uploaded and feed artifacts published."
