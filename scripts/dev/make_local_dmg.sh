#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVED="$REPO/build/local/DerivedData"
STAGE="$REPO/build/local/dmg-root"
DMG="$REPO/build/local/PromptImprover-local.dmg"

rm -rf "$DERIVED" "$STAGE"
mkdir -p "$STAGE"

# Build Release
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project "$REPO/PromptImprover.xcodeproj" \
  -scheme PromptImprover \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  build

# Prepara DMG root
ditto "$DERIVED/Build/Products/Release/PromptImprover.app" "$STAGE/PromptImprover.app"
ln -s /Applications "$STAGE/Applications"

# Crea DMG
hdiutil create -volname "PromptImprover" -srcfolder "$STAGE" -format UDZO -ov "$DMG"

echo "DMG generado en: $DMG"
if [[ "${NO_OPEN:-0}" != "1" ]]; then
  open "$DMG"
fi
