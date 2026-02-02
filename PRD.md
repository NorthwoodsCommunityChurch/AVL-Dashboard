# Computer Dashboard - Product Requirements Document

## Overview

A native macOS system consisting of two apps:

1. **Dashboard** - A main window app displaying a grid of discovered Macs with real-time status
2. **Agent** - A menu bar app running on each Mac that broadcasts machine metrics

Both apps communicate over the local network using Bonjour for auto-discovery and HTTP for data exchange.

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
│  │  :PORT   │  │  :PORT   │  │  :PORT   │      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘      │
│       │  Bonjour     │             │             │
│       │  mDNS        │             │             │
│  ┌────▼──────────────▼─────────────▼─────┐      │
│  │           Dashboard App               │      │
│  │     (discovers + polls agents)        │      │
│  └───────────────────────────────────────┘      │
└─────────────────────────────────────────────────┘
```

### Discovery & Communication Protocol

| Layer       | Technology                  | Purpose                              |
|-------------|-----------------------------|--------------------------------------|
| Discovery   | Bonjour (NSNetService)      | Agents advertise `_computerdash._tcp` service |
| Transport   | HTTP (local network only)   | Dashboard polls each agent for metrics |
| Data Format | JSON                        | Metric payloads                      |

### Agent HTTP Endpoint

Each agent runs a lightweight HTTP server on a dynamic port (advertised via Bonjour).

**`GET /status`** returns:

```json
{
  "hardwareUUID": "8A2E3F1B-...",
  "hostname": "Aarons-MacBook-Pro",
  "cpuTempCelsius": 42.5,
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

The `hardwareUUID` is the machine's permanent IOPlatformUUID (read from IOKit's `IOPlatformExpertDevice`). This value never changes, even if the hostname changes on the network. The dashboard uses this as the stable key to match agents to stored machine records.

### Polling Behavior

- Dashboard polls each known agent every **5 seconds**
- If an agent fails to respond for **3 consecutive polls**, it is marked offline
- If an agent responds again after being offline, it is marked online immediately

---

## Agent App (Menu Bar)

### Behavior

- Launches as a menu bar-only app (no dock icon, no main window)
- Starts Bonjour advertisement on launch
- Runs a local HTTP server on a system-assigned port
- Reads CPU temperature from Apple Silicon thermal sensors via IOKit
- Reads system uptime via boot time from `sysctl`
- Reads active network interface info (IP address, MAC address, Wi-Fi/Ethernet) via `getifaddrs` and `SCNetworkInterface`
- Reads FileVault encryption status via `fdesetup status`

### Menu Bar Icon

- Uses a simple SF Symbol icon (e.g., `gauge.with.dots.needle.bottom.50percent`)
- Dropdown menu contains:
  - **Connection status** - "Dashboard Connected" / "No Dashboard Connected" (based on whether the dashboard has polled recently)
  - **Separator**
  - **Quit** - Terminates the agent

### CPU Temperature Reading

Apple Silicon Macs expose thermal sensors through IOKit's `AppleARMIODevice`. The agent reads the CPU die temperature sensors and averages them. Key sensor keys include:

- `SOC MTR Temp Sensor` variants (M1/M2/M3/M4 series)

Fallback: If direct sensor access fails, use `sudo powermetrics` output (requires privilege).

Primary approach: Use IOKit HID system to read thermal sensors without elevated privileges.

---

## Dashboard App

### Main Window

- Standard macOS window, resizable
- Title bar: "Computer Dashboard"
- Background: Dark or system-adaptive (supports light/dark mode)
- Content: Scrollable grid of computer cards

### Grid Layout

- Uses a responsive grid (LazyVGrid) that adapts to window width
- Minimum card width: ~180pt
- Grid spacing: 12pt
- Cards fill available columns automatically

### Sorting

A segmented control or dropdown in the toolbar allows sorting by:

- **Name** (default) - Alphabetical by display name
- **Temperature** - Highest temp first
- **Uptime** - Longest uptime first

Sort preference is persisted across app launches.

### Computer Card - Front

Each card is a rounded rectangle containing (top to bottom):

```
┌─────────────────────┐
│    ┌───────────┐    │
│    │           │    │  Temperature ring
│    │   42°C    │    │  (colored arc around circle)
│    │           │    │
│    └───────────┘    │
│                     │
│     Computer Name   │  Display name (custom or hostname)
│                     │
│   Up: 3d 14h 22m   │  Uptime in human-readable format
│  192.168.1.5 (WiFi) │  IP address and interface type
│  🔒 FileVault On    │  Encryption status
│                     │
│        ● Online     │  Green dot = online, Red dot = offline
└─────────────────────┘
```

#### Temperature Ring

- Circular progress ring around the temperature value
- Color is interpolated based on the configured thresholds:
  - **Below "Good" threshold**: Green
  - **Between "Good" and "Warning"**: Yellow/Orange gradient
  - **Between "Warning" and "Critical"**: Orange/Red gradient
  - **Above "Critical"**: Red, pulsing animation
- Ring shows temperature as a proportion of 0-120 C range

#### Uptime Display

- Format: `Xd Xh Xm` (e.g., "3d 14h 22m")
- Updates every poll cycle

#### Online Indicator

- Filled circle: Green when online, Red when offline
- Label text: "Online" or "Offline"

### Computer Card - Back (Settings)

Clicking a card flips it with a 3D rotation animation to reveal:

```
┌─────────────────────┐
│  Display Name       │
│  ┌────────────────┐ │
│  │ Edit Suite 1   │ │  Editable text field (defaults to hostname)
│  └────────────────┘ │
│                     │
│  Good (°C)          │
│  ┌────────────────┐ │
│  │ 50             │ │  Editable text field
│  └────────────────┘ │
│                     │
│  Warning (°C)       │
│  ┌────────────────┐ │
│  │ 70             │ │  Editable text field
│  └────────────────┘ │
│                     │
│  Critical (°C)      │
│  ┌────────────────┐ │
│  │ 90             │ │  Editable text field
│  └────────────────┘ │
│                     │
│  MAC: AA:BB:CC:DD:EE│  MAC address (read-only)
│                     │
│  [Done]   [Delete]  │  Done flips back, Delete removes
└─────────────────────┘
```

- **Display name**: Editable field, defaults to hostname. Custom names are preserved even if the machine's hostname changes on the network (matching is done by Hardware UUID, not hostname).
- **MAC address**: Read-only label showing the active network interface MAC address.
- **Temperature thresholds**: Editable fields for Good, Warning, Critical in Celsius
- **Default values**: Good = 50, Warning = 70, Critical = 90
- **Done button**: Flips card back to front, saves thresholds and display name
- **Delete button**: Removes the machine from the dashboard (with confirmation alert)
- All settings are persisted per-machine (keyed by Hardware UUID)

### Auto-Discovery

- Dashboard uses Bonjour browser to discover `_computerdash._tcp` services
- When a new agent is found, a card is added to the grid automatically
- Machines persist in local storage even after disconnecting
- Machines are only removed via the Delete button

### Data Persistence

Stored in `UserDefaults` or a local JSON file in Application Support:

```json
{
  "sortOrder": "name",
  "machines": [
    {
      "hardwareUUID": "8A2E3F1B-...",
      "lastKnownHostname": "Aarons-MacBook-Pro",
      "displayName": "Edit Suite 1",
      "thresholds": {
        "good": 50,
        "warning": 70,
        "critical": 90
      },
      "lastSeen": "2025-01-15T10:30:00Z"
    }
  ]
}
```

- `hardwareUUID` is the stable machine identifier (never changes)
- `lastKnownHostname` is updated on each poll (for reference if display name is cleared)
- `displayName` is user-editable; defaults to hostname when first discovered
- When a new agent is discovered, the dashboard checks `hardwareUUID` against stored machines before creating a new card

---

## Technology Stack

| Component          | Technology                              |
|--------------------|-----------------------------------------|
| Language           | Swift 5.9+                              |
| UI Framework       | SwiftUI                                 |
| Networking         | Network.framework (HTTP server on agent), URLSession (dashboard polling) |
| Discovery          | Bonjour / NWBrowser + NWListener        |
| Temperature Sensor | IOKit (Apple Silicon thermal sensors)   |
| Persistence        | JSON file in Application Support        |
| Build System       | Xcode / Swift Package Manager           |
| Minimum Target     | macOS 14 Sonoma                         |

---

## Project Structure

```
ComputerDashboard/
├── README.md
├── PRD.md
├── .gitignore
├── ComputerDashboard.xcworkspace
│
├── Shared/                          # Shared Swift package
│   ├── Package.swift
│   └── Sources/
│       └── Shared/
│           ├── Models/
│           │   ├── MachineStatus.swift      # Status payload model (includes hardwareUUID)
│           │   ├── MachineIdentity.swift    # Persistent machine record (UUID, display name, thresholds)
│           │   └── MachineThresholds.swift   # Threshold settings model
│           ├── Networking/
│           │   ├── BonjourConstants.swift    # Service type, domain constants
│           │   └── StatusEndpoint.swift      # Shared endpoint/path definitions
│           └── Extensions/
│               └── TimeInterval+Format.swift # Uptime formatting
│
├── Dashboard/                       # Dashboard macOS app
│   ├── Dashboard.xcodeproj
│   └── Dashboard/
│       ├── DashboardApp.swift              # App entry point
│       ├── Views/
│       │   ├── DashboardGridView.swift     # Main grid layout
│       │   ├── ComputerCardView.swift      # Card front face
│       │   ├── ComputerCardBackView.swift  # Card back (settings)
│       │   ├── FlipCardView.swift          # Flip animation container
│       │   ├── TemperatureRingView.swift   # Circular temp gauge
│       │   └── OnlineIndicatorView.swift   # Green/red dot
│       ├── ViewModels/
│       │   ├── DashboardViewModel.swift    # Grid state management
│       │   └── MachineViewModel.swift      # Per-machine state
│       ├── Services/
│       │   ├── DiscoveryService.swift      # Bonjour browser
│       │   ├── PollingService.swift        # HTTP polling loop
│       │   └── PersistenceService.swift    # Load/save machines
│       └── Assets.xcassets
│
├── Agent/                           # Menu bar agent app
│   ├── Agent.xcodeproj
│   └── Agent/
│       ├── AgentApp.swift                  # App entry point (menu bar)
│       ├── Views/
│       │   └── AgentMenuView.swift         # Dropdown menu content
│       ├── Services/
│       │   ├── BonjourAdvertiser.swift      # Service advertisement
│       │   ├── MetricsServer.swift         # HTTP server for /status
│       │   └── SystemMetrics.swift         # CPU temp + uptime reading
│       └── Assets.xcassets
│
└── Scripts/
    └── build.sh                     # Build script for both targets
```

---

## Security Considerations

- **No authentication on local HTTP**: Acceptable for trusted local networks. The agent only exposes read-only system metrics (temperature, uptime, hostname). No sensitive data is transmitted.
- **No remote access**: Bonjour discovery is local-network only by design.
- **No secrets in source**: No API keys, passwords, or credentials required.
- **No PII in persistence**: Only machine hostnames and threshold settings are stored.
- **Code signing**: Ad-hoc signing for local distribution (`codesign --force --deep --sign -`).
- **Non-sandboxed**: Required for IOKit sensor access and local network server. Entitlements file documents the reasons.
- **Input validation**: Temperature threshold fields validate numeric input and clamp to reasonable ranges (0-150 C).

---

## Git Hygiene

### .gitignore

Must exclude:
- `*.xcuserdata`
- `DerivedData/`
- `.build/`
- `*.xcworkspace/xcuserdata/`
- `.DS_Store`
- `*.ipa`
- `*.dSYM.zip`
- `*.dSYM`

### No Sensitive Data

- No hardcoded IPs, hostnames, or user-specific paths
- No credentials or tokens
- Machine discovery is purely runtime via Bonjour
- Persistence files are in user-specific Application Support (not in repo)

---

## Non-Goals (Out of Scope)

- Remote (WAN) monitoring
- Authentication / encryption (local trusted network only)
- Historical data / graphing
- Notifications / alerts
- Agent auto-update mechanism
- Windows or Linux support
- App Store distribution

---

## Resolved Decisions

1. **Agent port selection**: Dynamic port, advertised through Bonjour service registration.
2. **Multiple dashboards**: Supported naturally since agents are stateless HTTP servers.
3. **Machine identity**: Hardware UUID (IOPlatformUUID) is the stable identifier. Machines are tracked even if their hostname changes on the network.
4. **Display name editing**: Included in v1. Editable on the card back. Defaults to hostname on first discovery.
5. **Card sorting**: Included in v1. Sort by name, temperature, or uptime via toolbar control.
