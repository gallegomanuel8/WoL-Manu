#!/usr/bin/env python3
"""
WoL Server v1.4 - Security Hardened Wake-on-LAN HTTP Server
Production-ready server with comprehensive input validation, DoS protection, and security features.

Features:
- RESTful API with JSON responses
- Comprehensive input validation (MAC, IP)
- DoS protection with size limits
- Security hardening against injections
- Health check endpoint
- Request logging and monitoring
- Magic packet broadcasting (UDP port 9)
"""

import os
import json
import logging
import socket
import re
import time
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import threading
import signal
import sys

# Server Configuration
SERVER_VERSION = "1.4"
DEFAULT_PORT = 5000
DEFAULT_HOST = "0.0.0.0"
MAX_REQUEST_SIZE = 1024  # 1KB max request size (DoS protection)
MAX_MAC_LENGTH = 50      # Max MAC address string length
MAX_IP_LENGTH = 15       # Max IPv4 address length  
REQUEST_TIMEOUT = 30     # Request timeout in seconds

# Global statistics
server_stats = {
    "start_time": datetime.now(timezone.utc),
    "requests_handled": 0,
    "magic_packets_sent": 0,
    "validation_errors": 0,
    "security_violations": 0
}

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] WoL Server: %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/tmp/wol-server.log', mode='a')
    ]
)
logger = logging.getLogger(__name__)

def validate_mac(mac_address):
    """
    Validates MAC address format with comprehensive security checks.
    
    Supports formats: AA:BB:CC:DD:EE:FF, AA-BB-CC-DD-EE-FF, AABBCCDDEEFF
    
    Security Features:
    - Input length validation (DoS protection)
    - Injection attempt detection
    - Format validation with hex digit checking
    - Common invalid MAC rejection
    
    Args:
        mac_address (str): MAC address string
        
    Returns:
        bool: True if valid and safe, False otherwise
    """
    global server_stats
    
    # Basic type and presence validation
    if not mac_address or not isinstance(mac_address, str):
        return False
    
    # DoS protection - length limit
    if len(mac_address) > MAX_MAC_LENGTH:
        logger.warning(f"MAC address too long ({len(mac_address)} chars): {mac_address[:20]}...")
        server_stats["security_violations"] += 1
        return False
    
    # Security: Check for injection attempts
    dangerous_patterns = [
        "';", "'\"", "--", "/*", "*/", "${", "<script", "../", "\\x", 
        "drop table", "delete from", "insert into", "update ", "select ",
        "union select", "exec(", "eval(", "system(", "__import__"
    ]
    
    mac_lower = mac_address.lower()
    for pattern in dangerous_patterns:
        if pattern in mac_lower:
            logger.warning(f"Security violation - potential injection in MAC: {pattern}")
            server_stats["security_violations"] += 1
            return False
    
    # Trim whitespace first
    mac_trimmed = mac_address.strip()
    
    # Check for mixed separators (invalid format)
    has_colon = ':' in mac_trimmed
    has_hyphen = '-' in mac_trimmed
    if has_colon and has_hyphen:
        return False  # Mixed separators not allowed
    
    # Clean MAC address (remove separators and whitespace)
    mac_clean = re.sub(r'[:\-\s]', '', mac_trimmed.upper())
    
    # Validate length and hex content
    if len(mac_clean) != 12:
        return False
    
    if not all(c in '0123456789ABCDEF' for c in mac_clean):
        return False
    
    # Reject common invalid MACs
    invalid_macs = {'000000000000', 'FFFFFFFFFFFF'}
    if mac_clean in invalid_macs:
        return False
    
    # Additional validation: not all same digits
    if len(set(mac_clean)) <= 1:  # All same character
        return False
    
    return True

def validate_ip(ip_address):
    """
    Validates IPv4 address format with security checks.
    
    Security Features:
    - IPv4 format validation (4 octets, 0-255 range)  
    - DoS protection with length limits
    - Injection attempt detection
    - Reserved IP address filtering
    
    Args:
        ip_address (str): IP address string
        
    Returns:
        bool: True if valid IPv4, False otherwise
    """
    global server_stats
    
    # Basic type and presence validation
    if not ip_address or not isinstance(ip_address, str):
        return False
    
    # Reject IPs with leading/trailing whitespace or escape characters
    if ip_address != ip_address.strip() or '\t' in ip_address or '\n' in ip_address:
        return False
    
    # DoS protection - length limit
    if len(ip_address) > MAX_IP_LENGTH:
        logger.warning(f"IP address too long ({len(ip_address)} chars)")
        server_stats["security_violations"] += 1
        return False
    
    # Security: Check for injection attempts
    dangerous_patterns = [
        "';", "'\"", "${", "<", ">", "&", "|", "`", "$(", "../", "\\x"
    ]
    
    for pattern in dangerous_patterns:
        if pattern in ip_address:
            logger.warning(f"Security violation - potential injection in IP: {pattern}")
            server_stats["security_violations"] += 1
            return False
    
    # Validate IPv4 format
    try:
        parts = ip_address.split('.')
        if len(parts) != 4:
            return False
        
        for part in parts:
            # Check for leading zeros (security best practice)
            if len(part) > 1 and part[0] == '0':
                return False
            
            # Validate numeric range
            num = int(part)
            if num < 0 or num > 255:
                return False
        
        # Additional security: reject problematic IPs
        if ip_address in ['0.0.0.0', '127.0.0.1', '255.255.255.255']:
            return False
        
        # Reject localhost range
        if ip_address.startswith('127.'):
            return False
            
        return True
        
    except (ValueError, AttributeError):
        return False

def create_magic_packet(mac_address):
    """
    Creates a secure Wake-on-LAN Magic Packet.
    
    Security Features:
    - Input validation before processing
    - Standard packet format (102 bytes)
    - Memory-safe binary construction
    - Error handling with logging
    
    Args:
        mac_address (str): Validated MAC address
        
    Returns:
        bytes: Magic packet (102 bytes) or None if error
    """
    try:
        # Validate MAC before processing
        if not validate_mac(mac_address):
            return None
        
        # Clean and normalize MAC
        mac_clean = re.sub(r'[:\-\s]', '', mac_address.upper())
        
        # Convert to bytes
        mac_bytes = bytes.fromhex(mac_clean)
        
        # Create Magic Packet: 6 bytes of 0xFF + 16 repetitions of MAC
        magic_packet = b'\xFF' * 6 + mac_bytes * 16
        
        # Validate packet size (security check)
        if len(magic_packet) != 102:
            logger.error(f"Invalid magic packet size: {len(magic_packet)} bytes")
            return None
        
        return magic_packet
        
    except Exception as e:
        logger.error(f"Error creating magic packet: {e}")
        return None

def send_magic_packet(mac_address, target_ip=None):
    """
    Sends Wake-on-LAN Magic Packet via UDP broadcast.
    
    Security Features:
    - Input validation before sending
    - Socket timeout configuration  
    - Error handling without information leakage
    - Broadcast-only transmission (security)
    
    Args:
        mac_address (str): Target device MAC address
        target_ip (str): Optional IP (for logging only)
        
    Returns:
        dict: Result with success status and metadata
    """
    global server_stats
    
    try:
        # Create magic packet
        magic_packet = create_magic_packet(mac_address)
        if not magic_packet:
            return {
                'success': False,
                'error': 'Invalid MAC address format',
                'mac': mac_address
            }
        
        # Create UDP socket with security settings
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(5.0)  # 5 second timeout
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        
        # Broadcast settings - configure for your network
        broadcast_ip = os.getenv('WOL_BROADCAST_IP', '192.168.1.255')  # Configure for your network
        wol_port = 9  # Standard Wake-on-LAN port
        
        try:
            # Send magic packet
            bytes_sent = sock.sendto(magic_packet, (broadcast_ip, wol_port))
            
            if bytes_sent == len(magic_packet):
                logger.info(f"Magic packet sent to {mac_address} via {broadcast_ip}:9 ({bytes_sent} bytes)")
                server_stats["magic_packets_sent"] += 1
                
                return {
                    'success': True,
                    'mac': mac_address,
                    'target_ip': target_ip,
                    'broadcast_ip': broadcast_ip,
                    'port': wol_port,
                    'packet_size': bytes_sent,
                    'timestamp': datetime.now(timezone.utc).isoformat()
                }
            else:
                logger.error(f"Incomplete packet send: {bytes_sent}/{len(magic_packet)} bytes")
                return {
                    'success': False,
                    'error': 'Incomplete packet transmission',
                    'mac': mac_address
                }
                
        finally:
            sock.close()
            
    except socket.timeout:
        logger.error(f"Socket timeout sending magic packet to {mac_address}")
        return {
            'success': False,
            'error': 'Network timeout',
            'mac': mac_address
        }
    except Exception as e:
        logger.error(f"Error sending magic packet to {mac_address}: {e}")
        return {
            'success': False,
            'error': 'Network error',  # Don't leak detailed error info
            'mac': mac_address
        }

class WoLHandler(BaseHTTPRequestHandler):
    """HTTP Request Handler for Wake-on-LAN Server with security features."""
    
    server_version = f"WoLServer/{SERVER_VERSION}"
    
    def log_message(self, format, *args):
        """Override default logging to use our logger."""
        logger.info(f"{self.client_address[0]} - {format % args}")
    
    def do_GET(self):
        """Handle GET requests - Health check only."""
        global server_stats
        server_stats["requests_handled"] += 1
        
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/health':
            self.handle_health_check()
        else:
            self.send_error_response(404, "Endpoint not found")
    
    def do_POST(self):
        """Handle POST requests - Wake-on-LAN functionality."""
        global server_stats
        server_stats["requests_handled"] += 1
        
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/wake':
            self.handle_wake_request()
        else:
            self.send_error_response(404, "Endpoint not found")
    
    def handle_health_check(self):
        """Handle health check requests."""
        uptime = datetime.now(timezone.utc) - server_stats["start_time"]
        
        health_data = {
            'status': 'healthy',
            'server': f'WoL Server v{SERVER_VERSION}',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'uptime_seconds': int(uptime.total_seconds()),
            'requests_handled': server_stats["requests_handled"],
            'magic_packets_sent': server_stats["magic_packets_sent"],
            'validation_errors': server_stats["validation_errors"],
            'security_violations': server_stats["security_violations"]
        }
        
        self.send_json_response(200, health_data)
    
    def handle_wake_request(self):
        """Handle Wake-on-LAN requests with comprehensive validation."""
        try:
            # Validate Content-Type
            content_type = self.headers.get('Content-Type', '')
            if not content_type.startswith('application/json'):
                self.send_error_response(400, "Content-Type must be application/json")
                return
            
            # Get content length with DoS protection
            try:
                content_length = int(self.headers.get('Content-Length', 0))
            except (ValueError, TypeError):
                content_length = 0
            
            if content_length > MAX_REQUEST_SIZE:
                logger.warning(f"Request too large: {content_length} bytes from {self.client_address[0]}")
                server_stats["security_violations"] += 1
                self.send_error_response(413, "Request too large")
                return
            
            if content_length <= 0:
                self.send_error_response(400, "Empty request body")
                return
            
            # Read and parse JSON with error handling
            try:
                raw_data = self.rfile.read(content_length)
                request_data = json.loads(raw_data.decode('utf-8'))
            except (json.JSONDecodeError, UnicodeDecodeError) as e:
                logger.warning(f"Invalid JSON from {self.client_address[0]}: {e}")
                server_stats["validation_errors"] += 1
                self.send_error_response(400, "Invalid JSON format")
                return
            
            # Validate required fields
            if not isinstance(request_data, dict):
                self.send_error_response(400, "Request must be a JSON object")
                return
            
            mac_address = request_data.get('mac')
            if not mac_address:
                self.send_error_response(400, "Missing required field: 'mac'")
                return
            
            # Extract optional fields
            target_ip = request_data.get('ip')
            device_name = request_data.get('name', 'Unknown Device')
            
            # Comprehensive input validation
            if not validate_mac(mac_address):
                logger.warning(f"Invalid MAC from {self.client_address[0]}: {mac_address}")
                server_stats["validation_errors"] += 1
                self.send_error_response(400, "Invalid MAC address format")
                return
            
            if target_ip and not validate_ip(target_ip):
                logger.warning(f"Invalid IP from {self.client_address[0]}: {target_ip}")
                server_stats["validation_errors"] += 1
                self.send_error_response(400, "Invalid IP address format")
                return
            
            # Validate device name (basic DoS protection)
            if len(str(device_name)) > 100:
                self.send_error_response(400, "Device name too long (max 100 characters)")
                return
            
            # Log the wake request
            logger.info(f"Wake request from {self.client_address[0]} for {device_name} ({mac_address})")
            
            # Send Magic Packet
            result = send_magic_packet(mac_address, target_ip)
            
            if result['success']:
                response_data = {
                    'status': 'success',
                    'message': 'Magic packet sent successfully',
                    'target': {
                        'ip': target_ip,
                        'mac': result['mac'],
                        'name': device_name
                    },
                    'broadcast_ip': result['broadcast_ip'],
                    'packet_size': result['packet_size'],
                    'timestamp': result['timestamp']
                }
                
                self.send_json_response(200, response_data)
            else:
                logger.error(f"Failed to send magic packet: {result.get('error')}")
                self.send_error_response(500, "Failed to send magic packet")
                
        except Exception as e:
            logger.error(f"Unexpected error handling wake request: {e}")
            self.send_error_response(500, "Internal server error")
    
    def send_json_response(self, status_code, data):
        """Send JSON response with proper headers."""
        response_json = json.dumps(data, indent=2)
        
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(response_json)))
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        
        self.wfile.write(response_json.encode('utf-8'))
    
    def send_error_response(self, status_code, message):
        """Send standardized error response."""
        error_data = {
            'status': 'error',
            'message': message,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        
        self.send_json_response(status_code, error_data)

class SecureHTTPServer(HTTPServer):
    """HTTP Server with security enhancements."""
    
    def __init__(self, server_address, RequestHandlerClass):
        super().__init__(server_address, RequestHandlerClass)
        self.timeout = REQUEST_TIMEOUT

def signal_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    logger.info("Received shutdown signal, stopping server...")
    sys.exit(0)

def main():
    """Main server entry point."""
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Server configuration
    host = os.getenv('WOL_HOST', DEFAULT_HOST)
    port = int(os.getenv('WOL_PORT', DEFAULT_PORT))
    
    # Create and start server
    try:
        server = SecureHTTPServer((host, port), WoLHandler)
        
        logger.info("=" * 60)
        logger.info(f"🌐 WoL Server v{SERVER_VERSION} starting...")
        logger.info(f"📡 Listening on {host}:{port}")
        logger.info(f"🔐 Security features: Input validation, DoS protection, Injection prevention")
        logger.info(f"📊 Health check: http://{host}:{port}/health")
        logger.info(f"🔌 Wake endpoint: http://{host}:{port}/wake")
        logger.info("=" * 60)
        
        # Start serving
        server.serve_forever()
        
    except PermissionError:
        logger.error(f"Permission denied - cannot bind to port {port}")
        logger.error("Try using a port > 1024 or run with sudo")
        sys.exit(1)
    except OSError as e:
        logger.error(f"Cannot start server: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        sys.exit(1)
    finally:
        logger.info("WoL Server shutdown complete")

if __name__ == '__main__':
    main()