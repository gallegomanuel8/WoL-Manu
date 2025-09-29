#!/bin/bash

# Script para implementar WoL Server en 192.168.1.200
# Uso: ./deploy-to-server.sh [usuario@192.168.1.200]

set -e

# Configuración
SERVER_IP="192.168.1.200"
DEFAULT_USER="user"  # Cambiar por el usuario apropiado
DEPLOYMENT_FILE="wol-server-deployment.tar.gz"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Obtener usuario del servidor
if [[ $# -eq 1 ]]; then
    SERVER_USER="$1"
elif [[ $# -eq 0 ]]; then
    read -p "Usuario del servidor [$DEFAULT_USER]: " SERVER_USER
    SERVER_USER=${SERVER_USER:-$DEFAULT_USER}
else
    echo "Uso: $0 [usuario]"
    exit 1
fi

echo "========================================="
echo "🚀 WoL Server Deployment Script"
echo "========================================="
echo "Servidor: $SERVER_USER@$SERVER_IP"
echo

# Verificar que el archivo de implementación existe
if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
    log_error "Archivo $DEPLOYMENT_FILE no encontrado"
    log_info "Ejecutando: tar -czf $DEPLOYMENT_FILE wol-server/"
    tar -czf "$DEPLOYMENT_FILE" wol-server/
    log_info "Archivo de implementación creado"
fi

log_step "1. Verificando conectividad con el servidor"
if ping -c 1 "$SERVER_IP" >/dev/null 2>&1; then
    log_info "Servidor $SERVER_IP es accesible"
else
    log_error "No se puede conectar con $SERVER_IP"
    exit 1
fi

log_step "2. Copiando archivos al servidor"
scp "$DEPLOYMENT_FILE" "$SERVER_USER@$SERVER_IP:~/"

log_step "3. Ejecutando instalación remota"
ssh "$SERVER_USER@$SERVER_IP" << 'ENDSSH'
    echo "🔧 Iniciando instalación en el servidor..."
    cd ~
    tar -xzf wol-server-deployment.tar.gz
    cd wol-server
    chmod +x install.sh
    
    echo "📋 Archivos extraídos:"
    ls -la
    
    echo "🚀 Ejecutando instalador (requiere sudo)..."
    sudo ./install.sh
ENDSSH

if [[ $? -eq 0 ]]; then
    echo
    log_info "🎉 ¡Implementación completada exitosamente!"
    echo
    echo "🌐 Endpoints disponibles:"
    echo "   Health: http://$SERVER_IP:5000/health"
    echo "   WoL: POST http://$SERVER_IP:5000/wol"
    echo
    echo "🧪 Prueba de conectividad:"
    echo "   curl http://$SERVER_IP:5000/health"
    echo
    
    log_step "4. Probando conectividad"
    sleep 3
    if curl -s "http://$SERVER_IP:5000/health" >/dev/null 2>&1; then
        log_info "✅ Servidor WoL respondiendo correctamente"
    else
        log_warn "⚠️  Servidor no responde - verificar firewall/logs"
    fi
    
    echo
    echo "📋 Comandos útiles en el servidor:"
    echo "   Ver logs:      ssh $SERVER_USER@$SERVER_IP 'sudo journalctl -u wol-server -f'"
    echo "   Ver estado:    ssh $SERVER_USER@$SERVER_IP 'sudo systemctl status wol-server'"
    echo "   Reiniciar:     ssh $SERVER_USER@$SERVER_IP 'sudo systemctl restart wol-server'"
    echo
    
else
    log_error "Error durante la implementación"
    exit 1
fi