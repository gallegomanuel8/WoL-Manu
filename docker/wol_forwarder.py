#!/usr/bin/env python3
"""
WoL Server Forwarder para WireGuard en Docker
Servidor: 192.168.3.99
Escucha paquetes WoL en puerto 8080 y los reenvía como broadcast a la red 192.168.3.x
"""

import socket
import sys
import logging
import signal
import threading
import time
from datetime import datetime

# Configuración específica para tu red
LISTEN_PORT = 8080
WOL_PORTS = [7, 9, 0]  # Puertos estándar Wake-on-LAN
LOCAL_BROADCAST = "192.168.3.255"  # Broadcast de tu red local
GLOBAL_BROADCAST = "255.255.255.255"

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/wol_forwarder.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class DockerWoLForwarder:
    def __init__(self):
        self.running = False
        self.server_socket = None
        self.stats = {
            'packets_received': 0,
            'packets_forwarded': 0,
            'start_time': datetime.now()
        }
        
    def create_broadcast_socket(self):
        """Crear socket para broadcast"""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            # Timeout para evitar bloqueos
            sock.settimeout(2.0)
            return sock
        except Exception as e:
            logger.error(f"Error creando socket broadcast: {e}")
            return None
    
    def validate_magic_packet(self, data):
        """Validar que el paquete sea un Magic Packet WoL válido"""
        if len(data) != 102:
            return False, f"Tamaño incorrecto: {len(data)} bytes (esperado: 102)"
        
        # Verificar header (6 bytes 0xFF)
        if data[:6] != b'\xFF' * 6:
            return False, "Header incorrecto"
        
        # Extraer MAC address del primer bloque
        mac_bytes = data[6:12]
        
        # Verificar que los siguientes 16 bloques sean idénticos
        for i in range(16):
            start_idx = 6 + (i * 6)
            end_idx = start_idx + 6
            if data[start_idx:end_idx] != mac_bytes:
                return False, f"MAC inconsistente en bloque {i+1}"
        
        # Convertir MAC a formato legible
        mac_str = ':'.join([f'{b:02x}' for b in mac_bytes])
        return True, mac_str
    
    def send_wakeonlan_style(self, magic_packet, target_ip, port, mac_address):
        """Enviar paquete WoL replicando exactamente el comportamiento de wakeonlan"""
        try:
            # Crear socket UDP con configuración idéntica a wakeonlan
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            
            # Configurar timeout similar a wakeonlan
            sock.settimeout(3.0)
            
            # Enviar el paquete
            bytes_sent = sock.sendto(magic_packet, (target_ip, port))
            sock.close()
            
            if bytes_sent == len(magic_packet):
                return True
            else:
                logger.warning(f"⚠️ Enviado parcial a {target_ip}:{port} - {bytes_sent}/{len(magic_packet)} bytes")
                return False
                
        except Exception as e:
            logger.error(f"❌ Error enviando estilo wakeonlan a {target_ip}:{port} - {e}")
            return False
    
    def forward_to_network(self, magic_packet, target_ip, mac_address):
        """Método legacy - mantenido para compatibilidad"""
        success_count = 0
        
        for port in WOL_PORTS:
            try:
                sock = self.create_broadcast_socket()
                if sock:
                    sock.sendto(magic_packet, (target_ip, port))
                    sock.close()
                    success_count += 1
                    logger.info(f"✅ WoL legacy enviado a {target_ip}:{port} para MAC {mac_address}")
                else:
                    logger.error(f"❌ No se pudo crear socket legacy para {target_ip}:{port}")
            except Exception as e:
                logger.error(f"❌ Error enviando legacy a {target_ip}:{port} - {e}")
        
        return success_count
    
    def forward_wol_packet(self, magic_packet, client_addr, mac_address):
        """Reenviar paquete WoL replicando comportamiento exacto de wakeonlan"""
        total_sent = 0
        
        # ESTRATEGIA OPTIMIZADA: Replicar wakeonlan exactamente
        # wakeonlan usa: puerto 9, broadcast 255.255.255.255
        
        # 1. Método principal: broadcast global puerto 9 (como wakeonlan)
        if self.send_wakeonlan_style(magic_packet, "255.255.255.255", 9, mac_address):
            total_sent += 1
            logger.info(f"✅ WoL enviado estilo wakeonlan a 255.255.255.255:9 para MAC {mac_address}")
        
        # 2. Broadcast local puerto 9 (compatibilidad red local)
        if self.send_wakeonlan_style(magic_packet, LOCAL_BROADCAST, 9, mac_address):
            total_sent += 1
            logger.info(f"✅ WoL enviado a broadcast local {LOCAL_BROADCAST}:9 para MAC {mac_address}")
        
        # 3. Envío directo puerto 9 (para dispositivos específicos)
        target_ip = "192.168.3.90"  # IP de tu dispositivo objetivo
        if self.send_wakeonlan_style(magic_packet, target_ip, 9, mac_address):
            total_sent += 1
            logger.info(f"✅ WoL enviado directo a {target_ip}:9 para MAC {mac_address}")
        
        # 4. Método de respaldo: puerto 7 (secundario)
        backup_targets = ["255.255.255.255", LOCAL_BROADCAST, target_ip]
        for target in backup_targets:
            if self.send_wakeonlan_style(magic_packet, target, 7, mac_address):
                total_sent += 1
                logger.info(f"✅ WoL respaldo enviado a {target}:7 para MAC {mac_address}")
        
        self.stats['packets_forwarded'] += total_sent
        return total_sent
    
    def handle_client(self, data, client_addr):
        """Procesar paquete recibido de cliente VPN"""
        self.stats['packets_received'] += 1
        
        logger.info(f"📦 Paquete #{self.stats['packets_received']} de {client_addr[0]}:{client_addr[1]} ({len(data)} bytes)")
        
        # Validar Magic Packet
        is_valid, result = self.validate_magic_packet(data)
        
        if not is_valid:
            logger.warning(f"⚠️ Paquete inválido de {client_addr[0]}: {result}")
            return
        
        mac_address = result
        logger.info(f"🎯 Magic Packet válido para MAC: {mac_address}")
        
        # Reenviar paquete a la red local
        forwarded = self.forward_wol_packet(data, client_addr, mac_address)
        logger.info(f"📡 Paquete reenviado a {forwarded} destinos en red 192.168.3.x")
        logger.info(f"🔥 Intentando despertar dispositivo MAC: {mac_address}")
    
    def print_stats(self):
        """Imprimir estadísticas del servidor"""
        uptime = datetime.now() - self.stats['start_time']
        logger.info("=" * 50)
        logger.info("📊 ESTADÍSTICAS DEL SERVIDOR")
        logger.info(f"⏱️ Tiempo activo: {uptime}")
        logger.info(f"📥 Paquetes recibidos: {self.stats['packets_received']}")
        logger.info(f"📤 Reenvíos realizados: {self.stats['packets_forwarded']}")
        logger.info("=" * 50)
    
    def start_server(self):
        """Iniciar servidor UDP en Docker"""
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            # Escuchar en todas las interfaces del contenedor
            self.server_socket.bind(('0.0.0.0', LISTEN_PORT))
            
            logger.info("🐳 WoL Forwarder para Docker iniciado")
            logger.info(f"🌐 Servidor WireGuard: 192.168.3.99")
            logger.info(f"👂 Escuchando en puerto: {LISTEN_PORT}")
            logger.info(f"📡 Red de destino: 192.168.3.x")
            logger.info(f"🎯 Dispositivo objetivo: 192.168.3.90")
            logger.info(f"🔌 Puertos WoL: {WOL_PORTS}")
            
            self.running = True
            stats_counter = 0
            
            while self.running:
                try:
                    # Recibir datos con timeout
                    self.server_socket.settimeout(5.0)
                    data, client_addr = self.server_socket.recvfrom(1024)
                    
                    # Procesar en hilo separado
                    thread = threading.Thread(
                        target=self.handle_client,
                        args=(data, client_addr)
                    )
                    thread.daemon = True
                    thread.start()
                    
                except socket.timeout:
                    # Cada 5 timeouts (25 segundos), mostrar que estamos vivos
                    stats_counter += 1
                    if stats_counter >= 5:
                        logger.info(f"💓 Servidor activo - Paquetes procesados: {self.stats['packets_received']}")
                        stats_counter = 0
                    continue
                except Exception as e:
                    if self.running:
                        logger.error(f"Error recibiendo datos: {e}")
                        
        except Exception as e:
            logger.error(f"❌ Error iniciando servidor: {e}")
        finally:
            self.stop_server()
    
    def stop_server(self):
        """Detener servidor"""
        logger.info("🛑 Deteniendo servidor WoL...")
        self.running = False
        if self.server_socket:
            self.server_socket.close()
        self.print_stats()
        logger.info("✅ Servidor Docker detenido correctamente")

# Instancia global
forwarder = DockerWoLForwarder()

def signal_handler(sig, frame):
    """Manejar señales de sistema"""
    logger.info(f"🔔 Señal recibida: {sig}")
    forwarder.stop_server()
    sys.exit(0)

def main():
    """Función principal"""
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info("=" * 60)
    logger.info("🌐 WoL Forwarder para WireGuard Docker v1.0")
    logger.info("🏠 Red: 192.168.3.x | 🐳 Docker: 192.168.3.99")
    logger.info("=" * 60)
    
    try:
        forwarder.start_server()
    except KeyboardInterrupt:
        logger.info("⌨️ Interrumpido por usuario")
    except Exception as e:
        logger.error(f"💥 Error fatal: {e}")

if __name__ == "__main__":
    main()