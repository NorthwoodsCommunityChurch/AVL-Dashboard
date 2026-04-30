# AVL Dashboard Project Context

## What This Project Does

A macOS dashboard for monitoring production computers. Shows CPU temperature, CPU usage, network throughput, and uptime for multiple machines on the network.

**Components:**
- **Dashboard.app** - SwiftUI app that displays all machines in a grid
- **DashboardAgent.app** - Menu bar agent that runs on each monitored machine, serves metrics via HTTP
- **DashboardAgent.exe** - Windows agent (Go-based) for Windows machines

---

## Architecture

### Agent Discovery & Polling

The Dashboard finds agents through three mechanisms (in priority order):

1. **Bonjour/mDNS** - Agents advertise `_computerdash._tcp` service. Dashboard uses NWBrowser to discover them.
2. **Manual Endpoints** - User can add machines by IP:port (stored in `manualEndpoint`)
3. **Fallback IP Polling** - Machines with a `lastKnownIP` but no manual endpoint get polled by direct IP

**Why three mechanisms?**
- Bonjour can fail when mDNS multicast doesn't propagate across network segments/VLANs
- Fallback IP polling ensures machines stay connected once discovered, even if Bonjour breaks

### Agent HTTP Endpoints

- `GET /status` - Returns JSON with all metrics (MachineStatus struct)
- `POST /update` - Accepts a zip file to self-update the agent

---

## Key Technical Details

### SMC Temperature Reading (Apple Silicon)

Reading CPU temperature on macOS requires direct SMC (System Management Controller) access:

- **Service name**: `AppleSMCKeysEndpoint` on Apple Silicon, `AppleSMC` on Intel
- **SMC struct size**: 80 bytes total. Swift's `SMCKeyInfoData` needs 3 padding bytes to match C's 4-byte alignment
- **Temperature keys vary by chip**:
  - M4, M1 Max: `Tp05`, `Tp0D`, `Tp0K`, `Tp0S`, `Tp17`, `Tp1E`, `Tp25`
  - M1: Different keys - use dynamic SMC enumeration to discover
  - Intel: `Tc0c`, `TC0P` (big-endian floats)
- **Byte order**: Apple Silicon stores `flt ` type as native little-endian; Intel uses big-endian
- **Fallback**: If static candidate keys don't match, enumerate all SMC keys with `Tp` or `Tc` prefix

### CPU Usage (Apple Silicon Heterogeneous Cores)

Apple Silicon has efficiency (E) and performance (P) cores. The standard `host_statistics(HOST_CPU_LOAD_INFO)` API sums ticks across all cores, which can be misleading:
- When P-cores are sleeping, they don't generate ticks
- E-cores at 100% can make the aggregate look like 100% even though P-cores are available

**Fix**: Use `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` for per-CPU stats. Average the per-core utilization so sleeping cores contribute 0% to the total.

### Persistence

Machine data stored in: `~/Library/Application Support/ComputerDashboard/machines.json`

Key persisted fields:
- `hardwareUUID` - Unique machine identifier
- `displayName` - User-editable name
- `lastKnownHostname` - Bonjour hostname
- `lastKnownIP` - IP from last successful poll (for fallback polling)
- `manualEndpoint` - User-specified IP:port
- `thresholds` - Temperature warning/critical levels

---

## Common Issues

### Machines Show Offline Despite Running Agents

**Symptoms**: Dashboard shows red X, but agent responds to `curl http://IP:49990/status`

**Cause**: mDNS/Bonjour not working on network (multicast blocked, VLANs, etc.)

**Solution**: The `lastKnownIP` fallback polling handles this automatically. If a machine was previously connected, its IP is saved and used for direct polling when Bonjour fails.

**To manually seed IPs** (one-time bootstrap):
```bash
# Scan subnet for agents
for i in $(seq 1 254); do
    curl -s --connect-timeout 0.5 "http://10.10.11.$i:49990/status" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{d[\"hostname\"]} -> 10.10.11.$i')" &
done
wait
```

### Agent Won't Start After Sparkle Update (macOS 26+)

**Symptoms**: Agent silently fails to launch after a Sparkle self-update. Crash log shows `AG::precondition_failure` → `abort()` originating from `SystemMetrics.checkFileVault()`.

**Cause**: `Process.waitUntilExit()` spins the main run loop while waiting for `fdesetup`. On macOS 26+, SwiftUI's AttributeGraph (AG) is stricter about state graph re-entrancy. The pumped run loop allows SwiftUI to dispatch view graph updates while still inside `@StateObject` initialization, which triggers `abort()`.

**Fix** (v1.0.28): Replace `waitUntilExit()` with `terminationHandler` + `DispatchSemaphore`. The semaphore blocks without pumping the run loop, preventing re-entrancy.

### Sparkle Framework Symlinks Destroyed by zip -r

**Symptoms**: After a Sparkle update installs v1.x on another machine, codesigning fails with "bundle format is ambiguous (could be app or framework)" for `Sparkle.framework`. Agent crashes or won't start.

**Cause**: `zip -r` follows symlinks and converts them to real files. Sparkle.framework uses a versioned structure with symlinks (`Sparkle -> Versions/Current/Sparkle`, etc.). Without those symlinks, `codesign` can't determine the bundle type.

**Fix** (v1.0.28): Use `ditto -c -k --keepParent` instead of `zip -r` in build.sh. `ditto` preserves symlinks. The top-level framework entries should be ~24-31 bytes (symlink path strings), not megabytes (real files).

**Manual recovery** (if an agent is already broken on a remote machine): Use `rsync -a --links` (not `scp -r`) to copy a correctly-structured Sparkle.framework, then re-sign inside-out.

### Temperature Shows -1

**Cause**: SMC keys not found for that chip variant

**Solution**: The agent now uses dynamic SMC key discovery as fallback. Push an updated agent to the affected machine:
```bash
# Create zip and push to specific machine
cd build
zip -r agent-update.zip DashboardAgent.app
curl -X POST -H "Content-Type: application/zip" \
    --data-binary @agent-update.zip \
    "http://MACHINE_IP:49990/update"
```

### CPU Shows 100% When Only E-Cores Loaded

**Cause**: Old implementation used aggregate CPU ticks, which doesn't account for sleeping P-cores

**Solution**: Per-CPU usage tracking (in current codebase). Deploy updated agent.

### Windows Agent: Inbound Port 49990 Silently Dropped

**Symptoms**: Agent runs and serves `/status` locally on the Windows machine, but the Dashboard can't reach it. SYN packets reach the NIC (visible in `pktmon`) but never reach the listener. Windows Firewall log shows no drops for port 49990, despite an explicit allow rule.

**Cause**: Windows Firewall auto-creates **two `Block` rules for the program path** (one IPv4, one IPv6, profile=Private) the first time an unrecognized program tries to listen on a port. These app-scoped block rules sit at the WFP `FWPM_LAYER_ALE_AUTH_RECV_ACCEPT_V4` layer and silently win over any port-scoped allow rule. Confirmed via `netsh wfp show netevents` — drops show as `FWPM_NET_EVENT_TYPE_PUBLIC_CLASSIFY_DROP` with the agent's app ID.

**Fix** — remove the auto-block rules (run as admin in PowerShell on the Windows machine):
```powershell
Get-NetFirewallApplicationFilter | Where-Object { $_.Program -match "dashboardagent" } | ForEach-Object {
    $r = $_ | Get-NetFirewallRule
    if ($r.Action -eq "Block") { $r | Remove-NetFirewallRule }
}
```

Then ensure an explicit allow rule is in place (already covered when adding a new Windows agent):
```powershell
New-NetFirewallRule -DisplayName "AVL Dashboard Agent" -Direction Inbound -Protocol TCP -LocalPort 49990 -Action Allow -Profile Any
```

**This affects every new Windows machine.** When deploying a fresh Windows agent: install → first run creates the auto-block → remove the auto-block → done.

---

## Build & Deploy

### Full Build
```bash
./Scripts/build.sh
```
Creates `build/Dashboard.app`, `build/DashboardAgent.app`, `build/DashboardAgent.exe`, and zip archives.

### Quick Agent Update (without full rebuild)
```bash
swift build -c release --product Agent
cp "$(swift build -c release --show-bin-path)/Agent" build/DashboardAgent.app/Contents/MacOS/Agent
codesign --force --deep --sign - build/DashboardAgent.app
```

### Push Update to All Agents
The Dashboard can push updates via the "Update All" button. Or manually:
```bash
cd build
zip -r agent-update.zip DashboardAgent.app
for ip in 10.10.11.112 10.10.11.134 10.10.11.133; do
    curl -X POST -H "Content-Type: application/zip" \
        --data-binary @agent-update.zip \
        "http://$ip:49990/update"
done
```

---

## File Structure

```
Sources/
├── Agent/                    # DashboardAgent.app
│   ├── AgentApp.swift       # Entry point, menu bar setup
│   └── Services/
│       ├── MetricsServer.swift    # HTTP server + Bonjour advertising
│       └── SystemMetrics.swift    # CPU, temp, network collection
├── Dashboard/                # Dashboard.app
│   ├── DashboardApp.swift
│   ├── ViewModels/
│   │   ├── DashboardViewModel.swift  # Discovery, polling, state
│   │   └── MachineViewModel.swift    # Per-machine state
│   ├── Views/
│   └── Services/
│       ├── DiscoveryService.swift    # NWBrowser for Bonjour
│       ├── PollingService.swift      # HTTP polling
│       └── PersistenceService.swift  # machines.json
└── Shared/                   # Shared between Agent and Dashboard
    ├── Models/
    │   ├── MachineStatus.swift       # JSON from /status
    │   └── MachineIdentity.swift     # Persisted machine data
    └── Networking/
        └── BonjourConstants.swift    # Service type, port

agent-windows/                # Go Windows agent
Scripts/build.sh              # Full build script
Resources/                    # Info.plist, icons
```
