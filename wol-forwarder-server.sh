#!/bin/bash
#
# Script para instalar en el servidor WireGuard
# Este script reenvía magic packets Wake-on-LAN desde VPN a la red local
#
# Uso: ./wol-forwarder-server.sh [start|stop|install]
#

WOL_MAC="00:11:22:33:44:55"
WOL_BROADCAST="192.168.1.255" 
WOL_TARGET_IP="192.168.1.100"
VPN_LISTEN_IP="10.8.0.1"
WOL_PORT="8080"

SCRIPT_PATH="/usr/local/bin/wol-forwarder"
SERVICE_PATH="/etc/systemd/system/wol-forwarder.service"
LOGFILE="/var/log/wol-forwarder.log"

install_forwarder() {
    echo "🔧 Instalando WoL Forwarder para WireGuard..."
    
    # Crear el script principal
    cat << EOF > $SCRIPT_PATH
#!/bin/bash
# WoL Forwarder para WireGuard
# Dispositivo objetivo: $WOL_MAC ($WOL_TARGET_IP)

LOG_FILE="$LOGFILE"

log() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" | tee -a "\$LOG_FILE"
}

start_forwarder() {
    log "Iniciando WoL Forwarder..."
    log "Escuchando en: $VPN_LISTEN_IP:$WOL_PORT"
    log "Objetivo: $WOL_MAC -> $WOL_BROADCAST"
    
    # Método 1: Usar socat con wakeonlan
    if command -v wakeonlan >/dev/null 2>&1; then
        log "Usando wakeonlan para reenvío"
        socat -v UDP-LISTEN:$WOL_PORT,fork,bind=$VPN_LISTEN_IP,reuseaddr \\
            EXEC:"wakeonlan -i $WOL_BROADCAST $WOL_MAC" 2>&1 | \\
            while read line; do log "SOCAT: \$line"; done &
    else
        # Método 2: Script Python integrado
        log "Usando script Python integrado"
        socat UDP-LISTEN:$WOL_PORT,fork,bind=$VPN_LISTEN_IP,reuseaddr \\
            EXEC:"$SCRIPT_PATH python_forwarder" &
    fi
    
    SOCAT_PID=\$!
    echo \$SOCAT_PID > /var/run/wol-forwarder.pid
    log "WoL Forwarder iniciado con PID: \$SOCAT_PID"
}

stop_forwarder() {
    log "Deteniendo WoL Forwarder..."
    
    if [ -f /var/run/wol-forwarder.pid ]; then
        PID=\$(cat /var/run/wol-forwarder.pid)
        if kill -0 \$PID 2>/dev/null; then
            kill \$PID
            log "Proceso \$PID detenido"
        fi
        rm -f /var/run/wol-forwarder.pid
    fi
    
    # Matar todos los procesos socat relacionados
    pkill -f "socat.*UDP.*$WOL_PORT"
    log "WoL Forwarder detenido"
}

python_forwarder() {
    # Mini forwarder Python integrado
    python3 << 'PYTHON_EOF'
import socket
import sys
import binascii

def forward_wol():
    data = sys.stdin.buffer.read()
    
    # Verificar que sea un magic packet (102 bytes, inicia con 6x0xFF)
    if len(data) == 102 and data[:6] == b'\\xFF' * 6:
        print(f"Magic packet recibido: {len(data)} bytes", file=sys.stderr)
        
        # Crear socket para broadcast local
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        
        # Reenviar a red local
        broadcasts = ["$WOL_BROADCAST", "255.255.255.255"]
        ports = [7, 9]
        
        for broadcast in broadcasts:
            for port in ports:
                try:
                    sock.sendto(data, (broadcast, port))
                    print(f"Reenviado a {broadcast}:{port}", file=sys.stderr)
                except Exception as e:
                    print(f"Error enviando a {broadcast}:{port}: {e}", file=sys.stderr)
        
        sock.close()
        print("Magic packet procesado", file=sys.stderr)
    else:
        print(f"Datos no válidos recibidos: {len(data)} bytes", file=sys.stderr)

forward_wol()
PYTHON_EOF
}

case "\$1" in
    start)
        start_forwarder
        ;;
    stop)
        stop_forwarder
        ;;
    restart)
        stop_forwarder
        sleep 2
        start_forwarder
        ;;
    python_forwarder)
        python_forwarder
        ;;
    *)
        echo "Uso: \$0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF

    chmod +x $SCRIPT_PATH
    echo "✅ Script instalado en: $SCRIPT_PATH"
    
    # Crear servicio systemd
    cat << EOF > $SERVICE_PATH
[Unit]
Description=WoL Forwarder for WireGuard
After=network.target
Wants=network.target

[Service]
Type=forking
ExecStart=$SCRIPT_PATH start
ExecStop=$SCRIPT_PATH stop
ExecReload=$SCRIPT_PATH restart
PIDFile=/var/run/wol-forwarder.pid
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    echo "✅ Servicio systemd creado: $SERVICE_PATH"
    
    # Habilitar e iniciar servicio
    systemctl daemon-reload
    systemctl enable wol-forwarder
    systemctl start wol-forwarder
    
    echo "🚀 WoL Forwarder instalado y iniciado"
    echo "📋 Para verificar el estado: systemctl status wol-forwarder"
    echo "📄 Logs en: $LOGFILE"
}

start_forwarder() {
    echo "🚀 Iniciando WoL Forwarder..."
    $SCRIPT_PATH start
}

stop_forwarder() {
    echo "⏹️ Deteniendo WoL Forwarder..."
    $SCRIPT_PATH stop
}

status_forwarder() {
    echo "📊 Estado del WoL Forwarder:"
    if systemctl is-active --quiet wol-forwarder; then
        echo "✅ Servicio activo"
        systemctl status wol-forwarder --no-pager -l
    else
        echo "❌ Servicio inactivo"
    fi
    
    echo ""
    echo "📋 Procesos relacionados:"
    ps aux | grep -E "(socat.*$WOL_PORT|wol-forwarder)" | grep -v grep || echo "Ninguno encontrado"
    
    echo ""
    echo "📄 Últimas líneas del log:"
    tail -10 $LOGFILE 2>/dev/null || echo "Log no encontrado"
}

case "$1" in
    install)
        install_forwarder
        ;;
    start)
        start_forwarder
        ;;
    stop) 
        stop_forwarder
        ;;
    status)
        status_forwarder
        ;;
    *)
        echo "🔧 WoL Forwarder para WireGuard"
        echo ""
        echo "Uso: $0 {install|start|stop|status}"
        echo ""
        echo "  install - Instala el forwarder como servicio del sistema"
        echo "  start   - Inicia el forwarder"  
        echo "  stop    - Detiene el forwarder"
        echo "  status  - Muestra el estado del forwarder"
        echo ""
        echo "Configuración actual:"
        echo "  MAC objetivo: $WOL_MAC"
        echo "  IP objetivo: $WOL_TARGET_IP"
        echo "  Broadcast: $WOL_BROADCAST"
        echo "  VPN Listen: $VPN_LISTEN_IP:$WOL_PORT"
        ;;
esac