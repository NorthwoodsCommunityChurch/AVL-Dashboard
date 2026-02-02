# Computer Dashboard

macOS system monitoring dashboard with a menu bar agent -- Bonjour auto-discovery, live CPU/temperature/network metrics, and Tailscale/VPN support.

<!-- TODO: Add screenshots
![Dashboard Grid](docs/images/dashboard-grid.png)
![Agent Menu](docs/images/agent-menu.png)
-->

## Features

**Dashboard App**
- Grid view of all monitored Macs with live-updating metric rings (CPU, temperature, network)
- Bonjour auto-discovery -- agents appear automatically on the local network
- Manual endpoint support for Tailscale/VPN connections
- Apple Watch-style metric rings with configurable temperature thresholds
- Card flip animation to reveal per-machine settings
- One-click VNC screen sharing from any machine card
- Sort by name, temperature, or uptime
- Light and dark mode support

**Agent App (Menu Bar)**
- Lightweight menu bar app -- no dock icon, minimal resource usage (~0.1% CPU, ~55 MB)
- HTTP server exposing read-only system metrics on demand
- Bonjour service registration for auto-discovery
- Reports: CPU usage, CPU temperature, network throughput, uptime, IP/MAC address, FileVault status, OS version, chip type

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel Mac

## Installation

1. Download `Dashboard.zip` and `DashboardAgent.zip` from [Releases](../../releases)
2. Extract both and move the `.app` files to `/Applications`
3. On first launch of each app, right-click > **Open** (required for ad-hoc signed apps)

Install the **Agent** on every Mac you want to monitor. Install the **Dashboard** on the Mac you want to view metrics from.

## Usage

### Agent Setup

1. Launch **DashboardAgent** on each Mac to monitor
2. The agent appears in the menu bar with a gauge icon
3. It begins advertising on the local network automatically

### Dashboard

1. Launch **Dashboard** on your monitoring station
2. Machines running the agent are discovered and appear in the grid automatically
3. Click any card to flip it and adjust the display name or temperature thresholds
4. Click the machine name pill to open a VNC screen sharing session
5. Use the toolbar sort control to order by name, temperature, or uptime

### Manual Endpoints (Tailscale/VPN)

For machines not on the local network:
1. Click **+** in the toolbar
2. Enter the IP address or hostname and port (default: 49990)
3. The machine appears in the grid once the agent responds

## Configuration

### Agent

The agent runs automatically with no configuration. It binds to port **49990** by default (incrementing if occupied, with dynamic fallback).

### Dashboard

Per-machine settings are accessible by clicking a card to flip it:
- **Display name** -- custom label (defaults to hostname)
- **Temperature thresholds** -- Good, Warning, Critical in Celsius (defaults: 50, 70, 90)

Settings persist in `~/Library/Application Support/ComputerDashboard/`.

## Network Architecture

```
┌─────────────────────────────────────────────────┐
│                 Local Network                    │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │  Agent   │  │  Agent   │  │  Agent   │      │
│  │ (Mac A)  │  │ (Mac B)  │  │ (Mac C)  │      │
│  │  :49990  │  │  :49990  │  │  :49990  │      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘      │
│       │  Bonjour     │             │             │
│       │  mDNS        │             │             │
│  ┌────▼──────────────▼─────────────▼─────┐      │
│  │           Dashboard App               │      │
│  │     (discovers + polls agents)        │      │
│  └──────────────────┬────────────────────┘      │
│                     │                            │
└─────────────────────┼────────────────────────────┘
                      │ Manual endpoints
              ┌───────▼───────┐
              │  Tailscale /  │
              │  VPN agents   │
              └───────────────┘
```

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Discovery | Bonjour (NWBrowser) | Agents advertise `_computerdash._tcp` |
| Manual | Direct IP:port | Reach agents across VPN/Tailscale |
| Transport | HTTP (Network.framework) | Dashboard polls each agent every 5 seconds |
| Data | JSON | Metric payloads |

## API Reference

### GET /status

Returns current system metrics as JSON:

```json
{
  "hardwareUUID": "8A2E3F1B-...",
  "hostname": "Aarons-MacBook-Pro",
  "cpuTempCelsius": 42.5,
  "cpuUsagePercent": 12.3,
  "networkBytesPerSec": 54200.0,
  "uptimeSeconds": 86400,
  "osVersion": "15.3",
  "chipType": "Apple M2",
  "network": {
    "ipAddress": "192.168.1.5",
    "macAddress": "AA:BB:CC:DD:EE:FF",
    "interfaceType": "Wi-Fi"
  },
  "fileVaultEnabled": true
}
```

## Building from Source

```bash
git clone https://github.com/NorthwoodsCommunityChurch/AVL-Dashboard.git
cd AVL-Dashboard
./Scripts/build.sh
```

The build script compiles both apps with Swift Package Manager, creates `.app` bundles in `./build/`, and applies ad-hoc code signing.

**Prerequisites:** Xcode or Swift toolchain (no external dependencies).

## Project Structure

```
AVL-Dashboard/
├── Package.swift                    # SPM manifest (targets: Shared, Dashboard, Agent)
├── Sources/
│   ├── Shared/                      # Shared library
│   │   ├── Models/                  # MachineStatus, MachineIdentity, Thresholds, SortOrder
│   │   ├── Networking/              # BonjourConstants, HTTPUtils
│   │   └── Extensions/             # TimeInterval + bytes/sec formatting
│   ├── Dashboard/                   # Dashboard app
│   │   ├── DashboardApp.swift       # Entry point
│   │   ├── Views/                   # Grid, cards, rings, flip animation
│   │   ├── ViewModels/             # DashboardViewModel, MachineViewModel
│   │   └── Services/               # Discovery, polling, persistence
│   └── Agent/                       # Menu bar agent
│       ├── AgentApp.swift           # Entry point
│       ├── Views/                   # Menu bar dropdown
│       └── Services/               # HTTP server, system metrics collection
├── Resources/
│   ├── Dashboard-Info.plist
│   └── Agent-Info.plist
└── Scripts/
    └── build.sh                     # Build + bundle + code sign
```

## Security

The agent runs an unauthenticated HTTP server exposing read-only system metrics. This is designed for trusted local networks. See [SECURITY.md](SECURITY.md) for details.

## License

MIT License -- see [LICENSE](LICENSE) for details.

## Credits

See [CREDITS.md](CREDITS.md) for acknowledgments and third-party references.
