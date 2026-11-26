# LimitsBar

A small macOS menu bar app that shows how much of your coding-agent subscription limits is left:

- **Claude** (Claude Code, Pro/Max/Team sign-in): 5-hour session, weekly, and per-model weekly limits
- **Codex** (OpenAI Codex CLI, ChatGPT sign-in): 5-hour and weekly limits
- **Muse** (Muse Code CLI): rolling window and weekly allowance
- **Devin** (Devin CLI): daily and weekly quota

Any other service can be added with a small script (see [Custom providers](#custom-providers)).

The menu bar shows a letter and two mini bars per provider: the top bar is the short window
(5 hours, or a day), the bottom bar is the tightest longer window (usually the week). Bars use the
menu bar text color and turn orange below 30% and red below 10%. A plain-number style
(`C80 X12 M86 D100`) is available in Settings. Click the item for every window with reset
countdowns.

Providers whose CLI or login isn't found are hidden automatically, so you only see what you use.

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

## Configuration

Settings, at the bottom of the panel, let you hide providers, pick the menu bar style, and turn on
launch at login. Provider and style choices are saved to `~/.config/limits-bar/config.json`
(`$XDG_CONFIG_HOME` is respected). You can also edit the file by hand; it is re-read on every
refresh. All fields are optional:

```json
{
  "menuBar": "bars",
  "disabled": ["devin"],
  "custom": [
    { "id": "example", "name": "Example", "tag": "E",
      "command": ["~/bin/example-quota"], "timeout": 30 }
  ]
}
```

- `menuBar`: `"bars"` (default) or `"numbers"`
- `disabled`: provider ids to hide (`claude`, `codex`, `muse`, `devin`, or a custom id)
- `custom`: extra providers, described below

## Custom providers

A custom provider is any command that prints usage JSON. `command` is the program and its
arguments; `~` is expanded, and a bare name is looked up on `PATH`. The output looks like this:

```json
{
  "plan": "Pro",
  "windows": [
    { "label": "Day",  "remainingPercent": 64, "resetsAt": "2030-01-01T00:00:00Z" },
    { "label": "Week", "usedPercent": 30,      "resetsAt": 1893456000 }
  ]
}
```

Each window takes `remainingPercent` or `usedPercent`, and `resetsAt` as an ISO 8601 string or
unix seconds. Print `{"error": "..."}` to show an error. List windows shortest first: the first
one becomes the top menu bar bar. See [`examples/custom-provider.sh`](examples/custom-provider.sh).

## Command line

```sh
swift run LimitsBar --dump              # print normalized usage as JSON
swift run LimitsBar --snapshot out.png  # render the panel and the menu bar item to PNGs
swift test
```

## Adding a provider

For a built-in provider, implement `UsageProvider` in `Sources/LimitsBarCore/Providers/`. Return
windows as remaining percent with an optional reset date, then register it in
`Providers.builtIns()` and `ProviderID.builtIns`. Pull requests for other services are welcome,
but please test against a real account. For a quick local addition, use a custom provider instead.

## License

MIT
