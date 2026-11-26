#!/usr/bin/env bash
# Stores the release secrets in the GitHub repo so the Release workflow can sign, notarize and
# publish. Run it yourself:
#
#   1. Keychain Access → My Certificates → "Developer ID Application: …" → Export → .p12
#   2. DEVELOPER_ID_P12=~/Desktop/developer_id.p12 \
#      NOTARY_KEY_P8=~/path/AuthKey_XXXX.p8 NOTARY_KEY_ID=XXXX NOTARY_ISSUER_ID=<uuid> \
#      ./scripts/setup-ci-secrets.sh
#   3. Delete the exported .p12.
#
# The script asks for the .p12 password, so run it in a terminal.
#
# Sets DEVELOPER_ID_P12_BASE64, DEVELOPER_ID_P12_PASSWORD, NOTARY_KEY_P8_BASE64,
# NOTARY_KEY_ID, NOTARY_ISSUER_ID and SPARKLE_PRIVATE_KEY.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="${REPO:-rromenskyi/limits-bar}"
: "${DEVELOPER_ID_P12:?path to the exported .p12}" "${NOTARY_KEY_P8:?path to the App Store Connect API key (.p8)}"
: "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER_ID:?}"

[[ -f "$DEVELOPER_ID_P12" ]] || { echo "error: $DEVELOPER_ID_P12 not found. Export it from Keychain Access first (step 1)." >&2; exit 1; }
[[ -f "$NOTARY_KEY_P8" ]] || { echo "error: $NOTARY_KEY_P8 not found" >&2; exit 1; }
[[ -t 0 ]] || { echo "error: no terminal to ask for the .p12 password; run this in Terminal" >&2; exit 1; }
read -r -s -p "Password of $DEVELOPER_ID_P12: " P12_PASSWORD; echo
# The password goes to openssl on stdin, never on its command line.
printf '%s\n' "$P12_PASSWORD" | openssl pkcs12 -in "$DEVELOPER_ID_P12" -passin stdin -nokeys -legacy >/dev/null 2>&1 \
  || printf '%s\n' "$P12_PASSWORD" | openssl pkcs12 -in "$DEVELOPER_ID_P12" -passin stdin -nokeys >/dev/null \
  || { echo "error: wrong password or not a .p12" >&2; exit 1; }

TMP="$(mktemp -d)"; chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT
GENERATE_KEYS="$(find .build/artifacts -name generate_keys -path "*/bin/*" | head -1)"
[[ -x "$GENERATE_KEYS" ]] || { echo "error: run swift build first (it fetches Sparkle's tools)" >&2; exit 1; }
EXPECTED="$(sed -n 's/^SPARKLE_PUBLIC_KEY="\(.*\)"$/\1/p' scripts/build-app.sh)"
ACTUAL="$("$GENERATE_KEYS" --account limits-bar -p | tail -1)"
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo "error: keychain Sparkle key ($ACTUAL) doesn't match build-app.sh ($EXPECTED)" >&2; exit 1; }
"$GENERATE_KEYS" --account limits-bar -x "$TMP/sparkle.key" >/dev/null

base64 -i "$DEVELOPER_ID_P12" | gh secret set DEVELOPER_ID_P12_BASE64 -R "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set DEVELOPER_ID_P12_PASSWORD -R "$REPO"
base64 -i "$NOTARY_KEY_P8" | gh secret set NOTARY_KEY_P8_BASE64 -R "$REPO"
printf '%s' "$NOTARY_KEY_ID" | gh secret set NOTARY_KEY_ID -R "$REPO"
printf '%s' "$NOTARY_ISSUER_ID" | gh secret set NOTARY_ISSUER_ID -R "$REPO"
gh secret set SPARKLE_PRIVATE_KEY -R "$REPO" < "$TMP/sparkle.key"
echo "Secrets set on $REPO. You can delete $DEVELOPER_ID_P12 now."
