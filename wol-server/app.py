#!/usr/bin/env python3
"""
WoL Server - API REST para Wake-on-LAN
Servidor Flask que recibe peticiones HTTP y envía paquetes mágicos WoL
"""

import os
import json
import logging
import subprocess
import re
from datetime import datetime
from flask import Flask, request, jsonify
from functools import wraps

# Configuración
app = Flask(__name__)
app.config['JSON_SORT_KEYS'] = False

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/wol-server.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Variables globales para configuración
CONFIG_FILE = '/etc/wol-server/config.json'
DEFAULT_CONFIG = {
    "api_key": "",
    "port": 5000,
    "allowed_networks": ["192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12"],
    "log_level": "INFO"
}

# Cargar configuración
def load_config():
    """Cargar configuración desde archivo JSON"""
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
                logger.info(f"Configuración cargada desde {CONFIG_FILE}")
                return {**DEFAULT_CONFIG, **config}
        else:
            logger.warning(f"Archivo de configuración {CONFIG_FILE} no encontrado, usando valores por defecto")
            return DEFAULT_CONFIG.copy()
    except Exception as e:
        logger.error(f"Error cargando configuración: {e}")
        return DEFAULT_CONFIG.copy()

config = load_config()

# Decorador para autenticación
def require_api_key(f):
    """Decorador que requiere API key si está configurada"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if config.get('api_key') and config['api_key'].strip():
            provided_key = request.headers.get('X-API-Key')
            if not provided_key or provided_key != config['api_key']:
                logger.warning(f"API Key inválida desde {request.remote_addr}")
                return jsonify({'error': 'API Key requerida o inválida'}), 401
        return f(*args, **kwargs)
    return decorated_function

# Validación de MAC address
def is_valid_mac(mac_address):
    """Validar formato de dirección MAC"""
    if not mac_address:
        return False
    
    # Limpiar MAC (quitar separadores)
    clean_mac = re.sub(r'[:\-\s]', '', mac_address.upper())
    
    # Verificar longitud y caracteres hexadecimales
    if len(clean_mac) != 12:
        return False
    
    return all(c in '0123456789ABCDEF' for c in clean_mac)

def format_mac(mac_address):
    """Formatear MAC address al formato estándar AA:BB:CC:DD:EE:FF"""
    clean_mac = re.sub(r'[:\-\s]', '', mac_address.upper())
    return ':'.join([clean_mac[i:i+2] for i in range(0, 12, 2)])

# Función para enviar Magic Packet
def send_magic_packet(mac_address, target_ip=None):
    """
    Enviar Magic Packet usando wakeonlan o implementación Python
    
    Args:
        mac_address (str): Dirección MAC del dispositivo
        target_ip (str): IP opcional para broadcast dirigido
    
    Returns:
        dict: Resultado de la operación
    """
    try:
        formatted_mac = format_mac(mac_address)
        
        # Intentar usar wakeonlan (comando del sistema)
        try:
            # Siempre usar broadcast de la red local, no la IP específica del dispositivo
            # porque el dispositivo está apagado y no puede responder
            cmd = ['wakeonlan', '-i', '192.168.3.255', formatted_mac]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                logger.info(f"Magic Packet enviado via wakeonlan a {formatted_mac} (broadcast: 192.168.3.255)")
                return {
                    'success': True,
                    'method': 'wakeonlan',
                    'mac': formatted_mac,
                    'target_ip': target_ip,
                    'broadcast': '192.168.3.255'
                }
            else:
                logger.warning(f"wakeonlan falló: {result.stderr}")
                
        except (subprocess.SubprocessError, FileNotFoundError) as e:
            logger.info(f"wakeonlan no disponible, usando implementación Python: {e}")
        
        # Fallback: Implementación Python nativa
        success = send_magic_packet_python(formatted_mac, target_ip)
        
        if success:
            logger.info(f"Magic Packet enviado via Python a {formatted_mac} (broadcast: 192.168.3.255)")
            return {
                'success': True,
                'method': 'python',
                'mac': formatted_mac,
                'target_ip': target_ip,
                'broadcast': '192.168.3.255'
            }
        else:
            raise Exception("Falló implementación Python")
            
    except Exception as e:
        logger.error(f"Error enviando Magic Packet a {mac_address}: {e}")
        return {
            'success': False,
            'error': str(e),
            'mac': mac_address
        }

def send_magic_packet_python(mac_address, target_ip=None):
    """Implementación Python nativa del Magic Packet"""
    import socket
    
    try:
        # Convertir MAC a bytes
        mac_bytes = bytes.fromhex(mac_address.replace(':', ''))
        
        # Crear Magic Packet (6 bytes 0xFF + 16 repeticiones MAC)
        magic_packet = b'\xFF' * 6 + mac_bytes * 16
        
        # Crear socket UDP
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        
        # Usar broadcast de la red local en lugar de IP específica del dispositivo
        # porque el dispositivo apagado no puede recibir en su IP específica
        target = '192.168.3.255'
        ports = [9, 7]  # Puertos Wake-on-LAN estándar
        
        # Enviar a múltiples puertos
        success_count = 0
        for port in ports:
            try:
                bytes_sent = sock.sendto(magic_packet, (target, port))
                if bytes_sent == len(magic_packet):
                    success_count += 1
            except Exception as e:
                logger.warning(f"Error enviando a {target}:{port} - {e}")
        
        sock.close()
        return success_count > 0
        
    except Exception as e:
        logger.error(f"Error en implementación Python: {e}")
        return False

# Rutas de la API

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'timestamp': datetime.now().isoformat(),
        'server': 'wol-server',
        'version': '1.0'
    })

@app.route('/wol', methods=['POST'])
@require_api_key
def wake_on_lan():
    """
    Endpoint principal para enviar Wake-on-LAN
    
    Body JSON esperado:
    {
        "mac": "AA:BB:CC:DD:EE:FF",
        "ip": "192.168.1.100",  // opcional
        "name": "Mi-PC"         // opcional
    }
    """
    try:
        # Validar Content-Type
        if not request.is_json:
            return jsonify({'error': 'Content-Type debe ser application/json'}), 400
        
        data = request.get_json()
        
        # Validar payload
        if not data or 'mac' not in data:
            return jsonify({'error': 'Campo "mac" es requerido'}), 400
        
        mac_address = data['mac']
        target_ip = data.get('ip')
        device_name = data.get('name', 'Desconocido')
        
        # Validar MAC address
        if not is_valid_mac(mac_address):
            return jsonify({'error': 'Formato de MAC address inválido'}), 400
        
        # Log del intento
        client_ip = request.remote_addr
        logger.info(f"WoL request desde {client_ip} para {device_name} ({mac_address}) IP: {target_ip}")
        
        # Enviar Magic Packet
        result = send_magic_packet(mac_address, target_ip)
        
        if result['success']:
            response = {
                'status': 'sent',
                'mac': result['mac'],
                'broadcast': result['broadcast'],
                'method': result['method'],
                'timestamp': datetime.now().isoformat()
            }
            
            if target_ip:
                response['target_ip'] = target_ip
            
            logger.info(f"Magic Packet enviado exitosamente a {result['mac']}")
            return jsonify(response), 200
        else:
            logger.error(f"Error enviando Magic Packet: {result.get('error', 'Error desconocido')}")
            return jsonify({
                'error': 'Error enviando Magic Packet',
                'details': result.get('error', 'Error desconocido')
            }), 500
            
    except Exception as e:
        logger.error(f"Error procesando petición WoL: {e}")
        return jsonify({'error': 'Error interno del servidor'}), 500

@app.route('/status', methods=['GET'])
@require_api_key
def server_status():
    """Información del estado del servidor"""
    return jsonify({
        'status': 'running',
        'config_file': CONFIG_FILE,
        'api_key_configured': bool(config.get('api_key')),
        'port': config.get('port', 5000),
        'allowed_networks': config.get('allowed_networks', []),
        'log_level': config.get('log_level', 'INFO'),
        'timestamp': datetime.now().isoformat()
    })

# Manejo de errores

@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint no encontrado'}), 404

@app.errorhandler(405)
def method_not_allowed(error):
    return jsonify({'error': 'Método HTTP no permitido'}), 405

@app.errorhandler(500)
def internal_error(error):
    logger.error(f"Error interno: {error}")
    return jsonify({'error': 'Error interno del servidor'}), 500

# Punto de entrada

if __name__ == '__main__':
    # Información de inicio
    logger.info("="*60)
    logger.info("🌐 WoL Server iniciando...")
    logger.info(f"📁 Archivo de configuración: {CONFIG_FILE}")
    logger.info(f"🔑 API Key configurada: {'Sí' if config.get('api_key') else 'No'}")
    logger.info(f"🚪 Puerto: {config.get('port', 5000)}")
    logger.info("="*60)
    
    # Ejecutar servidor
    app.run(
        host='0.0.0.0',
        port=config.get('port', 5000),
        debug=False
    )