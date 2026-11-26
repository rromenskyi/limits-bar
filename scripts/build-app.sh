#!/usr/bin/env bash
# Builds build/LimitsBar.app: universal release binary, embedded Sparkle.framework, signed.
#
#   VERSION=1.2.3 ./scripts/build-app.sh                         # ad-hoc signed
#   VERSION=1.2.3 SIGN_IDENTITY="Developer ID Application: ..." ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0}"
APP="build/LimitsBar.app"
# Public half of the Sparkle EdDSA key; the private half signs releases (see RELEASING.md).
SPARKLE_PUBLIC_KEY="Ukk6zaeV5vKF+wRJ/G7xHaP+m8QbtdfsHqSwBIOlSlE="
FEED_URL="https://github.com/rromenskyi/limits-bar/releases/latest/download/appcast.xml"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"
SPARKLE="$BIN_DIR/Sparkle.framework"
[[ -d "$SPARKLE" ]] || SPARKLE="$(find .build -path "*release*" -name Sparkle.framework -type d | head -1)"
[[ -d "$SPARKLE" ]] || { echo "error: Sparkle.framework not found under .build" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/LimitsBar" "$APP/Contents/MacOS/LimitsBar"
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
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
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
    <key>SUFeedURL</key><string>${FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

./scripts/codesign-app.sh "$APP"
echo "Built $APP ($VERSION)"
