#!/usr/bin/env bash
# Builds, signs, notarizes and packages a release on this Mac, then writes the appcast.
# Publish the results with `gh release create` (see RELEASING.md).
#
#   VERSION=0.1.0 SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=<profile> ./scripts/release-local.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VERSION:?}" "${SIGN_IDENTITY:?}"
swift test
./scripts/build-app.sh
./scripts/build-dmg.sh
./scripts/notarize.sh build/LimitsBar.dmg
./scripts/make-appcast.sh
shasum -a 256 build/LimitsBar.dmg
