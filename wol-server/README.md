# WoL Server - Wake-on-LAN HTTP API

Servidor Flask que proporciona una API REST para enviar paquetes Wake-on-LAN, diseñado para funcionar con la aplicación Swift "WoL Manu".

## 📋 Características

- **API REST completa** con endpoints `/health`, `/wol` y `/status`
- **Autenticación con API Key** opcional pero recomendada
- **Validación de MAC address** con múltiples formatos soportados
- **Doble implementación WoL**: `wakeonlan` command + Python nativo
- **Logging completo** con rotación automática
- **Servicio systemd** con auto-restart y seguridad hardened
- **Configuración UFW** automática para redes privadas
- **Health checks** incorporados

## 🚀 Instalación Rápida

### En el servidor (192.168.3.99):

```bash
# Descargar archivos del servidor
scp app.py requirements.txt install.sh root@192.168.3.99:/tmp/

# Conectar al servidor
ssh root@192.168.3.99

# Ejecutar instalador
cd /tmp
sudo ./install.sh install
```

El instalador automáticamente:
- ✅ Instala Python 3, pip, virtualenv, wakeonlan, etc.
- ✅ Crea usuario del sistema `wol-server`
- ✅ Configura servicio systemd
- ✅ Genera API Key aleatoria
- ✅ Configura firewall UFW
- ✅ Inicia y habilita el servicio

## 🔧 Configuración

### Archivo de configuración: `/etc/wol-server/config.json`

```json
{
    "api_key": "generated-random-key-here",
    "port": 5000,
    "allowed_networks": [
        "192.168.0.0/16",
        "10.0.0.0/8", 
        "172.16.0.0/12"
    ],
    "log_level": "INFO"
}
```

### Cambiar configuración:

```bash
sudo nano /etc/wol-server/config.json
sudo systemctl restart wol-server
```

## 🌐 API Endpoints

### GET `/health`
Health check básico, no requiere autenticación.

**Respuesta:**
```json
{
    "status": "ok",
    "timestamp": "2025-09-29T15:00:00Z",
    "server": "wol-server",
    "version": "1.0"
}
```

### POST `/wol`
Enviar paquete Wake-on-LAN.

**Headers requeridos:**
```
Content-Type: application/json
X-API-Key: your-api-key-here  // Si está configurada
```

**Body JSON:**
```json
{
    "mac": "70:85:C2:98:7B:3E",
    "ip": "192.168.3.90",        // opcional
    "name": "Mi PC Gaming"       // opcional
}
```

**Respuesta exitosa (200):**
```json
{
    "status": "sent",
    "mac": "70:85:C2:98:7B:3E",
    "broadcast": "255.255.255.255",
    "method": "wakeonlan",
    "timestamp": "2025-09-29T15:00:00Z"
}
```

### GET `/status`
Información del servidor (requiere API Key).

## 🧪 Pruebas Manuales

### Health Check:
```bash
curl http://192.168.3.99:5000/health
```

### Enviar WoL:
```bash
curl -X POST http://192.168.3.99:5000/wol \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR-API-KEY-HERE" \
  -d '{"mac": "70:85:C2:98:7B:3E", "ip": "192.168.3.90", "name": "Test Device"}'
```

### Status del servidor:
```bash
curl -H "X-API-Key: YOUR-API-KEY-HERE" http://192.168.3.99:5000/status
```

## 🛠️ Gestión del Servicio

### Comandos systemd:
```bash
# Ver estado
sudo systemctl status wol-server

# Ver logs en tiempo real
sudo journalctl -u wol-server -f

# Reiniciar
sudo systemctl restart wol-server

# Parar
sudo systemctl stop wol-server

# Iniciar
sudo systemctl start wol-server

# Deshabilitar auto-start
sudo systemctl disable wol-server
```

### Archivos importantes:
```bash
# Configuración
/etc/wol-server/config.json

# Logs
/var/log/wol-server.log
sudo journalctl -u wol-server

# Servicio
/etc/systemd/system/wol-server.service

# Aplicación
/opt/wol-server/app.py
```

## 🔐 Seguridad

### API Key:
- Generada automáticamente durante instalación
- Almacenada en `/etc/wol-server/config.json`
- Solo lectura para el usuario `wol-server`
- Requerida para endpoints `/wol` y `/status`

### Firewall:
El instalador configura UFW para permitir el puerto solo desde redes privadas:
- `192.168.0.0/16` (LANs domésticas)
- `10.0.0.0/8` (VPNs)
- `172.16.0.0/12` (Docker networks)

### Hardening del servicio:
- Usuario del sistema sin shell (`wol-server`)
- `NoNewPrivileges=yes`
- `ProtectSystem=strict`
- `ProtectHome=yes`
- `PrivateTmp=yes`

## 🐛 Troubleshooting

### El servicio no inicia:
```bash
sudo systemctl status wol-server --no-pager
sudo journalctl -u wol-server --no-pager
```

### Error de permisos:
```bash
sudo chown -R wol-server:wol-server /opt/wol-server
sudo chown -R wol-server:wol-server /etc/wol-server
sudo chmod 600 /etc/wol-server/config.json
```

### Firewall bloqueando:
```bash
sudo ufw status
sudo ufw allow from 192.168.0.0/16 to any port 5000
```

### Health check falla:
```bash
# Verificar que el servicio esté escuchando
sudo netstat -tlpn | grep :5000

# Probar conexión local
curl -v http://localhost:5000/health
```

### WoL no funciona:
```bash
# Verificar wakeonlan
which wakeonlan
wakeonlan --help

# Probar manualmente
wakeonlan 70:85:C2:98:7B:3E

# Verificar logs del servidor
sudo tail -f /var/log/wol-server.log
```

## 📈 Integración con App Swift

Una vez instalado, configura tu aplicación Swift con:

1. **Modo VPN**: ✅ Habilitado
2. **IP Servidor**: `192.168.3.99`
3. **Puerto**: `5000` 
4. **API Key**: La generada durante instalación
5. **Fallback Local**: ✅ Recomendado

La aplicación automáticamente:
- Hará health check antes de enviar WoL
- Reintentará con backoff exponencial
- Usará fallback local si VPN falla (si configurado)

## 🔄 Actualizaciones

Para actualizar el servidor:

```bash
# Descargar nuevas versiones
scp app.py requirements.txt root@192.168.3.99:/opt/wol-server/

# Reiniciar servicio
ssh root@192.168.3.99 'systemctl restart wol-server'
```

## 📊 Logs y Monitoring

### Logs estructurados:
```bash
# Logs de la aplicación
sudo tail -f /var/log/wol-server.log

# Logs del sistema
sudo journalctl -u wol-server -f

# Filtrar solo errores
sudo journalctl -u wol-server -p err

# Logs desde hace 1 hora
sudo journalctl -u wol-server --since "1 hour ago"
```

### Métricas importantes:
- Peticiones WoL exitosas/fallidas
- Tiempo de respuesta de health checks
- Errores de autenticación
- Uso de CPU/memoria del servicio

## 🗑️ Desinstalación

Para remover completamente el servidor:

```bash
sudo /path/to/install.sh uninstall
```

Esto removerá:
- Servicio systemd
- Usuario del sistema
- Archivos de configuración
- Logs
- Reglas UFW

---

## 📞 Soporte

Si encuentras problemas:

1. Revisa los logs: `sudo journalctl -u wol-server -f`
2. Verifica la configuración: `cat /etc/wol-server/config.json`
3. Prueba health check: `curl http://localhost:5000/health`
4. Verifica permisos y firewall
5. Reinicia el servicio: `sudo systemctl restart wol-server`

**¡Tu servidor WoL está listo para recibir peticiones desde la aplicación Swift!** 🚀