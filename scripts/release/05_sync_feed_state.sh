#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config

require_cmd git
require_cmd rsync

mkdir -p "$UPDATES_DIR"

set +e
git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$GITHUB_PAGES_BRANCH" >/dev/null 2>&1
ls_remote_status="$?"
set -e

if [[ "$ls_remote_status" -eq 2 ]]; then
  log "GitHub Pages branch '$GITHUB_PAGES_BRANCH' not found. Continuing in bootstrap mode."
  exit 0
fi
if [[ "$ls_remote_status" -ne 0 ]]; then
  die "Failed to query origin/$GITHUB_PAGES_BRANCH (ls-remote exit code $ls_remote_status)."
fi

log "Synchronizing existing feed state from origin/$GITHUB_PAGES_BRANCH:$GITHUB_PAGES_PATH"
git -C "$REPO_ROOT" fetch origin "$GITHUB_PAGES_BRANCH"

worktree_dir="$(mktemp -d "${TMPDIR:-/tmp}/promptimprover-sync-pages.XXXXXX")"
cleanup() {
  git -C "$REPO_ROOT" worktree remove "$worktree_dir" --force >/dev/null 2>&1 || true
  rm -rf "$worktree_dir"
}
trap cleanup EXIT

git -C "$REPO_ROOT" worktree add "$worktree_dir" "origin/$GITHUB_PAGES_BRANCH"

source_dir="$worktree_dir/$GITHUB_PAGES_PATH"
if [[ -d "$source_dir" ]]; then
  rsync -a --delete "$source_dir/" "$UPDATES_DIR/"
  log "Feed state synchronized into $UPDATES_DIR"
else
  log "Pages branch exists but '$GITHUB_PAGES_PATH' is missing. Continuing with empty local updates directory."
fi
