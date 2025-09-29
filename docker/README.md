# WoL Forwarder para WireGuard Docker

Este directorio contiene los archivos necesarios para desplegar un **forwarder de Wake-on-LAN** en tu servidor Docker WireGuard.

## 🎯 Objetivo

La aplicación Swift "WoL Manu" envía paquetes mágicos WoL al puerto **8090** del servidor Docker (`192.168.1.200`), y este contenedor los reenvía como broadcast a la red local `192.168.3.x`, solucionando el problema de que los broadcasts no atraviesan túneles VPN punto a punto.

⚠️ **Nota**: Se usa el puerto 8090 porque el 8080 está ocupado por Pi-hole en el servidor.

## 📁 Archivos

- **`wol_forwarder.py`** - Script Python que escucha en puerto 8080 y reenvía paquetes WoL
- **`Dockerfile`** - Imagen Docker Alpine con Python 3.11
- **`docker-compose.yml`** - Configuración del servicio con logs y healthcheck
- **`deploy_to_server.sh`** - Script automático de despliegue
- **`test_wol_forwarder.py`** - Script de prueba para verificar funcionamiento
- **`README.md`** - Este archivo de documentación

## 🚀 Despliegue Rápido

### Opción 1: Despliegue Automático

```bash
cd docker/
chmod +x deploy_to_server.sh
./deploy_to_server.sh
```

### Opción 2: Despliegue Manual

1. **Copiar archivos al servidor:**
```bash
scp wol_forwarder.py Dockerfile docker-compose.yml root@192.168.1.200:/opt/wol-forwarder/
```

2. **Conectar al servidor y construir:**
```bash
ssh root@192.168.1.200
cd /opt/wol-forwarder
docker build -t wol-forwarder:latest .
```

3. **Iniciar el servicio:**
```bash
docker-compose up -d
```

## 🧪 Verificación

### 1. Comprobar que el contenedor está ejecutándose:
```bash
ssh root@192.168.1.200 'docker ps | grep wol-forwarder'
```

### 2. Ver logs del forwarder:
```bash
ssh root@192.168.1.200 'docker logs -f wol-forwarder'
```

### 3. Probar desde local:
```bash
python3 test_wol_forwarder.py
```

## 🔧 Configuración

### Configuración de Red

El forwarder está configurado para tu red específica:

- **Servidor Docker:** `192.168.1.200:8090` (⚠️ Puerto cambiado por Pi-hole)
- **Red local:** `192.168.3.x` 
- **Red VPN:** `10.8.0.x` (clientes) / `10.8.1.1` (servidor)
- **Broadcast local:** `192.168.1.255`
- **Dispositivo objetivo:** `192.168.1.100`

### Variables de Entorno

Puedes personalizar la configuración editando `docker-compose.yml`:

```yaml
environment:
  - LISTEN_PORT=8080
  - LOCAL_BROADCAST=192.168.1.255
  - TARGET_IP=192.168.1.100
```

## 🎭 Flujo de Funcionamiento

1. **App Swift** → Envía Magic Packet a `192.168.1.200:8090`
2. **Docker Forwarder** → Recibe packet y valida formato WoL
3. **Reenvío múltiple** → Broadcast a:
   - `192.168.1.255:9` (broadcast local)
   - `192.168.1.255:7` (puerto alternativo)
   - `192.168.1.100:9` (dirección directa del dispositivo)
   - `255.255.255.255:9` (broadcast global)

## 📊 Monitorización

### Logs en tiempo real:
```bash
ssh root@192.168.1.200 'docker logs -f wol-forwarder'
```

### Estadísticas del contenedor:
```bash
ssh root@192.168.1.200 'docker stats wol-forwarder'
```

### Health check:
```bash
ssh root@192.168.1.200 'docker inspect wol-forwarder | grep Health -A 10'
```

## 🛠️ Comandos Útiles

| Acción | Comando |
|--------|---------|
| Reiniciar servicio | `ssh root@192.168.1.200 'cd /opt/wol-forwarder && docker-compose restart'` |
| Parar servicio | `ssh root@192.168.1.200 'cd /opt/wol-forwarder && docker-compose down'` |
| Reconstruir imagen | `ssh root@192.168.1.200 'cd /opt/wol-forwarder && docker-compose build --no-cache'` |
| Ver configuración | `ssh root@192.168.1.200 'cat /opt/wol-forwarder/docker-compose.yml'` |

## 🐛 Troubleshooting

### El contenedor no se inicia:
```bash
# Ver logs de error
ssh root@192.168.1.200 'docker logs wol-forwarder'

# Verificar puerto disponible
ssh root@192.168.1.200 'netstat -tulpn | grep :8080'
```

### No recibe paquetes:
```bash
# Probar conectividad desde tu Mac
nc -u 192.168.1.200 8080

# Verificar firewall en servidor
ssh root@192.168.1.200 'iptables -L | grep 8080'
```

### El dispositivo no despierta:
```bash
# Verificar que los broadcasts llegan a la red
ssh root@192.168.1.200 'tcpdump -i any port 9 or port 7'

# Probar WoL directo desde servidor
ssh root@192.168.1.200 'apt-get install wakeonlan && wakeonlan 00:11:22:33:44:55'
```

## 🔐 Seguridad

- El contenedor corre con usuario no privilegiado (`woluser:1001`)
- Solo expone el puerto 8080/UDP
- Logs rotativos limitados (10MB x 3 archivos)
- Healthcheck automático cada 30 segundos

## 📱 Uso desde la App Swift

Una vez desplegado, la aplicación Swift automáticamente enviará paquetes WoL a `192.168.1.200:8080`. No necesitas cambiar nada en la app - ya está configurada para usar este servidor.

Para verificar que funciona:

1. Ejecuta la app Swift
2. Configura el dispositivo con MAC `00:11:22:33:44:55` e IP `192.168.1.100`
3. Presiona el botón "Wake Up"
4. Verifica los logs: `ssh root@192.168.1.200 'docker logs wol-forwarder --tail 5'`

¡El forwarder debería mostrar que recibió y reenviò el paquete mágico! 🎉