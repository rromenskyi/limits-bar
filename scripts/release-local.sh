#!/usr/bin/env bash
# Builds, signs, notarizes and packages a release on this Mac, then writes the appcast.
# Publish the results with `gh release create` (see RELEASING.md).
#
#   VERSION=0.1.0 SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=<profile> ./scripts/release-local.sh
set -euo pipefail
cd "$(dirname "$0")/.."
# Publish with: git tag "v$VERSION" && git push origin "v$VERSION" && gh release create "v$VERSION" ...
: "${VERSION:?}" "${SIGN_IDENTITY:?}"
git diff --quiet && git diff --cached --quiet \
  || { echo "error: uncommitted changes; a release must be built from a committed tree" >&2; exit 1; }
swift test
./scripts/build-app.sh
./scripts/build-dmg.sh
./scripts/notarize.sh build/LimitsBar.dmg
./scripts/make-appcast.sh
shasum -a 256 build/LimitsBar.dmg
