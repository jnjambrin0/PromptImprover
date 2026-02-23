#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVED="$REPO/build/local/DerivedData"
DMG="$REPO/build/local/PromptImprover-local.dmg"
DMG_ASSETS_DIR="$REPO/scripts/release/dmg-assets"
APP_PATH="$DERIVED/Build/Products/Release/PromptImprover.app"

rm -rf "$DERIVED"

# Build Release
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project "$REPO/PromptImprover.xcodeproj" \
  -scheme PromptImprover \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  build

# Ensure dmgbuild is available via venv (PEP 668 safe)
DMGBUILD_VENV="$REPO/build/.dmgbuild-venv"
if [[ ! -x "$DMGBUILD_VENV/bin/dmgbuild" ]]; then
  echo "Creating dmgbuild virtual environment..."
  python3 -m venv "$DMGBUILD_VENV"
  "$DMGBUILD_VENV/bin/pip" install --quiet dmgbuild
fi

# Create branded DMG
mkdir -p "$(dirname "$DMG")"
"$DMGBUILD_VENV/bin/dmgbuild" \
  -s "$DMG_ASSETS_DIR/dmg-settings.py" \
  -D app="$APP_PATH" \
  -D background="$DMG_ASSETS_DIR/dmg-background.png" \
  "PromptImprover" \
  "$DMG"

echo "DMG generated at: $DMG"
if [[ "${NO_OPEN:-0}" != "1" ]]; then
  open "$DMG"
fi
