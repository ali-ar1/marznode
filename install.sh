#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# MarzNode Installer / Manager
# Version: v0.1.7
# Notes:
#  - Always refreshes certs/ from repo on install & update (no prompt)
#  - client.pem: if Y/Enter => download default from repo; if N => prompt paste
#  - Xray core:
#      * If Y/Enter => download default release zip from GitHub (arch-aware)
#      * If N and URL provided => download from given URL
#      * If N and empty input => use built-in binary from app repo
# ==============================================================================

# Colors
declare -r -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[0;33m'
    [BLUE]='\033[0;34m'
    [PURPLE]='\033[0;35m'
    [CYAN]='\033[0;36m'
    [RESET]='\033[0m'
)

if [[ -z "${COLORS[BLUE]}" ]]; then
    echo "Error: COLORS array is not properly defined"
    exit 1
fi

SCRIPT_NAME="marznode"
SCRIPT_VERSION="v0.1.7"
SCRIPT_URL="https://raw.githubusercontent.com/ali-ar1/marznode/main/install.sh"
INSTALL_DIR="/var/lib/marznode"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"

# GitHub paths
GITHUB_REPO_APP="https://github.com/marzneshin/marznode.git"   # app repo (for built-in xray)
GITHUB_API_XRAY="https://api.github.com/repos/XTLS/Xray-core/releases"
DEFAULT_XRAY_CONFIG_URL="https://raw.githubusercontent.com/ali-ar1/marznode/main/xray_config.json"
CLIENT_PEM_URL="https://raw.githubusercontent.com/ali-ar1/marznode/main/client.pem"
CERTS_REPO="https://github.com/ali-ar1/marznode.git"
CERTS_DIR_IN_REPO="certs"
INSTALL_CERTS_DIR="${INSTALL_DIR}/certs"

DEPENDENCIES=("docker" "curl" "wget" "unzip" "git" "jq")

log() { echo -e "${COLORS[BLUE]}[INFO]${COLORS[RESET]} $*"; }
warn() { echo -e "${COLORS[YELLOW]}[WARN]${COLORS[RESET]} $*" >&2; }
error() { echo -e "${COLORS[RED]}[ERROR]${COLORS[RESET]} $*" >&2; exit 1; }
success() { echo -e "${COLORS[GREEN]}[SUCCESS]${COLORS[RESET]} $*"; }

check_root() { [[ $EUID -eq 0 ]] || error "This script must be run as root"; }

show_version() { log "MarzNode Script Version: $SCRIPT_VERSION"; }

update_script() {
    local script_path="/usr/local/bin/$SCRIPT_NAME"
    if [[ -f "$script_path" ]]; then
        log "Updating the script..."
        curl -fsSL -o "$script_path" "$SCRIPT_URL" || error "Failed to download script"
        chmod +x "$script_path"
        success "Script updated to the latest version!"
        echo "Current version: $SCRIPT_VERSION"
    else
        warn "Script is not installed. Use 'install-script' command to install the script first."
    fi
}

check_dependencies() {
    local missing_deps=()
    for dep in "${DEPENDENCIES[@]}"; do
        command -v "$dep" &>/dev/null || missing_deps+=("$dep")
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "Installing missing dependencies: ${missing_deps[*]}"
        apt update && apt install -y "${missing_deps[@]}" || warn "Some dependencies might have failed to install."
    fi

    command -v docker &>/dev/null || { log "Installing Docker..."; curl -fsSL https://get.docker.com | sh; }
    docker compose version &>/dev/null || {
        log "Installing Docker Compose plugin..."
        mkdir -p /root/.docker/cli-plugins
        curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /root/.docker/cli-plugins/docker-compose
        chmod +x /root/.docker/cli-plugins/docker-compose
        local compose_version=$(docker compose version --short || true)
        success "Docker Compose plugin ${compose_version:-installed}";
    }
}

is_installed() { [[ -d "$INSTALL_DIR" && -f "$COMPOSE_FILE" ]]; }
is_running() { docker ps | grep -q "marzneshin-marznode-1"; }

create_directories() {
    mkdir -p "$INSTALL_DIR" "${INSTALL_DIR}/data" "${INSTALL_DIR}/assets" "$INSTALL_CERTS_DIR"
    wget -q -O /var/lib/marznode/assets/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat || true
    wget -q -O /var/lib/marznode/assets/geoip.dat   https://github.com/v2fly/geoip/releases/latest/download/geoip.dat || true
    wget -q -O /var/lib/marznode/assets/iran.dat    https://github.com/bootmortis/iran-hosted-domains/releases/latest/download/iran.dat || true
}

# --- Certs helpers ------------------------------------------------------------
refresh_certs_folder() {
    log "Refreshing SSL certs folder from repo..."
    rm -rf /tmp/marznode_repo
    git clone --depth=1 "$CERTS_REPO" /tmp/marznode_repo || error "Failed to clone certs repo $CERTS_REPO"
    mkdir -p "$INSTALL_CERTS_DIR"
    rm -rf "${INSTALL_CERTS_DIR:?}"/* || true
    if [[ -d "/tmp/marznode_repo/${CERTS_DIR_IN_REPO}" ]]; then
        cp -r "/tmp/marznode_repo/${CERTS_DIR_IN_REPO}/." "$INSTALL_CERTS_DIR/" || error "Failed to copy certs folder"
        success "SSL certs copied to $INSTALL_CERTS_DIR"
    else
        warn "No '${CERTS_DIR_IN_REPO}' directory found in repo."
    fi
    rm -rf /tmp/marznode_repo || true
}

get_certificate() {
    log "Do you want to use the default panel client.pem from repo? (y/N or press Enter for default):"
    read -r use_default
    if [[ $use_default =~ ^[Yy]$ ]] || [[ -z $use_default ]]; then
        log "Downloading default client.pem..."
        wget -q -O "${INSTALL_DIR}/client.pem" "$CLIENT_PEM_URL" || error "Failed to download client.pem from $CLIENT_PEM_URL"
        success "client.pem saved to ${INSTALL_DIR}/client.pem"
    else
        log "Please paste the MarzNode certificate from the panel (press Enter on an empty line to finish):"
        > "${INSTALL_DIR}/client.pem"
        while IFS= read -r line; do
            [[ -z "$line" ]] && break
            echo "$line" >> "${INSTALL_DIR}/client.pem"
        done
        echo
        success "Custom client.pem saved to ${INSTALL_DIR}/client.pem"
    fi
    refresh_certs_folder
}

show_xray_versions() {
    log "Available Xray versions:"
    curl -s "$GITHUB_API_XRAY" | jq -r '.[0:20] | .[] | .tag_name' | nl
}

# --- Xray selection per user's rule ------------------------------------------
select_xray_version_and_source() {
    show_xray_versions
    local choice
    read -p "Select Xray version (1-20): " choice
    local selected_version=$(curl -s "$GITHUB_API_XRAY" | jq -r ".[0:20] | .[$((choice-1))] | .tag_name")
    [[ -z "$selected_version" || "$selected_version" == "null" ]] && error "Invalid selection"
    echo "Selected Xray version: $selected_version"

    while true; do
        read -p "Use default GitHub download link? (Y/n): " yn
        if [[ $yn =~ ^[Yy]$ ]] || [[ -z $yn ]]; then
            XRAY_DOWNLOAD_MODE="default"
            XRAY_SELECTED_VERSION="$selected_version"
            XRAY_CUSTOM_URL=""
            return 0
        elif [[ $yn =~ ^[Nn]$ ]]; then
            read -p "Enter custom Xray URL (press Enter to use built-in binary from app repo): " custom_url
            if [[ -z "$custom_url" ]]; then
                XRAY_DOWNLOAD_MODE="builtin"
                XRAY_SELECTED_VERSION="$selected_version"
                XRAY_CUSTOM_URL=""
                return 0
            else
                XRAY_DOWNLOAD_MODE="custom"
                XRAY_SELECTED_VERSION="$selected_version"
                XRAY_CUSTOM_URL="$custom_url"
                return 0
            fi
        else
            echo "Invalid input. Please enter Y or n."
        fi
    done
}

resolve_arch() {
    case "$(uname -m)" in
        'i386'|'i686') echo '32' ;;
        'amd64'|'x86_64') echo '64' ;;
        'armv5tel') echo 'arm32-v5' ;;
        'armv6l') grep Features /proc/cpuinfo | grep -qw 'vfp' && echo 'arm32-v6' || echo 'arm32-v5' ;;
        'armv7'|'armv7l') grep Features /proc/cpuinfo | grep -qw 'vfp' && echo 'arm32-v7a' || echo 'arm32-v5' ;;
        'armv8'|'aarch64') echo 'arm64-v8a' ;;
        'mips') echo 'mips32' ;;
        'mipsle') echo 'mips32le' ;;
        'mips64') lscpu | grep -q "Little Endian" && echo 'mips64le' || echo 'mips64' ;;
        'mips64le') echo 'mips64le' ;;
        'ppc64') echo 'ppc64' ;;
        'ppc64le') echo 'ppc64le' ;;
        'riscv64') echo 'riscv64' ;;
        's390x') echo 's390x' ;;
        *) error "Unsupported architecture" ;;
    esac
}

download_xray_core() {
    local mode="$1"          # default|custom|builtin
    local version="$2"       # tag like v1.x.x
    local custom_url="${3:-}"
    local arch
    arch=$(resolve_arch)

    if [[ "$mode" == "builtin" ]]; then
        log "Using built-in Xray core binary from app repo..."
        rm -rf /tmp/marznode_repo
        git clone --depth=1 "$GITHUB_REPO_APP" /tmp/marznode_repo || error "Failed to clone app repo"
        if [[ -f /tmp/marznode_repo/xray ]]; then
            cp /tmp/marznode_repo/xray "$INSTALL_DIR/xray" || error "Failed to copy built-in Xray binary"
            chmod +x "$INSTALL_DIR/xray"
            rm -rf /tmp/marznode_repo
            success "Built-in Xray binary installed."
        else
            rm -rf /tmp/marznode_repo
            error "Built-in Xray binary not found in app repo"
        fi
        return
    fi

    local url
    if [[ "$mode" == "custom" ]]; then
        url="$custom_url"
    else
        local xray_filename="Xray-linux-${arch}.zip"
        url="https://github.com/XTLS/Xray-core/releases/download/${version}/${xray_filename}"
    fi

    log "Downloading Xray core from: $url"
    wget -q --show-progress "$url" -O "/tmp/xray.zip" || error "Failed to download Xray core"
    unzip -o "/tmp/xray.zip" -d "$INSTALL_DIR" || error "Failed to unzip Xray"
    rm -f /tmp/xray.zip
    chmod +x "$INSTALL_DIR/xray"

    # Refresh rule datasets
    wget -q --show-progress "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"   -O "${INSTALL_DIR}/data/geoip.dat" || true
    wget -q --show-progress "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" -O "${INSTALL_DIR}/data/geosite.dat" || true

    success "Xray-core ${version} installed successfully."
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
      - ${INSTALL_DIR}:/var/lib/marznode
      - /var/lib/marznode/assets:/usr/local/share/xray
EOF
    success "Docker Compose file created at $COMPOSE_FILE"
}

install_marznode() {
    if [ -d "./marznode" ]; then
        warn "Found 'marznode' directory in current working directory. Removing it..."
        rm -rf ./marznode || error "Failed to remove ./marznode directory"
        log "Removing existing $INSTALL_DIR directory..."
        rm -rf "$INSTALL_DIR" || error "Failed to remove $INSTALL_DIR directory"
    else
        log "No 'marznode' directory found in current working directory. Proceeding..."
    fi

    if is_installed; then
        warn "MarzNode is already installed. Removing previous installation..."
        uninstall_marznode
    fi

    check_dependencies
    create_directories

    echo
    get_certificate
    echo

    local port
    while true; do
        read -p "Enter the service port (default: 5566): " port
        port=${port:-5566}
        if ! ss -tuln | grep -q ":$port "; then
            break
        else
            warn "Port $port is already in use. Please choose a different port."
        fi
    done
    echo

    # clone app repo to fetch default xray_config and/or built-in xray
    rm -rf "${INSTALL_DIR}/repo" || true
    git clone "$GITHUB_REPO_APP" "${INSTALL_DIR}/repo" || error "Failed to clone app repo"
    cp "${INSTALL_DIR}/repo/xray_config.json" "${INSTALL_DIR}/xray_config.json" || true

    local replace_config
    read -p "Use default xray_config.json from ${DEFAULT_XRAY_CONFIG_URL}? (y/N or Enter for default): " replace_config
    if [[ $replace_config =~ ^[Yy]$ ]] || [[ -z $replace_config ]]; then
        log "Downloading default xray_config.json..."
        rm -f "${INSTALL_DIR}/xray_config.json"
        wget -q --show-progress "$DEFAULT_XRAY_CONFIG_URL" -O "${INSTALL_DIR}/xray_config.json" || error "Failed to download default xray_config.json"
        jq . "${INSTALL_DIR}/xray_config.json" > /dev/null 2>&1 || error "Downloaded xray_config.json is not a valid JSON file"
        success "Default xray_config.json downloaded successfully"
    else
        local config_url
        read -p "Enter the URL for a custom xray_config.json: " config_url
        if [[ -z "$config_url" ]]; then
        log "Using built-in xray_config.json from ${INSTALL_DIR}/repo/xray_config.json"
        cp "${INSTALL_DIR}/repo/xray_config.json" "${INSTALL_DIR}/xray_config.json" || error "Failed to copy built-in xray_config.json"
        success "Built-in Xray_config.json copied successfully"
    else
        log "Downloading custom xray_config.json..."
        rm -f "${INSTALL_DIR}/xray_config.json"
        wget -q --show-progress "$config_url" -O "${INSTALL_DIR}/xray_config.json" || error "Failed to download xray_config.json"
        jq . "${INSTALL_DIR}/xray_config.json" > /dev/null 2>&1 || error "Downloaded xray_config.json is not a valid JSON file"
        success "Custom xray_config.json downloaded successfully"
    fi

    # Choose and install Xray per rules
    select_xray_version_and_source
    download_xray_core "$XRAY_DOWNLOAD_MODE" "$XRAY_SELECTED_VERSION" "$XRAY_CUSTOM_URL"

    setup_docker_compose "$port"
    docker compose -f "$COMPOSE_FILE" up -d

    if command -v ufw &> /dev/null; then
        ufw allow "$port" || true
        log "Firewall rule added for port $port"
    else
        warn "ufw not found. Please manually open port $port in your firewall."
    fi

    success "MarzNode installed successfully!"

uninstall_marznode() {
    log "Uninstalling MarzNode..."
    if [[ -f "$COMPOSE_FILE" ]]; then
        docker compose -f "$COMPOSE_FILE" down --remove-orphans || true
    fi
    rm -rf "$INSTALL_DIR"
    success "MarzNode uninstalled successfully"
}

update_marznode() {
    if ! is_installed; then
        error "MarzNode is not installed. Please install it first."
        return 1
    fi

    log "Updating MarzNode..."

    log "Pulling latest MarzNode Docker image..."
    docker compose -f "$COMPOSE_FILE" pull || warn "Failed to pull latest Docker image. Continuing..."

    local replace_config
    read -p "Use default xray_config.json from ${DEFAULT_XRAY_CONFIG_URL}? (y/N or Enter for default): " replace_config
    if [[ $replace_config =~ ^[Yy]$ ]] || [[ -z $replace_config ]]; then
        log "Downloading default xray_config.json..."
        rm -f "${INSTALL_DIR}/xray_config.json"
        wget -q --show-progress "$DEFAULT_XRAY_CONFIG_URL" -O "${INSTALL_DIR}/xray_config.json" || error "Failed to download default xray_config.json"
        jq . "${INSTALL_DIR}/xray_config.json" > /dev/null 2>&1 || error "Downloaded xray_config.json is not a valid JSON file"
        success "Default xray_config.json downloaded successfully"
    else
        local config_url
        read -p "Enter the URL for a custom xray_config.json: " config_url
        if [[ -z "$config_url" ]]; then
        log "Using built-in xray_config.json from ${INSTALL_DIR}/repo/xray_config.json"
        cp "${INSTALL_DIR}/repo/xray_config.json" "${INSTALL_DIR}/xray_config.json" || error "Failed to copy built-in xray_config.json"
        success "Built-in Xray_config.json copied successfully"
    else
        log "Downloading custom xray_config.json..."
        rm -f "${INSTALL_DIR}/xray_config.json"
        wget -q --show-progress "$config_url" -O "${INSTALL_DIR}/xray_config.json" || error "Failed to download xray_config.json"
        jq . "${INSTALL_DIR}/xray_config.json" > /dev/null 2>&1 || error "Downloaded xray_config.json is not a valid JSON file"
        success "Custom xray_config.json downloaded successfully"
    fi

    # Refresh client.pem (prompted) and certs folder (always)
    get_certificate

    # Choose and install Xray per rules
    select_xray_version_and_source
    download_xray_core "$XRAY_DOWNLOAD_MODE" "$XRAY_SELECTED_VERSION" "$XRAY_CUSTOM_URL"

    log "Restarting MarzNode service..."
    docker compose -f "$COMPOSE_FILE" down || true
    docker compose -f "$COMPOSE_FILE" up -d || error "Failed to restart MarzNode service."

    success "MarzNode updated successfully!"
}

manage_service() {
    if ! is_installed; then
        error "MarzNode is not installed. Please install it first."
        return 1
    fi

    local action=${1:-}
    case "$action" in
        start)
            if is_running; then
                warn "MarzNode is already running."
            else
                log "Starting MarzNode..."
                docker compose -f "$COMPOSE_FILE" up -d
                success "MarzNode started"
            fi
            ;;
        stop)
            if ! is_running; then
                warn "MarzNode is not running."
            else
                log "Stopping MarzNode..."
                docker compose -f "$COMPOSE_FILE" down
                success "MarzNode stopped"
            fi
            ;;
        restart)
            log "Restarting MarzNode..."
            docker compose -f "$COMPOSE_FILE" down || true
            docker compose -f "$COMPOSE_FILE" up -d
            success "MarzNode restarted"
            ;;
        *)
            print_help
            ;;
    esac
}

show_status() {
    if ! is_installed; then
        error "Status: Not Installed"
        return 1
    fi
    if is_running; then
        success "Status: Up and Running [uptime: $(docker ps --filter "name=marzneshin-marznode-1" --format "{{.Status}}")]"
    else
        error "Status: Stopped"
    fi
}

show_logs() {
    log "Showing MarzNode logs (press Ctrl+C to exit):"
    docker compose -f "$COMPOSE_FILE" logs --tail=100 -f
}

install_script() {
    local script_path="/usr/local/bin/$SCRIPT_NAME"
    curl -fsSL -o "$script_path" "$SCRIPT_URL" || error "Failed to download script"
    chmod +x "$script_path"
    success "Script installed successfully. You can now use '$SCRIPT_NAME' from anywhere."
}

uninstall_script() {
    local script_path="/usr/local/bin/$SCRIPT_NAME"
    if [[ -f "$script_path" ]]; then
        rm -f "$script_path"
        success "Script uninstalled successfully from $script_path"
    else
        warn "Script not found at $script_path. Nothing to uninstall."
    fi
}

print_help() {
    echo
    echo "Usage: $SCRIPT_NAME <command>"
    echo
    echo "Commands [$SCRIPT_VERSION]:"
    echo "  install          Install MarzNode"
    echo "  uninstall        Uninstall MarzNode"
    echo "  update           Update MarzNode to the latest version"
    echo "  start            Start MarzNode service"
    echo "  stop             Stop MarzNode service"
    echo "  restart          Restart MarzNode service"
    echo "  status           Show MarzNode and Xray status"
    echo "  logs             Show MarzNode logs"
    echo "  version          Show script version"
    echo "  install-script   Install this script to /usr/local/bin"
    echo "  uninstall-script Uninstall this script from /usr/local/bin"
    echo "  update-script    Update this script to the latest version"
    echo "  help             Show this help message"
    echo
}

main() {
    check_root
    if [[ $# -eq 0 ]]; then
        print_help
        exit 0
    fi
    case "$1" in
        install)         install_marznode ;;
        uninstall)       uninstall_marznode ;;
        update)          update_marznode ;;
        start|stop|restart) manage_service "$1" ;;
        status)          show_status ;;
        logs|log)        show_logs ;;
        version)         show_version ;;
        install-script)  install_script ;;
        uninstall-script) uninstall_script ;;
        update-script)   update_script ;;
        help|*)          print_help ;;
    esac
}

main "$@"
