# LimitsBar

A small macOS menu bar app that shows how much of your coding-agent subscription limits is left:

- **Claude** (Claude Code, Pro/Max/Team sign-in): 5-hour session, weekly, and per-model weekly limits
- **Codex** (OpenAI Codex CLI, ChatGPT sign-in): 5-hour and weekly limits
- **Muse** (Muse Code CLI): rolling window and weekly allowance
- **Devin** (Devin CLI): daily and weekly quota

The menu bar shows one number per provider, the remaining percent of its tightest window,
for example `C80 X12 M86 D100`. Click it for every window, with reset countdowns.

## How it works

LimitsBar has no logins of its own. It reuses the credentials the vendor CLIs already keep on your
Mac and calls the same usage endpoints those CLIs call:

| Provider | Credentials read from | Request |
|---|---|---|
| Claude | login keychain item `Claude Code-credentials` (via `/usr/bin/security`), or `~/.claude/.credentials.json` | `GET api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` (`$CODEX_HOME`) | `GET chatgpt.com/backend-api/wham/usage` |
| Muse | none; runs `muse usage --json` | handled by the CLI |
| Devin | `~/.local/share/devin/credentials.toml` | `GetUserStatus` on the server named in that file |

Each token goes only to its own vendor. Nothing is stored, logged, or sent anywhere else.

Tokens are never refreshed. A refresh can rotate the refresh token and sign the CLI out, so when a
token has expired the row shows as stale until you next use that CLI.

The endpoints are unofficial and undocumented. A vendor can change them at any time, and the
affected row then shows an error while the others keep working.

Usage is checked every 5 minutes, and the refresh button checks right away.

## Install

Requires macOS 14 or later and Swift 6 (Xcode 16 or later).

```sh
git clone https://github.com/rromenskyi/limits-bar.git
cd limits-bar
./scripts/build-app.sh
cp -R build/LimitsBar.app /Applications/
open /Applications/LimitsBar.app
```

The app is ad-hoc signed. If Gatekeeper complains, right-click the app and choose Open.

Settings, at the bottom of the panel, let you hide providers you don't use, show only the tightest
number in the menu bar, and launch at login.

## Command line

```sh
swift run LimitsBar --dump              # print normalized usage as JSON
swift run LimitsBar --snapshot out.png  # render the panel to a PNG
swift test
```

## Adding a provider

Implement `UsageProvider` in `Sources/LimitsBarCore/Providers/`. Return windows as remaining
percent with an optional reset date, then add the provider to `Providers.all()` and `ProviderID`.

## License

MIT
