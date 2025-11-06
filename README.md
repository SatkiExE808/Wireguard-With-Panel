# WireGuard with wg-easy Panel

A simple, automated installer for WireGuard VPN with wg-easy web management panel. This project provides a one-command installation script that sets up a fully functional WireGuard VPN server with an intuitive web interface for managing clients.

## Features

- **Automated Installation**: Single command to install everything
- **Web-Based Management**: Easy-to-use web interface for managing VPN clients
- **Docker-Based**: Runs in containers for easy deployment and updates
- **Cross-Platform Support**: Works on Ubuntu, Debian, CentOS, Fedora, and RHEL
- **Automatic Firewall Configuration**: Configures UFW or firewalld automatically
- **QR Code Generation**: Generate QR codes for mobile clients
- **Secure by Default**: Automatic password generation and secure configuration
- **Zero-Config**: Detects server IP and configures everything automatically

## What is wg-easy?

[wg-easy](https://github.com/wg-easy/wg-easy) is a simple, web-based management interface for WireGuard VPN. It provides:

- Easy client creation and management
- QR code generation for mobile devices
- Traffic statistics per client
- One-click client configuration download
- Simple and intuitive UI

## Prerequisites

- A Linux server (Ubuntu, Debian, CentOS, Fedora, or RHEL)
- Root or sudo access
- Public IP address or domain name
- Ports 51820 (UDP) and 51821 (TCP) accessible from the internet

## Quick Start (Recommended)

### Automated Installation

Run the following commands as root (or with sudo):

```bash
# Clone the repository
git clone https://github.com/SatkiExE808/Wireguard-With-Panel.git
cd Wireguard-With-Panel

# Run the installation script
sudo bash install.sh
```

The script will:
1. Detect your operating system
2. Install Docker and Docker Compose if not present
3. Detect your server's public IP
4. Generate a secure password for the web UI
5. Configure system settings (IP forwarding, etc.)
6. Configure firewall rules
7. Start WireGuard with wg-easy panel
8. Display access information

### Access Your VPN Panel

After installation, you'll see output like:

```
========================================
Installation Complete!
========================================

Web UI Access:
  URL: http://YOUR_SERVER_IP:51821
  Password: YOUR_GENERATED_PASSWORD

WireGuard UDP Port: 51820
```

Open the URL in your browser and use the provided password to access the management panel.

## Manual Installation

If you prefer to install manually or already have Docker installed:

### 1. Install Docker

Follow the official Docker installation guide for your OS:
- [Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Debian](https://docs.docker.com/engine/install/debian/)
- [CentOS](https://docs.docker.com/engine/install/centos/)

### 2. Clone the Repository

```bash
git clone https://github.com/SatkiExE808/Wireguard-With-Panel.git
cd Wireguard-With-Panel
```

### 3. Configure Environment Variables

```bash
# Copy the example configuration
cp .env.example .env

# Edit the configuration
nano .env
```

Set at minimum:
- `WG_HOST`: Your server's public IP or domain
- `PASSWORD`: A secure password for the web UI

### 4. Enable IP Forwarding

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.src_valid_mark=1

# Make it persistent
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.conf.all.src_valid_mark=1" | sudo tee -a /etc/sysctl.conf
```

### 5. Configure Firewall

#### UFW (Ubuntu/Debian)
```bash
sudo ufw allow 51820/udp  # WireGuard
sudo ufw allow 51821/tcp  # Web UI
```

#### Firewalld (CentOS/RHEL/Fedora)
```bash
sudo firewall-cmd --permanent --add-port=51820/udp
sudo firewall-cmd --permanent --add-port=51821/tcp
sudo firewall-cmd --reload
```

### 6. Start the Service

```bash
docker compose up -d
```

## Configuration Options

Edit the `.env` file to customize your installation. See `.env.example` for all available options.

### Key Configuration Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `WG_HOST` | Server IP or domain (required) | - |
| `PASSWORD` | Web UI password (required) | - |
| `WG_PORT` | WireGuard VPN port | 51820 |
| `WG_UI_PORT` | Web interface port | 51821 |
| `WG_DEFAULT_DNS` | DNS servers for clients | 1.1.1.1, 1.0.0.1 |
| `WG_ALLOWED_IPS` | Traffic routing | 0.0.0.0/0, ::/0 |
| `WG_DEFAULT_ADDRESS` | VPN subnet | 10.8.0.x |
| `WG_MTU` | Maximum transmission unit | 1420 |

## Usage

### Managing the Service

```bash
# View logs
docker compose logs -f

# Restart the service
docker compose restart

# Stop the service
docker compose down

# Start the service
docker compose up -d

# Update to latest version
docker compose pull
docker compose up -d
```

### Adding VPN Clients

1. Open the web UI: `http://YOUR_SERVER_IP:51821`
2. Log in with your password
3. Click "New Client"
4. Enter a name for the client
5. Download the configuration or scan the QR code with your mobile device

### Connecting Clients

#### Mobile (iOS/Android)
1. Install the WireGuard app from your app store
2. Scan the QR code from the web UI
3. Enable the VPN connection

#### Desktop (Windows/macOS/Linux)
1. Install WireGuard from [wireguard.com](https://www.wireguard.com/install/)
2. Download the configuration file from the web UI
3. Import the configuration
4. Activate the tunnel

## Updating

To update to the latest version of wg-easy:

```bash
cd Wireguard-With-Panel
docker compose pull
docker compose up -d
```

Your configuration and client data will be preserved in the `./wg-easy` directory.

## Security Considerations

1. **Change Default Password**: Always use a strong, unique password
2. **Use HTTPS**: Consider using a reverse proxy (nginx, Caddy) with HTTPS for the web UI
3. **Firewall**: Ensure only necessary ports are open
4. **Regular Updates**: Keep Docker and wg-easy updated
5. **Backup**: Regularly backup the `./wg-easy` directory
6. **Limit Access**: Consider restricting web UI access to specific IPs

### Setting Up HTTPS (Optional)

For production use, it's recommended to use a reverse proxy with HTTPS:

```bash
# Example with Caddy
docker run -d \
  --name caddy \
  -p 80:80 \
  -p 443:443 \
  -v caddy_data:/data \
  -v caddy_config:/config \
  caddy caddy reverse-proxy \
  --from vpn.yourdomain.com \
  --to localhost:51821
```

## Troubleshooting

### Cannot Access Web UI

1. Check if the container is running:
   ```bash
   docker ps | grep wg-easy
   ```

2. Check firewall rules:
   ```bash
   sudo ufw status  # Ubuntu/Debian
   sudo firewall-cmd --list-all  # CentOS/RHEL
   ```

3. Check logs:
   ```bash
   docker compose logs -f
   ```

### VPN Connection Issues

1. Verify IP forwarding is enabled:
   ```bash
   sysctl net.ipv4.ip_forward
   # Should return: net.ipv4.ip_forward = 1
   ```

2. Check if WireGuard port is open:
   ```bash
   sudo netstat -unlp | grep 51820
   ```

3. Verify `WG_HOST` in `.env` matches your public IP

### Port Already in Use

If port 51820 or 51821 is already in use, edit `.env`:

```bash
WG_PORT=51822
WG_UI_PORT=51823
```

Then restart:
```bash
docker compose down
docker compose up -d
```

## Backup and Restore

### Backup

```bash
# Backup WireGuard configuration and client data
tar -czf wg-easy-backup-$(date +%Y%m%d).tar.gz wg-easy/ .env
```

### Restore

```bash
# Extract backup
tar -xzf wg-easy-backup-YYYYMMDD.tar.gz

# Restart service
docker compose up -d
```

## Uninstalling

To completely remove WireGuard and wg-easy:

```bash
# Stop and remove containers
docker compose down

# Remove configuration and data
rm -rf wg-easy/

# Optional: Remove Docker (if installed by this script)
sudo apt-get remove docker-ce docker-ce-cli containerd.io  # Ubuntu/Debian
sudo yum remove docker-ce docker-ce-cli containerd.io       # CentOS/RHEL
```

## File Structure

```
Wireguard-With-Panel/
├── install.sh              # Automated installation script
├── docker-compose.yml      # Docker Compose configuration
├── .env.example           # Example environment variables
├── .env                   # Your configuration (created during install)
├── wg-easy/              # WireGuard data (created during install)
│   ├── wg0.conf          # WireGuard server configuration
│   └── ...               # Client configurations
└── README.md             # This file
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is provided as-is for educational and personal use.

## Acknowledgments

- [WireGuard](https://www.wireguard.com/) - Fast, modern, secure VPN tunnel
- [wg-easy](https://github.com/wg-easy/wg-easy) - Simple WireGuard management interface
- [Docker](https://www.docker.com/) - Containerization platform

## Support

For issues and questions:
- Open an issue on GitHub
- Check the [wg-easy documentation](https://github.com/wg-easy/wg-easy)
- Review WireGuard's [quick start guide](https://www.wireguard.com/quickstart/)

## Disclaimer

This software is provided for legitimate VPN use cases. Users are responsible for complying with all applicable laws and regulations in their jurisdiction. Use responsibly and ensure you have proper authorization for any systems you configure.
