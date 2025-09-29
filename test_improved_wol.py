#!/usr/bin/env python3
"""
Script de prueba para el Wake-on-LAN mejorado
Envía magic packets usando las mismas estrategias que la aplicación Swift
"""

import socket
import struct
import subprocess
import time
import sys

def parse_mac_address(mac_str):
    """Parse MAC address string into bytes"""
    # Remove common separators and convert to uppercase
    clean_mac = mac_str.replace(':', '').replace('-', '').replace(' ', '').upper()
    
    if len(clean_mac) != 12:
        raise ValueError(f"Invalid MAC address format: {mac_str}")
    
    # Convert to bytes
    mac_bytes = []
    for i in range(0, 12, 2):
        hex_byte = clean_mac[i:i+2]
        try:
            byte_val = int(hex_byte, 16)
            mac_bytes.append(byte_val)
        except ValueError:
            raise ValueError(f"Invalid hex in MAC address: {hex_byte}")
    
    return bytes(mac_bytes)

def build_magic_packet(mac_bytes):
    """Build Wake-on-LAN magic packet: 6 bytes of 0xFF + 16 repetitions of MAC"""
    if len(mac_bytes) != 6:
        raise ValueError("MAC address must be 6 bytes")
    
    # 6 bytes of 0xFF
    packet = b'\xFF' * 6
    
    # 16 repetitions of the MAC address
    packet += mac_bytes * 16
    
    return packet

def send_udp_to_address(magic_packet, address, port):
    """Send UDP packet to specific address"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        sock.sendto(magic_packet, (address, port))
        sock.close()
        return True
    except Exception as e:
        print(f"   ❌ Error enviando a {address}:{port} - {e}")
        return False

def calculate_subnet_broadcast(ip_address):
    """Calculate subnet broadcast for /24 network"""
    try:
        parts = ip_address.split('.')
        if len(parts) == 4:
            return f"{parts[0]}.{parts[1]}.{parts[2]}.255"
    except:
        pass
    return None

def test_improved_wol(mac_address, target_ip=None):
    """Test the improved Wake-on-LAN functionality"""
    print(f"🧪 === PRUEBA DE WAKE-ON-LAN MEJORADO ===")
    print()
    
    print(f"🎯 Objetivo:")
    print(f"   MAC Address: {mac_address}")
    if target_ip:
        print(f"   IP Address: {target_ip}")
    print()
    
    # Parse MAC and build magic packet
    try:
        mac_bytes = parse_mac_address(mac_address)
        magic_packet = build_magic_packet(mac_bytes)
        print(f"✅ Magic Packet construido: {len(magic_packet)} bytes")
    except Exception as e:
        print(f"❌ Error construyendo Magic Packet: {e}")
        return False
    
    success_count = 0
    ports = [9, 7]  # Standard Wake-on-LAN ports
    
    print()
    print("📡 Enviando Magic Packets usando múltiples estrategias...")
    print()
    
    # Strategy 1: Global broadcast
    print("🌐 Estrategia 1: Broadcast Global")
    for port in ports:
        if send_udp_to_address(magic_packet, "255.255.255.255", port):
            print(f"   ✅ Enviado a 255.255.255.255:{port}")
            success_count += 1
    
    # Strategy 2: Direct to target IP (if provided)
    if target_ip:
        print()
        print("🎯 Estrategia 2: Envío Dirigido")
        for port in ports:
            if send_udp_to_address(magic_packet, target_ip, port):
                print(f"   ✅ Enviado dirigido a {target_ip}:{port}")
                success_count += 1
        
        # Also try subnet broadcast
        subnet_broadcast = calculate_subnet_broadcast(target_ip)
        if subnet_broadcast:
            print()
            print("🔀 Estrategia 2b: Subnet Broadcast")
            for port in ports:
                if send_udp_to_address(magic_packet, subnet_broadcast, port):
                    print(f"   ✅ Enviado a subnet broadcast {subnet_broadcast}:{port}")
                    success_count += 1
    
    # Strategy 3: Common subnets (VPN scenarios)
    print()
    print("🔄 Estrategia 3: Subnets Comunes")
    common_subnets = ["192.168.1.255", "192.168.0.255", "192.168.3.255", "10.0.0.255", "172.16.0.255"]
    for subnet in common_subnets:
        for port in ports:
            if send_udp_to_address(magic_packet, subnet, port):
                print(f"   ✅ Enviado a subnet común {subnet}:{port}")
                success_count += 1
    
    print()
    print(f"📊 === RESUMEN ===")
    print(f"Magic Packets enviados exitosamente: {success_count}")
    print(f"Estado: {'✅ ÉXITO' if success_count > 0 else '❌ FALLO'}")
    
    if success_count > 0:
        print()
        print("💡 La aplicación Swift debería funcionar correctamente tanto en VPN como en red directa.")
    
    return success_count > 0

def main():
    """Main test function"""
    # Use the same configuration from config.json
    mac_address = "70:85:C2:98:7B:3E"
    target_ip = "192.168.3.99"
    
    try:
        success = test_improved_wol(mac_address, target_ip)
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⏹️ Prueba interrumpida por el usuario.")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n💥 Error inesperado: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()