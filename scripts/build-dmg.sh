#!/usr/bin/env bash
# Packs build/LimitsBar.app into build/LimitsBar.dmg (drag-to-Applications layout).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/LimitsBar.app"
DMG="build/LimitsBar.dmg"
[[ -d "$APP" ]] || { echo "error: $APP not found; run build-app.sh first" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "LimitsBar" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Built $DMG"
