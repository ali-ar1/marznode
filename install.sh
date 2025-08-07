#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Ensure COLORS array is properly defined
declare -r -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[0;33m'
    [BLUE]='\033[0;34m'
    [PURPLE]='\033[0;35m'
    [CYAN]='\033[0;36m'
    [RESET]='\033[0m'
)

# Check if COLORS array is defined correctly
if [[ -z "${COLORS[BLUE]}" ]]; then
    echo "Error: COLORS array is not properly defined"
    exit 1
fi

SCRIPT_NAME="marznode"
SCRIPT_VERSION="v0.1.4"
SCRIPT_URL="https://raw.githubusercontent.com/ali-ar1/marznode/main/install.sh"
INSTALL_DIR="/var/lib/marznode"
LOG_FILE="${INSTALL_DIR}/marznode.log"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
GITHUB_REPO="https://github.com/marzneshin/marznode.git"
GITHUB_API="https://api.github.com/repos/XTLS/Xray-core/releases"
DEFAULT_XRAY_CONFIG_URL="https://raw.githubusercontent.com/ali-ar1/marznode/main/xray_config.json"
DEFAULT_CERTIFICATE="-----BEGIN CERTIFICATE-----
MIIEnDCCAoQCAQAwDQYJKoZIhvcNAQENBQAwEzERMA8GA1UEAwwIR296YXJnYWgw
IBcNMjQxMDE0MTExNTA5WhgPMjEyNDA5MjAxMTE1MDlaMBMxETAPBgNVBAMMCEdv
emFyZ2FoMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAj6mbif/IaMJw
i0UNzxcFzkYCe09HkdJp92U6xgaqE6fhUJOaRhPwLOnagJQopWR7yZlNaPa7/Nvc
l7alVVVYdqPwlQLu06uIajdSQuwENxK6BSp60zHG7K2vL0365SRT/32g7FK6XS8z
O96miDLWsMrIMRiGHlRAsJ7N8ReaKjaT6E9rKQPHhPGMAQOZPGE12iA0NbI9LZs2
fXhSQgBs9T4b3XDQJArKPeFrdzT3kq2zkkvbpgwo/InEj7Jo/BxbG90wqFC5NKlb
94pXu0rOUVIezdayAEejUAEyzA0gIP1+7/0XQMksJbLscI9sFl0SbjotrHg7Cyy6
AKEnvQm2aMD4LQ6QHurKaW1BBF76N2nWuZOAB2gjXesjWeWT1c6zGgOvFg76MGJl
lIF3qwrvuiOCAkQkNkLEF67suCbTD/1P01GgsA9jCaqzoID65UNMkAEPSAaNUcT3
QhhIyOPKAlRSxNcTFj/PMAHves9fCmarrlcXpikhWXroR+NzCzphjswiK/twje0U
BW+E/4H1DD3OXj8go5SZA3UG1H6aAq3RU+mRZq4bR8p0yluleIYAz1OoLHygq2s8
bPtDuovZl6Rv2cfbsPD+8ucH0O6W8iA+eAb2r55u9++4pQK6VE1L+kGyon6H7FPm
V1262ISvPg9BTdeNpSZlMeSfyJCToEsCAwEAATANBgkqhkiG9w0BAQ0FAAOCAgEA
T1fSdCP8mt+mcFbdLDEs5Dyg/74WuL64ouB38saODH+xMBW4/SdTj+S65sOj8poY
ef3sldMEc2xgv+sjXb5fSTdRqcTFTisS5CQaI+aKSPfXXV+JgmHM4t7991FDhARk
lV9RxCOq+tLi96MtcKLdHOxU/Uf5f+B+BXG3U4ILItjBetXQGrUn83ZtMMeyYjB8
b7vL9RuGr3Lrx6OldYTMSXFZ89eGhqjOFtEEAYU9xpF6XClyTU8xZ4eosRl7L3zM
6GY2uP+3yeXz8tXfc8Noz/FAxD01SKkDOTyOUww+t8VxPKNdXCwKSrNd+EOTqUfH
4iWN7W5z/CQk5KfhGpWYgHFI5TVRRF2+i2j2AE9voYt43BzZDI92gNqp2xsAUUa+
SLoxPfQL9OL6vtssk54wkGIDC6q/GHOWNQ0ZRAqO20NgaFgODh961bUxV8lDymGI
0vnfxCRpmo4OICxxdj950LXRQE9eBTqdKr3AUr2Ye8vp/9kSn5gqen0E73CrXJi/
+BhecoOU+9/wO4lUmGmFlSD+b5IttfxcFhZXaSyvdtJrgcPy3bA+MI7iQiZ9u8nQ
uwIBNqosV1N+hvnSCfOHyZCKQkuVuSVEmpCyZyMBoj8e0VGQPEpanQLPh9iQRVsk
1561fl0TUmIzU1op1KbrW7r8bY9P2CQ4vehroL2/hHs=
-----END CERTIFICATE-----"

DEPENDENCIES=(
    "docker"
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

show_version() {
    log "MarzNode Script Version: $SCRIPT_VERSION"
}

update_script() {
    local script_path="/usr/local/bin/$SCRIPT_NAME"
    
    if [[ -f "$script_path" ]]; then
        log "Updating the script..."
        curl -o "$script_path" $SCRIPT_URL
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
        curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /root/.docker/cli-plugins/docker-compose
        chmod +x /root/.docker/cli-plugins/docker-compose
        local compose_version=$(docker compose version --short)
        success "Docker Compose plugin version ${compose_version} installed."
    }
}

is_installed() { [[ -d "$INSTALL_DIR" && -f "$COMPOSE_FILE" ]]; }
is_running() { docker ps | grep -q "marzneshin-marznode-1"; }

create_directories() {
    mkdir -p "$INSTALL_DIR" "${INSTALL_DIR}/data" "${INSTALL_DIR}/assets"
    wget -O /var/lib/marznode/assets/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
    wget -O /var/lib/marznode/assets/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat
    wget -O /var/lib/marznode/assets/iran.dat https://github.com/bootmortis/iran-hosted-domains/releases/latest/download/iran.dat
}

get_certificate() {
    log "Do you want to use the default Marznode certificate? (y/N or press Enter for default):"
    read -r use_default
    if [[ $use_default =~ ^[Yy]$ ]] || [[ -z $use_default ]]; then
        log "Using default certificate..."
        echo "$DEFAULT_CERTIFICATE" > "${INSTALL_DIR}/client.pem"
        success "Default certificate saved to ${INSTALL_DIR}/client.pem"
    else
        log "Please paste the Marznode certificate from the Marzneshin panel (press Enter on an empty line to finish):"
        > "${INSTALL_DIR}/client.pem"
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                break
            fi
            echo "$line" >> "${INSTALL_DIR}/client.pem"
        done
        echo
        success "Certificate saved to ${INSTALL_DIR}/client.pem"
    fi
}

show_xray_versions() {
    log "Available Xray versions:"
    curl -s "$GITHUB_API" | jq -r '.[0:20] | .[] | .tag_name' | nl
}

select_xray_version() {
    show_xray_versions
    local choice
    read -p "Select Xray version (1-20): " choice
    local selected_version=$(curl -s "$GITHUB_API" | jq -r ".[0:20] | .[$((choice-1))] | .tag_name")

    echo "Selected Xray version: $selected_version"
    while true; do
        read -p "Confirm selection? (Y/n): " confirm
        if [[ $confirm =~ ^[Yy]$ ]] || [[ -z $confirm ]]; then
            download_xray_core "$selected_version"
            return 0
        elif [[ $confirm =~ ^[Nn]$ ]]; then
            echo "Selection cancelled. Please choose again."
            return 1
        else
            echo "Invalid input. Please enter Y or n."
        fi
    done
}

download_xray_core() {
    local version="$1"
    case "$(uname -m)" in
        'i386' | 'i686') arch='32' ;;
        'amd64' | 'x86_64') arch='64' ;;
        'armv5tel') arch='arm32-v5' ;;
        'armv6l')
        arch='arm32-v6'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || arch='arm32-v5'
        ;;
        'armv7' | 'armv7l')
        arch='arm32-v7a'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || arch='arm32-v5'
        ;;
        'armv8' | 'aarch64') arch='arm64-v8a' ;;
        'mips') arch='mips32' ;;
        'mipsle') arch='mips32le' ;;
        'mips64')
        arch='mips64'
        lscpu | grep -q "Little Endian" && arch='mips64le'
        ;;
        'mips64le') arch='mips64le' ;;
        'ppc64') arch='ppc64' ;;
        'ppc64le') arch='ppc64le' ;;
        'riscv64') arch='riscv64' ;;
        's390x') arch='s390x' ;;
        *)
        error "The architecture is not supported."
        exit 1
        ;;
    esac
    local xray_filename="Xray-linux-${arch}.zip"
    local download_url="https://github.com/XTLS/Xray-core/releases/download/${version}/${xray_filename}"

    wget -q --show-progress "$download_url" -O "/tmp/${xray_filename}"
    unzip -o "/tmp/${xray_filename}" -d "${INSTALL_DIR}"
    rm "/tmp/${xray_filename}"

    chmod +x "${INSTALL_DIR}/xray"

    wget -q --show-progress "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" -O "${INSTALL_DIR}/data/geoip.dat"
    wget -q --show-progress "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" -O "${INSTALL_DIR}/data/geosite.dat"

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

    if [ -d "${INSTALL_DIR}/repo" ]; then
        rm -rf "${INSTALL_DIR}/repo"
    fi
    git clone "$GITHUB_REPO" "${INSTALL_DIR}/repo"
    cp "${INSTALL_DIR}/repo/xray_config.json" "${INSTALL_DIR}/xray_config.json"
    
    local replace_config
    read -p "Do you want to use the default xray_config.json? (y/N or press Enter for default): " replace_config
    if [[ $replace_config =~ ^[Yy]$ ]] || [[ -z $replace_config ]]; then
        log "Downloading default xray_config.json from $DEFAULT_XRAY_CONFIG_URL..."
        rm -f "${INSTALL_DIR}/xray_config.json"
        wget -q --show-progress "$DEFAULT_XRAY_CONFIG_URL" -O "${INSTALL_DIR}/xray_config.json" || error "Failed to download default xray_config.json from $DEFAULT_XRAY_CONFIG_URL"
        jq . "${INSTALL_DIR}/xray_config.json" > /dev/null 2>&1 || error "Downloaded xray_config.json is not a valid JSON file"
        success "Default xray_config.json downloaded successfully"
    else
        local config_url
        read -p "Enter the URL for the new xray_config.json: " config_url
        if [[ -n "$config_url" ]]; then
            log "Downloading new xray_config.json from $config_url..."
            rm -f "${INSTALL_DIR}/xray_config.json"
            wget -q --show-progress "$config_url" -O "${INSTALL_DIR}/xray_config.json" || error "Failed to download xray_config.json from $config_url"
            jq . "${INSTALL_DIR}/xray_config.json" > /dev/null 2>&1 || error "Downloaded xray_config.json is not a valid JSON file"
            success "xray_config.json downloaded successfully"
        else
            error "No URL provided. Aborting config replacement."
        fi
    fi

    while true; do
        if select_xray_version; then
            break
        fi
    done
        
    setup_docker_compose "$port"
    
    docker compose -f "$COMPOSE_FILE" up -d
    
    if command -v ufw &> /dev/null; then
        ufw allow "$port"
        log "Firewall rule added for port $port"
    else
        warn "ufw not found. Please manually open port $INSTALL_DIR in your firewall."
    fi
    
    success "MarzNode installed successfully!"
}

uninstall_marznode() {
    log "Uninstalling MarzNode..."
    if [[ -f "$COMPOSE_FILE" ]]; then
        docker compose -f "$COMPOSE_FILE" down --remove-orphans
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
    docker compose -f "$COMPOSE_FILE" pull || error "Failed to pull latest Docker image."

    local replace_config
    read -p "Do you want to use the default xray_config.json? (y/N or press Enter for default): " replace_config
    if [[ $replace_config =~ ^[Yy]$ ]] || [[ -z $replace_config ]]; then
        log "Downloading default xray_config.json from $DEFAULT_XRAY_CONFIG_URL..."
        rm -f "${INSTALL_DIR}/xray_config.json"
        wget -q --show-progress "$DEFAULT_XRAY_CONFIG_URL" -O "${INSTALL_DIR}/xray_config.json" || error "Failed to download default xray_config.json from $DEFAULT_XRAY_CONFIG_URL"
        jq . "${INSTALL_DIR}/xray_config.json" > /dev/null 2>&1 || error "Downloaded xray_config.json is not a valid JSON file"
        success "Default xray_config.json downloaded successfully"
    else
        local config_url
        read -p "Enter the URL for the new xray_config.json: " config_url
        if [[ -n "$config_url" ]]; then
            log "Downloading new xray_config.json from $config_url..."
            rm -f "${INSTALL_DIR}/xray_config.json"
            wget -q --show-progress "$config_url" -O "${INSTALL_DIR}/xray_config.json" || error "Failed to download xray_config.json from $config_url"
            jq . "${INSTALL_DIR}/xray_config.json" > /dev/null 2>&1 || error "Downloaded xray_config.json is not a valid JSON file"
            success "xray_config.json downloaded successfully"
        else
            error "No URL provided. Aborting config replacement."
        fi
    fi

    log "Selecting new Xray version..."
    while true; do
        if select_xray_version; then
            break
        fi
    done

    log "Restarting MarzNode service..."
    docker compose -f "$COMPOSE_FILE" down
    docker compose -f "$COMPOSE_FILE" up -d || error "Failed to restart MarzNode service."

    success "MarzNode updated successfully!"
}

manage_service() {
    if ! is_installed; then
        error "MarzNode is not installed. Please install it first."
        return 1
    fi

    local action=$1
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
            docker compose -f "$COMPOSE_FILE" down
            docker compose -f "$COMPOSE_FILE" up -d
            success "MarzNode restarted"
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
    
    curl -s -o "$script_path" $SCRIPT_URL
    chmod +x "$script_path"
    success "Script installed successfully. You can now use '$SCRIPT_NAME' command from anywhere."
}

uninstall_script() {
    local script_path="/usr/local/bin/$SCRIPT_NAME"
    if [[ -f "$script_path" ]]; then
        rm "$script_path"
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
