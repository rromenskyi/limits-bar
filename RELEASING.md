# Releasing

Releases are signed with a Developer ID, notarized, packed as `LimitsBar.dmg`, and announced to
installed copies through a Sparkle feed. The feed is the `appcast.xml` asset of the latest GitHub
release (`releases/latest/download/appcast.xml`), so publishing a release is all it takes.

## From CI (normal path)

Tag and push:

```sh
git tag v0.2.0
git push origin v0.2.0
```

`.github/workflows/release.yml` tests, builds, signs, notarizes, signs the update for Sparkle and
publishes the release with `LimitsBar.dmg` and `appcast.xml`. Versions are plain `X.Y.Z` and must
increase, since Sparkle compares them.

The workflow needs these repository secrets; without them it skips the build with a notice.

| Secret | What |
|---|---|
| `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD` | Developer ID Application certificate and key, exported as .p12 |
| `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | App Store Connect API key used by `notarytool` |
| `SPARKLE_PRIVATE_KEY` | EdDSA key that signs updates (public half is in `scripts/build-app.sh`) |

`scripts/setup-ci-secrets.sh` sets all of them; read its header for the steps.

## From a Mac

With the Developer ID in the login keychain, a `notarytool` keychain profile, and the Sparkle key
stored in the keychain under the account `limits-bar`:

```sh
VERSION=0.2.0 \
SIGN_IDENTITY="Developer ID Application: <Team> (<TEAMID>)" \
NOTARY_PROFILE=<profile> \
./scripts/release-local.sh

gh release create v0.2.0 build/LimitsBar.dmg build/appcast.xml --title "LimitsBar 0.2.0" --generate-notes
```

## The Sparkle key

The update signing key was generated with Sparkle's `generate_keys --account limits-bar`. Keep the
private key safe: losing it means existing installs can't verify new updates. Export it with
`generate_keys --account limits-bar -x <file>`.
