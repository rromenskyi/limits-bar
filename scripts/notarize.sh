#!/usr/bin/env bash
# Signs, notarizes and staples a DMG. Credentials, in order of preference:
#   NOTARY_PROFILE                                  (notarytool keychain profile, local use)
#   NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID  (App Store Connect API key, CI)
set -euo pipefail
DMG="${1:?usage: notarize.sh path/to/file.dmg}"
: "${SIGN_IDENTITY:?SIGN_IDENTITY is required}"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
  AUTH=(--key "$NOTARY_KEY_PATH" --key-id "${NOTARY_KEY_ID:?}" --issuer "${NOTARY_ISSUER_ID:?}")
else
  echo "error: set NOTARY_PROFILE or NOTARY_KEY_PATH/NOTARY_KEY_ID/NOTARY_ISSUER_ID" >&2
  exit 1
fi

SIGN_OPTS=(--force --timestamp --sign "$SIGN_IDENTITY")
[[ -n "${SIGNING_KEYCHAIN:-}" ]] && SIGN_OPTS+=(--keychain "$SIGNING_KEYCHAIN")
codesign "${SIGN_OPTS[@]}" "$DMG"

OUT="$(xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait --timeout 45m --output-format json)"
echo "$OUT"
STATUS="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$OUT")"
if [[ "$STATUS" != "Accepted" ]]; then
  ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' <<<"$OUT")"
  [[ -n "$ID" ]] && xcrun notarytool log "$ID" "${AUTH[@]}" || true
  echo "error: notarization $STATUS" >&2
  exit 1
fi

for i in 1 2 3 4 5; do
  xcrun stapler staple "$DMG" && break
  [[ $i == 5 ]] && exit 1
  sleep $((i * 15))
done
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "notarized and stapled $DMG"
