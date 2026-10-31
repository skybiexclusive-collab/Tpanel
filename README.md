# 🚀 TPanel 1.0 - Next-Gen Lightweight Hosting Control Panel

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OS-Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20|%2024.04%20|%2026.04%20Beta-orange.svg)](https://ubuntu.com/)
[![Python](https://img.shields.io/badge/Python-3.10+-yellow.svg)](https://www.python.org/)
[![Web Server](https://img.shields.io/badge/Nginx-Port_333-green.svg)](https://nginx.org/)

**TPanel 1.0** is an open-source, resource-friendly hosting management platform tailored for modern Ubuntu installations. Featuring an enterprise-grade dark dashboard inspired by aaPanel, it replaces complex, heavy control panels with a lean FastAPI core, automated system-level virtual host generation, and a dedicated Nginx service architecture.

---

## 📋 Core Capabilities

- **aaPanel-Inspired Dashboard:** Real-time polling metrics for CPU load, RAM consumption, and total disk usage.
- **Segregated Port Architecture:**
  - **TPanel Control Hub:** Operates on port `8080`.
  - **Web Applications (Nginx):** Listens on port `333` to eliminate port conflicts with legacy setups.
- **Instant Virtual Host Provisioning:** Automated vhost generation, document root initialization, default landing page deployment, and atomic Nginx reload.
- **Environment Isolation:** Zero OS pollution—all Python dependencies are isolated inside `/opt/tpanel/venv`.
- **Systemd Integration:** Pre-configured auto-healing daemon that restores service automatically across server reboots.

---

## 🖥️ Supported Operating Systems

| Distribution | Support Tier |
| :--- | :--- |
| **Ubuntu 22.04 LTS (Jammy Jellyfish)** | Supported (Stable) |
| **Ubuntu 24.04 LTS (Noble Numbat)** | Supported (Stable) |
| **Ubuntu 26.04 (Resolute Raccoon)** | Experimental (Beta) |

---

## ⚡ Quick Start (One-Line Installer)

Log in to your Ubuntu target machine as `root` via SSH or terminal console, then execute:

```bash
curl -sSL https://github.com/skybiexclusive-collab/Tpanel/main/tpanelsetup.sh | bash
