#!/usr/bin/env python3
"""
Unit tests para validaciones en el servidor Wake-on-LAN
Prueba las funciones de validación de MAC, IP y construcción de magic packet
"""

import unittest
import re
from unittest.mock import patch, MagicMock
import socket

# Importamos las funciones que queremos testear
# Como app.py no está estructurado como módulo, necesitamos simular las funciones
def is_valid_mac(mac_address):
    """
    Valida formato de dirección MAC
    Acepta formatos: XX:XX:XX:XX:XX:XX, XX-XX-XX-XX-XX-XX, XXXXXXXXXXXX
    """
    if not mac_address or not isinstance(mac_address, str):
        return False
    
    # Remover espacios
    mac = mac_address.strip()
    
    # Evitar MACs comunes inválidas
    invalid_macs = {
        '00:00:00:00:00:00', '00-00-00-00-00-00', '000000000000',
        'FF:FF:FF:FF:FF:FF', 'FF-FF-FF-FF-FF-FF', 'FFFFFFFFFFFF'
    }
    
    if mac.upper() in invalid_macs:
        return False
    
    # Verificar longitud máxima para prevenir DoS
    if len(mac) > 20:
        return False
    
    # Formato con dos puntos
    if ':' in mac:
        parts = mac.split(':')
        if len(parts) != 6:
            return False
        pattern = r'^[0-9A-Fa-f]{2}$'
        return all(re.match(pattern, part) for part in parts)
    
    # Formato con guiones
    elif '-' in mac:
        parts = mac.split('-')
        if len(parts) != 6:
            return False
        pattern = r'^[0-9A-Fa-f]{2}$'
        return all(re.match(pattern, part) for part in parts)
    
    # Formato sin separadores
    else:
        if len(mac) != 12:
            return False
        pattern = r'^[0-9A-Fa-f]{12}$'
        return bool(re.match(pattern, mac))

def is_valid_ip(ip_address):
    """
    Valida formato de dirección IP
    """
    if not ip_address or not isinstance(ip_address, str):
        return False
    
    # Verificar que no tenga espacios al inicio o final
    if ip_address != ip_address.strip():
        return False
    
    # Verificar longitud máxima
    if len(ip_address) > 15:  # Max IPv4: xxx.xxx.xxx.xxx
        return False
    
    try:
        # Usar socket.inet_aton para validación estricta IPv4
        socket.inet_aton(ip_address)
        
        # Verificar que no sea una IP reservada problemática
        parts = ip_address.split('.')
        if len(parts) != 4:
            return False
        
        # Verificar que no haya leading zeros (excepto "0" solo)
        for part in parts:
            if len(part) > 1 and part[0] == '0':
                return False
        
        # Rechazar 0.0.0.0, 127.x.x.x, 255.255.255.255
        first_octet = int(parts[0])
        if first_octet == 0 or first_octet == 127 or ip_address == '255.255.255.255':
            return False
        
        return True
    except (socket.error, ValueError):
        return False

def build_magic_packet(mac_address):
    """
    Construye el paquete mágico Wake-on-LAN
    """
    if not is_valid_mac(mac_address):
        return None
    
    # Normalizar MAC removiendo separadores
    mac_clean = mac_address.replace(':', '').replace('-', '').upper()
    
    try:
        # Convertir a bytes
        mac_bytes = bytes.fromhex(mac_clean)
        
        # Construir magic packet: 6 bytes de 0xFF + 16 repeticiones de MAC
        magic_packet = b'\xFF' * 6 + mac_bytes * 16
        
        return magic_packet
    except ValueError:
        return None

class TestMACValidation(unittest.TestCase):
    """Tests para validación de direcciones MAC"""
    
    def test_valid_mac_formats(self):
        """Test formatos válidos de MAC"""
        valid_macs = [
            "00:1B:63:84:45:E6",
            "AA:BB:CC:DD:EE:FF",
            "00-1B-63-84-45-E6", 
            "AA-BB-CC-DD-EE-FF",
            "001B638445E6",
            "AABBCCDDEEFF",
            "00:1b:63:84:45:e6",  # lowercase
            "aa:bb:cc:dd:ee:ff"   # lowercase
        ]
        
        for mac in valid_macs:
            with self.subTest(mac=mac):
                self.assertTrue(is_valid_mac(mac), f"Should accept valid MAC: {mac}")
    
    def test_invalid_mac_formats(self):
        """Test formatos inválidos de MAC"""
        invalid_macs = [
            "",                           # vacío
            None,                         # None
            "00:1B:63:84:45",            # muy corto
            "00:1B:63:84:45:E6:FF",      # muy largo
            "00:1B:63:84:45:ZZ",         # caracteres inválidos
            "00:1B-63:84:45:E6",         # separadores mixtos
            "001B638445E",               # sin separadores muy corto
            "001B638445E6FF",            # sin separadores muy largo
            "GG:HH:II:JJ:KK:LL",         # caracteres no-hex
            "00:1B:63:84:45:E6:extra",   # contenido extra
        ]
        
        for mac in invalid_macs:
            with self.subTest(mac=mac):
                self.assertFalse(is_valid_mac(mac), f"Should reject invalid MAC: {mac}")
    
    def test_invalid_common_macs(self):
        """Test MACs comunes que deberían ser rechazadas"""
        invalid_macs = [
            "00:00:00:00:00:00",
            "00-00-00-00-00-00", 
            "000000000000",
            "FF:FF:FF:FF:FF:FF",
            "FF-FF-FF-FF-FF-FF",
            "FFFFFFFFFFFF"
        ]
        
        for mac in invalid_macs:
            with self.subTest(mac=mac):
                self.assertFalse(is_valid_mac(mac), f"Should reject common invalid MAC: {mac}")
    
    def test_mac_dos_protection(self):
        """Test protección contra DoS con MACs muy largas"""
        long_mac = "00:1B:63:84:45:E6" + ":FF" * 20  # MAC extremadamente larga
        self.assertFalse(is_valid_mac(long_mac), "Should reject overly long MAC")
    
    def test_mac_edge_cases(self):
        """Test casos edge de MAC"""
        edge_cases = [
            123,              # número en lugar de string
            [],               # lista vacía
            {},               # diccionario vacío
            "   ",            # solo espacios
            "\n\t",           # caracteres de escape
        ]
        
        for case in edge_cases:
            with self.subTest(case=case):
                self.assertFalse(is_valid_mac(case), f"Should handle edge case: {case}")

class TestIPValidation(unittest.TestCase):
    """Tests para validación de direcciones IP"""
    
    def test_valid_ip_addresses(self):
        """Test direcciones IP válidas"""
        valid_ips = [
            "192.168.1.100",
            "10.0.0.1",
            "172.16.0.1", 
            "8.8.8.8",
            "1.1.1.1",
            "192.168.0.255",
            "10.255.255.254"
        ]
        
        for ip in valid_ips:
            with self.subTest(ip=ip):
                self.assertTrue(is_valid_ip(ip), f"Should accept valid IP: {ip}")
    
    def test_invalid_ip_addresses(self):
        """Test direcciones IP inválidas"""
        invalid_ips = [
            "",                    # vacío
            None,                  # None
            "256.1.1.1",          # octet > 255
            "192.168.1",          # muy corto
            "192.168.1.1.1",      # muy largo
            "192.168.1.256",      # último octet > 255
            "abc.def.ghi.jkl",    # no numérico
            "192.168.1.-1",       # octet negativo
            "192.168.1.01",       # leading zero
            "192.168.01.1",       # leading zero en otro octet
        ]
        
        for ip in invalid_ips:
            with self.subTest(ip=ip):
                self.assertFalse(is_valid_ip(ip), f"Should reject invalid IP: {ip}")
    
    def test_reserved_ip_addresses(self):
        """Test direcciones IP reservadas que deberían ser rechazadas"""
        reserved_ips = [
            "0.0.0.0",           # all zeros
            "127.0.0.1",         # localhost
            "127.1.1.1",         # loopback range
            "255.255.255.255",   # broadcast
        ]
        
        for ip in reserved_ips:
            with self.subTest(ip=ip):
                self.assertFalse(is_valid_ip(ip), f"Should reject reserved IP: {ip}")
    
    def test_ip_dos_protection(self):
        """Test protección contra DoS con IPs muy largas"""
        long_ip = "192.168.1.1" + ".1" * 20  # IP extremadamente larga
        self.assertFalse(is_valid_ip(long_ip), "Should reject overly long IP")
    
    def test_ip_edge_cases(self):
        """Test casos edge de IP"""
        edge_cases = [
            123,              # número
            [],               # lista
            {},               # diccionario
            "   ",            # espacios
            "192.168.1.1 ",   # espacio al final
            " 192.168.1.1",   # espacio al inicio
        ]
        
        for case in edge_cases:
            with self.subTest(case=case):
                self.assertFalse(is_valid_ip(case), f"Should handle edge case: {case}")

class TestMagicPacketConstruction(unittest.TestCase):
    """Tests para construcción del paquete mágico"""
    
    def test_build_valid_magic_packet(self):
        """Test construcción de paquete mágico válido"""
        mac = "00:1B:63:84:45:E6"
        packet = build_magic_packet(mac)
        
        self.assertIsNotNone(packet, "Should build magic packet for valid MAC")
        self.assertEqual(len(packet), 102, "Magic packet should be 102 bytes")
        
        # Verificar preamble (6 bytes de 0xFF)
        preamble = packet[:6]
        self.assertEqual(preamble, b'\xFF' * 6, "Preamble should be 6 bytes of 0xFF")
        
        # Verificar repeticiones de MAC (16 veces)
        expected_mac_bytes = bytes.fromhex("001B638445E6")
        for i in range(16):
            start = 6 + (i * 6)
            end = start + 6
            mac_repetition = packet[start:end]
            self.assertEqual(mac_repetition, expected_mac_bytes, f"MAC repetition {i} should be correct")
    
    def test_build_magic_packet_different_formats(self):
        """Test construcción con diferentes formatos de MAC"""
        test_cases = [
            ("00:1B:63:84:45:E6", "001B638445E6"),
            ("00-1B-63-84-45-E6", "001B638445E6"), 
            ("001B638445E6", "001B638445E6"),
            ("aa:bb:cc:dd:ee:ff", "AABBCCDDEEFF"),
        ]
        
        for mac_input, expected_hex in test_cases:
            with self.subTest(mac=mac_input):
                packet = build_magic_packet(mac_input)
                self.assertIsNotNone(packet, f"Should build packet for MAC format: {mac_input}")
                
                expected_mac_bytes = bytes.fromhex(expected_hex)
                # Verificar primera repetición de MAC en el paquete
                first_mac = packet[6:12]
                self.assertEqual(first_mac, expected_mac_bytes, f"First MAC repetition should match for {mac_input}")
    
    def test_build_magic_packet_invalid_mac(self):
        """Test construcción con MAC inválida"""
        invalid_macs = [
            "",
            None,
            "invalid",
            "00:1B:63:84:45",
            "ZZ:ZZ:ZZ:ZZ:ZZ:ZZ"
        ]
        
        for mac in invalid_macs:
            with self.subTest(mac=mac):
                packet = build_magic_packet(mac)
                self.assertIsNone(packet, f"Should not build packet for invalid MAC: {mac}")

class TestIntegration(unittest.TestCase):
    """Tests de integración para el flujo completo"""
    
    def test_complete_wol_validation_flow(self):
        """Test del flujo completo de validación WoL"""
        # Datos válidos
        valid_data = {
            'mac_address': '00:1B:63:84:45:E6',
            'ip_address': '192.168.1.100',
            'device_name': 'TestDevice'
        }
        
        # Validar MAC
        self.assertTrue(is_valid_mac(valid_data['mac_address']), "MAC should be valid")
        
        # Validar IP
        self.assertTrue(is_valid_ip(valid_data['ip_address']), "IP should be valid")
        
        # Validar longitud del nombre
        self.assertLessEqual(len(valid_data['device_name']), 50, "Device name should not be too long")
        
        # Construir magic packet
        packet = build_magic_packet(valid_data['mac_address'])
        self.assertIsNotNone(packet, "Should build magic packet")
        self.assertEqual(len(packet), 102, "Magic packet should have correct size")
    
    def test_invalid_request_data(self):
        """Test con datos de request inválidos"""
        invalid_cases = [
            {'mac_address': 'invalid', 'ip_address': '192.168.1.100', 'device_name': 'Test'},
            {'mac_address': '00:1B:63:84:45:E6', 'ip_address': 'invalid', 'device_name': 'Test'},
            {'mac_address': '00:1B:63:84:45:E6', 'ip_address': '192.168.1.100', 'device_name': 'A' * 100},
        ]
        
        for case in invalid_cases:
            with self.subTest(case=case):
                mac_valid = is_valid_mac(case['mac_address'])
                ip_valid = is_valid_ip(case['ip_address'])
                name_valid = len(case['device_name']) <= 50
                
                # Al menos una validación debería fallar
                self.assertFalse(mac_valid and ip_valid and name_valid, 
                               f"Should reject invalid data: {case}")

if __name__ == '__main__':
    # Configurar verbose output
    unittest.main(verbosity=2, buffer=True)