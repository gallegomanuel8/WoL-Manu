#!/usr/bin/env python3
"""
Wake-on-LAN script specifically designed to work through WireGuard VPN
This script tries multiple advanced strategies for VPN scenarios
"""

import socket
import subprocess
import time
import sys
import json

def get_network_info():
    """Get current network configuration"""
    info = {}
    try:
        # Get VPN interface info
        result = subprocess.run(['ifconfig', 'utun6'], capture_output=True, text=True)
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'inet ' in line:
                    parts = line.strip().split()
                    for i, part in enumerate(parts):
                        if part == 'inet':
                            info['vpn_ip'] = parts[i+1]
                            break
        
        # Get local interface info
        result = subprocess.run(['ifconfig', 'en0'], capture_output=True, text=True)
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'inet ' in line and '127.0.0.1' not in line:
                    parts = line.strip().split()
                    for i, part in enumerate(parts):
                        if part == 'inet':
                            info['local_ip'] = parts[i+1]
                            break
    except:
        pass
    
    return info

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
    """Build Wake-on-LAN magic packet"""
    if len(mac_bytes) != 6:
        raise ValueError("MAC address must be 6 bytes")
    
    packet = b'\xFF' * 6
    packet += mac_bytes * 16
    return packet

def send_raw_udp(magic_packet, dest_ip, dest_port, source_ip=None, interface=None):
    """Send UDP packet with specific source/interface"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        # Try to bind to specific source if provided
        if source_ip:
            try:
                sock.bind((source_ip, 0))
            except:
                pass  # Fallback to default binding
        
        sock.sendto(magic_packet, (dest_ip, dest_port))
        sock.close()
        return True
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False

def advanced_wol_strategies(mac_address, target_ip):
    """Advanced Wake-on-LAN strategies for VPN scenarios"""
    print(f"🚀 === WAKE-ON-LAN AVANZADO A TRAVÉS DE VPN ===")
    print(f"🎯 Objetivo: {target_ip} ({mac_address})")
    print()
    
    # Get network info
    net_info = get_network_info()
    print("🌐 Información de red:")
    if 'vpn_ip' in net_info:
        print(f"   VPN (WireGuard): {net_info['vpn_ip']}")
    if 'local_ip' in net_info:
        print(f"   Red local: {net_info['local_ip']}")
    print()
    
    # Build magic packet
    try:
        mac_bytes = parse_mac_address(mac_address)
        magic_packet = build_magic_packet(mac_bytes)
        print(f"✅ Magic Packet construido: {len(magic_packet)} bytes")
    except Exception as e:
        print(f"❌ Error: {e}")
        return False
    
    success_count = 0
    strategies = []
    
    print("\n📡 Probando estrategias avanzadas...")
    
    # Strategy 1: Direct unicast through VPN
    print("\n🎯 Estrategia 1: Unicast directo a través de VPN")
    for port in [9, 7, 0]:  # Port 0 is sometimes used
        if send_raw_udp(magic_packet, target_ip, port):
            print(f"   ✅ Enviado a {target_ip}:{port}")
            strategies.append(f"Directo {target_ip}:{port}")
            success_count += 1
    
    # Strategy 2: Broadcast to target subnet through VPN
    print("\n🌐 Estrategia 2: Broadcast de subnet a través de VPN")
    target_subnet_broadcast = f"{'.'.join(target_ip.split('.')[:-1])}.255"
    for port in [9, 7]:
        if send_raw_udp(magic_packet, target_subnet_broadcast, port):
            print(f"   ✅ Enviado a broadcast {target_subnet_broadcast}:{port}")
            strategies.append(f"Broadcast {target_subnet_broadcast}:{port}")
            success_count += 1
    
    # Strategy 3: Try with different source IPs
    print("\n🔀 Estrategia 3: Desde diferentes IPs de origen")
    if 'vpn_ip' in net_info:
        for port in [9, 7]:
            if send_raw_udp(magic_packet, target_ip, port, source_ip=net_info['vpn_ip']):
                print(f"   ✅ Desde VPN IP {net_info['vpn_ip']} → {target_ip}:{port}")
                strategies.append(f"VPN-src {target_ip}:{port}")
                success_count += 1
    
    # Strategy 4: Multiple target IPs in the same subnet
    print("\n🔄 Estrategia 4: IPs múltiples en la subnet")
    subnet_base = '.'.join(target_ip.split('.')[:-1])
    common_ips = [f"{subnet_base}.1", f"{subnet_base}.254", f"{subnet_base}.255"]
    
    for ip in common_ips:
        if ip != target_ip:  # Don't repeat the target
            for port in [9, 7]:
                if send_raw_udp(magic_packet, ip, port):
                    print(f"   ✅ Enviado a {ip}:{port}")
                    strategies.append(f"Subnet {ip}:{port}")
                    success_count += 1
    
    # Strategy 5: Try using netcat or socat if available
    print("\n⚙️ Estrategia 5: Herramientas del sistema")
    try:
        # Create a temporary file with the magic packet
        with open('/tmp/magic_packet.bin', 'wb') as f:
            f.write(magic_packet)
        
        # Try with netcat if available
        for port in [9, 7]:
            try:
                result = subprocess.run([
                    'nc', '-u', '-w1', target_ip, str(port)
                ], input=magic_packet, timeout=5)
                if result.returncode == 0:
                    print(f"   ✅ Netcat a {target_ip}:{port}")
                    strategies.append(f"Netcat {target_ip}:{port}")
                    success_count += 1
            except:
                pass
    except:
        pass
    
    print(f"\n📊 === RESUMEN ===")
    print(f"Intentos exitosos: {success_count}")
    print(f"Estrategias que funcionaron: {len(set(strategies))}")
    
    if success_count > 0:
        print("✅ Magic packets enviados - esperando respuesta del dispositivo...")
        return True
    else:
        print("❌ No se pudo enviar ningún magic packet")
        return False

def wait_for_device_with_timeout(ip_address, max_wait=90):
    """Wait for device with longer timeout for VPN scenarios"""
    print(f"\n⏳ Esperando respuesta del dispositivo...")
    print(f"   IP: {ip_address}")
    print(f"   Tiempo máximo: {max_wait} segundos")
    print("   (Los dispositivos a través de VPN pueden tardar más)")
    
    start_time = time.time()
    attempt = 0
    
    while (time.time() - start_time) < max_wait:
        attempt += 1
        elapsed = int(time.time() - start_time)
        
        print(f"   📡 Intento {attempt} ({elapsed}s): ", end="", flush=True)
        
        try:
            result = subprocess.run(
                ['/sbin/ping', '-c', '1', '-W', '3000', ip_address],
                capture_output=True,
                timeout=5
            )
            if result.returncode == 0:
                print("✅ ¡RESPUESTA RECIBIDA!")
                return True
            else:
                print("Sin respuesta")
        except:
            print("Timeout")
        
        time.sleep(3)  # Longer interval for VPN
    
    print(f"\n   ⏰ Tiempo agotado después de {max_wait} segundos")
    return False

def main():
    """Main function"""
    # Configuration
    mac_address = "70:85:C2:98:7B:3E"
    target_ip = "192.168.3.90"
    
    print("🔧 Iniciando Wake-on-LAN avanzado a través de WireGuard VPN")
    print("=" * 60)
    
    # Check initial status
    print("1️⃣ Verificando estado inicial...")
    try:
        result = subprocess.run(['/sbin/ping', '-c', '1', '-W', '3000', target_ip], 
                              capture_output=True, timeout=5)
        if result.returncode == 0:
            print("   ✅ El dispositivo ya está encendido")
            return True
        else:
            print("   💤 El dispositivo está apagado - procediendo con Wake-on-LAN")
    except:
        print("   💤 El dispositivo no responde - procediendo con Wake-on-LAN")
    
    print("\n2️⃣ Enviando magic packets...")
    wol_success = advanced_wol_strategies(mac_address, target_ip)
    
    if not wol_success:
        print("\n❌ No se pudieron enviar los magic packets")
        return False
    
    print("\n3️⃣ Esperando que el dispositivo se encienda...")
    device_online = wait_for_device_with_timeout(target_ip, max_wait=90)
    
    print("\n" + "=" * 60)
    print("📊 RESULTADO FINAL")
    
    if device_online:
        print("🎉 ¡ÉXITO! El dispositivo respondió")
        print("✅ Wake-on-LAN a través de VPN funcionando")
    else:
        print("❌ El dispositivo no respondió")
        print("\n💡 Posibles soluciones:")
        print("   • Configurar reenvío de broadcasts en el servidor VPN")
        print("   • Usar un relay/bridge en la red remota")
        print("   • Configurar port forwarding específico para WoL")
        print("   • El dispositivo puede tardar más en arrancar")
    
    return device_online

if __name__ == "__main__":
    try:
        success = main()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⏹️ Cancelado por el usuario")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n💥 Error: {e}")
        sys.exit(1)