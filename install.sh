#!/bin/bash

# WireGuard with wg-easy Panel Auto-Installer
# This script automatically installs Docker and sets up WireGuard with wg-easy web panel

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    print_info "Detected OS: $OS $VER"
}

# Install Docker
install_docker() {
    if command -v docker &> /dev/null; then
        print_info "Docker is already installed"
        docker --version
    else
        print_info "Installing Docker..."

        case $OS in
            ubuntu|debian)
                apt-get update
                apt-get install -y ca-certificates curl gnupg lsb-release

                # Add Docker's official GPG key
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                chmod a+r /etc/apt/keyrings/docker.gpg

                # Set up the repository
                echo \
                  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
                  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

                apt-get update
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                ;;
            centos|rhel|fedora)
                yum install -y yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                systemctl start docker
                systemctl enable docker
                ;;
            *)
                print_error "Unsupported OS: $OS"
                exit 1
                ;;
        esac

        print_info "Docker installed successfully"
    fi
}

# Get server IP address
get_server_ip() {
    # Try to get public IP
    SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip || echo "")

    if [[ -z "$SERVER_IP" ]]; then
        # Fallback to local IP
        SERVER_IP=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
    fi

    if [[ -z "$SERVER_IP" ]]; then
        print_warn "Could not detect server IP automatically"
        read -p "Please enter your server's public IP address: " SERVER_IP
    else
        print_info "Detected server IP: $SERVER_IP"
        read -p "Is this correct? (Y/n): " confirm
        if [[ $confirm == "n" || $confirm == "N" ]]; then
            read -p "Please enter your server's public IP address: " SERVER_IP
        fi
    fi
}

# Check if a port is in use
is_port_in_use() {
    local port=$1
    local protocol=$2  # tcp or udp

    if [[ "$protocol" == "tcp" ]]; then
        # Check TCP port
        if ss -tlnH | grep -q ":${port} " || netstat -tln 2>/dev/null | grep -q ":${port} "; then
            return 0  # Port is in use
        fi
    elif [[ "$protocol" == "udp" ]]; then
        # Check UDP port
        if ss -ulnH | grep -q ":${port} " || netstat -uln 2>/dev/null | grep -q ":${port} "; then
            return 0  # Port is in use
        fi
    fi

    return 1  # Port is free
}

# Find next available port
find_available_port() {
    local start_port=$1
    local protocol=$2
    local max_attempts=100
    local port=$start_port

    for ((i=0; i<$max_attempts; i++)); do
        if ! is_port_in_use $port $protocol; then
            echo $port
            return 0
        fi
        ((port++))
    done

    print_error "Could not find available port after checking $max_attempts ports starting from $start_port"
    exit 1
}

# Check and resolve port conflicts
check_port_conflicts() {
    print_info "Checking for port conflicts..."

    # Default ports
    WG_PORT=51820
    WG_UI_PORT=51821

    # Check if .env exists and has custom ports
    if [[ -f .env ]]; then
        if grep -q "^WG_PORT=" .env; then
            WG_PORT=$(grep "^WG_PORT=" .env | cut -d'=' -f2)
        fi
        if grep -q "^WG_UI_PORT=" .env; then
            WG_UI_PORT=$(grep "^WG_UI_PORT=" .env | cut -d'=' -f2)
        fi
    fi

    local original_wg_port=$WG_PORT
    local original_ui_port=$WG_UI_PORT
    local port_changed=false

    # Check WireGuard UDP port
    if is_port_in_use $WG_PORT udp; then
        print_warn "Port $WG_PORT/udp is already in use"
        WG_PORT=$(find_available_port $((WG_PORT + 1)) udp)
        print_info "Using alternative WireGuard port: $WG_PORT/udp"
        port_changed=true
    else
        print_info "WireGuard port $WG_PORT/udp is available"
    fi

    # Check Web UI TCP port
    if is_port_in_use $WG_UI_PORT tcp; then
        print_warn "Port $WG_UI_PORT/tcp is already in use"
        WG_UI_PORT=$(find_available_port $((WG_UI_PORT + 1)) tcp)
        print_info "Using alternative Web UI port: $WG_UI_PORT/tcp"
        port_changed=true
    else
        print_info "Web UI port $WG_UI_PORT/tcp is available"
    fi

    # Export variables for use in other functions
    export WG_PORT
    export WG_UI_PORT

    if [[ "$port_changed" == true ]]; then
        echo ""
        print_warn "Port conflicts detected and resolved:"
        if [[ $original_wg_port -ne $WG_PORT ]]; then
            echo "  - WireGuard: $original_wg_port → $WG_PORT (UDP)"
        fi
        if [[ $original_ui_port -ne $WG_UI_PORT ]]; then
            echo "  - Web UI: $original_ui_port → $WG_UI_PORT (TCP)"
        fi
        echo ""
    fi
}

# Generate secure password
generate_password() {
    if [[ -f .env ]] && grep -q "PASSWORD=" .env; then
        print_info "Password already exists in .env file"
        PASSWORD=$(grep "PASSWORD=" .env | cut -d'=' -f2)
    else
        PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        print_info "Generated secure password for web UI"
    fi
}

# Create .env file
create_env_file() {
    print_info "Creating .env configuration file..."

    # Build port configuration lines
    local wg_port_line=""
    local ui_port_line=""

    # If ports are not defaults, set them explicitly in .env
    if [[ ${WG_PORT:-51820} -ne 51820 ]]; then
        wg_port_line="WG_PORT=${WG_PORT}"
    else
        wg_port_line="# WG_PORT=51820"
    fi

    if [[ ${WG_UI_PORT:-51821} -ne 51821 ]]; then
        ui_port_line="WG_UI_PORT=${WG_UI_PORT}"
    else
        ui_port_line="# WG_UI_PORT=51821"
    fi

    cat > .env <<EOF
# WireGuard Configuration
WG_HOST=${SERVER_IP}
PASSWORD=${PASSWORD}

# WireGuard VPN port (UDP) - Change if needed (default: 51820)
${wg_port_line}

# Web UI port (TCP) - Change if needed (default: 51821)
${ui_port_line}

# Optional: Default DNS servers (default: 1.1.1.1, 1.0.0.1)
# WG_DEFAULT_DNS=1.1.1.1, 1.0.0.1

# Optional: Allowed IPs (default: 0.0.0.0/0, ::/0 for all traffic)
# WG_ALLOWED_IPS=0.0.0.0/0, ::/0

# Optional: Client subnet (default: 10.8.0.0)
# WG_DEVICE=eth0
EOF

    chmod 600 .env
    print_info ".env file created successfully"
}

# Create docker-compose.yml file
create_docker_compose() {
    if [[ -f docker-compose.yml ]]; then
        print_info "docker-compose.yml already exists, skipping..."
        return
    fi

    print_info "Creating docker-compose.yml..."

    cat > docker-compose.yml <<'EOF'
version: "3.8"

services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:latest
    container_name: wg-easy
    environment:
      - WG_HOST=${WG_HOST}
      - PASSWORD=${PASSWORD}
      - WG_PORT=${WG_PORT:-51820}
      - WG_DEFAULT_DNS=${WG_DEFAULT_DNS:-1.1.1.1, 1.0.0.1}
      - WG_ALLOWED_IPS=${WG_ALLOWED_IPS:-0.0.0.0/0, ::/0}
      - WG_PERSISTENT_KEEPALIVE=${WG_PERSISTENT_KEEPALIVE:-25}
      - WG_DEFAULT_ADDRESS=${WG_DEFAULT_ADDRESS:-10.8.0.x}
      - WG_MTU=${WG_MTU:-1420}
    volumes:
      - ./wg-easy:/etc/wireguard
    ports:
      - "${WG_PORT:-51820}:51820/udp"
      - "${WG_UI_PORT:-51821}:51821/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
EOF

    print_info "docker-compose.yml created successfully"
}

# Enable IP forwarding
enable_ip_forward() {
    print_info "Enabling IP forwarding..."

    # Enable for current session
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    sysctl -w net.ipv4.conf.all.src_valid_mark=1 > /dev/null

    # Make it persistent
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    if ! grep -q "net.ipv4.conf.all.src_valid_mark=1" /etc/sysctl.conf; then
        echo "net.ipv4.conf.all.src_valid_mark=1" >> /etc/sysctl.conf
    fi

    sysctl -p > /dev/null
    print_info "IP forwarding enabled"
}

# Configure firewall
configure_firewall() {
    print_info "Configuring firewall..."

    WG_PORT=${WG_PORT:-51820}
    WG_UI_PORT=${WG_UI_PORT:-51821}

    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        print_info "Configuring UFW firewall..."
        ufw allow ${WG_PORT}/udp comment 'WireGuard VPN'
        ufw allow ${WG_UI_PORT}/tcp comment 'WireGuard Web UI'
        print_info "UFW firewall rules added"
    elif command -v firewall-cmd &> /dev/null; then
        print_info "Configuring firewalld..."
        firewall-cmd --permanent --add-port=${WG_PORT}/udp
        firewall-cmd --permanent --add-port=${WG_UI_PORT}/tcp
        firewall-cmd --reload
        print_info "Firewalld rules added"
    else
        print_warn "No firewall detected (UFW or firewalld). Make sure ports ${WG_PORT}/udp and ${WG_UI_PORT}/tcp are open."
    fi
}

# Check for port conflicts
check_port_conflicts() {
    print_info "Checking for port conflicts..."

    WG_PORT=${WG_PORT:-51820}
    WG_UI_PORT=${WG_UI_PORT:-51821}

    # Check if ports are in use
    if lsof -i :${WG_PORT} &> /dev/null || ss -tulpn 2>/dev/null | grep -q ":${WG_PORT}"; then
        print_error "Port ${WG_PORT} is already in use!"
        echo ""
        print_warn "This could be caused by:"
        echo "  1. Another WireGuard instance running"
        echo "  2. Previous wg-easy container still running"
        echo "  3. Native WireGuard service running"
        echo ""
        print_info "To fix this issue, run:"
        echo "  sudo bash fix-port-conflict.sh"
        echo ""
        read -p "Do you want to continue anyway? This might fail. (y/N): " continue_confirm
        if [[ $continue_confirm != "y" && $continue_confirm != "Y" ]]; then
            exit 1
        fi
    fi

    if lsof -i :${WG_UI_PORT} &> /dev/null || ss -tulpn 2>/dev/null | grep -q ":${WG_UI_PORT}"; then
        print_warn "Port ${WG_UI_PORT} is already in use!"
        read -p "Continue anyway? (y/N): " continue_confirm
        if [[ $continue_confirm != "y" && $continue_confirm != "Y" ]]; then
            exit 1
        fi
    fi

    print_info "Port check completed"
}

# Stop any existing containers
stop_existing_containers() {
    print_info "Checking for existing wg-easy containers..."

    if docker ps -a | grep -q wg-easy; then
        print_warn "Found existing wg-easy container"
        read -p "Stop and remove it? (Y/n): " remove_confirm
        if [[ $remove_confirm != "n" && $remove_confirm != "N" ]]; then
            print_info "Stopping and removing existing container..."
            docker stop wg-easy 2>/dev/null || true
            docker rm wg-easy 2>/dev/null || true
            print_info "Container removed"
        fi
    fi
}

# Start WireGuard with wg-easy
start_wireguard() {
    print_info "Starting WireGuard with wg-easy panel..."

    docker compose up -d

    # Wait for container to be ready
    sleep 5

    if docker ps | grep -q wg-easy; then
        print_info "WireGuard with wg-easy is running!"
    else
        print_error "Failed to start wg-easy container"
        echo ""
        print_info "Showing container logs:"
        docker compose logs
        echo ""
        print_error "If you see a port binding error, run: sudo bash fix-port-conflict.sh"
        exit 1
    fi
}

# Print access information
print_access_info() {
    WG_UI_PORT=${WG_UI_PORT:-51821}

    echo ""
    echo "========================================"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo "========================================"
    echo ""
    echo "Web UI Access:"
    echo "  URL: http://${SERVER_IP}:${WG_UI_PORT}"
    echo "  Password: ${PASSWORD}"
    echo ""
    echo "WireGuard UDP Port: ${WG_PORT:-51820}"
    echo ""
    echo "Useful Commands:"
    echo "  View logs:     docker compose logs -f"
    echo "  Restart:       docker compose restart"
    echo "  Stop:          docker compose down"
    echo "  Start:         docker compose up -d"
    echo ""
    echo "Configuration file: .env"
    echo "WireGuard data:    ./wg-easy/"
    echo ""
    echo "========================================"
    echo ""
    echo -e "${YELLOW}IMPORTANT SECURITY NOTES:${NC}"
    echo "1. Save your password securely!"
    echo "2. Consider using a reverse proxy with HTTPS for production"
    echo "3. Change the default password in the .env file if needed"
    echo "4. Make sure your firewall is properly configured"
    echo ""
}

# Main installation flow
main() {
    echo "========================================"
    echo "WireGuard with wg-easy Auto-Installer"
    echo "========================================"
    echo ""

    detect_os
    install_docker
    get_server_ip
    check_port_conflicts
    generate_password
    create_env_file
    create_docker_compose
    enable_ip_forward
    configure_firewall
    check_port_conflicts
    stop_existing_containers
    start_wireguard
    print_access_info
}

# Run main function
main
