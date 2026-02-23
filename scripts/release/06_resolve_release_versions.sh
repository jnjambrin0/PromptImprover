#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
load_release_state

require_cmd git
require_cmd python3

release_tag="${RELEASE_TAG:-}"
if [[ -z "$release_tag" ]]; then
  release_tag="$(git -C "$REPO_ROOT" describe --tags --exact-match 2>/dev/null || true)"
fi
[[ -n "$release_tag" ]] || die "RELEASE_TAG is required (or run from an exact release tag checkout)."
[[ "$release_tag" =~ ^v[0-9]+([.][0-9]+){0,2}$ ]] || die "Invalid RELEASE_TAG format: $release_tag (expected vX, vX.Y, or vX.Y.Z)"

short_version="${release_tag#v}"

appcast_path="$UPDATES_DIR/appcast.xml"
highest_version=""
if [[ -f "$appcast_path" ]]; then
  highest_version="$(
    python3 - <<'PY' "$appcast_path"
import re
import sys
import xml.etree.ElementTree as ET

appcast_path = sys.argv[1]
pattern = re.compile(r'^[0-9]+(?:\.[0-9]+){0,2}$')

def parse_version(raw: str):
    parts = [int(p) for p in raw.split('.')]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])

def attr_value(node, suffix):
    for key, value in node.attrib.items():
        if key.endswith(suffix):
            return value
    return None

def child_value(node, suffix):
    for child in node:
        tag = child.tag
        if isinstance(tag, str) and tag.endswith(suffix):
            return (child.text or "").strip()
    return None

root = ET.parse(appcast_path).getroot()
best = None

for item in root.findall('.//item'):
    enclosure = item.find('enclosure')
    version = None
    if enclosure is not None:
        version = attr_value(enclosure, 'version')
    if not version:
        version = child_value(item, 'version')
    if not version:
        continue
    if not pattern.match(version):
        continue
    if best is None or parse_version(version) > parse_version(best):
        best = version

if best:
    print(best)
PY
  )"
fi

if [[ -z "$highest_version" ]]; then
  next_build_version="1"
else
  IFS='.' read -r -a parts <<<"$highest_version"
  case "${#parts[@]}" in
    1)
      next_build_version="$((parts[0] + 1))"
      ;;
    2)
      next_build_version="${parts[0]}.$((parts[1] + 1))"
      ;;
    3)
      next_build_version="${parts[0]}.${parts[1]}.$((parts[2] + 1))"
      ;;
    *)
      die "Unsupported highest sparkle:version format in appcast: $highest_version"
      ;;
  esac
fi

write_release_state RELEASE_TAG "$release_tag"
write_release_state RELEASE_SHORT_VERSION_OVERRIDE "$short_version"
write_release_state RELEASE_BUILD_VERSION_OVERRIDE "$next_build_version"

log "Resolved release versions from tag/feed: tag=$release_tag short=$short_version build=$next_build_version highest_published=${highest_version:-none}"
