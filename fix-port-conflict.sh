#!/bin/bash

# WireGuard Port Conflict Fix Script
# This script resolves port 51820 binding conflicts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

echo "========================================"
echo "WireGuard Port Conflict Fix"
echo "========================================"
echo ""

# Check what's using port 51820
print_step "Checking what's using port 51820..."
echo ""

PORT_USERS=$(lsof -i :51820 2>/dev/null || ss -tulpn 2>/dev/null | grep 51820 || echo "")

if [[ -z "$PORT_USERS" ]]; then
    print_info "Port 51820 appears to be free now"
else
    print_warn "Port 51820 is in use:"
    echo "$PORT_USERS"
    echo ""
fi

# Check for existing Docker containers
print_step "Checking for existing wg-easy containers..."
if command -v docker &> /dev/null; then
    CONTAINERS=$(docker ps -a --filter "name=wg-easy" --format "{{.ID}} {{.Names}} {{.Status}}")

    if [[ -n "$CONTAINERS" ]]; then
        print_warn "Found existing wg-easy container(s):"
        echo "$CONTAINERS"
        echo ""

        read -p "Do you want to stop and remove these containers? (Y/n): " confirm
        if [[ $confirm != "n" && $confirm != "N" ]]; then
            print_info "Stopping and removing wg-easy containers..."
            docker stop wg-easy 2>/dev/null || true
            docker rm wg-easy 2>/dev/null || true
            print_info "Containers removed"
        fi
    else
        print_info "No existing wg-easy containers found"
    fi
else
    print_warn "Docker command not found, skipping container check"
fi

# Check for native WireGuard service
print_step "Checking for native WireGuard service..."
if systemctl is-active --quiet wg-quick@* 2>/dev/null; then
    WG_SERVICES=$(systemctl list-units --type=service --state=running | grep wg-quick || echo "")

    if [[ -n "$WG_SERVICES" ]]; then
        print_warn "Found running WireGuard service(s):"
        echo "$WG_SERVICES"
        echo ""

        read -p "Do you want to stop these WireGuard services? (Y/n): " confirm
        if [[ $confirm != "n" && $confirm != "N" ]]; then
            print_info "Stopping WireGuard services..."
            systemctl stop wg-quick@* 2>/dev/null || true
            print_info "WireGuard services stopped"

            read -p "Do you want to disable them from starting on boot? (y/N): " disable_confirm
            if [[ $disable_confirm == "y" || $disable_confirm == "Y" ]]; then
                systemctl disable wg-quick@* 2>/dev/null || true
                print_info "WireGuard services disabled"
            fi
        fi
    else
        print_info "No active WireGuard services found"
    fi
else
    print_info "No active WireGuard services detected"
fi

# Check for WireGuard interfaces
print_step "Checking for active WireGuard interfaces..."
WG_INTERFACES=$(ip link show | grep -i wg || echo "")

if [[ -n "$WG_INTERFACES" ]]; then
    print_warn "Found WireGuard interface(s):"
    echo "$WG_INTERFACES"
    echo ""

    # Try to bring down interfaces
    if command -v wg &> /dev/null; then
        WG_IFACES=$(wg show interfaces 2>/dev/null || echo "")
        if [[ -n "$WG_IFACES" ]]; then
            read -p "Do you want to bring down these interfaces? (Y/n): " confirm
            if [[ $confirm != "n" && $confirm != "N" ]]; then
                for iface in $WG_IFACES; do
                    print_info "Bringing down interface: $iface"
                    ip link set $iface down 2>/dev/null || true
                    ip link delete $iface 2>/dev/null || true
                done
                print_info "Interfaces brought down"
            fi
        fi
    fi
else
    print_info "No active WireGuard interfaces found"
fi

# Offer to use a different port
echo ""
print_step "Port Configuration Options"
echo ""
echo "You have the following options:"
echo "  1. Try to start wg-easy on default port 51820 (recommended if conflict resolved)"
echo "  2. Configure wg-easy to use a different port"
echo "  3. Exit and investigate manually"
echo ""

read -p "Enter your choice (1-3): " choice

case $choice in
    1)
        print_info "Attempting to start wg-easy on port 51820..."
        cd "$(dirname "$0")"
        if [[ -f docker-compose.yml ]]; then
            docker compose up -d
            echo ""
            print_info "Done! Check status with: docker compose logs -f"
        else
            print_error "docker-compose.yml not found"
            exit 1
        fi
        ;;
    2)
        read -p "Enter new WireGuard port (default 51820): " NEW_PORT
        NEW_PORT=${NEW_PORT:-51820}

        read -p "Enter new Web UI port (default 51821): " NEW_UI_PORT
        NEW_UI_PORT=${NEW_UI_PORT:-51821}

        print_info "Creating .env file with custom ports..."
        cd "$(dirname "$0")"

        # Check if .env exists
        if [[ -f .env ]]; then
            # Update existing .env
            if grep -q "^WG_PORT=" .env; then
                sed -i "s/^WG_PORT=.*/WG_PORT=$NEW_PORT/" .env
            else
                echo "WG_PORT=$NEW_PORT" >> .env
            fi

            if grep -q "^WG_UI_PORT=" .env; then
                sed -i "s/^WG_UI_PORT=.*/WG_UI_PORT=$NEW_UI_PORT/" .env
            else
                echo "WG_UI_PORT=$NEW_UI_PORT" >> .env
            fi
        else
            # Create new .env
            print_warn ".env file not found. Please run install.sh first or create .env manually"
            echo "Add these lines to your .env file:"
            echo "WG_PORT=$NEW_PORT"
            echo "WG_UI_PORT=$NEW_UI_PORT"
        fi

        print_info "Configuration updated"
        print_info "New WireGuard port: $NEW_PORT/udp"
        print_info "New Web UI port: $NEW_UI_PORT/tcp"
        echo ""
        print_warn "Remember to update your firewall rules for the new ports:"
        echo "  sudo ufw allow $NEW_PORT/udp"
        echo "  sudo ufw allow $NEW_UI_PORT/tcp"
        echo ""

        read -p "Start wg-easy now? (Y/n): " start_confirm
        if [[ $start_confirm != "n" && $start_confirm != "N" ]]; then
            docker compose up -d
            print_info "Done! Check status with: docker compose logs -f"
        fi
        ;;
    3)
        print_info "Exiting. Here are some useful debugging commands:"
        echo "  - Check port usage: sudo lsof -i :51820"
        echo "  - Check Docker containers: docker ps -a"
        echo "  - Check WireGuard interfaces: sudo wg show"
        echo "  - Check system services: systemctl list-units | grep wg"
        exit 0
        ;;
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "========================================"
print_info "Port conflict resolution complete!"
echo "========================================"
