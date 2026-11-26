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

# The update key must match the public key the app ships with, or every install would reject the
# update while the release still looks fine.
EXPECTED="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' build/LimitsBar.app/Contents/Info.plist)"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  OPENSSL="$(brew --prefix openssl@3 2>/dev/null)/bin/openssl"
  [[ -x "$OPENSSL" ]] || OPENSSL=openssl
  SEED="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | base64 --decode | head -c 32 | xxd -p | tr -d '\n')"
  ACTUAL="$(printf '302e020100300506032b657004220420%s' "$SEED" | xxd -r -p \
    | "$OPENSSL" pkey -inform DER -pubout -outform DER | tail -c 32 | base64)"
else
  GENERATE_KEYS="$(dirname "$SIGN_UPDATE")/generate_keys"
  ACTUAL="$("$GENERATE_KEYS" --account limits-bar -p | tail -1)"
fi
[[ -n "$ACTUAL" && "$ACTUAL" == "$EXPECTED" ]] \
  || { echo "error: the Sparkle signing key doesn't match the app's SUPublicEDKey ($EXPECTED)" >&2; exit 1; }

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
