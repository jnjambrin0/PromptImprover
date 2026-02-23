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

release_tag="${RELEASE_TAG:-}"
if [[ -z "$release_tag" ]]; then
  release_tag="$(git -C "$REPO_ROOT" describe --tags --exact-match 2>/dev/null || true)"
fi
[[ -n "$release_tag" ]] || die "RELEASE_TAG is required (or run from an exact release tag checkout)."

run_with_timeout "GitHub release asset upload" gh release upload "$release_tag" "$RELEASE_DMG_PATH" --repo "$GITHUB_REPOSITORY" --clobber

worktree_dir="$(mktemp -d "${TMPDIR:-/tmp}/promptimprover-pages.XXXXXX")"
cleanup() {
  git -C "$REPO_ROOT" worktree remove "$worktree_dir" --force >/dev/null 2>&1 || true
  rm -rf "$worktree_dir"
}
trap cleanup EXIT

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
