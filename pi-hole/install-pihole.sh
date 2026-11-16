#!/usr/bin/env bash
#
# install-pihole.sh   (run on your Mac or a Linux workstation)
#
# Copies install-pihole-ubuntu.sh to the target Ubuntu/Debian VM and runs it
# over SSH. Installs Docker (if needed) and starts Pi-hole there.
# You'll be prompted for your sudo password and a Pi-hole admin password.
#
# Usage:   ./install-pihole.sh <user@host | ssh-alias> [timezone]
# Example: ./install-pihole.sh hud America/New_York

set -euo pipefail

TARGET="${1:-}"
TZ_NAME="${2:-America/New_York}"

if [ -z "$TARGET" ] || [ "$TARGET" = "-h" ] || [ "$TARGET" = "--help" ]; then
  echo "Usage: $0 <user@host | ssh-alias> [timezone]"
  echo "Example: $0 hud America/New_York"
  [ -n "$TARGET" ] && exit 0
  exit 2
fi

case "$TZ_NAME" in
  *[!A-Za-z0-9_+/-]*) echo "Invalid timezone: $TZ_NAME" >&2; exit 2 ;;
esac

for c in ssh scp; do
  command -v "$c" >/dev/null 2>&1 || { echo "Missing required command: $c" >&2; exit 1; }
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_SRC="$HERE/install-pihole-ubuntu.sh"
[ -f "$REMOTE_SRC" ] || { echo "Missing $REMOTE_SRC (keep it next to this script)." >&2; exit 1; }

REMOTE_TMP="/tmp/pihole-install.$$.sh"

echo "Copying installer to $TARGET ..."
scp -q "$REMOTE_SRC" "$TARGET:$REMOTE_TMP"

echo "Running installer on $TARGET ..."
ssh -t "$TARGET" "bash '$REMOTE_TMP' --tz '$TZ_NAME'; rc=\$?; rm -f '$REMOTE_TMP'; exit \$rc"
