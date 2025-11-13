#!/usr/bin/env python3
"""
Simple web application for VPC demonstration
Serves a simple HTML page showing VPC information
"""

import http.server
import socketserver
import socket
import os
import json
from datetime import datetime
from pathlib import Path

# Get VPC information from environment or defaults
VPC_NAME = os.environ.get('VPC_NAME', 'Unknown')
SUBNET_NAME = os.environ.get('SUBNET_NAME', 'Unknown')
HOST_IP = os.environ.get('HOST_IP', 'Unknown')
NAMESPACE = os.environ.get('NAMESPACE', 'Unknown')
BACKEND_IP = os.environ.get('BACKEND_IP', '10.0.2.2')  # Default private subnet IP
BACKEND_PORT = os.environ.get('BACKEND_PORT', '9000')

# Validate and normalize BACKEND_PORT (ensure it's a valid port number string)
try:
    # Validate it's a number between 1-65535
    port_num = int(BACKEND_PORT)
    if port_num < 1 or port_num > 65535:
        BACKEND_PORT = '9000'  # Use default if invalid
    else:
        BACKEND_PORT = str(port_num)  # Ensure it's a string
except (ValueError, TypeError):
    BACKEND_PORT = '9000'  # Use default if not a number

# Ensure BACKEND_IP is a valid IP or hostname (basic validation)
if not BACKEND_IP or BACKEND_IP.strip() == '':
    BACKEND_IP = '10.0.2.2'  # Default private subnet IP

# Get hostname
try:
    HOSTNAME = socket.gethostname()
except:
    HOSTNAME = 'Unknown'

# HTML template
HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPC Web Application Dashboard</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            min-height: 100vh;
            padding: 20px;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
        }}
        .header {{
            text-align: center;
            color: white;
            margin-bottom: 30px;
        }}
        .header h1 {{
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }}
        .header p {{
            font-size: 1.1em;
            opacity: 0.9;
        }}
        .grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }}
        .card {{
            background: rgba(255, 255, 255, 0.95);
            padding: 25px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            transition: transform 0.3s ease;
        }}
        .card:hover {{
            transform: translateY(-5px);
            box-shadow: 0 6px 12px rgba(0, 0, 0, 0.15);
        }}
        .card h2 {{
            color: #667eea;
            margin-bottom: 15px;
            font-size: 1.3em;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }}
        .card h3 {{
            color: #764ba2;
            margin: 15px 0 10px 0;
            font-size: 1.1em;
        }}
        .info-row {{
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid #eee;
        }}
        .info-label {{
            font-weight: 600;
            color: #555;
        }}
        .info-value {{
            color: #333;
            font-family: 'Courier New', monospace;
        }}
        .status-badge {{
            display: inline-block;
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
        }}
        .status-running {{
            background: #4CAF50;
            color: white;
        }}
        .status-error {{
            background: #f44336;
            color: white;
        }}
        .status-loading {{
            background: #FF9800;
            color: white;
        }}
        .table-container {{
            overflow-x: auto;
            margin-top: 15px;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9em;
        }}
        th {{
            background: #667eea;
            color: white;
            padding: 10px;
            text-align: left;
        }}
        td {{
            padding: 10px;
            border-bottom: 1px solid #eee;
        }}
        tr:hover {{
            background: #f5f5f5;
        }}
        .stats-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-top: 15px;
        }}
        .stat-card {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
        }}
        .stat-value {{
            font-size: 2em;
            font-weight: bold;
            margin-bottom: 5px;
        }}
        .stat-label {{
            font-size: 0.9em;
            opacity: 0.9;
        }}
        button {{
            background: #4CAF50;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
            margin-top: 10px;
            transition: background 0.3s ease;
        }}
        button:hover {{
            background: #45a049;
        }}
        button:disabled {{
            background: #999;
            cursor: not-allowed;
        }}
        .error {{
            background: #ffebee;
            color: #c62828;
            padding: 15px;
            border-radius: 5px;
            border-left: 4px solid #f44336;
            margin: 15px 0;
        }}
        .loading {{
            text-align: center;
            padding: 20px;
            color: #666;
        }}
        .footer {{
            text-align: center;
            color: white;
            margin-top: 30px;
            padding: 20px;
            opacity: 0.8;
        }}
        .backend-section {{
            grid-column: 1 / -1;
        }}
        .badge {{
            display: inline-block;
            padding: 3px 8px;
            border-radius: 12px;
            font-size: 0.75em;
            font-weight: 600;
            margin-left: 5px;
        }}
        .badge-public {{
            background: #4CAF50;
            color: white;
        }}
        .badge-private {{
            background: #FF9800;
            color: white;
        }}
        .badge-admin {{
            background: #f44336;
            color: white;
        }}
        .badge-user {{
            background: #2196F3;
            color: white;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 VPC Web Application Dashboard</h1>
            <p>Frontend running in Public Subnet | Backend API in Private Subnet</p>
        </div>
        
        <div class="grid">
            <!-- Frontend VPC Information -->
            <div class="card">
                <h2>🖥️ Frontend VPC Info</h2>
                <div class="info-row">
                    <span class="info-label">VPC Name:</span>
                    <span class="info-value">{vpc_name}</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Subnet:</span>
                    <span class="info-value">{subnet_name} <span class="badge badge-public">PUBLIC</span></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Host IP:</span>
                    <span class="info-value">{host_ip}</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Namespace:</span>
                    <span class="info-value">{namespace}</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Hostname:</span>
                    <span class="info-value">{hostname}</span>
                </div>
                <div style="margin-top: 15px;">
                    <span class="status-badge status-running">✅ Running</span>
                </div>
            </div>
            
            <!-- Backend Connection Info -->
            <div class="card">
                <h2>🔗 Backend API Connection</h2>
                <div class="info-row">
                    <span class="info-label">Backend URL:</span>
                    <span class="info-value">http://{backend_ip}:{backend_port}</span>
                </div>
                <div id="backend-status" class="loading">Loading backend data...</div>
                <button onclick="fetchBackendData()">🔄 Refresh Data</button>
                <div id="backend-error" class="error" style="display: none;"></div>
            </div>
            
            <!-- Backend VPC Information (populated by JavaScript) -->
            <div class="card" id="backend-vpc-card" style="display: none;">
                <h2>🔒 Backend VPC Info</h2>
                <div id="backend-vpc-content"></div>
            </div>
            
            <!-- Statistics (populated by JavaScript) -->
            <div class="card" id="stats-card" style="display: none;">
                <h2>📊 Statistics</h2>
                <div class="stats-grid" id="stats-grid"></div>
            </div>
        </div>
        
        <!-- Backend Data Section -->
        <div class="card backend-section" id="backend-data-section" style="display: none;">
            <h2>📦 Backend API Data</h2>
            
            <!-- Users Table -->
            <div id="users-section" style="display: none;">
                <h3>👥 Users</h3>
                <div class="table-container">
                    <table id="users-table">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Name</th>
                                <th>Email</th>
                                <th>Role</th>
                            </tr>
                        </thead>
                        <tbody id="users-tbody"></tbody>
                    </table>
                </div>
            </div>
            
            <!-- Products Table -->
            <div id="products-section" style="display: none;">
                <h3>🛍️ Products</h3>
                <div class="table-container">
                    <table id="products-table">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Name</th>
                                <th>Price</th>
                                <th>Stock</th>
                            </tr>
                        </thead>
                        <tbody id="products-tbody"></tbody>
                    </table>
                </div>
            </div>
        </div>
        
        <div class="footer">
            <p>Deployed at: {timestamp} | Raw JSON available in browser console (F12)</p>
        </div>
    </div>
    
    <script>
        const BACKEND_URL = 'http://{backend_ip}:{backend_port}';
        
        // Fetch data from backend API
        async function fetchBackendData() {{
            const statusDiv = document.getElementById('backend-status');
            const errorDiv = document.getElementById('backend-error');
            const backendDataSection = document.getElementById('backend-data-section');
            const backendVpcCard = document.getElementById('backend-vpc-card');
            const backendVpcContent = document.getElementById('backend-vpc-content');
            const statsCard = document.getElementById('stats-card');
            const statsGrid = document.getElementById('stats-grid');
            const usersSection = document.getElementById('users-section');
            const productsSection = document.getElementById('products-section');
            const usersTbody = document.getElementById('users-tbody');
            const productsTbody = document.getElementById('products-tbody');
            
            // Reset UI
            statusDiv.innerHTML = '<span class="status-badge status-loading">⏳ Loading...</span>';
            statusDiv.className = 'loading';
            errorDiv.style.display = 'none';
            backendDataSection.style.display = 'none';
            backendVpcCard.style.display = 'none';
            statsCard.style.display = 'none';
            usersSection.style.display = 'none';
            productsSection.style.display = 'none';
            
            try {{
                console.log('Fetching data from:', BACKEND_URL);
                const response = await fetch(BACKEND_URL);
                
                if (!response.ok) {{
                    throw new Error(`HTTP error! status: ${{response.status}}`);
                }}
                
                const data = await response.json();
                
                // Console log the raw JSON object (for debugging)
                console.log('Backend API Response:', data);
                console.log('Raw JSON String:', JSON.stringify(data, null, 2));
                
                // Display backend VPC info
                if (data.vpc_info) {{
                    const vpcInfo = data.vpc_info;
                    backendVpcContent.innerHTML = `
                        <div class="info-row">
                            <span class="info-label">VPC Name:</span>
                            <span class="info-value">${{vpcInfo.vpc_name || 'N/A'}}</span>
                        </div>
                        <div class="info-row">
                            <span class="info-label">Subnet:</span>
                            <span class="info-value">${{vpcInfo.subnet_name || 'N/A'}} <span class="badge badge-private">PRIVATE</span></span>
                        </div>
                        <div class="info-row">
                            <span class="info-label">Host IP:</span>
                            <span class="info-value">${{vpcInfo.host_ip || 'N/A'}}</span>
                        </div>
                        <div class="info-row">
                            <span class="info-label">Namespace:</span>
                            <span class="info-value">${{vpcInfo.namespace || 'N/A'}}</span>
                        </div>
                        <div class="info-row">
                            <span class="info-label">Hostname:</span>
                            <span class="info-value">${{vpcInfo.hostname || 'N/A'}}</span>
                        </div>
                    `;
                    backendVpcCard.style.display = 'block';
                }}
                
                // Display statistics
                if (data.data && data.data.stats) {{
                    const stats = data.data.stats;
                    statsGrid.innerHTML = `
                        <div class="stat-card">
                            <div class="stat-value">${{stats.total_users || 0}}</div>
                            <div class="stat-label">Total Users</div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-value">${{stats.total_products || 0}}</div>
                            <div class="stat-label">Total Products</div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-value">$${{(stats.total_revenue || 0).toFixed(2)}}</div>
                            <div class="stat-label">Total Revenue</div>
                        </div>
                    `;
                    statsCard.style.display = 'block';
                }}
                
                // Display users
                if (data.data && data.data.users && data.data.users.length > 0) {{
                    usersTbody.innerHTML = data.data.users.map(user => `
                        <tr>
                            <td>${{user.id}}</td>
                            <td>${{user.name}}</td>
                            <td>${{user.email}}</td>
                            <td><span class="badge badge-${{user.role === 'admin' ? 'admin' : 'user'}}">${{user.role}}</span></td>
                        </tr>
                    `).join('');
                    usersSection.style.display = 'block';
                }}
                
                // Display products
                if (data.data && data.data.products && data.data.products.length > 0) {{
                    productsTbody.innerHTML = data.data.products.map(product => `
                        <tr>
                            <td>${{product.id}}</td>
                            <td>${{product.name}}</td>
                            <td>$${{product.price.toFixed(2)}}</td>
                            <td>${{product.stock}}</td>
                        </tr>
                    `).join('');
                    productsSection.style.display = 'block';
                }}
                
                // Show backend data section
                backendDataSection.style.display = 'block';
                
                // Update status
                statusDiv.innerHTML = '<span class="status-badge status-running">✅ Connected</span>';
                statusDiv.className = '';
                
            }} catch (error) {{
                console.error('Error fetching backend data:', error);
                errorDiv.textContent = `Error: ${{error.message}}. Make sure the backend API is running in the private subnet.`;
                errorDiv.style.display = 'block';
                statusDiv.innerHTML = '<span class="status-badge status-error">❌ Connection Failed</span>';
                statusDiv.className = '';
            }}
        }}
        
        // Auto-fetch on page load
        window.addEventListener('DOMContentLoaded', function() {{
            fetchBackendData();
        }});
    </script>
</body>
</html>
"""

class VPCWebHandler(http.server.SimpleHTTPRequestHandler):
    """Custom HTTP handler that serves VPC information"""
    
    def do_GET(self):
        """Handle GET requests"""
        if self.path == '/' or self.path == '/index.html':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            
            # Format the HTML template with all variables
            # Ensure all values are strings and properly formatted
            try:
                html = HTML_TEMPLATE.format(
                    vpc_name=str(VPC_NAME),
                    subnet_name=str(SUBNET_NAME),
                    host_ip=str(HOST_IP),
                    namespace=str(NAMESPACE),
                    hostname=str(HOSTNAME),
                    backend_ip=str(BACKEND_IP),
                    backend_port=str(BACKEND_PORT),  # Ensure it's a string
                    timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                )
                self.wfile.write(html.encode())
            except KeyError as e:
                # If template formatting fails, send error message
                error_msg = f"Template formatting error: Missing key {e}. BACKEND_IP={BACKEND_IP}, BACKEND_PORT={BACKEND_PORT}"
                self.send_response(500)
                self.end_headers()
                self.wfile.write(error_msg.encode())
            except Exception as e:
                # Catch any other errors
                error_msg = f"Error generating HTML: {e}. BACKEND_IP={BACKEND_IP}, BACKEND_PORT={BACKEND_PORT}"
                self.send_response(500)
                self.end_headers()
                self.wfile.write(error_msg.encode())
        else:
            self.send_response(404)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b'404 - Not Found')
    
    def log_message(self, format, *args):
        """Suppress default logging"""
        pass

def main():
    """Start the web server"""
    PORT = int(os.environ.get('PORT', 8000))
    
    with socketserver.TCPServer(("", PORT), VPCWebHandler) as httpd:
        print(f"Server starting on port {PORT}")
        print(f"VPC: {VPC_NAME}, Subnet: {SUBNET_NAME}, IP: {HOST_IP}")
        httpd.serve_forever()

if __name__ == "__main__":
    main()