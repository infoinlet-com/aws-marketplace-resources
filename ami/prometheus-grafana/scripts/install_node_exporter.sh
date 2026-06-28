#!/bin/bash

#################################################################
# Node Exporter Installation Script
# 
# Purpose: Install and configure Node Exporter for Prometheus monitoring
# Usage: ./install_node_exporter.sh
# Compatible: Ubuntu/Debian and RHEL/CentOS/Amazon Linux
# Version: 1.8.2 (Latest stable)
#################################################################

set -euo pipefail

# Configuration
readonly NODE_EXPORTER_VERSION="1.8.2"
readonly NODE_EXPORTER_USER="node_exporter"
readonly NODE_EXPORTER_PORT="9100"
readonly INSTALL_DIR="/usr/local/bin"
readonly SERVICE_FILE="/etc/systemd/system/node_exporter.service"
readonly DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root or with sudo
check_privileges() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo privileges"
        exit 1
    fi
}

# Check if Node Exporter is already installed
check_existing_installation() {
    if systemctl is-active --quiet node_exporter 2>/dev/null; then
        log_warn "Node Exporter is already running"
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled"
            exit 0
        fi
        log_info "Stopping existing Node Exporter service"
        sudo systemctl stop node_exporter || true
        sudo systemctl disable node_exporter || true
    fi
}

# Install Node Exporter
install_node_exporter() {
    log_info "Installing Node Exporter v${NODE_EXPORTER_VERSION}"
    
    # Create user
    if ! id "$NODE_EXPORTER_USER" &>/dev/null; then
        sudo useradd --no-create-home --shell /bin/false "$NODE_EXPORTER_USER"
        log_info "Created user: $NODE_EXPORTER_USER"
    fi
    
    # Download and extract
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    if ! curl -sSL "$DOWNLOAD_URL" -o "node_exporter.tar.gz"; then
        log_error "Failed to download Node Exporter"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    tar xzf node_exporter.tar.gz
    
    # Install binary
    sudo cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" "$INSTALL_DIR/"
    sudo chown "$NODE_EXPORTER_USER:$NODE_EXPORTER_USER" "$INSTALL_DIR/node_exporter"
    sudo chmod +x "$INSTALL_DIR/node_exporter"
    
    # Create systemd service
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
Wants=network-online.target
After=network-online.target

[Service]
User=$NODE_EXPORTER_USER
Group=$NODE_EXPORTER_USER
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=$INSTALL_DIR/node_exporter \\
    --web.listen-address=0.0.0.0:$NODE_EXPORTER_PORT \\
    --collector.systemd \\
    --log.level=info

[Install]
WantedBy=multi-user.target
EOF
    
    # Start service
    sudo systemctl daemon-reload
    sudo systemctl enable node_exporter
    sudo systemctl start node_exporter
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_info "Installation completed successfully"
}

# Validate installation
validate_installation() {
    log_info "Validating Node Exporter installation"
    
    # Check service status
    if ! sudo systemctl is-active --quiet node_exporter; then
        log_error "Validation failed: Node Exporter service is not running"
        return 1
    fi
    
    # Check if port is listening
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ss -tuln | grep -q ":$NODE_EXPORTER_PORT "; then
            break
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "Validation failed: Port $NODE_EXPORTER_PORT is not listening"
            return 1
        fi
        
        sleep 1
        ((attempt++))
    done
    
    # Test metrics endpoint
    if ! curl -sf "http://localhost:$NODE_EXPORTER_PORT/metrics" > /dev/null; then
        log_error "Validation failed: Metrics endpoint not responding"
        return 1
    fi
    
    log_info "Validation completed successfully"
    return 0
}

# Display installation summary
show_summary() {
    echo
    echo "======================================"
    echo "Node Exporter Installation Summary"
    echo "======================================"
    echo "Version: $NODE_EXPORTER_VERSION"
    echo "Status: $(sudo systemctl is-active node_exporter)"
    echo "Port: $NODE_EXPORTER_PORT"
    echo "Metrics URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-hostname 2>/dev/null || hostname):$NODE_EXPORTER_PORT/metrics"
    echo "Service: systemctl status node_exporter"
    echo "======================================"
    echo
    echo "Next steps:"
    echo "1. Ensure port $NODE_EXPORTER_PORT is open in security groups"
    echo "2. Tag this VM instance with 'vm_monitor=true' for Prometheus discovery"
    echo "3. Wait for Prometheus to scrape metrics (may take a few minutes)"
    echo "4. Verify in Grafana Dashboard"
}

# Main execution
main() {
    log_info "Starting Node Exporter installation"
    
    check_privileges
    check_existing_installation
    
    if install_node_exporter && validate_installation; then
        log_info "✅ Node Exporter installation and validation: SUCCESS"
        show_summary
        exit 0
    else
        log_error "❌ Node Exporter installation or validation: FAILED"
        
        # Show service status for troubleshooting
        echo
        echo "Service status:"
        sudo systemctl status node_exporter --no-pager || true
        echo
        echo "Recent logs:"
        sudo journalctl -u node_exporter --no-pager -n 10 || true
        
        exit 1
    fi
}

# Execute main function
main "$@"
