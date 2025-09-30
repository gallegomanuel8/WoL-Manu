#!/bin/bash
"""
Deploy Script for WoL Server v1.4
Automatically deploys the WoL server to target server with all configurations and security features.

Features:
- Secure file transfer via SCP
- Automatic service installation
- Configuration setup
- Health check validation
- Rollback capability
"""

# Configuration - Set these environment variables or edit these values
SERVER_IP="${WOL_SERVER_IP:-192.168.1.100}"  # Change to your server IP
SERVER_USER="${WOL_SERVER_USER:-root}"        # Change to your server username
SERVER_PORT="22"
LOCAL_PROJECT_DIR="/Users/manu/Projects/WoL Manu"
REMOTE_BASE_DIR="/root/wol-server"
SERVICE_NAME="wol-server"
WOL_PORT="5000"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if SSH key is set up
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${SERVER_USER}@${SERVER_IP}" exit 2>/dev/null; then
        error "Cannot connect to ${SERVER_IP} without password. Please set up SSH key authentication."
        echo "Run: ssh-copy-id ${SERVER_USER}@${SERVER_IP}"
        exit 1
    fi
    
    # Check if local files exist
    if [[ ! -f "${LOCAL_PROJECT_DIR}/wol_server.py" ]]; then
        error "wol_server.py not found in ${LOCAL_PROJECT_DIR}"
        exit 1
    fi
    
    if [[ ! -f "${LOCAL_PROJECT_DIR}/Tests/test_wol_server.py" ]]; then
        error "test_wol_server.py not found in ${LOCAL_PROJECT_DIR}/Tests/"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Create remote directory structure
setup_remote_directories() {
    log "Setting up remote directory structure..."
    
    ssh "${SERVER_USER}@${SERVER_IP}" << 'EOF'
        # Create directory structure
        mkdir -p ~/wol-server/{logs,tests,config,backup}
        
        # Set proper permissions
        chmod 755 ~/wol-server
        chmod 755 ~/wol-server/{logs,tests,config,backup}
        
        # Create log directory
        sudo mkdir -p /var/log/wol-server
        sudo chown $USER:$USER /var/log/wol-server
        chmod 755 /var/log/wol-server
EOF
    
    if [[ $? -eq 0 ]]; then
        success "Remote directories created"
    else
        error "Failed to create remote directories"
        exit 1
    fi
}

# Backup existing installation
backup_existing() {
    log "Backing up existing installation..."
    
    ssh "${SERVER_USER}@${SERVER_IP}" << EOF
        if [[ -f ~/wol-server/wol_server.py ]]; then
            cp ~/wol-server/wol_server.py ~/wol-server/backup/wol_server.py.$(date +%Y%m%d_%H%M%S)
            echo "Existing server backed up"
        fi
        
        if sudo systemctl is-active --quiet wol-server; then
            sudo systemctl stop wol-server
            echo "Stopped existing service"
        fi
EOF
    
    success "Backup completed"
}

# Transfer files to server
transfer_files() {
    log "Transferring files to server..."
    
    # Transfer main server file
    scp "${LOCAL_PROJECT_DIR}/wol_server.py" "${SERVER_USER}@${SERVER_IP}:${REMOTE_BASE_DIR}/"
    if [[ $? -ne 0 ]]; then
        error "Failed to transfer wol_server.py"
        exit 1
    fi
    
    # Transfer tests
    scp "${LOCAL_PROJECT_DIR}/Tests/test_wol_server.py" "${SERVER_USER}@${SERVER_IP}:${REMOTE_BASE_DIR}/tests/"
    if [[ $? -ne 0 ]]; then
        error "Failed to transfer tests"
        exit 1
    fi
    
    # Make server executable
    ssh "${SERVER_USER}@${SERVER_IP}" "chmod +x ${REMOTE_BASE_DIR}/wol_server.py"
    
    success "Files transferred successfully"
}

# Create systemd service
create_systemd_service() {
    log "Creating systemd service..."
    
    ssh "${SERVER_USER}@${SERVER_IP}" << EOF
        # Create systemd service file
        sudo tee /etc/systemd/system/wol-server.service > /dev/null << 'SERVICE_EOF'
[Unit]
Description=WoL Server v1.4 - Security Hardened Wake-on-LAN Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=${SERVER_USER}
Group=${SERVER_USER}
WorkingDirectory=${REMOTE_BASE_DIR}
ExecStart=/usr/bin/python3 ${REMOTE_BASE_DIR}/wol_server.py
Restart=always
RestartSec=3
KillMode=mixed
TimeoutStopSec=5

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=false
ReadWritePaths=${REMOTE_BASE_DIR}/logs /var/log/wol-server /tmp

# Environment variables
Environment=WOL_HOST=0.0.0.0
Environment=WOL_PORT=${WOL_PORT}
Environment=PYTHONUNBUFFERED=1

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=wol-server

[Install]
WantedBy=multi-user.target
SERVICE_EOF

        # Reload systemd and enable service
        sudo systemctl daemon-reload
        sudo systemctl enable wol-server
        
        echo "Systemd service created and enabled"
EOF
    
    if [[ $? -eq 0 ]]; then
        success "Systemd service created"
    else
        error "Failed to create systemd service"
        exit 1
    fi
}

# Start the service
start_service() {
    log "Starting WoL Server service..."
    
    ssh "${SERVER_USER}@${SERVER_IP}" << 'EOF'
        sudo systemctl start wol-server
        
        # Wait a moment for service to start
        sleep 3
        
        # Check service status
        if sudo systemctl is-active --quiet wol-server; then
            echo "✅ Service started successfully"
            sudo systemctl status wol-server --no-pager -l
        else
            echo "❌ Service failed to start"
            sudo journalctl -u wol-server -n 20 --no-pager
            exit 1
        fi
EOF
    
    if [[ $? -eq 0 ]]; then
        success "WoL Server started successfully"
    else
        error "Failed to start WoL Server"
        exit 1
    fi
}

# Health check
health_check() {
    log "Performing health check..."
    
    # Wait for server to fully start
    sleep 5
    
    # Test health endpoint
    local health_response
    health_response=$(curl -s "http://${SERVER_IP}:${WOL_PORT}/health" || echo "failed")
    
    if echo "$health_response" | grep -q "healthy"; then
        success "Health check passed - Server is responding"
        echo "Response: $health_response"
    else
        error "Health check failed - Server is not responding properly"
        echo "Response: $health_response"
        
        # Show recent logs for debugging
        ssh "${SERVER_USER}@${SERVER_IP}" "sudo journalctl -u wol-server -n 10 --no-pager"
        exit 1
    fi
}

# Run tests on server
run_tests() {
    log "Running tests on server..."
    
    ssh "${SERVER_USER}@${SERVER_IP}" << EOF
        cd ${REMOTE_BASE_DIR}/tests
        python3 test_wol_server.py
EOF
    
    if [[ $? -eq 0 ]]; then
        success "All tests passed on server"
    else
        warning "Some tests failed - check server logs"
    fi
}

# Create management scripts
create_management_scripts() {
    log "Creating management scripts..."
    
    ssh "${SERVER_USER}@${SERVER_IP}" << EOF
        # Create start script
        cat > ${REMOTE_BASE_DIR}/start.sh << 'SCRIPT_EOF'
#!/bin/bash
echo "Starting WoL Server..."
sudo systemctl start wol-server
sudo systemctl status wol-server --no-pager
SCRIPT_EOF

        # Create stop script
        cat > ${REMOTE_BASE_DIR}/stop.sh << 'SCRIPT_EOF'
#!/bin/bash
echo "Stopping WoL Server..."
sudo systemctl stop wol-server
echo "Server stopped"
SCRIPT_EOF

        # Create status script
        cat > ${REMOTE_BASE_DIR}/status.sh << 'SCRIPT_EOF'
#!/bin/bash
echo "=== WoL Server Status ==="
sudo systemctl status wol-server --no-pager
echo ""
echo "=== Recent Logs ==="
sudo journalctl -u wol-server -n 10 --no-pager
echo ""
echo "=== Health Check ==="
curl -s http://localhost:${WOL_PORT}/health | python3 -m json.tool
SCRIPT_EOF

        # Create logs script
        cat > ${REMOTE_BASE_DIR}/logs.sh << 'SCRIPT_EOF'
#!/bin/bash
echo "=== WoL Server Logs ==="
sudo journalctl -u wol-server -n 50 --no-pager
SCRIPT_EOF

        # Make scripts executable
        chmod +x ${REMOTE_BASE_DIR}/{start,stop,status,logs}.sh
        
        echo "Management scripts created"
EOF
    
    success "Management scripts created"
}

# Firewall configuration
configure_firewall() {
    log "Configuring firewall..."
    
    ssh "${SERVER_USER}@${SERVER_IP}" << EOF
        # Check if ufw is available and active
        if command -v ufw &> /dev/null; then
            # Allow WoL Server port
            sudo ufw allow ${WOL_PORT}/tcp comment "WoL Server v1.4"
            
            # Allow UDP port 9 for Magic Packets (outgoing)
            sudo ufw allow out 9/udp comment "WoL Magic Packets"
            
            echo "UFW firewall rules added"
        else
            echo "UFW not available, skipping firewall configuration"
        fi
EOF
    
    success "Firewall configured"
}

# Print deployment summary
deployment_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "🚀 WoL Server v1.4 deployed successfully to ${SERVER_IP}"
    echo "📡 Server endpoint: http://${SERVER_IP}:${WOL_PORT}"
    echo "❤️  Health check: http://${SERVER_IP}:${WOL_PORT}/health"
    echo "🔌 Wake endpoint: http://${SERVER_IP}:${WOL_PORT}/wake"
    echo ""
    echo "🛠️  Management Commands (on server):"
    echo "   ~/wol-server/status.sh  - Check server status"
    echo "   ~/wol-server/logs.sh    - View recent logs"
    echo "   ~/wol-server/start.sh   - Start server"
    echo "   ~/wol-server/stop.sh    - Stop server"
    echo ""
    echo "🔧 Systemctl Commands:"
    echo "   sudo systemctl status wol-server"
    echo "   sudo systemctl restart wol-server"
    echo "   sudo journalctl -u wol-server -f"
    echo ""
    echo "✅ Deployment completed successfully!"
}

# Rollback function
rollback() {
    error "Rolling back deployment..."
    
    ssh "${SERVER_USER}@${SERVER_IP}" << 'EOF'
        # Stop service
        sudo systemctl stop wol-server 2>/dev/null
        
        # Restore backup if exists
        LATEST_BACKUP=$(ls -t ~/wol-server/backup/wol_server.py.* 2>/dev/null | head -1)
        if [[ -n "$LATEST_BACKUP" ]]; then
            cp "$LATEST_BACKUP" ~/wol-server/wol_server.py
            echo "Restored from backup: $LATEST_BACKUP"
        fi
        
        # Try to start service again
        sudo systemctl start wol-server 2>/dev/null
EOF
    
    error "Rollback completed"
    exit 1
}

# Main deployment function
main() {
    echo "🚀 WoL Server v1.4 Deployment Script"
    echo "===================================="
    echo "Target: ${SERVER_USER}@${SERVER_IP}:${WOL_PORT}"
    echo ""
    
    # Set trap for errors
    trap rollback ERR
    
    # Execute deployment steps
    check_prerequisites
    setup_remote_directories
    backup_existing
    transfer_files
    create_systemd_service
    configure_firewall
    start_service
    health_check
    run_tests
    create_management_scripts
    
    # Clear trap
    trap - ERR
    
    deployment_summary
}

# Handle command line arguments
case "$1" in
    "health")
        curl -s "http://${SERVER_IP}:${WOL_PORT}/health" | python3 -m json.tool
        ;;
    "logs")
        ssh "${SERVER_USER}@${SERVER_IP}" "sudo journalctl -u wol-server -n 20 --no-pager"
        ;;
    "status")
        ssh "${SERVER_USER}@${SERVER_IP}" "sudo systemctl status wol-server --no-pager"
        ;;
    "restart")
        ssh "${SERVER_USER}@${SERVER_IP}" "sudo systemctl restart wol-server"
        echo "Server restarted"
        ;;
    "stop")
        ssh "${SERVER_USER}@${SERVER_IP}" "sudo systemctl stop wol-server"
        echo "Server stopped"
        ;;
    "start")
        ssh "${SERVER_USER}@${SERVER_IP}" "sudo systemctl start wol-server"
        echo "Server started"
        ;;
    *)
        main
        ;;
esac