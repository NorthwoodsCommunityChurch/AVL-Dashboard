# Computer Dashboard - Product Requirements Document

## Overview

A native macOS system consisting of two apps:

1. **Dashboard** - A main window app displaying a grid of discovered Macs with real-time status
2. **Agent** - A menu bar app running on each Mac that serves system metrics on demand

Both apps communicate over the local network using Bonjour for auto-discovery and HTTP for data exchange. Manual endpoint support enables monitoring over Tailscale or other VPN tunnels.

---

## Architecture

### System Diagram

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

### Discovery & Communication Protocol

| Layer       | Technology                  | Purpose                              |
|-------------|-----------------------------|--------------------------------------|
| Discovery   | Bonjour (NWBrowser)         | Agents advertise `_computerdash._tcp` service |
| Manual      | Direct IP:port polling      | Reach agents across VPN/Tailscale    |
| Transport   | HTTP (NWListener + NWConnection) | Dashboard polls each agent for metrics |
| Data Format | JSON                        | Metric payloads                      |

### Agent HTTP Endpoint

Each agent runs a lightweight HTTP server, binding to port **49990** by default (incrementing up to 10 times if occupied, falling back to a dynamic port).

**`GET /status`** returns:

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

- `hardwareUUID` — IOPlatformUUID from IOKit, permanent and unique per machine
- `cpuTempCelsius` — Max CPU die temperature from IOKit HID thermal sensors (Apple Silicon); -1 if unavailable
- `cpuUsagePercent` — Delta-based CPU usage from `host_statistics` tick counters (0–100)
- `networkBytesPerSec` — Combined in+out throughput across active `en*` interfaces
- `fileVaultEnabled` — Cached at agent launch via `fdesetup status`

### Polling Behavior

- Dashboard polls each known agent every **5 seconds**
- If an agent fails to respond for **3 consecutive polls**, it is marked offline
- If an agent responds again after being offline, it is marked online immediately

---

## Agent App (Menu Bar)

### Behavior

- Launches as a menu bar-only app (no dock icon, no main window)
- Starts a lightweight HTTP server on port 49990 (with retry/fallback)
- Registers Bonjour service (`_computerdash._tcp`) once the listener is ready
- Metrics are computed on-demand (no background polling loops)
- Cached at launch: hardware UUID, chip type, FileVault status
- Computed per request: CPU temperature, CPU usage, network throughput, uptime, network info

### Resource Footprint

The agent is passive by design:
- No timers or loops collecting metrics — only computes when the dashboard polls
- NWListener sits idle between connections
- Single recurring 5-second timer tracks dashboard connection status
- ~0.1% CPU, ~55 MB RSS in steady state

### Menu Bar

- SF Symbol icon: `gauge.with.dots.needle.bottom.50percent`
- Dropdown shows:
  - Active port number (e.g., "Serving on port 49990")
  - Connection status: "Dashboard Connected" / "No Dashboard Connected"
  - Quit button

### Metrics Collection

| Metric | Source | Notes |
|--------|--------|-------|
| CPU Temperature | IOKit HID private API (`dlopen`/`dlsym`) | Filters by CPU die sensor prefixes (`pACC MTR`, `eACC MTR`, `PMU TP`); falls back to hottest sensor |
| CPU Usage | `host_statistics` with `HOST_CPU_LOAD_INFO` | Delta-based tick counting between polls |
| Network Throughput | `getifaddrs` with `AF_LINK` / `if_data` | Sums `ifi_ibytes + ifi_obytes` across active `en*` interfaces |
| Uptime | `sysctl` with `KERN_BOOTTIME` | Seconds since boot |
| Network Info | `getifaddrs` with `AF_INET` | Prefers `en0` (Wi-Fi); reads MAC via `sysctl` route table |
| FileVault | `fdesetup status` subprocess | Cached once at launch |
| Hardware UUID | IOKit `IOPlatformExpertDevice` | Cached once at launch |
| Chip Type | `sysctlbyname` (`machdep.cpu.brand_string` or `hw.model`) | Cached once at launch |

---

## Dashboard App

### Main Window

- Standard macOS window, resizable
- Title bar: "Computer Dashboard"
- Supports light/dark mode (uses `.thickMaterial` backgrounds)
- Content: Scrollable grid of computer cards

### Grid Layout

- LazyVGrid with adaptive columns (minimum 150pt per column)
- Grid spacing: 8pt
- Cards fill available columns automatically
- "+" toolbar button opens Add Machine sheet for manual endpoints

### Sorting

Toolbar segmented control with options:
- **Name** (default) — Alphabetical by display name
- **Temperature** — Highest temp first
- **Uptime** — Longest uptime first

Sort preference is persisted across app launches.

### Computer Card - Front

Each card displays live metrics in a compact layout:

```
┌───────────────────────┐
│   [💻 Machine Name ▢] │  Capsule button → VNC screen sharing
│                       │
│   ⭕    ⭕    ⭕      │  Three metric rings (Apple Watch style)
│   12%  42°  1KB/s    │  CPU · Temp · Network
│                       │
│  ⏱ 3d 14h 22m        │  Uptime
│  🌐 192.168.1.5 (WiFi)│  IP + interface type
│  🔒 FileVault  AA:BB… │  Encryption + MAC address
└───────────────────────┘
```

#### Metric Rings

Three circular progress rings in an Apple Watch style:

1. **CPU Usage** — 0–100%, colored green → yellow → orange → red
2. **Temperature** — 0–120°C, colored by user-configured thresholds (green → yellow → orange → red)
3. **Network** — 0–100 MB/s, colored mint → teal → cyan → blue

When a machine goes **offline**, all three rings fill solid red with bold X icons and "---" labels.

#### Machine Name Button

- Capsule-shaped pill with accent-colored background
- Shows wifi/globe icon for manual endpoint machines
- Screen sharing icon on the right
- Tapping opens Apple Screen Sharing (`vnc://` URL) using the machine's IP
- Disabled when no IP address is available

#### Metric Tiles

Compact rows showing uptime, network info, FileVault status, and MAC address in light-background rounded rectangles.

### Computer Card - Back (Settings)

Clicking a card flips it with a 3D rotation animation to reveal:

- **Display name** — Editable text field (defaults to hostname)
- **Temperature thresholds** — Good, Warning, Critical in Celsius (defaults: 50, 70, 90)
- **OS version and chip type** — Read-only labels
- **Done button** — Flips back, saves settings
- **Delete button** — Removes machine with confirmation alert

All settings are persisted per-machine, keyed by Hardware UUID.

### Manual Endpoint Support (Tailscale/VPN)

For machines not on the local network:

1. Click "+" in the toolbar
2. Enter hostname/IP and port (defaults to 49990)
3. Dashboard begins polling the endpoint directly
4. Machine appears in the grid once the first successful response arrives
5. If the same machine is also discovered via Bonjour, the Bonjour connection takes priority
6. Manual endpoints persist across app launches

### Auto-Discovery

- Dashboard uses NWBrowser to discover `_computerdash._tcp` services
- When a new agent is found, a card is added to the grid automatically
- Machines persist in local storage even after disconnecting
- Machines are only removed via the Delete button

### Data Persistence

Stored as a JSON file in Application Support:

```json
{
  "sortOrder": "name",
  "machines": [
    {
      "hardwareUUID": "8A2E3F1B-...",
      "lastKnownHostname": "Aarons-MacBook-Pro",
      "displayName": "Edit Suite 1",
      "thresholds": { "good": 50, "warning": 70, "critical": 90 },
      "lastSeen": "2025-01-15T10:30:00Z",
      "manualEndpoint": "100.64.0.5:49990"
    }
  ]
}
```

- `hardwareUUID` — Stable machine identifier (never changes)
- `lastKnownHostname` — Updated each poll (fallback if display name is cleared)
- `displayName` — User-editable; defaults to hostname on first discovery
- `manualEndpoint` — Optional; present only for manually added machines

---

## Technology Stack

| Component          | Technology                                |
|--------------------|-------------------------------------------|
| Language           | Swift 5.9+                                |
| UI Framework       | SwiftUI (Observation framework)           |
| Networking         | Network.framework (NWListener, NWConnection, NWBrowser) |
| Discovery          | Bonjour / NWBrowser + NWListener          |
| CPU Temperature    | IOKit HID private API (dlopen/dlsym)      |
| CPU Usage          | Mach host_statistics API                  |
| Network Throughput | getifaddrs with AF_LINK interface data    |
| Persistence        | JSON file in Application Support          |
| Build System       | Swift Package Manager                     |
| Minimum Target     | macOS 14 Sonoma                           |

---

## Project Structure

```
Computer Dashboard/
├── Package.swift                              # SPM manifest (3 targets: Shared, Dashboard, Agent)
├── PRD.md
├── .gitignore
│
├── Sources/
│   ├── Shared/                                # Shared library
│   │   ├── Models/
│   │   │   ├── MachineStatus.swift            # JSON status payload + NetworkInfo
│   │   │   ├── MachineIdentity.swift          # Persistent machine record
│   │   │   ├── MachineThresholds.swift        # Temperature threshold settings
│   │   │   └── SortOrder.swift                # Grid sort options
│   │   ├── Networking/
│   │   │   ├── BonjourConstants.swift          # Service type, default port, paths
│   │   │   └── HTTPUtils.swift                # HTTP response builders
│   │   └── Extensions/
│   │       └── TimeIntervalFormat.swift        # Uptime + bytes/sec formatting
│   │
│   ├── Dashboard/                              # Dashboard macOS app
│   │   ├── DashboardApp.swift                  # App entry point
│   │   ├── Views/
│   │   │   ├── DashboardGridView.swift         # Main grid + toolbar
│   │   │   ├── ComputerCardView.swift          # Card front (rings + metrics)
│   │   │   ├── ComputerCardBackView.swift      # Card back (settings)
│   │   │   ├── FlipCardView.swift              # 3D flip animation container
│   │   │   ├── TemperatureRingView.swift       # MetricRingView + TemperatureRingView
│   │   │   ├── OnlineIndicatorView.swift       # Reusable online/offline dot
│   │   │   └── AddMachineSheet.swift           # Manual endpoint entry form
│   │   ├── ViewModels/
│   │   │   ├── DashboardViewModel.swift        # Grid state, polling, manual endpoints
│   │   │   └── MachineViewModel.swift          # Per-machine observable state
│   │   └── Services/
│   │       ├── DiscoveryService.swift          # Bonjour NWBrowser wrapper
│   │       ├── PollingService.swift            # HTTP polling loop
│   │       └── PersistenceService.swift        # JSON load/save
│   │
│   └── Agent/                                  # Menu bar agent app
│       ├── AgentApp.swift                      # App entry point (menu bar)
│       ├── Views/
│       │   └── AgentMenuView.swift             # Dropdown menu content
│       └── Services/
│           ├── MetricsServer.swift             # HTTP server + Bonjour registration
│           └── SystemMetrics.swift             # All metric collectors
│
├── Resources/
│   ├── Agent-Info.plist
│   └── Dashboard-Info.plist
│
└── Scripts/
    └── build.sh                                # Builds both apps to ./build/
```

---

## Security Considerations

- **No authentication on local HTTP**: Acceptable for trusted local networks. The agent only exposes read-only system metrics. No sensitive data is transmitted.
- **No remote access by default**: Bonjour discovery is local-network only. Manual endpoints require explicit user action.
- **No secrets in source**: No API keys, passwords, or credentials required.
- **No PII in persistence**: Only machine hostnames, IPs, and threshold settings are stored.
- **Code signing**: Ad-hoc signing for local distribution (`codesign --force --deep --sign -`).
- **Non-sandboxed**: Required for IOKit sensor access, network server, and `fdesetup` subprocess.
- **VNC URLs**: Constructed from machine-reported IP addresses. Only opens the system Screen Sharing client.
- **Private API usage**: IOKit HID temperature API accessed via `dlopen`/`dlsym`. Not App Store compatible; may break across macOS versions.

---

## Non-Goals (Out of Scope)

- Authentication / encryption (local trusted network assumption)
- Historical data / graphing
- Notifications / alerts
- Agent auto-update mechanism
- Windows or Linux support
- App Store distribution (due to private IOKit API usage)

---

## Resolved Decisions

1. **Agent port selection**: Fixed port 49990 with increment retry (up to 10), then dynamic fallback. Fixed port enables manual endpoint connections.
2. **Multiple dashboards**: Supported naturally since agents are stateless HTTP servers.
3. **Machine identity**: Hardware UUID (IOPlatformUUID) is the stable identifier. Machines are tracked even if their hostname changes.
4. **Display name editing**: Editable on card back. Defaults to hostname on first discovery.
5. **Card sorting**: Sort by name, temperature, or uptime via toolbar segmented control.
6. **Offline visualization**: All three metric rings fill solid red with X icons. No separate online/offline text.
7. **Screen sharing**: Machine name button opens VNC connection using the machine's reported IP.
8. **Tailscale/VPN support**: Manual endpoint entry allows monitoring machines across network boundaries.
9. **FileVault caching**: `fdesetup status` is called once at agent launch rather than per-poll to minimize subprocess overhead.
