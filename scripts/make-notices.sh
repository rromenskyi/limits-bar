#!/usr/bin/env bash
# Writes THIRD_PARTY_NOTICES.md from the resolved dependencies' own license files (to stdout, or
# atomically to the given file). The app bundle and the repo copy both come from here; CI fails if
# the repo copy is stale.
#
#   ./scripts/make-notices.sh THIRD_PARTY_NOTICES.md
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -gt 0 ]]; then
  OUT="$1"; TMP="$(mktemp "${OUT}.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT
  "$0" > "$TMP"
  mv "$TMP" "$OUT"; trap - EXIT
  exit 0
fi

# The license must come from the pinned revision, not an older checkout.
SPARKLE_REVISION="$(plutil -extract pins.0.state.revision raw -o - Package.resolved)"
checkout_matches() { [[ "$(git -C .build/checkouts/Sparkle rev-parse HEAD 2>/dev/null)" == "$SPARKLE_REVISION" ]]; }
checkout_matches || swift package resolve >/dev/null
checkout_matches || { echo "error: .build/checkouts/Sparkle is not at $SPARKLE_REVISION" >&2; exit 1; }
SPARKLE_VERSION="$(plutil -extract pins.0.state.version raw -o - Package.resolved)"
[[ "$(plutil -extract pins.0.identity raw -o - Package.resolved)" == "sparkle" ]] \
  || { echo "error: Package.resolved changed; update make-notices.sh" >&2; exit 1; }
[[ "$(plutil -extract pins raw -o - Package.resolved)" == "1" ]] \
  || { echo "error: new dependency in Package.resolved; add its license to make-notices.sh" >&2; exit 1; }

cat <<HEADER
# Third-party notices

LimitsBar is released under the MIT License (see LICENSE). It ships with the
third-party software listed below, under the licenses that follow.

Claude, Codex, Devin and Muse are trademarks of their respective owners.
LimitsBar is an independent project and is not affiliated with or endorsed by them.

## Sparkle ${SPARKLE_VERSION}

https://sparkle-project.org — embedded as Sparkle.framework for updates.
Sparkle's license covers its bundled components (bsdiff, sais-lite, ed25519,
SUSignatureVerifier).

\`\`\`text
HEADER
sed -e 's/[[:space:]]*$//' .build/checkouts/Sparkle/LICENSE
echo '```'
