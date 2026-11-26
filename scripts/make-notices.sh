#!/usr/bin/env bash
# Prints THIRD_PARTY_NOTICES.md from the resolved dependencies' own license files.
# The app bundle and the repo copy both come from here; CI fails if the repo copy is stale.
#
#   ./scripts/make-notices.sh > THIRD_PARTY_NOTICES.md
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d .build/checkouts/Sparkle ]] || swift package resolve >/dev/null
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
