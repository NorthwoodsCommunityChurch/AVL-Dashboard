# Security Policy

## Intended Use

This application is designed for **local network use only** within trusted environments (e.g., church production rooms, edit suites, facility networks). It is **not intended** for deployment on public networks or the internet.

## Network Exposure

### Agent (Menu Bar App)

The agent runs an HTTP server that exposes read-only system metrics.

| Port | Protocol | Description |
|------|----------|-------------|
| 49990 | HTTP (TCP) | System metrics endpoint (`GET /status`) |

**What is exposed:**
- Hostname and hardware UUID
- CPU usage percentage and temperature
- Network throughput (bytes/sec)
- System uptime
- OS version and chip type
- IP address, MAC address, interface type
- FileVault encryption status

**What is NOT exposed:**
- File system contents
- Running processes
- User data or credentials
- Write access of any kind

### Dashboard App

The dashboard does not run a server. It only makes outbound HTTP requests to agents and listens for Bonjour advertisements on the local network.

### Bonjour / mDNS

Both apps use Bonjour service type `_computerdash._tcp` for auto-discovery. This is multicast DNS, limited to the local network segment.

## Authentication

There is no authentication on the agent HTTP endpoint. This is intentional:
- The agent only exposes read-only system metrics
- No sensitive data is transmitted (no passwords, tokens, or user files)
- The attack surface is limited to information disclosure of basic system stats
- Local network trust is assumed

## Recommendations

1. **Network isolation** — Run on a dedicated production/AV network, separate from public Wi-Fi
2. **Firewall rules** — Restrict port 49990 to known dashboard IPs if your network supports it
3. **VPN/Tailscale endpoints** — When using manual endpoints across network boundaries, ensure the VPN itself provides authentication and encryption
4. **Physical security** — Ensure machines running the agent are in secured locations

## Private API Usage

The agent uses IOKit HID private APIs (`dlopen`/`dlsym`) to read CPU temperature sensors. This is:
- Not App Store compatible
- Subject to breakage across macOS versions
- Read-only access to thermal sensor data only

## Data Storage

| Data | Location | Contents |
|------|----------|----------|
| Machine list | `~/Library/Application Support/ComputerDashboard/` | Hostnames, IPs, display names, temperature thresholds |

No credentials or sensitive data are stored.

## Reporting a Vulnerability

If you discover a security issue:

1. **Do not** open a public GitHub issue
2. Report via GitHub's private vulnerability reporting on this repository
3. Include steps to reproduce
4. Allow reasonable time for a fix before public disclosure
