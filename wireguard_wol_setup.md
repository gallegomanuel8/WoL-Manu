# Configuración WireGuard con Soporte Wake-on-LAN

Esta guía explica cómo configurar el servidor WireGuard para reenviar magic packets de Wake-on-LAN desde clientes VPN a la red local.

## 🔍 Análisis de tu configuración actual

**Tu configuración detectada:**
- **IP VPN:** `10.0.0.2`
- **Subnet VPN:** `10.8.0.0/24`
- **Interfaz:** `utun6`
- **Dispositivo objetivo:** `192.168.1.100` (MAC: `00:11:22:33:44:55`)
- **Red objetivo:** `192.168.3.0/24`

## 🎯 Soluciones para Wake-on-LAN a través de WireGuard

### **Solución A: Configuración del Servidor WireGuard** 

#### 1. Configurar el servidor WireGuard

En el **servidor WireGuard**, necesitas modificar la configuración para permitir el reenvío de broadcasts Wake-on-LAN:

```ini
# /etc/wireguard/wg0.conf (en el servidor)
[Interface]
PrivateKey = <tu_private_key>
Address = 10.0.0.1/24
ListenPort = 51820

# Habilitar IP forwarding y broadcast forwarding
PostUp = echo 1 > /proc/sys/net/ipv4/ip_forward
PostUp = echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter
PostUp = echo 1 > /proc/sys/net/ipv4/conf/all/proxy_arp

# Reenviar magic packets específicos de WoL
PostUp = socat UDP-LISTEN:9,fork,broadcast,bind=10.0.0.1 UDP-DATAGRAM:192.168.1.255:9,broadcast &
PostUp = socat UDP-LISTEN:7,fork,broadcast,bind=10.0.0.1 UDP-DATAGRAM:192.168.1.255:7,broadcast &

# Script personalizado para WoL
PostUp = /etc/wireguard/wol-forwarder.sh start

PostDown = pkill -f "socat.*UDP.*9"
PostDown = pkill -f "socat.*UDP.*7"
PostDown = /etc/wireguard/wol-forwarder.sh stop

[Peer]
PublicKey = <tu_public_key>
AllowedIPs = 10.0.0.2/32
```

#### 2. Script de reenvío WoL personalizado

Crear `/etc/wireguard/wol-forwarder.sh` en el servidor:

```bash
#!/bin/bash
# /etc/wireguard/wol-forwarder.sh

WOL_TARGET_MAC="00:11:22:33:44:55"
WOL_TARGET_BROADCAST="192.168.1.255"
VPN_INTERFACE="wg0"
LOCAL_INTERFACE="eth0"  # Ajustar según tu interfaz local

start() {
    echo "Iniciando WoL forwarder..."
    
    # Relay UDP 9 (puerto principal WoL)
    socat UDP-LISTEN:9,fork,bind=10.0.0.1,reuseaddr \
          EXEC:"wakeonlan -i $WOL_TARGET_BROADCAST $WOL_TARGET_MAC" &
    
    # Relay UDP 7 (puerto alternativo WoL)  
    socat UDP-LISTEN:7,fork,bind=10.0.0.1,reuseaddr \
          EXEC:"wakeonlan -i $WOL_TARGET_BROADCAST $WOL_TARGET_MAC" &
    
    # Relay específico por IP - reenvía cualquier magic packet a broadcast local
    socat UDP-LISTEN:8080,fork,bind=10.0.0.1,reuseaddr \
          EXEC:"/etc/wireguard/process-wol-packet.py" &
    
    echo "WoL forwarder iniciado"
}

stop() {
    echo "Deteniendo WoL forwarder..."
    pkill -f "socat.*UDP.*9"
    pkill -f "socat.*UDP.*7"  
    pkill -f "socat.*UDP.*8080"
    echo "WoL forwarder detenido"
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 2; start ;;
    *) echo "Uso: $0 {start|stop|restart}" ;;
esac
```

#### 3. Script Python para procesar magic packets

Crear `/etc/wireguard/process-wol-packet.py`:

```python
#!/usr/bin/env python3
"""
Script que recibe magic packets desde WireGuard VPN y los reenvía como broadcast local
"""
import socket
import subprocess
import sys
import binascii

def is_magic_packet(data):
    """Verifica si los datos son un magic packet válido"""
    if len(data) != 102:
        return False
    
    # Verificar 6 bytes de 0xFF al inicio
    if data[:6] != b'\xFF' * 6:
        return False
    
    # Verificar que el resto son 16 repeticiones de la misma MAC
    mac_part = data[6:12]
    for i in range(16):
        start = 6 + (i * 6)
        end = start + 6
        if data[start:end] != mac_part:
            return False
    
    return True

def forward_magic_packet(data):
    """Reenvía el magic packet como broadcast local"""
    try:
        # Crear socket para broadcast local
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        
        # Enviar a múltiples direcciones de broadcast
        broadcasts = ['192.168.1.255', '255.255.255.255']
        ports = [7, 9]
        
        for broadcast in broadcasts:
            for port in ports:
                try:
                    sock.sendto(data, (broadcast, port))
                    print(f"Magic packet enviado a {broadcast}:{port}")
                except:
                    pass
        
        sock.close()
        return True
    except Exception as e:
        print(f"Error reenviando magic packet: {e}")
        return False

def main():
    """Lee magic packet desde stdin y lo reenvía"""
    try:
        # Leer datos desde stdin (enviados por socat)
        data = sys.stdin.buffer.read()
        
        if is_magic_packet(data):
            print("Magic packet válido recibido desde VPN")
            if forward_magic_packet(data):
                print("Magic packet reenviado exitosamente")
            else:
                print("Error reenviando magic packet")
        else:
            print("Datos recibidos no son un magic packet válido")
            
    except Exception as e:
        print(f"Error procesando datos: {e}")

if __name__ == "__main__":
    main()
```

### **Solución B: Usar un puerto específico para WoL**

Si no puedes modificar la configuración principal del servidor, puedes configurar un puerto específico:

#### En el servidor WireGuard:
```bash
# Escuchar en puerto específico para WoL
socat UDP-LISTEN:8080,fork,reuseaddr EXEC:"wakeonlan -i 192.168.1.255 00:11:22:33:44:55"
```

#### En tu aplicación Swift:
Agregar una estrategia adicional que envíe a un puerto específico del servidor:

```swift
// En WakeOnLANService.swift, agregar esta estrategia
// Estrategia 6: Puerto específico del servidor WireGuard
if let targetIP = targetIP {
    // Obtener IP del gateway VPN (normalmente .1 en la subnet)
    let vpnGateway = "10.0.0.1"  // IP del servidor WireGuard
    let wolPort: UInt16 = 8080   // Puerto específico para WoL
    
    if sendUDPToAddress(data: magicPacket, address: vpnGateway, port: wolPort) {
        print("[WoLService] ✅ Enviado a servidor WireGuard \\(vpnGateway):\\(wolPort)")
        successCount += 1
    }
}
```

## 🚀 Implementación inmediata (Solución B)

Vamos a implementar la **Solución B** que es más fácil y no requiere cambios complejos en el servidor:

### 1. Crear el forwarder en el servidor WireGuard

```bash
#!/bin/bash
# En el servidor WireGuard, crear /usr/local/bin/wol-forwarder
cat << 'EOF' > /usr/local/bin/wol-forwarder
#!/bin/bash
WOL_MAC="00:11:22:33:44:55"
WOL_BROADCAST="192.168.1.255"

echo "WoL Forwarder iniciado - Puerto 8080"
echo "Objetivo: $WOL_MAC -> $WOL_BROADCAST"

socat -v UDP-LISTEN:8080,fork,reuseaddr \
    EXEC:"wakeonlan -i $WOL_BROADCAST $WOL_MAC"
EOF

chmod +x /usr/local/bin/wol-forwarder
```

### 2. Actualizar tu aplicación Swift

Vamos a agregar el código para enviar al servidor WireGuard:
```

<function_calls>
<invoke name="edit_files">
<parameter name="title">Add WireGuard server-specific Wake-on-LAN strategy