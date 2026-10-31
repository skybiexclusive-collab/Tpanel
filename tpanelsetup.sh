#!/usr/bin/env bash
# ========================================================
# TPanel 1.0 - Automated Installation Script (aaPanel Theme)
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
    echo -e "${YELLOW} WARNING Ubuntu 26.04 (Beta) detected. Running in experimental mode...${NC}"
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
    cpu = psutil.cpu_percent(interval=None)
    return {
        "cpu_usage": f"{cpu}%",
        "cpu_val": cpu,
        "ram_total": f"{round(ram.total / (1024**3), 2)} GB",
        "ram_used": f"{round(ram.used / (1024**3), 2)} GB",
        "ram_percent": f"{ram.percent}%",
        "ram_val": ram.percent,
        "disk_total": f"{round(disk.total / (1024**3), 2)} GB",
        "disk_used": f"{round(disk.used / (1024**3), 2)} GB",
        "disk_percent": f"{disk.percent}%",
        "disk_val": disk.percent
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

def get_domains():
    if not os.path.exists("/home/tpanel"):
        return []
    return [d for d in os.listdir("/home/tpanel") if os.path.isdir(os.path.join("/home/tpanel", d))]

def create_website(domain: str):
    domain = domain.strip().lower()
    site_dir = f"/home/tpanel/{domain}/public_html"
    os.makedirs(site_dir, exist_ok=True)
    
    index_file = os.path.join(site_dir, "index.html")
    if not os.path.exists(index_file):
        with open(index_file, "w") as f:
            f.write(f"<!DOCTYPE html><html><head><title>{domain}</title></head><body style='font-family:sans-serif;text-align:center;padding:50px;'><h1>Website {domain} is online!</h1><p>Managed via TPanel 1.0 (Port 333)</p></body></html>")

    conf_path = f"/etc/nginx/sites-available/{domain}"
    with open(conf_path, "w") as f:
        f.write(NGINX_TEMPLATE.format(domain=domain))

    enabled_path = f"/etc/nginx/sites-enabled/{domain}"
    if not os.path.exists(enabled_path):
        os.symlink(conf_path, enabled_path)

    test = subprocess.run(["nginx", "-t"], capture_output=True, text=True)
    if test.returncode != 0:
        return {"status": "error", "message": f"Nginx syntax error: {test.stderr}"}

    subprocess.run(["systemctl", "reload", "nginx"])
    return {"status": "success", "message": f"Domain {domain} successfully created and bound to Port 333."}
EOF

# Backend: FastAPI Main Application
cat << 'EOF' > /opt/tpanel/core/main.py
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from modules.system import get_system_stats
from modules.nginx_manager import create_website, get_domains

app = FastAPI(title="TPanel 1.0 Enterprise API")

class DomainRequest(BaseModel):
    domain: str

@app.get("/api/stats")
def stats():
    return get_system_stats()

@app.get("/api/sites")
def list_sites():
    return {"sites": get_domains()}

@app.post("/api/create-site")
def add_site(data: DomainRequest):
    return create_website(data.domain)

app.mount("/", StaticFiles(directory="/opt/tpanel/web", html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=False)
EOF

# Frontend: aaPanel Professional Theme
cat << 'EOF' > /opt/tpanel/web/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TPanel 1.0 - Linux Control Center</title>
    <style>
        :root {
            --bg-sidebar: #24282c;
            --bg-sidebar-active: #191c1f;
            --primary: #20a53a;
            --primary-hover: #1c8b32;
            --bg-main: #f0f2f5;
            --card-bg: #ffffff;
            --text-dark: #333333;
            --text-muted: #777777;
            --border-color: #e5e7eb;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
        body { background-color: var(--bg-main); color: var(--text-dark); display: flex; height: 100vh; overflow: hidden; }

        /* Sidebar Navigation */
        .sidebar { width: 220px; background-color: var(--bg-sidebar); color: #c2c5ca; display: flex; flex-direction: column; flex-shrink: 0; }
        .sidebar-brand { height: 60px; display: flex; align-items: center; padding: 0 20px; font-size: 18px; font-weight: 700; color: #fff; border-bottom: 1px solid #2f343a; }
        .sidebar-brand span { color: var(--primary); margin-left: 4px; }
        .sidebar-menu { list-style: none; margin-top: 15px; flex-grow: 1; }
        .sidebar-menu li a { display: flex; align-items: center; padding: 12px 20px; color: #a6abb3; text-decoration: none; font-size: 14px; transition: all 0.2s; border-left: 3px solid transparent; }
        .sidebar-menu li a:hover, .sidebar-menu li a.active { background-color: var(--bg-sidebar-active); color: #fff; border-left-color: var(--primary); }

        /* Main Workspace */
        .wrapper { flex-grow: 1; display: flex; flex-direction: column; overflow-y: auto; }
        .header { height: 60px; background-color: var(--card-bg); border-bottom: 1px solid var(--border-color); display: flex; align-items: center; justify-content: space-between; padding: 0 25px; }
        .header-title { font-size: 16px; font-weight: 600; }
        .badge-tag { background-color: #e8f5e9; color: var(--primary); padding: 4px 10px; border-radius: 4px; font-size: 12px; font-weight: 600; }
        .content { padding: 25px; display: flex; flex-direction: column; gap: 20px; }

        /* Metric Widgets */
        .metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 18px; }
        .metric-card { background: var(--card-bg); border-radius: 6px; padding: 18px; border: 1px solid var(--border-color); display: flex; flex-direction: column; gap: 10px; box-shadow: 0 1px 3px rgba(0,0,0,0.03); }
        .metric-head { display: flex; justify-content: space-between; font-size: 13px; color: var(--text-muted); font-weight: 600; }
        .metric-value { font-size: 22px; font-weight: 700; color: #111; }
        .progress-bar-bg { width: 100%; height: 7px; background: #e9ecef; border-radius: 4px; overflow: hidden; }
        .progress-fill { height: 100%; width: 0%; background: var(--primary); transition: width 0.4s ease; }

        /* Data Panel & Action Area */
        .panel-card { background: var(--card-bg); border-radius: 6px; border: 1px solid var(--border-color); box-shadow: 0 1px 3px rgba(0,0,0,0.03); overflow: hidden; }
        .panel-header { padding: 14px 20px; border-bottom: 1px solid var(--border-color); font-size: 14px; font-weight: 600; display: flex; justify-content: space-between; align-items: center; background-color: #fafbfc; }
        .panel-body { padding: 20px; }

        .input-row { display: flex; gap: 12px; max-width: 600px; margin-bottom: 20px; }
        .input-text { flex-grow: 1; padding: 10px 14px; border: 1px solid var(--border-color); border-radius: 4px; font-size: 14px; outline: none; }
        .input-text:focus { border-color: var(--primary); }
        .btn-green { background-color: var(--primary); color: #fff; border: none; padding: 10px 20px; border-radius: 4px; font-weight: 600; cursor: pointer; transition: background 0.2s; }
        .btn-green:hover { background-color: var(--primary-hover); }

        /* Table */
        .data-table { width: 100%; border-collapse: collapse; font-size: 13px; text-align: left; }
        .data-table th { background: #f8fafc; color: var(--text-muted); padding: 12px 16px; border-bottom: 1px solid var(--border-color); font-weight: 600; }
        .data-table td { padding: 12px 16px; border-bottom: 1px solid var(--border-color); color: var(--text-dark); }
        .status-pill { background: #e8f5e9; color: var(--primary); padding: 3px 8px; border-radius: 3px; font-size: 11px; font-weight: 600; }

        @media (max-width: 768px) {
            body { flex-direction: column; height: auto; }
            .sidebar { width: 100%; height: auto; }
            .sidebar-menu { display: flex; overflow-x: auto; margin-top: 0; }
            .input-row { flex-direction: column; }
        }
    </style>
</head>
<body>
    <div class="sidebar">
        <div class="sidebar-brand">TPanel<span>1.0</span></div>
        <ul class="sidebar-menu">
            <li><a href="#" class="active">📊 Dashboard</a></li>
            <li><a href="#">🌐 Website (Nginx)</a></li>
            <li><a href="#">🗄️ Database</a></li>
            <li><a href="#">📁 Files</a></li>
            <li><a href="#">⚙️ Settings</a></li>
        </ul>
    </div>

    <div class="wrapper">
        <div class="header">
            <span class="header-title">System Overview & Management</span>
            <span class="badge-tag">Service: Port 333 Active</span>
        </div>

        <div class="content">
            <!-- Hardware Metrics -->
            <div class="metric-grid">
                <div class="metric-card">
                    <div class="metric-head"><span>CPU USAGE</span><span id="cpuText">0%</span></div>
                    <div class="metric-value" id="cpuMain">-</div>
                    <div class="progress-bar-bg"><div class="progress-fill" id="cpuBar"></div></div>
                </div>
                <div class="metric-card">
                    <div class="metric-head"><span>MEMORY (RAM)</span><span id="ramText">0%</span></div>
                    <div class="metric-value" id="ramMain">-</div>
                    <div class="progress-bar-bg"><div class="progress-fill" id="ramBar"></div></div>
                </div>
                <div class="metric-card">
                    <div class="metric-head"><span>DISK UTILIZATION</span><span id="diskText">0%</span></div>
                    <div class="metric-value" id="diskMain">-</div>
                    <div class="progress-bar-bg"><div class="progress-fill" id="diskBar"></div></div>
                </div>
            </div>

            <!-- Virtual Host Deployment -->
            <div class="panel-card">
                <div class="panel-header">
                    <span>Deploy New Site (Port 333)</span>
                </div>
                <div class="panel-body">
                    <div class="input-row">
                        <input type="text" id="domainInput" class="input-text" placeholder="example.com">
                        <button class="btn-green" onclick="createSite()">Add Website</button>
                    </div>
                    <p id="resultMsg" style="font-size: 13px; margin-bottom: 15px; font-weight: 600;"></p>

                    <!-- Deployed Sites Table -->
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Site Domain</th>
                                <th>Status</th>
                                <th>Document Root</th>
                                <th>Port</th>
                            </tr>
                        </thead>
                        <tbody id="siteList">
                            <tr><td colspan="4" style="text-align: center; color: #999;">Loading deployed websites...</td></tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>

    <script>
        async function fetchStats() {
            try {
                let res = await fetch('/api/stats');
                let d = await res.json();
                
                document.getElementById('cpuText').innerText = d.cpu_usage;
                document.getElementById('cpuMain').innerText = d.cpu_usage;
                document.getElementById('cpuBar').style.width = d.cpu_usage;

                document.getElementById('ramText').innerText = d.ram_percent;
                document.getElementById('ramMain').innerText = `${d.ram_used} / ${d.ram_total}`;
                document.getElementById('ramBar').style.width = d.ram_percent;

                document.getElementById('diskText').innerText = d.disk_percent;
                document.getElementById('diskMain').innerText = `${d.disk_used} / ${d.disk_total}`;
                document.getElementById('diskBar').style.width = d.disk_percent;
            } catch(e) {}
        }

        async function fetchSites() {
            try {
                let res = await fetch('/api/sites');
                let d = await res.json();
                let table = document.getElementById('siteList');
                if(!d.sites || d.sites.length === 0) {
                    table.innerHTML = `<tr><td colspan="4" style="text-align:center; color:#999;">No virtual hosts registered yet.</td></tr>`;
                    return;
                }
                table.innerHTML = d.sites.map(site => `
                    <tr>
                        <td><strong>${site}</strong></td>
                        <td><span class="status-pill">Running</span></td>
                        <td><code>/home/tpanel/${site}/public_html</code></td>
                        <td>333</td>
                    </tr>
                `).join('');
            } catch(e) {}
        }

        async function createSite() {
            let input = document.getElementById('domainInput');
            let domain = input.value.trim();
            let msg = document.getElementById('resultMsg');
            if(!domain) return alert('Please enter a valid domain name');
            
            msg.style.color = '#555';
            msg.innerText = "Configuring vhost & reloading web server...";
            
            try {
                let res = await fetch('/api/create-site', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({domain: domain})
                });
                let data = await res.json();
                msg.style.color = data.status === 'success' ? '#20a53a' : '#d32f2f';
                msg.innerText = data.message;
                if(data.status === 'success') {
                    input.value = '';
                    fetchSites();
                }
            } catch(err) {
                msg.style.color = '#d32f2f';
                msg.innerText = "Server communication failure.";
            }
        }

        fetchStats();
        fetchSites();
        setInterval(fetchStats, 4000);
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
Description=TPanel 1.0 Enterprise Web Hosting Control Panel
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
echo -e "${GREEN}[INFO] TPanel 1.0 V1 Installation Completed!!${NC}"
echo -e "Panel Dashboard:    ${YELLOW}http://${SERVER_IP}:8080${NC}"
echo -e "Nginx HTTP Service: ${YELLOW}http://${SERVER_IP}:333${NC}"
echo -e "${GREEN}===============================================${NC}"
