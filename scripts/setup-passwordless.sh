#!/usr/bin/env bash
# Setup passwordless battery limit switching for Omarchy
set -euo pipefail

echo "==> Setting up passwordless battery limit switching for Omarchy..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Helper script installation
sudo install -m 755 -d /usr/local/bin
sudo tee /usr/local/bin/omarchy-battery-limit > /dev/null << 'HELPER'
#!/usr/bin/env bash
set -euo pipefail

BAT_PATH=""
for d in /sys/class/power_supply/BAT* /sys/class/power_supply/battery; do
  if [[ -f "$d/charge_control_end_threshold" ]]; then
    BAT_PATH="$d"
    break
  fi
done

TMPFILES_PATH="/etc/tmpfiles.d/battery-limiter.conf"

cmd="${1:-get}"

case "$cmd" in
  get)
    if [[ -n "$BAT_PATH" ]]; then
      limit=$(cat "$BAT_PATH/charge_control_end_threshold")
      echo "supported=true"
      echo "limit=$limit"
    else
      echo "supported=false"
      echo "limit=100"
    fi
    ;;
  set)
    pct="${2:-100}"
    if ! [[ "$pct" =~ ^[0-9]+$ ]] || (( pct < 50 || pct > 100 )); then
      echo "Invalid percentage: $pct" >&2
      exit 1
    fi
    if [[ -z "$BAT_PATH" ]]; then
      echo "Battery charge control not supported" >&2
      exit 1
    fi
    echo "$pct" > "$BAT_PATH/charge_control_end_threshold"
    if (( pct == 100 )); then
      rm -f "$TMPFILES_PATH"
    else
      mkdir -p /etc/tmpfiles.d
      printf 'w %s/charge_control_end_threshold - - - - %s\n' "$BAT_PATH" "$pct" > "$TMPFILES_PATH"
    fi
    ;;
  *)
    echo "Usage: $0 {get|set <pct>}" >&2
    exit 1
    ;;
esac
HELPER
sudo chmod 755 /usr/local/bin/omarchy-battery-limit

# Polkit rule installation
sudo tee /etc/polkit-1/rules.d/90-omarchy-battery-limit.rules > /dev/null << 'RULE'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "/usr/local/bin/omarchy-battery-limit" &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
RULE
sudo chmod 644 /etc/polkit-1/rules.d/90-omarchy-battery-limit.rules

echo "==> Done! You can now switch charge limits instantly with zero password prompts."
