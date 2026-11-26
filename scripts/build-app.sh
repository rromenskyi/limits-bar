#!/usr/bin/env bash
# Builds build/LimitsBar.app: universal release binary, embedded Sparkle.framework, signed.
#
#   VERSION=1.2.3 ./scripts/build-app.sh                         # ad-hoc signed
#   VERSION=1.2.3 SIGN_IDENTITY="Developer ID Application: ..." ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: VERSION must look like 1.2.3, got '$VERSION'" >&2; exit 1; }
APP="build/LimitsBar.app"
# Public half of the Sparkle EdDSA key; the private half signs releases (see RELEASING.md).
SPARKLE_PUBLIC_KEY="Ukk6zaeV5vKF+wRJ/G7xHaP+m8QbtdfsHqSwBIOlSlE="
FEED_URL="https://github.com/rromenskyi/limits-bar/releases/latest/download/appcast.xml"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"
SPARKLE="$BIN_DIR/Sparkle.framework"
[[ -d "$SPARKLE" ]] || { echo "error: $SPARKLE not found" >&2; exit 1; }

# Only signed (release) builds get the update feed; a local ad-hoc build must not replace itself
# with the latest release.
SPARKLE_KEYS=""
if [[ -n "${SIGN_IDENTITY:-}" && "${SIGN_IDENTITY}" != "-" ]]; then
  SPARKLE_KEYS="    <key>SUFeedURL</key><string>${FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/LimitsBar" "$APP/Contents/MacOS/LimitsBar"
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
./scripts/make-notices.sh "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
LOCALIZATIONS="$(for d in Resources/Localization/*.lproj; do n="$(basename "$d" .lproj)"; printf '        <string>%s</string>\n' "$n"; done)"
# The binary links @rpath/Sparkle.framework; point rpath at Contents/Frameworks like Xcode would.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/LimitsBar"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>LimitsBar</string>
    <key>CFBundleDisplayName</key><string>LimitsBar</string>
    <key>CFBundleIdentifier</key><string>io.github.rromenskyi.limitsbar</string>
    <key>CFBundleExecutable</key><string>LimitsBar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
${LOCALIZATIONS}
    </array>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Roman Romenskyi. MIT License.</string>
${SPARKLE_KEYS}
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" >/dev/null
./scripts/codesign-app.sh "$APP"
echo "Built $APP ($VERSION)"
