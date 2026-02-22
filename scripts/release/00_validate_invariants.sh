#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

REQUIRE_CURRENT_IN_APPCAST=0
if [[ "${1:-}" == "--require-current-in-appcast" ]]; then
  REQUIRE_CURRENT_IN_APPCAST=1
fi

load_release_config
load_release_state

require_cmd "$XCODEBUILD_BIN"
require_cmd python3

settings="$($XCODEBUILD_BIN -project "$PROJECT_FILE" -scheme "$SCHEME_NAME" -configuration "$CONFIGURATION" -showBuildSettings)"

bundle_id="$(build_setting "PRODUCT_BUNDLE_IDENTIFIER" "$settings")"
current_build="$(build_setting "CURRENT_PROJECT_VERSION" "$settings")"
short_version="$(build_setting "MARKETING_VERSION" "$settings")"
sparkle_feed_url="$(build_setting "SPARKLE_FEED_URL" "$settings")"
sparkle_public_key="$(build_setting "SPARKLE_PUBLIC_ED_KEY" "$settings")"

[[ -n "$bundle_id" ]] || die "Could not resolve PRODUCT_BUNDLE_IDENTIFIER"
[[ -n "$current_build" ]] || die "Could not resolve CURRENT_PROJECT_VERSION"
[[ -n "$short_version" ]] || die "Could not resolve MARKETING_VERSION"
[[ -n "$sparkle_feed_url" ]] || die "Could not resolve SPARKLE_FEED_URL"
[[ -n "$sparkle_public_key" ]] || die "SPARKLE_PUBLIC_ED_KEY is empty. Generate keys with Sparkle's generate_keys and set the build setting before releasing."

python3 - <<'PY' "$EXPECTED_BUNDLE_IDENTIFIER" "$bundle_id" "$current_build" "$short_version" "$sparkle_feed_url" "$sparkle_public_key"
import base64
import binascii
import re
import sys

expected_bundle, bundle, build, short, feed, public_key = sys.argv[1:7]
pattern = re.compile(r'^[0-9]+(?:\.[0-9]+){0,2}$')

if bundle != expected_bundle:
    raise SystemExit(f"Bundle identifier mismatch: expected {expected_bundle}, found {bundle}")

if not pattern.match(build):
    raise SystemExit(f"Invalid CFBundleVersion format: {build}")

if not pattern.match(short):
    raise SystemExit(f"Invalid CFBundleShortVersionString format: {short}")

if not feed.startswith("https://"):
    raise SystemExit(f"SPARKLE_FEED_URL must use HTTPS: {feed}")

try:
    decoded = base64.b64decode(public_key, validate=True)
except binascii.Error as exc:
    raise SystemExit(f"SPARKLE_PUBLIC_ED_KEY must be valid base64 (ed25519 public key): {exc}") from exc

if len(decoded) != 32:
    raise SystemExit("SPARKLE_PUBLIC_ED_KEY must decode to 32 bytes (ed25519 public key length).")
PY

if [[ "$sparkle_feed_url" != "$SPARKLE_FEED_URL" ]]; then
  die "SPARKLE_FEED_URL mismatch. Expected $SPARKLE_FEED_URL but build setting is $sparkle_feed_url"
fi

appcast_path="$UPDATES_DIR/appcast.xml"
if [[ -f "$appcast_path" ]]; then
  python3 - <<'PY' "$appcast_path" "$current_build" "$short_version" "$REQUIRE_CURRENT_IN_APPCAST"
import re
import sys
import xml.etree.ElementTree as ET

appcast_path, current_build, short_version, require_current = sys.argv[1:5]
require_current = require_current == "1"
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

root = ET.parse(appcast_path).getroot()
items = root.findall('.//item')

published_versions = []
current_item = None
for item in items:
    enclosure = item.find('enclosure')
    if enclosure is None:
        continue
    v = attr_value(enclosure, 'version')
    short = attr_value(enclosure, 'shortVersionString')
    if not v:
        continue
    if not pattern.match(v):
        raise SystemExit(f"Invalid sparkle:version in appcast: {v}")
    published_versions.append(v)
    if v == current_build:
        current_item = (v, short)

if published_versions:
    if require_current:
        prior_published_versions = [version for version in published_versions if version != current_build]
        if prior_published_versions:
            highest = max(prior_published_versions, key=parse_version)
            if parse_version(current_build) <= parse_version(highest):
                raise SystemExit(
                    f"CFBundleVersion must be strictly greater than highest prior sparkle:version. "
                    f"current={current_build}, highest={highest}"
                )
    else:
        highest = max(published_versions, key=parse_version)
        if parse_version(current_build) <= parse_version(highest):
            raise SystemExit(
                f"CFBundleVersion must be strictly greater than highest published sparkle:version. "
                f"current={current_build}, highest={highest}"
            )

if require_current:
    if current_item is None:
        raise SystemExit(
            f"Current build {current_build} is missing from appcast. "
            "Run generate_appcast before publishing."
        )
    _, found_short = current_item
    if (found_short or "") != short_version:
        raise SystemExit(
            "Mismatch between app bundle versions and appcast item fields: "
            f"expected shortVersion={short_version}, found shortVersion={found_short}"
        )
PY
fi

write_release_state RELEASE_BUNDLE_IDENTIFIER "$bundle_id"
write_release_state RELEASE_BUILD_VERSION "$current_build"
write_release_state RELEASE_SHORT_VERSION "$short_version"

log "Release invariants validated (bundle=$bundle_id build=$current_build short=$short_version)"
