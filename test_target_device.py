#!/usr/bin/env python3
"""
Test script for the specific target device
MAC: 00:11:22:33:44:55
IP: 192.168.1.100
"""

import socket
import subprocess
import time
import sys
import json

# Device configuration
TARGET_MAC = "00:11:22:33:44:55"
TARGET_IP = "192.168.1.100"
DEVICE_NAME = "Dispositivo Objetivo"

def load_config():
    """Load configuration from config.json"""
    try:
        with open('config.json', 'r') as f:
            return json.load(f)
    except:
        return {
            "deviceName": DEVICE_NAME,
            "ipAddress": TARGET_IP,
            "macAddress": TARGET_MAC
        }

def ping_device(ip_address, timeout=3):
    """Check if device responds to ping"""
    try:
        result = subprocess.run(
            ['/sbin/ping', '-c', '1', '-W', '3000', ip_address],
            capture_output=True,
            timeout=5
        )
        return result.returncode == 0
    except:
        return False

def parse_mac_address(mac_str):
    """Parse MAC address string into bytes"""
    clean_mac = mac_str.replace(':', '').replace('-', '').replace(' ', '').upper()
    
    if len(clean_mac) != 12:
        raise ValueError(f"Invalid MAC address format: {mac_str}")
    
    mac_bytes = []
    for i in range(0, 12, 2):
        hex_byte = clean_mac[i:i+2]
        byte_val = int(hex_byte, 16)
        mac_bytes.append(byte_val)
    
    return bytes(mac_bytes)

def build_magic_packet(mac_bytes):
    """Build Wake-on-LAN magic packet: 6 bytes of 0xFF + 16 repetitions of MAC"""
    if len(mac_bytes) != 6:
        raise ValueError("MAC address must be 6 bytes")
    
    packet = b'\xFF' * 6
    packet += mac_bytes * 16
    
    return packet

def send_wol_packet(mac_address, target_ip):
    """Send Wake-on-LAN packet using multiple strategies"""
    print(f"📡 Enviando Magic Packets para despertar el dispositivo...")
    print(f"   MAC: {mac_address}")
    print(f"   IP: {target_ip}")
    
    try:
        mac_bytes = parse_mac_address(mac_address)
        magic_packet = build_magic_packet(mac_bytes)
        print(f"   Magic Packet: {len(magic_packet)} bytes construido ✅")
    except Exception as e:
        print(f"   ❌ Error construyendo magic packet: {e}")
        return False
    
    success_count = 0
    strategies = []
    
    # Strategy 1: Direct to target IP
    for port in [9, 7]:
        if send_udp_to_address(magic_packet, target_ip, port):
            strategies.append(f"Dirigido {target_ip}:{port}")
            success_count += 1
    
    # Strategy 2: Subnet broadcast
    subnet_broadcast = f"{'.'.join(target_ip.split('.')[:-1])}.255"
    for port in [9, 7]:
        if send_udp_to_address(magic_packet, subnet_broadcast, port):
            strategies.append(f"Subnet {subnet_broadcast}:{port}")
            success_count += 1
    
    # Strategy 3: Common subnets for VPN scenarios
    common_subnets = ["192.168.1.255", "192.168.0.255", "10.0.0.255"]
    for subnet in common_subnets:
        for port in [9, 7]:
            if send_udp_to_address(magic_packet, subnet, port):
                strategies.append(f"Común {subnet}:{port}")
                success_count += 1
    
    print(f"   ✅ {success_count} paquetes enviados exitosamente")
    if strategies:
        print(f"   📋 Estrategias exitosas: {', '.join(strategies[:3])}{'...' if len(strategies) > 3 else ''}")
    
    return success_count > 0

def send_udp_to_address(magic_packet, address, port):
    """Send UDP packet to specific address"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        sock.sendto(magic_packet, (address, port))
        sock.close()
        return True
    except:
        return False

def wait_for_device(ip_address, max_wait=60):
    """Wait for device to come online, checking every 2 seconds"""
    print(f"⏳ Esperando a que el dispositivo {ip_address} responda...")
    print(f"   (máximo {max_wait} segundos, Ctrl+C para cancelar)")
    
    start_time = time.time()
    attempt = 0
    
    while (time.time() - start_time) < max_wait:
        attempt += 1
        elapsed = int(time.time() - start_time)
        
        print(f"   📡 Intento {attempt} ({elapsed}s): ", end="", flush=True)
        
        if ping_device(ip_address):
            print("✅ ¡DISPOSITIVO ENCENDIDO!")
            return True
        else:
            print("Sin respuesta")
        
        time.sleep(2)
    
    print(f"   ⏰ Tiempo agotado después de {max_wait} segundos")
    return False

def main():
    """Main test function"""
    config = load_config()
    mac_address = config.get("macAddress", TARGET_MAC)
    ip_address = config.get("ipAddress", TARGET_IP)
    device_name = config.get("deviceName", DEVICE_NAME)
    
    print(f"🎯 === PRUEBA WAKE-ON-LAN PARA DISPOSITIVO ESPECÍFICO ===")
    print(f"📱 Dispositivo: {device_name}")
    print(f"📍 IP: {ip_address}")
    print(f"🔗 MAC: {mac_address}")
    print()
    
    # Check initial status
    print("1️⃣ Verificando estado inicial...")
    initial_status = ping_device(ip_address)
    if initial_status:
        print("   ✅ El dispositivo ya está encendido")
        print("   💡 No es necesario enviar Wake-on-LAN")
        return True
    else:
        print("   💤 El dispositivo está apagado (perfecto para la prueba)")
    
    print()
    
    # Send Wake-on-LAN
    print("2️⃣ Enviando Wake-on-LAN...")
    wol_success = send_wol_packet(mac_address, ip_address)
    
    if not wol_success:
        print("   ❌ Error enviando magic packets")
        return False
    
    print()
    
    # Wait for device to wake up
    print("3️⃣ Esperando respuesta del dispositivo...")
    device_online = wait_for_device(ip_address, max_wait=60)
    
    print()
    print("📊 === RESULTADO FINAL ===")
    
    if device_online:
        print("🎉 ¡ÉXITO! El dispositivo se ha encendido correctamente")
        print("✅ Wake-on-LAN funcionando perfectamente")
        
        # Double check with one more ping
        print("\n🔍 Verificación final...")
        if ping_device(ip_address):
            print("✅ Confirmado: dispositivo responde al ping")
        else:
            print("⚠️  Dispositivo puede estar encendido pero no responde a ping")
    else:
        print("❌ El dispositivo no respondió")
        print("💡 Posibles causas:")
        print("   • Wake-on-LAN no está habilitado en el dispositivo")
        print("   • El dispositivo no está conectado por cable (Ethernet)")
        print("   • Configuración de red o firewall")
        print("   • El dispositivo tarda más en arrancar")
    
    return device_online

if __name__ == "__main__":
    try:
        success = main()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⏹️ Prueba cancelada por el usuario")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n💥 Error: {e}")
        sys.exit(1)