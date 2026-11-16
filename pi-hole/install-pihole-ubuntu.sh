#!/usr/bin/env bash
#
# install-pihole-ubuntu.sh
#
# Installs Docker Engine (if missing) and runs Pi-hole in Docker on Ubuntu/Debian.
# Run it directly ON the Ubuntu/Debian machine as a normal user with sudo
# rights (not as root). install-pihole.sh (Mac/Linux workstation) and
# install-pihole.ps1 (PowerShell) copy it to the VM and run it over SSH instead.
#
# Usage:  bash install-pihole-ubuntu.sh [--tz America/New_York] [--dir ~/pihole]
#
# The Pi-hole admin password is prompted for, or taken from $PIHOLE_PASSWORD.
# Safe to re-run: existing compose/.env files are backed up before being replaced.

set -euo pipefail

TZ_NAME="America/New_York"
INSTALL_DIR="$HOME/pihole"

while [ $# -gt 0 ]; do
  case "$1" in
    --tz)  TZ_NAME="${2:?--tz needs a value}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:?--dir needs a value}"; shift 2 ;;
    -h|--help)
      echo "Usage: bash $0 [--tz America/New_York] [--dir ~/pihole]"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
[ "$(id -u)" -ne 0 ] || die "Run as a normal user with sudo, not as root."
command -v sudo >/dev/null 2>&1 || die "sudo is required."
[ -r /etc/os-release ] || die "Cannot detect the OS (/etc/os-release missing)."
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) die "Only Ubuntu and Debian are supported (found: ${ID:-unknown})." ;;
esac
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
[ -n "$CODENAME" ] || die "Cannot determine the release codename."

case "$TZ_NAME" in
  *[!A-Za-z0-9_+/-]*) die "Invalid timezone: $TZ_NAME" ;;
esac
[ -e "/usr/share/zoneinfo/$TZ_NAME" ] || echo "WARNING: /usr/share/zoneinfo/$TZ_NAME not found; check the timezone name."

USER_NAME="$(id -un)"
say "Target: $(hostname) ($PRETTY_NAME), user $USER_NAME, install dir $INSTALL_DIR"
sudo -v

# ------------------------------------------------------------------- docker
install_docker() {
  say "Installing Docker Engine from Docker's apt repository"

  local old
  old="$(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc \
         docker-buildx podman-docker containerd runc 2>/dev/null | cut -f1 || true)"
  if [ -n "$old" ]; then
    echo "These packages conflict with Docker's official packages:"
    echo "$old" | sed 's/^/  - /'
    if [ -t 0 ]; then
      read -rp "Remove them and continue? [y/N] " ans
      case "$ans" in [Yy]*) ;; *) die "Aborted." ;; esac
    else
      die "Conflicting packages present and no terminal to confirm removal."
    fi
    # shellcheck disable=SC2086
    sudo apt-get remove -y $old
  fi

  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/${ID}
Suites: ${CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker
}

if command -v docker >/dev/null 2>&1 && sudo docker compose version >/dev/null 2>&1; then
  say "Docker and the Compose plugin are already installed; skipping install"
else
  install_docker
fi
sudo docker info >/dev/null 2>&1 || die "The Docker daemon is not running."

if ! id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx docker; then
  sudo usermod -aG docker "$USER_NAME"
  echo "Added $USER_NAME to the docker group (takes effect at your next login)."
fi

# ------------------------------------------------------------------ port 53
port53_holders() {
  # Ignore docker-proxy so a re-run with Pi-hole already up doesn't trip.
  sudo ss -lntupH 'sport = :53' 2>/dev/null | grep -v docker-proxy || true
}

free_port_53() {
  local holders
  holders="$(port53_holders)"
  if [ -z "$holders" ]; then
    echo "Port 53 is free."
    return 0
  fi

  if echo "$holders" | grep -q 'systemd-resolve'; then
    say "systemd-resolved is holding port 53; turning off its DNS stub listener"
    sudo mkdir -p /etc/systemd/resolved.conf.d
    printf '[Resolve]\nDNSStubListener=no\n' | \
      sudo tee /etc/systemd/resolved.conf.d/pihole.conf >/dev/null
    sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    sudo systemctl restart systemd-resolved
    holders="$(port53_holders)"
  fi

  if [ -n "$holders" ]; then
    echo "$holders" >&2
    die "Something else is still listening on port 53 (see above). Stop it and re-run."
  fi
  echo "Port 53 is free."
}

say "Checking port 53"
free_port_53

# ----------------------------------------------------------------- password
PW=""
get_password() {
  local p1 p2
  if [ -n "${PIHOLE_PASSWORD:-}" ]; then
    PW="$PIHOLE_PASSWORD"
    case "$PW" in *\'*) die "PIHOLE_PASSWORD must not contain a single quote (')." ;; esac
    return 0
  fi
  [ -t 0 ] || die "No terminal to prompt on; set PIHOLE_PASSWORD instead."
  while true; do
    read -rsp "Pi-hole admin password (min 8 chars, no single quote): " p1; echo
    read -rsp "Confirm password: " p2; echo
    if [ "$p1" != "$p2" ]; then echo "Passwords do not match."; continue; fi
    if [ "${#p1}" -lt 8 ]; then echo "Use at least 8 characters."; continue; fi
    case "$p1" in *\'*) echo "A single quote (') is not allowed."; continue ;; esac
    PW="$p1"
    return 0
  done
}
get_password

# ------------------------------------------------------------ compose + .env
say "Writing $INSTALL_DIR/docker-compose.yml and .env"
mkdir -p "$INSTALL_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
for f in docker-compose.yml .env; do
  if [ -e "$INSTALL_DIR/$f" ]; then
    cp -p "$INSTALL_DIR/$f" "$INSTALL_DIR/$f.bak.$STAMP"
    echo "Backed up existing $f to $f.bak.$STAMP"
  fi
done

# The password lives in .env (mode 600), not in the compose file.
( umask 077
  printf "PIHOLE_PASSWORD='%s'\nPIHOLE_TZ=%s\n" "$PW" "$TZ_NAME" > "$INSTALL_DIR/.env" )
PW=""

cat > "$INSTALL_DIR/docker-compose.yml" <<'EOF'
services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"
      - "443:443/tcp"
      # - "67:67/udp"   # only if Pi-hole is your DHCP server (also needs NET_ADMIN)
    environment:
      TZ: "${PIHOLE_TZ}"
      FTLCONF_webserver_api_password: "${PIHOLE_PASSWORD}"
      # Required when using Docker's default bridge network
      FTLCONF_dns_listeningMode: "ALL"
    volumes:
      - "./etc-pihole:/etc/pihole"
    cap_add:
      - SYS_NICE
    restart: unless-stopped
EOF

# -------------------------------------------------------------------- start
cd "$INSTALL_DIR"
say "Pulling image and starting Pi-hole"
sudo docker compose config -q
sudo docker compose pull
sudo docker compose up -d

say "Waiting for Pi-hole to become healthy (up to 90 s)"
status=""
for _ in $(seq 1 45); do
  status="$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' pihole 2>/dev/null || true)"
  [ "$status" = "healthy" ] && break
  sleep 2
done

if [ "$status" != "healthy" ]; then
  echo "Pi-hole did not report healthy (status: ${status:-unknown}). Last log lines:" >&2
  sudo docker logs --tail 30 pihole >&2 || true
  exit 1
fi

# ------------------------------------------------------------------ summary
IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") print $(i + 1)}' | head -n1)"
[ -n "$IP" ] || IP="$(hostname -I | awk '{print $1}')"

say "Pi-hole is up and healthy"
cat <<MSG
  Admin UI : http://${IP}/admin
  Test DNS : dig @${IP} example.com        (from another machine)
  Blocking : dig @${IP} doubleclick.net    (expect 0.0.0.0)
  Config   : ${INSTALL_DIR}  (password is in .env, mode 600)
  Update   : cd ${INSTALL_DIR} && docker compose pull && docker compose up -d

Before pointing your network at it:
  - Make ${IP} a static IP or a DHCP reservation.
  - In Pi-hole Settings > DNS, use real upstream resolvers (never your router/Firewalla).
  - Enable VM autostart on the hypervisor so DNS returns after a host reboot.
MSG
