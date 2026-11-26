#!/usr/bin/env bash
# Captures raw screenshots for the website from build/LimitsBar.app in demo mode (no real accounts).
#   ./scripts/site-captures.sh <out-dir>
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: site-captures.sh <out-dir>}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
BIN=build/LimitsBar.app/Contents/MacOS/LimitsBar
CFG="$(mktemp -d)"
trap 'rm -rf "$CFG"' EXIT

run() { # name, seconds, env...
  local name="$1" secs="$2"; shift 2
  # Only this script's own instance is stopped; an installed copy keeps running.
  env LIMITSBAR_DEMO=1 XDG_CONFIG_HOME="$CFG" "$@" "$BIN" ${LANG_ARGS:-} >/dev/null 2>&1 &
  local pid=$!
  /usr/bin/osascript -e "delay $secs"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

mkdir -p "$CFG/limits-bar"
for style in compact bars numbers; do
  printf '{"menuBar":"%s","alerts":{"enabled":false}}' "$style" > "$CFG/limits-bar/config.json"
  run "status-$style" 4 LIMITSBAR_CAPTURE="$OUT/status-$style.png"
done
printf '{"alerts":{"enabled":false}}' > "$CFG/limits-bar/config.json"
for look in dark light; do
  run "menu-$look" 7 LIMITSBAR_APPEARANCE="$look" LIMITSBAR_CAPTURE_MENU="$OUT/menu-$look.png"
done
for lang in ru ja de; do
  LANG_ARGS="-AppleLanguages ($lang)" run "menu-$lang" 7 LIMITSBAR_APPEARANCE=dark LIMITSBAR_CAPTURE_MENU="$OUT/menu-$lang.png"
done
rm -f "$OUT"/*-early.png 2>/dev/null || true
ls "$OUT"
