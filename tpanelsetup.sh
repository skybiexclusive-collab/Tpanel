#!/usr/bin/env bash
# ========================================================
# TPanel 1.0 - Automated Installation Script
# Supported OS: Ubuntu 22.04 LTS, 24.04 LTS, 26.04 (Beta)
# ========================================================

set -e

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}       Starting TPanel 1.0 Setup       ${NC}"
echo -e "${BLUE}======================================${NC}"

# Root verification
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[Error] Please execute this script with root privileges (sudo bash tpanelsetup.sh).${NC}"
  exit 1
fi

# Operating system detection
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
  VERSION=$VERSION_ID
else
  echo -e "${RED}[Error] Unable to read OS release details.${NC}"
  exit 1
fi

if [ "$DISTRO" != "ubuntu" ]; then
  echo -e "${RED}[Error] TPanel exclusively supports Ubuntu environments.${NC}"
  exit 1
fi

case "$VERSION" in
  "22.04"|"24.04")
    echo -e "${GREEN}✓ Compatible stable release detected: Ubuntu $VERSION${NC}"
    ;;
  "26.04")
    echo -e "${YELLOW}⚠ Ubuntu 26.04 (Beta) detected. Running in experimental mode...${NC}"
    ;;
  *)
    echo -e "${RED}[Error] Unsupported Ubuntu release ($VERSION).${NC}"
    echo "Supported releases: 22.04 LTS, 24.04 LTS, 26.04 (Beta)"
    exit 1
    ;;
esac

# Terminate legacy or conflicting web server processes
echo -e "${BLUE}--> Cleaning up conflicting services...${NC}"
systemctl stop lshttpd lsws apache2 2>/dev/null || true
systemctl disable lshttpd lsws apache2 2>/dev/null || true
pkill -9 -f litespeed 2>/dev/null || true

# System package installation
echo -e "${BLUE}--> Installing base system packages...${NC}"
apt-get update -y
apt-get install -y curl git ufw python3 python3-pip python3-venv nginx certbot python3-certbot-nginx

# Directory structure
echo -e "${BLUE}--> Setting up TPanel directory layout...${NC}"
mkdir -p /opt/tpanel/core/modules
mkdir -p /opt/tpanel/web
mkdir -p /home/tpanel

# Python virtual environment setup
echo -e "${BLUE}--> Configuring isolated Python virtual environment...${NC}"
python3 -m venv /opt/tpanel/venv
/opt/tpanel/venv/bin/pip install --upgrade pip
/opt/tpanel/venv/bin/pip install fastapi uvicorn psutil jinja2

# Module: System Stats
cat << 'EOF' > /opt/tpanel/core/modules/system.py
import psutil

def get_system_stats():
    ram = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    return {
        "cpu_usage": f"{psutil.cpu_percent(interval=1)}%",
        "ram_total": f"{round(ram.total / (1024**3), 2)} GB",
        "ram_used": f"{round(ram.used / (1024**3), 2)} GB",
        "ram_percent": f"{ram.percent}%",
        "disk_total": f"{round(disk.total / (1024**3), 2)} GB",
        "disk_used": f"{round(disk.used / (1024**3), 2)} GB",
        "disk_percent": f"{disk.percent}%"
    }
EOF

# Module: Nginx Virtual Host Manager (Port 333)
cat << 'EOF' > /opt/tpanel/core/modules/nginx_manager.py
import os
import subprocess

NGINX_TEMPLATE = """server {{
    listen 333;
    server_name {domain} www.{domain};
    root /home/tpanel/{domain}/public_html;
    index index.html index.htm;

    location / {{
        try_files $uri $uri/ =404;
    }}
}}
"""

def create_website(domain: str):
    site_dir = f"/home/tpanel/{domain}/public_html"
    os.makedirs(site_dir, exist_ok=True)
    
    index_file = os.path.join(site_dir, "index.html")
    if not os.path.exists(index_file):
        with open(index_file, "w") as f:
            f.write(f"<h1>Website {domain} is online on TPanel 1.0 (Port 333)!</h1>")

    conf_path = f"/etc/nginx/sites-available/{domain}"
    with open(conf_path, "w") as f:
        f.write(NGINX_TEMPLATE.format(domain=domain))

    enabled_path = f"/etc/nginx/sites-enabled/{domain}"
    if not os.path.exists(enabled_path):
        os.symlink(conf_path, enabled_path)

    test = subprocess.run(["nginx", "-t"], capture_output=True, text=True)
    if test.returncode != 0:
        return {"status": "error", "message": f"Nginx configuration error: {test.stderr}"}

    subprocess.run(["systemctl", "reload", "nginx"])
    return {"status": "success", "message": f"Domain {domain} deployed successfully on port 333."}
EOF

# Backend: FastAPI Main Application
cat << 'EOF' > /opt/tpanel/core/main.py
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from modules.system import get_system_stats
from modules.nginx_manager import create_website

app = FastAPI(title="TPanel 1.0 API")

class DomainRequest(BaseModel):
    domain: str

@app.get("/api/stats")
def stats():
    return get_system_stats()

@app.post("/api/create-site")
def add_site(data: DomainRequest):
    return create_website(data.domain)

app.mount("/", StaticFiles(directory="/opt/tpanel/web", html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=False)
EOF

# Frontend: Control Interface
cat << 'EOF' > /opt/tpanel/web/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TPanel 1.0 Dashboard Panel</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #f8fafc; padding: 20px; margin: 0; }
        .container { max-width: 600px; margin: auto; }
        .card { background: #1e293b; padding: 18px; border-radius: 10px; margin-bottom: 16px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
        h2, h3 { margin-top: 0; }
        input { width: 100%; padding: 12px; margin: 10px 0; border-radius: 6px; border: 1px solid #334155; background: #0f172a; color: #fff; box-sizing: border-box; font-size: 15px; }
        button { width: 100%; padding: 12px; background: #2563eb; border: none; color: white; border-radius: 6px; font-weight: bold; cursor: pointer; font-size: 15px; }
        button:hover { background: #1d4ed8; }
        .stat { display: flex; justify-content: space-between; margin-bottom: 8px; font-size: 14px; }
        #resultMsg { font-weight: bold; color: #38bdf8; word-break: break-all; margin-top: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <h2> Welcome To TPanel 1.0 Control Panel!</h2>
        
        <div class="card">
            <h3>System Status</h3>
            <div class="stat"><span>CPU Usage:</span> <b id="cpu">Loading...</b></div>
            <div class="stat"><span>Memory (RAM) Usage:</span> <b id="ram">Loading...</b></div>
            <div class="stat"><span>Storage All Disk Usage:</span> <b id="disk">Loading...</b></div>
        </div>

        <div class="card">
            <h3>Deploy Virtual Host</h3>
            <input type="text" id="domainInput" placeholder="example.com">
            <button onclick="createSite()">Create Website</button>
            <p id="resultMsg"></p>
        </div>
    </div>

    <script>
        async function fetchStats() {
            try {
                let res = await fetch('/api/stats');
                let data = await res.json();
                document.getElementById('cpu').innerText = data.cpu_usage;
                document.getElementById('ram').innerText = `${data.ram_used} / ${data.ram_total} (${data.ram_percent})`;
                document.getElementById('disk').innerText = `${data.disk_used} / ${data.disk_total} (${data.disk_percent})`;
            } catch(e) {}
        }

        async function createSite() {
            let domain = document.getElementById('domainInput').value.trim();
            let msgEl = document.getElementById('resultMsg');
            if(!domain) return alert('Please enter a valid domain name.');
            msgEl.innerText = "Processing configuration...";
            try {
                let res = await fetch('/api/create-site', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({domain: domain})
                });
                let data = await res.json();
                msgEl.innerText = data.message;
            } catch(err) {
                msgEl.innerText = "An error occurred while creating the website.";
            }
        }

        fetchStats();
        setInterval(fetchStats, 5000);
    </script>
</body>
</html>
EOF

# Reconfigure default Nginx port to 333
echo -e "${BLUE}--> Binding default Nginx listener to port 333...${NC}"
sed -i 's/listen 80 default_server;/listen 333 default_server;/g' /etc/nginx/sites-available/default 2>/dev/null || true
sed -i 's/listen \[::\]:80 default_server;/listen \[::\]:333 default_server;/g' /etc/nginx/sites-available/default 2>/dev/null || true
nginx -t && systemctl restart nginx
systemctl enable nginx

# Configure systemd service
echo -e "${BLUE}--> Registering TPanel systemd daemon...${NC}"
cat << 'EOF' > /etc/systemd/system/tpanel.service
[Unit]
Description=TPanel 1.0 Web Hosting Control Panel
After=network.target nginx.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/tpanel/core
ExecStart=/opt/tpanel/venv/bin/python /opt/tpanel/core/main.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tpanel
systemctl restart tpanel

# Firewall configuration
echo -e "${BLUE}--> Opening ports (333, 8080)...${NC}"
ufw allow 333/tcp 2>/dev/null || true
ufw allow 8080/tcp 2>/dev/null || true
firewall-cmd --permanent --add-port=333/tcp 2>/dev/null || true
firewall-cmd --permanent --add-port=8080/tcp 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true

# Summary
SERVER_IP=$(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP")
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN} TPanel 1.0 Installation Complete!!${NC}"
echo -e "Tpanel 1.0 URL:    ${YELLOW}http://${SERVER_IP}:8080${NC}"
echo -e "Nginx Server PORT:   ${YELLOW}http://${SERVER_IP}:333${NC}"
echo -e "${GREEN}===============================================${NC}"
