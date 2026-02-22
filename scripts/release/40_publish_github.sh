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

release_tag="${RELEASE_TAG:-}"
if [[ -z "$release_tag" ]]; then
  release_tag="$(git -C "$REPO_ROOT" describe --tags --exact-match 2>/dev/null || true)"
fi
[[ -n "$release_tag" ]] || die "RELEASE_TAG is required (or run from an exact release tag checkout)."

gh release upload "$release_tag" "$RELEASE_DMG_PATH" --repo "$GITHUB_REPOSITORY" --clobber

worktree_dir="$(mktemp -d "${TMPDIR:-/tmp}/promptimprover-pages.XXXXXX")"
cleanup() {
  git -C "$REPO_ROOT" worktree remove "$worktree_dir" --force >/dev/null 2>&1 || true
  rm -rf "$worktree_dir"
}
trap cleanup EXIT

if git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$GITHUB_PAGES_BRANCH" >/dev/null 2>&1; then
  git -C "$REPO_ROOT" fetch origin "$GITHUB_PAGES_BRANCH"
  git -C "$REPO_ROOT" worktree add "$worktree_dir" "origin/$GITHUB_PAGES_BRANCH"
else
  git -C "$REPO_ROOT" worktree add --detach "$worktree_dir"
  git -C "$worktree_dir" checkout --orphan "$GITHUB_PAGES_BRANCH"
  git -C "$worktree_dir" rm -rf . >/dev/null 2>&1 || true
fi

mkdir -p "$worktree_dir/$GITHUB_PAGES_PATH"
rsync -a --delete "$UPDATES_DIR/" "$worktree_dir/$GITHUB_PAGES_PATH/"

if [[ -n "$(git -C "$worktree_dir" status --porcelain)" ]]; then
  # updates/ is ignored in the app branch; force add in pages worktree.
  git -C "$worktree_dir" add -f "$GITHUB_PAGES_PATH"
  git -C "$worktree_dir" commit -m "Publish updates for $release_tag"
  git -C "$worktree_dir" push origin HEAD:"$GITHUB_PAGES_BRANCH"
else
  log "No GitHub Pages changes to publish."
fi

log "GitHub release asset uploaded and feed artifacts published."
