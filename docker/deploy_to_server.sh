#!/bin/bash

# Script para desplegar WoL Forwarder en servidor Docker
# Configuración
SERVER_IP="192.168.3.99"
SERVER_USER="root"  # Ajustar según tu configuración
DOCKER_PATH="/opt/wol-forwarder"

echo "🐳 Desplegando WoL Forwarder al servidor Docker $SERVER_IP"
echo "⚠️ NOTA: Usando puerto 8090 (8080 ocupado por Pi-hole)"
echo "=" * 60

# Verificar que estamos en el directorio correcto
if [[ ! -f "wol_forwarder.py" || ! -f "Dockerfile" ]]; then
    echo "❌ Error: Ejecuta este script desde el directorio docker/"
    echo "   Archivos requeridos: wol_forwarder.py, Dockerfile, docker-compose.yml"
    exit 1
fi

# Función para ejecutar comandos en el servidor remoto
execute_remote() {
    echo "🔄 Ejecutando en servidor: $1"
    ssh "$SERVER_USER@$SERVER_IP" "$1"
}

# Función para copiar archivos al servidor
copy_to_server() {
    echo "📤 Copiando $1 al servidor..."
    scp "$1" "$SERVER_USER@$SERVER_IP:$DOCKER_PATH/"
}

echo "1️⃣ Verificando conectividad con el servidor..."
if ! ping -c 1 "$SERVER_IP" &> /dev/null; then
    echo "❌ No se puede conectar al servidor $SERVER_IP"
    exit 1
fi

echo "✅ Servidor accesible"

echo "2️⃣ Verificando acceso SSH..."
if ! ssh -o ConnectTimeout=5 "$SERVER_USER@$SERVER_IP" "echo 'SSH OK'" &> /dev/null; then
    echo "❌ No se puede conectar por SSH a $SERVER_USER@$SERVER_IP"
    echo "   Asegúrate de tener las claves SSH configuradas"
    exit 1
fi

echo "✅ SSH accesible"

echo "3️⃣ Creando directorio en servidor..."
execute_remote "mkdir -p $DOCKER_PATH"

echo "4️⃣ Copiando archivos al servidor..."
copy_to_server "wol_forwarder.py"
copy_to_server "Dockerfile"
copy_to_server "docker-compose.yml"

echo "5️⃣ Deteniendo contenedor existente (si existe)..."
execute_remote "cd $DOCKER_PATH && docker-compose down" || true

echo "6️⃣ Construyendo imagen Docker..."
execute_remote "cd $DOCKER_PATH && docker build -t wol-forwarder:latest ."

if [ $? -ne 0 ]; then
    echo "❌ Error construyendo la imagen Docker"
    exit 1
fi

echo "7️⃣ Iniciando servicio WoL Forwarder..."
execute_remote "cd $DOCKER_PATH && docker-compose up -d"

if [ $? -ne 0 ]; then
    echo "❌ Error iniciando el contenedor"
    exit 1
fi

echo "8️⃣ Verificando estado del contenedor..."
execute_remote "docker ps | grep wol-forwarder"

echo "9️⃣ Mostrando logs iniciales..."
sleep 3
execute_remote "docker logs wol-forwarder --tail 20"

echo ""
echo "✅ ¡Despliegue completado!"
echo "🌐 Servidor WoL Forwarder ejecutándose en $SERVER_IP:8090"
echo ""
echo "📋 Comandos útiles:"
echo "   Ver logs:      ssh $SERVER_USER@$SERVER_IP 'docker logs -f wol-forwarder'"
echo "   Reiniciar:     ssh $SERVER_USER@$SERVER_IP 'cd $DOCKER_PATH && docker-compose restart'"
echo "   Parar:         ssh $SERVER_USER@$SERVER_IP 'cd $DOCKER_PATH && docker-compose down'"
echo "   Estado:        ssh $SERVER_USER@$SERVER_IP 'docker ps | grep wol-forwarder'"
echo ""
echo "🎯 La aplicación Swift ahora puede enviar paquetes WoL a $SERVER_IP:8090"
