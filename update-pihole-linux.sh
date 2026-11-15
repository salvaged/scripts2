#!/usr/bin/env bash
#
# update-pihole-linux.sh
#
# Weekly Pi-hole (Docker) updater for Linux. Run it ON the machine where
# Pi-hole runs. "Update" = pull the newest pihole/pihole image and recreate
# the container if the image changed. Config is backed up first.
#
# Usage:
#   ./update-pihole-linux.sh --install-cron [--dir ~/pihole] [--day 0] [--time 05:00]
#   ./update-pihole-linux.sh --remove-cron
#   ./update-pihole-linux.sh --run [--dir ~/pihole]      # update right now
#
#   --dir   folder with docker-compose.yml (default: ~/pihole of the sudo user)
#   --day   0-6, 0 = Sunday (default 0)
#   --time  24h HH:MM, local time (default 05:00)
#
# Re-runs itself with sudo. Schedule: /etc/cron.d/pihole-update
# Log: /var/log/pihole-update.log (rotated weekly)

set -euo pipefail

usage() { sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

ACTION="run"; DAY="0"; TIME="05:00"; DIR=""
SELF_INSTALL="/usr/local/sbin/pihole-update.sh"
CRON_FILE="/etc/cron.d/pihole-update"
LOGROTATE_FILE="/etc/logrotate.d/pihole-update"
LOG_FILE="${PIHOLE_UPDATE_LOG:-/var/log/pihole-update.log}"
CONTAINER="pihole"

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
  if [ -z "$DIR" ]; then
    owner="${SUDO_USER:-root}"
    home="$(getent passwd "$owner" | cut -d: -f6)"
    DIR="${home:-/root}/pihole"
  fi
  [ -d "$DIR" ] || die "Directory not found: $DIR (use --dir)"
  DIR="$(cd "$DIR" && pwd)"
  case "$DIR" in *\'*|*%*) die "--dir must not contain ' or % characters" ;; esac
  compose_found=""
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [ -f "$DIR/$f" ] && compose_found="$f"
  done
  [ -n "$compose_found" ] || die "No compose file in $DIR"
fi

# ------------------------------------------------------------------ update
do_run() {
  if [ -t 1 ]; then exec > >(tee -a "$LOG_FILE") 2>&1; else exec >>"$LOG_FILE" 2>&1; fi

  log "=== Pi-hole update starting (dir: $DIR) ==="
  command -v docker >/dev/null 2>&1 || { log "docker not found"; exit 1; }
  docker info >/dev/null 2>&1 || { log "Docker daemon is not running"; exit 1; }
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
  command -v cron >/dev/null 2>&1 || command -v crond >/dev/null 2>&1 || \
    echo "WARNING: no cron daemon found. Install it first (Ubuntu/Debian: sudo apt install cron)." >&2

  abs_self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  if [ "$abs_self" != "$SELF_INSTALL" ]; then
    install -m 0755 "$abs_self" "$SELF_INSTALL"
  fi

  minute="${TIME#*:}"; hour="${TIME%:*}"
  cat > "$CRON_FILE" <<EOF
# Managed by update-pihole-linux.sh: weekly Pi-hole update
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$minute $hour * * $DAY root $SELF_INSTALL --run --dir '$DIR'
EOF
  chmod 644 "$CRON_FILE"

  cat > "$LOGROTATE_FILE" <<EOF
$LOG_FILE {
    weekly
    rotate 8
    compress
    missingok
    notempty
}
EOF

  days=(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)
  echo "Installed weekly update: every ${days[$DAY]} at $TIME (server local time)"
  echo "  Cron entry : $CRON_FILE"
  echo "  Script     : $SELF_INSTALL"
  echo "  Log        : $LOG_FILE"
  echo "  Test now   : sudo $SELF_INSTALL --run --dir '$DIR'"
}

do_remove() {
  rm -f "$CRON_FILE" "$LOGROTATE_FILE" "$SELF_INSTALL"
  echo "Removed weekly update (cron entry, logrotate config and installed script). Log kept: $LOG_FILE"
}

case "$ACTION" in
  run)     do_run ;;
  install) do_install ;;
  remove)  do_remove ;;
esac
