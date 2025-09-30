#!/usr/bin/env python3
"""
Script de prueba para el WoL Forwarder
Envía un Magic Packet al servidor Docker para probar el reenvío
"""

import socket
import sys
import time

def create_magic_packet(mac_address):
    """Crear Magic Packet WoL"""
    # Limpiar MAC address
    mac = mac_address.replace(':', '').replace('-', '').upper()
    if len(mac) != 12:
        raise ValueError("MAC address inválida")
    
    # Convertir a bytes
    mac_bytes = bytes.fromhex(mac)
    
    # Magic packet: 6 bytes de 0xFF + 16 repeticiones de MAC
    magic_packet = b'\xFF' * 6 + mac_bytes * 16
    
    return magic_packet

def send_test_packet(server_ip, server_port, mac_address):
    """Enviar packet de prueba al forwarder"""
    try:
        magic_packet = create_magic_packet(mac_address)
        
        print(f"🧪 Enviando Magic Packet de prueba...")
        print(f"   📍 Servidor: {server_ip}:{server_port}")
        print(f"   🎯 MAC objetivo: {mac_address}")
        print(f"   📦 Tamaño packet: {len(magic_packet)} bytes")
        
        # Crear socket UDP
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(5.0)
        
        # Enviar packet
        start_time = time.time()
        sent_bytes = sock.sendto(magic_packet, (server_ip, server_port))
        end_time = time.time()
        
        sock.close()
        
        print(f"✅ Packet enviado exitosamente!")
        print(f"   📤 Bytes enviados: {sent_bytes}")
        print(f"   ⏱️ Tiempo: {(end_time - start_time)*1000:.1f}ms")
        
        return True
        
    except Exception as e:
        print(f"❌ Error enviando packet: {e}")
        return False

def main():
    # Configuración
    SERVER_IP = "192.168.1.100"
    SERVER_PORT = 8090  # Cambiado a 8090 (8080 ocupado por Pi-hole)
    TARGET_MAC = "00:11:22:33:44:55"  # Tu dispositivo
    
    print("🧪 PRUEBA DEL WOL FORWARDER DOCKER")
    print("=" * 50)
    print(f"🐳 Servidor Docker: {SERVER_IP}")
    print(f"🔌 Puerto Forwarder: {SERVER_PORT}")
    print(f"🎯 MAC objetivo: {TARGET_MAC}")
    print()
    
    # Probar conectividad básica
    print("1️⃣ Probando conectividad al servidor...")
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(3.0)
        sock.connect((SERVER_IP, SERVER_PORT))
        sock.close()
        print("✅ Servidor accesible")
    except Exception as e:
        print(f"⚠️ Advertencia: {e}")
        print("   (Esto es normal para UDP, continuando...)")
    
    print()
    
    # Enviar packet de prueba
    print("2️⃣ Enviando Magic Packet de prueba...")
    if send_test_packet(SERVER_IP, SERVER_PORT, TARGET_MAC):
        print()
        print("✅ ¡Prueba completada exitosamente!")
        print()
        print("🔍 Para verificar que el forwarder recibió el packet:")
        print(f"   ssh root@{SERVER_IP} 'docker logs wol-forwarder --tail 10'")
        print()
        print("📱 Ahora puedes probar desde la aplicación Swift")
        print("   La app debería enviar paquetes a este servidor automáticamente")
        
    else:
        print()
        print("❌ Error en la prueba")
        print()
        print("🔧 Para depurar:")
        print(f"   1. Verificar que el contenedor esté ejecutándose:")
        print(f"      ssh root@{SERVER_IP} 'docker ps | grep wol-forwarder'")
        print()
        print(f"   2. Ver logs del contenedor:")
        print(f"      ssh root@{SERVER_IP} 'docker logs wol-forwarder'")
        print()
        print(f"   3. Verificar conectividad de red:")
        print(f"      ping {SERVER_IP}")

if __name__ == "__main__":
    main()