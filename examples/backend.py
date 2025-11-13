#!/usr/bin/env python3
"""
Backend API for VPC demonstration
Serves JSON data about system and VPC information
"""

import http.server
import socketserver
import socket
import os
import json
from datetime import datetime
from urllib.parse import urlparse, parse_qs

# Get VPC information from environment or defaults
VPC_NAME = os.environ.get('VPC_NAME', 'Unknown')
SUBNET_NAME = os.environ.get('SUBNET_NAME', 'Unknown')
HOST_IP = os.environ.get('HOST_IP', 'Unknown')
NAMESPACE = os.environ.get('NAMESPACE', 'Unknown')

# Get hostname
try:
    HOSTNAME = socket.gethostname()
except:
    HOSTNAME = 'Unknown'

# Sample data to serve
SAMPLE_DATA = {
    "service": "backend-api",
    "version": "1.0.0",
    "status": "running",
    "vpc_info": {
        "vpc_name": VPC_NAME,
        "subnet_name": SUBNET_NAME,
        "host_ip": HOST_IP,
        "namespace": NAMESPACE,
        "hostname": HOSTNAME,
        "subnet_type": "private"
    },
    "system_info": {
        "timestamp": datetime.now().isoformat(),
        "uptime": "N/A",
        "environment": "VPC Private Subnet"
    },
    "data": {
        "users": [
            {"id": 1, "name": "Alice", "email": "alice@example.com", "role": "admin"},
            {"id": 2, "name": "Bob", "email": "bob@example.com", "role": "user"},
            {"id": 3, "name": "Charlie", "email": "charlie@example.com", "role": "user"}
        ],
        "products": [
            {"id": 1, "name": "Product A", "price": 99.99, "stock": 50},
            {"id": 2, "name": "Product B", "price": 149.99, "stock": 30},
            {"id": 3, "name": "Product C", "price": 199.99, "stock": 20}
        ],
        "stats": {
            "total_users": 3,
            "total_products": 3,
            "total_revenue": 10499.70,
            "last_updated": datetime.now().isoformat()
        }
    }
}

class BackendAPIHandler(http.server.SimpleHTTPRequestHandler):
    """Custom HTTP handler that serves JSON API"""
    
    def do_GET(self):
        """Handle GET requests"""
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        
        # CORS headers for cross-origin requests
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
        
        # Update timestamp
        SAMPLE_DATA["system_info"]["timestamp"] = datetime.now().isoformat()
        SAMPLE_DATA["data"]["stats"]["last_updated"] = datetime.now().isoformat()
        
        # Serve JSON data
        response_data = SAMPLE_DATA.copy()
        
        # Allow query parameters to filter data
        query_params = parse_qs(parsed_path.query)
        if 'endpoint' in query_params:
            endpoint = query_params['endpoint'][0]
            if endpoint == 'users':
                response_data = {"users": SAMPLE_DATA["data"]["users"]}
            elif endpoint == 'products':
                response_data = {"products": SAMPLE_DATA["data"]["products"]}
            elif endpoint == 'stats':
                response_data = {"stats": SAMPLE_DATA["data"]["stats"]}
            elif endpoint == 'vpc_info':
                response_data = {"vpc_info": SAMPLE_DATA["vpc_info"]}
        
        json_response = json.dumps(response_data, indent=2)
        self.wfile.write(json_response.encode())
    
    def do_OPTIONS(self):
        """Handle OPTIONS requests for CORS"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
    
    def log_message(self, format, *args):
        """Log requests"""
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {args[0]} {args[1]} {args[2]}")

def main():
    """Start the API server"""
    PORT = int(os.environ.get('PORT', 9000))
    
    with socketserver.TCPServer(("", PORT), BackendAPIHandler) as httpd:
        print(f"Backend API server starting on port {PORT}")
        print(f"VPC: {VPC_NAME}, Subnet: {SUBNET_NAME}, IP: {HOST_IP}")
        print(f"API endpoint: http://{HOST_IP}:{PORT}/api")
        httpd.serve_forever()

if __name__ == "__main__":
    main()