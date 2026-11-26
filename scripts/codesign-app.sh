#!/usr/bin/env bash
# Signs an app bundle inside-out. Without SIGN_IDENTITY it signs ad-hoc; with it, it uses the
# hardened runtime and a secure timestamp, as notarization requires.
set -euo pipefail
APP="${1:?usage: codesign-app.sh path/to/LimitsBar.app}"
IDENTITY="${SIGN_IDENTITY:-}"

if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
  echo "signed $APP ad-hoc"
  exit 0
fi

OPTS=(--force --timestamp --options runtime --sign "$IDENTITY")
[[ -n "${SIGNING_KEYCHAIN:-}" ]] && OPTS+=(--keychain "$SIGNING_KEYCHAIN")

# Nested code first, deepest paths first: loose executables, then XPC services and helper
# apps (keeping their entitlements), then frameworks, then the app itself.
while IFS= read -r -d '' f; do
  [[ -L "$f" ]] && continue
  file -b "$f" | grep -q "Mach-O" || continue
  [[ "$f" == "$APP/Contents/MacOS/LimitsBar" ]] && continue
  [[ "$f" == *.xpc/Contents/MacOS/* || "$f" == *.app/Contents/MacOS/* ]] && continue
  codesign "${OPTS[@]}" --preserve-metadata=entitlements "$f"
done < <(find "$APP/Contents/Frameworks" -type f -perm -u+x -print0 | sort -rz)

while IFS= read -r -d '' b; do
  if [[ "$b" == *.xpc || "$b" == *.app ]]; then
    codesign "${OPTS[@]}" --preserve-metadata=entitlements "$b"
  else
    codesign "${OPTS[@]}" "$b"
  fi
done < <(find "$APP/Contents/Frameworks" -depth -type d \( -name "*.xpc" -o -name "*.app" -o -name "*.framework" \) -print0)

codesign "${OPTS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "signed $APP as $IDENTITY"
