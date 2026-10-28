#!/usr/bin/env bash
#
# Despliega wol_server.py con validación de X-API-Key en el servidor relay
# y, opcionalmente, endurece SSH (solo clave pública).
#
# Uso:
#   scripts/deploy_relay_api_key.sh [usuario@host] [--harden-ssh] [--only-ssh]
#
#   usuario@host   servidor relay (o variable WOL_RELAY_HOST), p. ej. root@192.168.1.10
#   --harden-ssh   desactiva el acceso SSH por contraseña (PasswordAuthentication no,
#                  PermitRootLogin prohibit-password). Asegúrate antes de que entras con clave.
#   --only-ssh     solo el endurecimiento de SSH, sin desplegar el servidor
#
# La API key se toma del Llavero de macOS (donde la guarda WoL Manu) o, si aún no se ha
# migrado, de config.json. Se envía por stdin: no aparece en argumentos ni en `ps`.
#
set -euo pipefail

HOST="${WOL_RELAY_HOST:-}"
HARDEN_SSH=0
ONLY_SSH=0
for arg in "$@"; do
    case "$arg" in
        --harden-ssh) HARDEN_SSH=1 ;;
        --only-ssh) HARDEN_SSH=1; ONLY_SSH=1 ;;
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

ssh_run() { ssh -o BatchMode=yes "$HOST" "$@"; }

if [[ $ONLY_SSH == 0 ]]; then
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
fi

# --- 4. SSH solo con clave (opcional) -------------------------------------------
# Los ajustes se insertan al PRINCIPIO de sshd_config: en la sección global gana el primer
# valor, y no todos los sshd_config incluyen sshd_config.d/. Después se verifica con sshd -T.
if [[ $HARDEN_SSH == 1 ]]; then
    echo "🛡️  Desactivando acceso SSH por contraseña"
    ssh_run "set -e
CFG=/etc/ssh/sshd_config
cp -p \$CFG \$CFG.bak-$TS
rm -f /etc/ssh/sshd_config.d/10-wol-hardening.conf
# Quitar un bloque previo de este script (idempotente) e insertar el nuevo arriba
python3 - \$CFG <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(r'(?ms)^# >>> wol-hardening.*?^# <<< wol-hardening\\n', '', text)
block = ('# >>> wol-hardening (scripts/deploy_relay_api_key.sh)\\n'
         'PasswordAuthentication no\\n'
         'KbdInteractiveAuthentication no\\n'
         'PermitRootLogin prohibit-password\\n'
         '# <<< wol-hardening\\n')
open(path, 'w').write(block + text)
PY
restore() { cp -p \$CFG.bak-$TS \$CFG; systemctl reload ssh; echo \"\$1: cambio revertido\" >&2; exit 1; }
sshd -t || restore 'Configuración SSH inválida'
systemctl reload ssh
sleep 1
EFFECTIVE=\$(sshd -T)
echo \"\$EFFECTIVE\" | grep -E '^(passwordauthentication|permitrootlogin) '
echo \"\$EFFECTIVE\" | grep -qx 'passwordauthentication no' || restore 'PasswordAuthentication no no se aplica'
echo \"\$EFFECTIVE\" | grep -qE '^permitrootlogin (without-password|prohibit-password)$' || restore 'PermitRootLogin no se aplica'
echo \"Copia de seguridad: \$CFG.bak-$TS\""
    # Comprobar que la clave sigue funcionando en una conexión nueva
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true; then
        echo "✅ Contraseña desactivada (verificado con sshd -T) y SSH con clave sigue funcionando"
    else
        echo "⚠️  No se pudo reconectar con clave: NO cierres ninguna sesión abierta y revisa" >&2
        exit 1
    fi
fi
