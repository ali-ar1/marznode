#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="marznode"
SCRIPT_VERSION="v0.1.1"
SCRIPT_URL="https://raw.githubusercontent.com/ali-ar1/marznode/main/install.sh"
INSTALL_DIR="/var/lib/marznode"
LOG_FILE="${INSTALL_DIR}/marznode.log"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
GITHUB_REPO="https://github.com/marzneshin/marznode.git"
GITHUB_API="https://api.github.com/repos/XTLS/Xray-core/releases"

declare -r -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[0;33m'
    [BLUE]='\033[0;34m'
    [PURPLE]='\033[0;35m'
    [CYAN]='\033[0;36m'
    [RESET]='\033[0m'
)

DEPENDENCIES=(
    "docker"
    "docker-compose"
    "curl"
    "wget"
    "unzip"
    "git"
    "jq"
)

log() { echo -e "${COLORS[BLUE]}[INFO]${COLORS[RESET]} $*"; }
warn() { echo -e "${COLORS[YELLOW]}[WARN]${COLORS[RESET]} $*" >&2; }
error() { echo -e "${COLORS[RED]}[ERROR]${COLORS[RESET]} $*" >&2; exit 1; }
success() { echo -e "${COLORS[GREEN]}[SUCCESS]${COLORS[RESET]} $*"; }

check_root() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root"
}

create_directories() {
    mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/data" "$INSTALL_DIR/assets"

    log "Downloading Xray asset files into ${INSTALL_DIR}/assets..."

    wget -q --show-progress -O "$INSTALL_DIR/assets/geosite.dat" https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
    wget -q --show-progress -O "$INSTALL_DIR/assets/geoip.dat" https://github.com/v2fly/geoip/releases/latest/download/geoip.dat
    wget -q --show-progress -O "$INSTALL_DIR/assets/iran.dat" https://github.com/bootmortis/iran-hosted-domains/releases/latest/download/iran.dat

    success "All asset files downloaded to ${INSTALL_DIR}/assets"
}

setup_docker_compose() {
    local port="${1:-55660}"
    cat > "$COMPOSE_FILE" <<EOF
services:
  marznode:
    image: dawsh/marznode:latest
    container_name: marzneshin-marznode-1
    restart: always
    network_mode: host
    command: [ "sh", "-c", "sleep 10 && python3 marznode.py" ]
    environment:
      SERVICE_PORT: "$port"
      XRAY_RESTART_ON_FAILURE: "True"
      XRAY_RESTART_ON_FAILURE_INTERVAL: "5"
      XRAY_VLESS_REALITY_FLOW: "xtls-rprx-vision"
      XRAY_EXECUTABLE_PATH: "/var/lib/marznode/xray"
      XRAY_ASSETS_PATH: "/var/lib/marznode/data"
      XRAY_CONFIG_PATH: "/var/lib/marznode/xray_config.json"
      SING_BOX_EXECUTABLE_PATH: "/usr/local/bin/sing-box"
      HYSTERIA_EXECUTABLE_PATH: "/usr/local/bin/hysteria"
      SSL_CLIENT_CERT_FILE: "/var/lib/marznode/client.pem"
      SSL_KEY_FILE: "./server.key"
      SSL_CERT_FILE: "./server.cert"
    volumes:
      - \${INSTALL_DIR}:/var/lib/marznode
      - /var/lib/marznode/assets:/usr/local/share/xray
EOF
    success "Docker Compose file created at $COMPOSE_FILE"
}

main "$@"
