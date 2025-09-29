#!/usr/bin/env python3
"""
Script de prueba para Wake-on-LAN
Envía un magic packet y luego hace ping para verificar si el dispositivo despierta
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

def send_wol_packet(mac_address):
    """Send Wake-on-LAN magic packet"""
    print(f"🔮 Construyendo magic packet para MAC: {mac_address}")
    
    try:
        # Parse MAC address
        mac_bytes = parse_mac_address(mac_address)
        print(f"   MAC bytes: {mac_bytes.hex(':').upper()}")
        
        # Build magic packet
        magic_packet = build_magic_packet(mac_bytes)
        print(f"   Magic packet size: {len(magic_packet)} bytes")
        
        # Create UDP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        
        # Send to broadcast address on port 9
        broadcast_addr = ('255.255.255.255', 9)
        sock.sendto(magic_packet, broadcast_addr)
        sock.close()
        
        print(f"✅ Magic packet enviado a {broadcast_addr[0]}:{broadcast_addr[1]}")
        return True
        
    except Exception as e:
        print(f"❌ Error enviando magic packet: {e}")
        return False

def ping_device(ip_address, duration_seconds=20, interval=1):
    """Ping device for specified duration and return if any ping succeeded"""
    print(f"📡 Haciendo ping a {ip_address} durante {duration_seconds} segundos...")
    
    start_time = time.time()
    ping_count = 0
    successful_pings = 0
    
    while (time.time() - start_time) < duration_seconds:
        ping_count += 1
        
        try:
            # Execute ping command (1 ping, 3 second timeout)
            result = subprocess.run(
                ['/sbin/ping', '-c', '1', '-W', '3000', ip_address],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode == 0:
                successful_pings += 1
                print(f"   ✅ Ping #{ping_count}: Respuesta recibida")
            else:
                print(f"   ❌ Ping #{ping_count}: Sin respuesta")
        
        except subprocess.TimeoutExpired:
            print(f"   ⏰ Ping #{ping_count}: Timeout")
        except Exception as e:
            print(f"   ❌ Ping #{ping_count}: Error - {e}")
        
        # Wait before next ping
        if (time.time() - start_time) < duration_seconds - 1:
            time.sleep(interval)
    
    success_rate = (successful_pings / ping_count) * 100 if ping_count > 0 else 0
    print(f"📊 Resultado: {successful_pings}/{ping_count} pings exitosos ({success_rate:.1f}%)")
    
    return successful_pings > 0

def main():
    """Main test function"""
    print("🧪 === PRUEBA DE WAKE-ON-LAN ===")
    print()
    
    # Configuration
    mac_address = "70:85:C2:98:7B:3E"
    ip_address = "192.168.3.90"
    
    print(f"🎯 Dispositivo objetivo:")
    print(f"   MAC Address: {mac_address}")
    print(f"   IP Address: {ip_address}")
    print()
    
    # Step 1: Check initial status
    print("1️⃣ Verificando estado inicial del dispositivo...")
    initial_ping = ping_device(ip_address, duration_seconds=3, interval=1)
    
    if initial_ping:
        print("⚠️  El dispositivo ya está encendido. La prueba continuará de todos modos.")
    else:
        print("💤 El dispositivo parece estar apagado (como se esperaba).")
    print()
    
    # Step 2: Send Wake-on-LAN packet
    print("2️⃣ Enviando magic packet Wake-on-LAN...")
    wol_success = send_wol_packet(mac_address)
    
    if not wol_success:
        print("❌ Fallo al enviar magic packet. Abortando prueba.")
        return False
    print()
    
    # Step 3: Wait for device to wake up
    print("3️⃣ Esperando 20 segundos para que el dispositivo despierte...")
    for i in range(20, 0, -1):
        print(f"   ⏳ {i} segundos restantes...", end='\r')
        time.sleep(1)
    print("   ✅ Tiempo de espera completado.                    ")
    print()
    
    # Step 4: Test connectivity
    print("4️⃣ Probando conectividad durante 20 segundos...")
    final_ping = ping_device(ip_address, duration_seconds=20, interval=1)
    print()
    
    # Results
    print("📋 === RESULTADOS DE LA PRUEBA ===")
    print(f"Magic packet enviado: {'✅ Sí' if wol_success else '❌ No'}")
    print(f"Dispositivo despertó: {'✅ Sí' if final_ping else '❌ No'}")
    
    if wol_success and final_ping:
        print("🎉 ¡PRUEBA EXITOSA! Wake-on-LAN está funcionando correctamente.")
        return True
    elif wol_success and not final_ping:
        print("⚠️  Magic packet enviado pero el dispositivo no respondió.")
        print("   Posibles causas:")
        print("   - Wake-on-LAN no está habilitado en el dispositivo")
        print("   - El dispositivo no soporta Wake-on-LAN")
        print("   - Problema de red o firewall")
        print("   - Dirección MAC o IP incorrecta")
        return False
    else:
        print("❌ PRUEBA FALLIDA. No se pudo enviar el magic packet.")
        return False

if __name__ == "__main__":
    try:
        success = main()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⏹️  Prueba interrumpida por el usuario.")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n💥 Error inesperado: {e}")
        sys.exit(1)