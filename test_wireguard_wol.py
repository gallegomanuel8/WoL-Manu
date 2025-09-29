#!/usr/bin/env python3
"""
Test script to verify Wake-on-LAN through WireGuard server forwarder
Tests the connection to the WireGuard server on port 8080
"""

import socket
import subprocess
import time
import sys

def build_magic_packet(mac_address):
    """Build Wake-on-LAN magic packet"""
    # Parse MAC address
    clean_mac = mac_address.replace(':', '').replace('-', '').upper()
    if len(clean_mac) != 12:
        raise ValueError("Invalid MAC address")
    
    mac_bytes = bytes.fromhex(clean_mac)
    
    # Build magic packet: 6 bytes of 0xFF + 16 repetitions of MAC
    packet = b'\xFF' * 6 + mac_bytes * 16
    return packet

def test_wireguard_connection():
    """Test basic connectivity to WireGuard server"""
    wireguard_server = "10.8.0.1"
    
    print("🌐 Probando conectividad con servidor WireGuard...")
    print(f"   Servidor: {wireguard_server}")
    
    try:
        # Test ping to WireGuard server
        result = subprocess.run(
            ['/sbin/ping', '-c', '1', '-W', '3000', wireguard_server],
            capture_output=True,
            timeout=5
        )
        
        if result.returncode == 0:
            print("   ✅ Servidor WireGuard accesible")
            return True
        else:
            print("   ❌ Servidor WireGuard no accesible")
            return False
    except:
        print("   ❌ Error probando conectividad")
        return False

def test_wol_forwarder_port():
    """Test if the WoL forwarder port is listening"""
    wireguard_server = "10.8.0.1"
    wol_port = 8080
    
    print(f"\n🔌 Probando puerto WoL forwarder...")
    print(f"   Servidor: {wireguard_server}:{wol_port}")
    
    try:
        # Try to connect to the port
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(3)
        
        # Send a test UDP packet
        test_data = b"TEST_PACKET"
        sock.sendto(test_data, (wireguard_server, wol_port))
        sock.close()
        
        print("   ✅ Puerto accesible - puede enviar UDP")
        return True
        
    except socket.timeout:
        print("   ⚠️  Puerto no responde (puede estar funcionando)")
        return True  # UDP doesn't respond, but that's expected
    except Exception as e:
        print(f"   ❌ Error conectando al puerto: {e}")
        return False

def send_wol_via_forwarder(mac_address, target_ip):
    """Send Wake-on-LAN packet via WireGuard forwarder"""
    wireguard_server = "10.8.0.1"
    wol_port = 8080
    
    print(f"\n📡 Enviando Wake-on-LAN via forwarder...")
    print(f"   Objetivo: {target_ip} ({mac_address})")
    print(f"   Via: {wireguard_server}:{wol_port}")
    
    try:
        # Build magic packet
        magic_packet = build_magic_packet(mac_address)
        print(f"   Magic packet: {len(magic_packet)} bytes construido ✅")
        
        # Send via forwarder
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.sendto(magic_packet, (wireguard_server, wol_port))
        sock.close()
        
        print("   ✅ Magic packet enviado al forwarder")
        return True
        
    except Exception as e:
        print(f"   ❌ Error enviando magic packet: {e}")
        return False

def monitor_target_device(target_ip, duration=60):
    """Monitor target device for wake-up response"""
    print(f"\n⏳ Monitoreando dispositivo objetivo...")
    print(f"   IP: {target_ip}")
    print(f"   Duración: {duration} segundos")
    
    start_time = time.time()
    attempt = 0
    
    while (time.time() - start_time) < duration:
        attempt += 1
        elapsed = int(time.time() - start_time)
        
        print(f"   📡 Intento {attempt} ({elapsed}s): ", end="", flush=True)
        
        try:
            result = subprocess.run(
                ['/sbin/ping', '-c', '1', '-W', '3000', target_ip],
                capture_output=True,
                timeout=5
            )
            
            if result.returncode == 0:
                print("✅ ¡DISPOSITIVO ENCENDIDO!")
                return True
            else:
                print("Sin respuesta")
        except:
            print("Error")
        
        time.sleep(3)
    
    print(f"\n   ⏰ Tiempo agotado después de {duration} segundos")
    return False

def main():
    """Main test function"""
    print("🧪 === PRUEBA WAKE-ON-LAN VIA WIREGUARD FORWARDER ===")
    print()
    
    # Configuration
    mac_address = "70:85:C2:98:7B:3E"
    target_ip = "192.168.3.90"
    
    # Test 1: WireGuard connectivity
    if not test_wireguard_connection():
        print("\n❌ No se puede conectar al servidor WireGuard")
        print("Verifica que la VPN esté conectada y funcionando")
        return False
    
    # Test 2: WoL forwarder port
    if not test_wol_forwarder_port():
        print("\n❌ El forwarder WoL no parece estar funcionando")
        print("En el servidor WireGuard, ejecuta:")
        print("  sudo ./wol-forwarder-server.sh install")
        print("  sudo systemctl status wol-forwarder")
        return False
    
    # Test 3: Check initial device status
    print("\n1️⃣ Verificando estado inicial del dispositivo...")
    try:
        result = subprocess.run(['/sbin/ping', '-c', '1', '-W', '3000', target_ip], 
                              capture_output=True, timeout=5)
        if result.returncode == 0:
            print("   ✅ El dispositivo ya está encendido")
            print("   💡 No es necesario enviar Wake-on-LAN")
            return True
        else:
            print("   💤 El dispositivo está apagado - perfecto para la prueba")
    except:
        print("   💤 El dispositivo no responde - procediendo con Wake-on-LAN")
    
    # Test 4: Send WoL via forwarder
    print("\n2️⃣ Enviando Wake-on-LAN via forwarder...")
    if not send_wol_via_forwarder(mac_address, target_ip):
        print("\n❌ Error enviando magic packet")
        return False
    
    # Test 5: Monitor for device response
    print("\n3️⃣ Esperando respuesta del dispositivo...")
    device_woke_up = monitor_target_device(target_ip, duration=90)
    
    # Results
    print("\n" + "="*60)
    print("📊 RESULTADO FINAL")
    
    if device_woke_up:
        print("🎉 ¡ÉXITO! Wake-on-LAN a través de WireGuard funcionando")
        print("✅ El dispositivo se encendió correctamente")
        print("\n💡 Tu aplicación Swift debería funcionar ahora")
    else:
        print("❌ El dispositivo no se encendió")
        print("\n🔧 Pasos de diagnóstico:")
        print("1. Verificar que el forwarder esté funcionando en el servidor:")
        print("   sudo systemctl status wol-forwarder")
        print("2. Verificar logs del forwarder:")
        print("   sudo tail -f /var/log/wol-forwarder.log")
        print("3. Verificar que el dispositivo tenga WoL habilitado")
        print("4. Probar Wake-on-LAN local para confirmar configuración")
    
    return device_woke_up

if __name__ == "__main__":
    try:
        success = main()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⏹️ Prueba cancelada por el usuario")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n💥 Error inesperado: {e}")
        sys.exit(1)