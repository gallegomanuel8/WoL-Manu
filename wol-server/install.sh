#!/bin/bash

# Instalador de WoL Server para Debian/Ubuntu
# Instala servicio systemd, configura UFW, genera API key, etc.

set -e  # Exit on error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración
WOL_USER="wol-server"
WOL_GROUP="wol-server"
WOL_HOME="/opt/wol-server"
CONFIG_DIR="/etc/wol-server"
LOG_FILE="/var/log/wol-server.log"
SERVICE_NAME="wol-server"
DEFAULT_PORT=5000

# Funciones helper
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root (use sudo)"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/debian_version ]]; then
        log_error "Este instalador está diseñado para Debian/Ubuntu"
        exit 1
    fi
    
    log_info "OS detectado: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
}

generate_api_key() {
    openssl rand -hex 32 2>/dev/null || dd if=/dev/urandom bs=32 count=1 2>/dev/null | xxd -p -c 32
}

# Función principal de instalación
main() {
    echo "========================================"
    echo "🌐 WoL Server Installer v1.0"
    echo "========================================"
    echo
    
    check_root
    check_os
    
    log_step "1. Actualizando repositorios del sistema"
    apt-get update -qq
    
    log_step "2. Instalando dependencias del sistema"
    apt-get install -y python3 python3-pip python3-venv wakeonlan openssl ufw systemd curl
    
    log_step "3. Creando usuario y grupo del sistema"
    if ! getent group "$WOL_GROUP" > /dev/null 2>&1; then
        groupadd --system "$WOL_GROUP"
        log_info "Grupo $WOL_GROUP creado"
    else
        log_info "Grupo $WOL_GROUP ya existe"
    fi
    
    if ! getent passwd "$WOL_USER" > /dev/null 2>&1; then
        useradd --system --gid "$WOL_GROUP" --home-dir "$WOL_HOME" --shell /bin/false "$WOL_USER"
        log_info "Usuario $WOL_USER creado"
    else
        log_info "Usuario $WOL_USER ya existe"
    fi
    
    log_step "4. Creando directorios"
    mkdir -p "$WOL_HOME"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_step "5. Copiando archivos de aplicación"
    if [[ -f "app.py" && -f "requirements.txt" ]]; then
        cp app.py "$WOL_HOME/"
        cp requirements.txt "$WOL_HOME/"
        log_info "Archivos de aplicación copiados"
    else
        log_error "Archivos app.py y requirements.txt no encontrados en el directorio actual"
        exit 1
    fi
    
    log_step "6. Configurando entorno virtual Python"
    cd "$WOL_HOME"
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    deactivate
    
    log_step "7. Generando configuración por defecto"
    API_KEY=$(generate_api_key)
    
    cat > "$CONFIG_DIR/config.json" << EOF
{
    "api_key": "$API_KEY",
    "port": $DEFAULT_PORT,
    "allowed_networks": [
        "192.168.0.0/16",
        "10.0.0.0/8",
        "172.16.0.0/12"
    ],
    "log_level": "INFO"
}
EOF
    
    log_info "Archivo de configuración creado en $CONFIG_DIR/config.json"
    log_info "API Key generada: $API_KEY"
    
    log_step "8. Configurando permisos (hardening)"
    # MEJORA #4: Permisos restrictivos para seguridad
    chown -R "$WOL_USER:$WOL_GROUP" "$WOL_HOME"
    chown -R "$WOL_USER:$WOL_GROUP" "$CONFIG_DIR"
    
    # Configuración: solo el usuario wol-server puede leer
    chmod 600 "$CONFIG_DIR/config.json"  
    chmod 700 "$CONFIG_DIR"  # Solo el usuario puede acceder al directorio
    
    # Directorio de aplicación: solo el usuario
    chmod 750 "$WOL_HOME"
    chmod 640 "$WOL_HOME"/*.py 2>/dev/null || true
    chmod 640 "$WOL_HOME"/*.txt 2>/dev/null || true
    
    # Log file: escribible por usuario, legible por grupo
    touch "$LOG_FILE"
    chown "$WOL_USER:$WOL_GROUP" "$LOG_FILE"
    chmod 640 "$LOG_FILE"  # Más restrictivo que 644
    
    log_step "9. Creando servicio systemd"
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=WoL Server - Wake-on-LAN HTTP API
After=network.target
Wants=network.target

[Service]
Type=simple
User=$WOL_USER
Group=$WOL_GROUP
WorkingDirectory=$WOL_HOME
Environment=PATH=$WOL_HOME/venv/bin
ExecStart=$WOL_HOME/venv/bin/python app.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

# MEJORA #4: Security settings hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$LOG_FILE $CONFIG_DIR
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictRealtime=yes
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

[Install]
WantedBy=multi-user.target
EOF
    
    log_step "10. Habilitando y iniciando servicio"
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    
    # Esperar un momento para que el servicio se inicie
    sleep 3
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "Servicio $SERVICE_NAME iniciado correctamente"
    else
        log_error "Error iniciando el servicio"
        systemctl status "$SERVICE_NAME" --no-pager
        exit 1
    fi
    
    log_step "11. Configurando firewall UFW"
    if command -v ufw >/dev/null 2>&1; then
        # Permitir puerto desde redes privadas
        ufw allow from 192.168.0.0/16 to any port "$DEFAULT_PORT" comment "WoL Server - LAN"
        ufw allow from 10.0.0.0/8 to any port "$DEFAULT_PORT" comment "WoL Server - VPN"
        ufw allow from 172.16.0.0/12 to any port "$DEFAULT_PORT" comment "WoL Server - Docker"
        
        if ufw status | grep -q "Status: active"; then
            ufw reload
            log_info "Reglas UFW actualizadas"
        else
            log_warn "UFW no está activo, reglas añadidas pero no aplicadas"
        fi
    else
        log_warn "UFW no disponible, configuración de firewall omitida"
    fi
    
    log_step "12. Verificando instalación"
    
    # Test health endpoint
    sleep 2
    if curl -s "http://localhost:$DEFAULT_PORT/health" >/dev/null 2>&1; then
        log_info "Health check OK - Servidor respondiendo"
    else
        log_warn "Health check falló - Verificar logs"
    fi
    
    echo
    echo "========================================"
    log_info "🎉 ¡Instalación completada exitosamente!"
    echo "========================================"
    echo
    echo "📋 INFORMACIÓN DEL SERVICIO:"
    echo "   Servicio: $SERVICE_NAME"
    echo "   Puerto: $DEFAULT_PORT"
    echo "   Usuario: $WOL_USER"
    echo "   Directorio: $WOL_HOME"
    echo "   Configuración: $CONFIG_DIR/config.json"
    echo "   Logs: $LOG_FILE"
    echo
    echo "🔑 API KEY GENERADA:"
    echo "   $API_KEY"
    echo
    echo "🌐 ENDPOINTS DISPONIBLES:"
    echo "   Health: http://localhost:$DEFAULT_PORT/health"
    echo "   WoL: POST http://localhost:$DEFAULT_PORT/wol"
    echo "   Status: http://localhost:$DEFAULT_PORT/status"
    echo
    echo "📋 COMANDOS ÚTILES:"
    echo "   Ver estado:     systemctl status $SERVICE_NAME"
    echo "   Ver logs:       journalctl -u $SERVICE_NAME -f"
    echo "   Reiniciar:      systemctl restart $SERVICE_NAME"
    echo "   Parar:          systemctl stop $SERVICE_NAME"
    echo "   Editar config:  nano $CONFIG_DIR/config.json"
    echo
    echo "🧪 PRUEBA DEL SERVICIO:"
    echo "   curl http://localhost:$DEFAULT_PORT/health"
    echo
    if [[ -n "${API_KEY}" ]]; then
        echo "🔒 GUARDAR API KEY SEGURA:"
        echo "   Copia esta API Key para configurar tu aplicación cliente"
        echo "   API Key: $API_KEY"
    fi
    echo
}

# Función para desinstalar (opcional)
uninstall() {
    echo "========================================"
    echo "🗑️  WoL Server Uninstaller"
    echo "========================================"
    echo
    
    log_step "Parando y deshabilitando servicio"
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    
    log_step "Removiendo archivos del sistema"
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    rm -rf "$WOL_HOME"
    rm -rf "$CONFIG_DIR"
    rm -f "$LOG_FILE"
    
    log_step "Removiendo usuario y grupo"
    userdel "$WOL_USER" 2>/dev/null || true
    groupdel "$WOL_GROUP" 2>/dev/null || true
    
    systemctl daemon-reload
    
    log_info "Desinstalación completada"
}

# Manejar argumentos de línea de comandos
case "${1:-install}" in
    "install")
        main
        ;;
    "uninstall")
        check_root
        uninstall
        ;;
    *)
        echo "Uso: $0 [install|uninstall]"
        echo "  install   - Instalar WoL Server (por defecto)"
        echo "  uninstall - Desinstalar WoL Server"
        exit 1
        ;;
esac