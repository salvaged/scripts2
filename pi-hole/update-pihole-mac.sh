#!/usr/bin/env bash
#
# update-pihole-mac.sh
#
# Weekly Pi-hole (Docker Desktop) updater for macOS. Run it ON the Mac where
# Pi-hole runs. "Update" = pull the newest pihole/pihole image and recreate
# the container if the image changed. Config is backed up first.
#
# Usage:
#   ./update-pihole-mac.sh --install-cron [--dir ~/pihole] [--day 0] [--time 05:00]
#   ./update-pihole-mac.sh --remove-cron
#   ./update-pihole-mac.sh --run [--dir ~/pihole]        # update right now
#
#   --dir   folder with docker-compose.yml (default: ~/pihole)
#   --day   0-6, 0 = Sunday (default 0)
#   --time  24h HH:MM, local time (default 05:00)
#
# Uses your user crontab. Log: ~/Library/Logs/pihole-update.log
# The Mac must be awake and Docker Desktop running at the scheduled time;
# cron does not catch up on missed runs.

set -euo pipefail

usage() { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# cron runs with a minimal PATH; make sure Docker's CLI is findable.
export PATH="/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin:$HOME/.docker/bin:$PATH"

ACTION="run"; DAY="0"; TIME="05:00"; DIR="$HOME/pihole"
SELF_INSTALL="$HOME/.local/bin/pihole-update.sh"
LOG_FILE="${PIHOLE_UPDATE_LOG:-$HOME/Library/Logs/pihole-update.log}"
CONTAINER="pihole"
MARK="# pihole-weekly-update"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --install-cron) ACTION="install"; shift ;;
    --remove-cron)  ACTION="remove";  shift ;;
    --run)          ACTION="run";     shift ;;
    --dir)  DIR="${2:?--dir needs a value}";   shift 2 ;;
    --day)  DAY="${2:?--day needs a value}";   shift 2 ;;
    --time) TIME="${2:?--time needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

case "$DAY" in [0-6]) ;; *) die "--day must be 0-6 (0 = Sunday)" ;; esac
printf '%s' "$TIME" | grep -Eq '^([01][0-9]|2[0-3]):[0-5][0-9]$' || die "--time must be HH:MM (24h)"

if [ "$ACTION" != "remove" ]; then
  [ -d "$DIR" ] || die "Directory not found: $DIR (use --dir)"
  DIR="$(cd "$DIR" && pwd)"
  case "$DIR" in *\"*|*%*) die "--dir must not contain \" or % characters" ;; esac
  compose_found=""
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [ -f "$DIR/$f" ] && compose_found="$f"
  done
  [ -n "$compose_found" ] || die "No compose file in $DIR"
fi

# ------------------------------------------------------------------ update
do_run() {
  mkdir -p "$(dirname "$LOG_FILE")"
  if [ -t 1 ]; then exec > >(tee -a "$LOG_FILE") 2>&1; else exec >>"$LOG_FILE" 2>&1; fi

  log "=== Pi-hole update starting (dir: $DIR) ==="
  command -v docker >/dev/null 2>&1 || { log "docker CLI not found"; exit 1; }
  docker info >/dev/null 2>&1 || { log "Docker Desktop is not running; skipping this run"; exit 1; }
  cd "$DIR"

  if [ -d "$DIR/etc-pihole" ]; then
    mkdir -p "$DIR/backups"
    bk="$DIR/backups/etc-pihole-$(date +%Y%m%d-%H%M%S).tar.gz"
    if tar -czf "$bk" -C "$DIR" etc-pihole; then
      log "Config backup: $bk"
      ls -1t "$DIR"/backups/etc-pihole-*.tar.gz 2>/dev/null | tail -n +5 | while read -r old; do rm -f -- "$old"; done
    else
      log "WARNING: config backup failed; continuing"
    fi
  fi

  before="$(docker inspect -f '{{.Image}}' "$CONTAINER" 2>/dev/null || echo none)"
  docker compose pull
  docker compose up -d
  docker image prune -f >/dev/null || true
  after="$(docker inspect -f '{{.Image}}' "$CONTAINER" 2>/dev/null || echo none)"

  status=""
  for _ in $(seq 1 45); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER" 2>/dev/null || true)"
    [ "$status" = "healthy" ] && break
    sleep 2
  done

  if [ "$status" != "healthy" ]; then
    log "FAILED: container status is '${status:-unknown}' after update. Last logs:"
    docker logs --tail 30 "$CONTAINER" 2>&1 || true
    log "Restore: stop the stack, extract the newest backup in $DIR/backups, start again."
    exit 1
  fi

  if [ "$before" = "$after" ]; then log "Already on the latest image; nothing changed."; else log "Updated to a newer image."; fi
  docker exec "$CONTAINER" pihole -v 2>&1 | sed 's/^/    /' || true
  log "=== Done ==="
}

# ------------------------------------------------------------ cron install
do_install() {
  command -v crontab >/dev/null 2>&1 || die "crontab not found"
  mkdir -p "$(dirname "$SELF_INSTALL")"
  abs_self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  if [ "$abs_self" != "$SELF_INSTALL" ]; then
    cp "$abs_self" "$SELF_INSTALL"
    chmod 755 "$SELF_INSTALL"
  fi

  minute="${TIME#*:}"; hour="${TIME%:*}"
  line="$minute $hour * * $DAY \"$SELF_INSTALL\" --run --dir \"$DIR\" $MARK"
  { crontab -l 2>/dev/null | grep -vF "$MARK" || true; echo "$line"; } | crontab -

  days=(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)
  echo "Installed weekly update: every ${days[$DAY]} at $TIME"
  echo "  Script   : $SELF_INSTALL"
  echo "  Log      : $LOG_FILE"
  echo "  Test now : \"$SELF_INSTALL\" --run --dir \"$DIR\""
  echo "  Check    : crontab -l"
  echo "If your project folder is in Documents, Desktop or Downloads, macOS may block cron from"
  echo "reading it. Either keep it in ~/pihole or give /usr/sbin/cron Full Disk Access"
  echo "(System Settings > Privacy & Security > Full Disk Access)."
}

do_remove() {
  if command -v crontab >/dev/null 2>&1; then
    { crontab -l 2>/dev/null | grep -vF "$MARK" || true; } | crontab -
  fi
  rm -f "$SELF_INSTALL"
  echo "Removed weekly update (cron entry and installed script). Log kept: $LOG_FILE"
}

case "$ACTION" in
  run)     do_run ;;
  install) do_install ;;
  remove)  do_remove ;;
esac
