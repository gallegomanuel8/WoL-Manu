#!/usr/bin/env bash
#
# Despliega wol_server.py con validación de X-API-Key en el servidor relay
# y, opcionalmente, endurece SSH (solo clave pública).
#
# Uso:
#   scripts/deploy_relay_api_key.sh [usuario@host] [--harden-ssh]
#
#   usuario@host   servidor relay (o variable WOL_RELAY_HOST), p. ej. root@192.168.1.10
#   --harden-ssh   desactiva el acceso SSH por contraseña (PasswordAuthentication no,
#                  PermitRootLogin prohibit-password). Asegúrate antes de que entras con clave.
#
# La API key se toma del Llavero de macOS (donde la guarda WoL Manu) o, si aún no se ha
# migrado, de config.json. Se envía por stdin: no aparece en argumentos ni en `ps`.
#
set -euo pipefail

HOST="${WOL_RELAY_HOST:-}"
HARDEN_SSH=0
for arg in "$@"; do
    case "$arg" in
        --harden-ssh) HARDEN_SSH=1 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) HOST="$arg" ;;
    esac
done

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "$HOST" ]]; then
    echo "Uso: $0 usuario@host [--harden-ssh] [--only-ssh]   (o exporta WOL_RELAY_HOST)" >&2
    exit 1
fi
SERVER_IP="${HOST#*@}"
# Broadcast de la /24 del servidor, salvo que se indique otro con WOL_BROADCAST_IP
BROADCAST="${WOL_BROADCAST_IP:-${SERVER_IP%.*}.255}"
PORT=5000
REMOTE_DIR=/root/wol-server
TS="$(date +%Y%m%d-%H%M%S)"

# --- API key -----------------------------------------------------------------
KEY="$(security find-generic-password -s "xxx.WoL-Manu" -a relay-api-key -w 2>/dev/null || true)"
if [[ -z "$KEY" ]]; then
    KEY="$(python3 -c "import json;print(json.load(open('$PROJECT_DIR/config.json')).get('apiKey',''))" 2>/dev/null || true)"
fi
if [[ -z "$KEY" ]]; then
    echo "❌ No hay API key: configúrala en WoL Manu (Configuración → VPN → API Key)." >&2
    exit 1
fi
echo "🔑 API key encontrada (${#KEY} caracteres)"

ssh_run() { ssh -o BatchMode=yes "$HOST" "$@"; }

# --- 1. Copia de seguridad y subida -------------------------------------------
echo "📦 Copia de seguridad de $REMOTE_DIR/wol_server.py → wol_server.py.bak-$TS"
ssh_run "cp -p $REMOTE_DIR/wol_server.py $REMOTE_DIR/wol_server.py.bak-$TS"

echo "⬆️  Subiendo wol_server.py"
scp -q -o BatchMode=yes "$PROJECT_DIR/wol_server.py" "$HOST:$REMOTE_DIR/wol_server.py.new"

# --- 2. Key (por stdin) y configuración del servicio -----------------------------
echo "🔐 Guardando la key en /etc/wol-server/api_key (600)"
printf '%s' "$KEY" | ssh_run 'umask 077; mkdir -p /etc/wol-server && cat > /etc/wol-server/api_key && chmod 600 /etc/wol-server/api_key'

echo "⚙️  Configurando y reiniciando wol-server"
ssh_run "set -e
mv $REMOTE_DIR/wol_server.py.new $REMOTE_DIR/wol_server.py
mkdir -p /etc/systemd/system/wol-server.service.d
cat > /etc/systemd/system/wol-server.service.d/override.conf <<'EOF'
[Service]
Environment=WOL_API_KEY_FILE=/etc/wol-server/api_key
Environment=WOL_BROADCAST_IP=$BROADCAST
EOF
systemctl daemon-reload
systemctl restart wol-server
sleep 2
systemctl is-active --quiet wol-server"

# --- 3. Verificación (sin MAC: no se envía ningún paquete) ------------------------
code() { curl -s -o /dev/null -w '%{http_code}' -m 5 "$@"; }
HEALTH=$(code "http://$SERVER_IP:$PORT/health")
NOKEY=$(code -X POST -H 'Content-Type: application/json' -d '{}' "http://$SERVER_IP:$PORT/wake")
WITHKEY=$(code -X POST -H 'Content-Type: application/json' -H @<(printf 'X-API-Key: %s\n' "$KEY") -d '{}' "http://$SERVER_IP:$PORT/wake")

echo "   /health            → $HEALTH (esperado 200)"
echo "   /wake sin key      → $NOKEY (esperado 401)"
echo "   /wake con key      → $WITHKEY (esperado 400: falta la MAC, no se envía nada)"

if [[ "$HEALTH" != 200 || "$NOKEY" != 401 || "$WITHKEY" != 400 ]]; then
    echo "❌ Algo no cuadra. Para volver atrás:" >&2
    echo "   ssh $HOST 'cp -p $REMOTE_DIR/wol_server.py.bak-$TS $REMOTE_DIR/wol_server.py && rm /etc/systemd/system/wol-server.service.d/override.conf && systemctl daemon-reload && systemctl restart wol-server'" >&2
    exit 1
fi
echo "✅ Servidor desplegado: /wake exige API key"

# --- 4. SSH solo con clave (opcional) -------------------------------------------
if [[ $HARDEN_SSH == 1 ]]; then
    echo "🛡️  Desactivando acceso SSH por contraseña"
    ssh_run "set -e
cat > /etc/ssh/sshd_config.d/10-wol-hardening.conf <<'EOF'
# Solo clave pública (añadido por scripts/deploy_relay_api_key.sh)
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
if sshd -t; then
    systemctl reload ssh
else
    rm /etc/ssh/sshd_config.d/10-wol-hardening.conf
    echo 'Configuración SSH inválida: cambio revertido' >&2
    exit 1
fi
sshd -T | grep -E '^(passwordauthentication|permitrootlogin) '"
    # Comprobar que la clave sigue funcionando en una conexión nueva
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true \
        && echo "✅ SSH con clave sigue funcionando; contraseña desactivada" \
        || echo "⚠️  No se pudo reconectar con clave: revisa la sesión antes de cerrar ninguna" >&2
fi
