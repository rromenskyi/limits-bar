#!/bin/sh
# Example custom provider for LimitsBar. Prints usage JSON on stdout.
# Replace the body with a real check (an API call, a CLI's own usage command, ...).
#
# Add it to ~/.config/limits-bar/config.json:
#   { "custom": [ { "id": "example", "name": "Example", "tag": "E",
#                   "command": ["/path/to/custom-provider.sh"] } ] }
cat <<JSON
{
  "plan": "Demo",
  "windows": [
    { "label": "Day",  "remainingPercent": 64, "resetsAt": "$(date -u -v+6H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+6 hours' +%Y-%m-%dT%H:%M:%SZ)" },
    { "label": "Week", "usedPercent": 30 }
  ]
}
JSON
