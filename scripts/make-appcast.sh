#!/usr/bin/env bash
# Signs build/LimitsBar.dmg for Sparkle and writes build/appcast.xml describing that release.
# The appcast is uploaded as a release asset, so the feed URL
# .../releases/latest/download/appcast.xml always describes the latest release.
#
# Private key: SPARKLE_PRIVATE_KEY (CI), or the "limits-bar" account in the login keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VERSION:?VERSION is required}"
DMG="build/LimitsBar.dmg"
REPO="${GITHUB_REPOSITORY:-rromenskyi/limits-bar}"
SIGN_UPDATE="$(find .build/artifacts -name sign_update -path "*/bin/sign_update" | grep -v old_dsa | head -1)"
[[ -x "$SIGN_UPDATE" ]] || { echo "error: Sparkle sign_update not found; run swift build first" >&2; exit 1; }

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  ATTRS="$(printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$DMG")"
else
  ATTRS="$("$SIGN_UPDATE" --account limits-bar "$DMG")"
fi
SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$ATTRS")"
LENGTH="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$ATTRS")"
[[ -n "$SIGNATURE" && -n "$LENGTH" ]] || { echo "error: unexpected sign_update output: $ATTRS" >&2; exit 1; }

URL="https://github.com/$REPO/releases/download/v$VERSION/LimitsBar.dmg"
cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>LimitsBar</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
XML
python3 -c "import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])" build/appcast.xml
echo "Wrote build/appcast.xml for $VERSION"
