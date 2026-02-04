package metrics

import (
	"os"
	"sync"
	"time"
)

// MachineStatus is the JSON payload returned by GET /status.
// Field names and types must match the Swift MachineStatus struct exactly.
type MachineStatus struct {
	HardwareUUID     string        `json:"hardwareUUID"`
	Hostname         string        `json:"hostname"`
	CPUTempCelsius   float64       `json:"cpuTempCelsius"`
	CPUUsagePercent  float64       `json:"cpuUsagePercent"`
	NetworkBytesPS   float64       `json:"networkBytesPerSec"`
	UptimeSeconds    float64       `json:"uptimeSeconds"`
	OSVersion        string        `json:"osVersion"`
	ChipType         string        `json:"chipType"`
	Networks         []NetworkInfo `json:"networks"`
	FileVaultEnabled bool          `json:"fileVaultEnabled"`
	AgentVersion     string        `json:"agentVersion"`
}

// NetworkInfo describes a single network interface.
type NetworkInfo struct {
	InterfaceName string `json:"interfaceName"`
	IPAddress     string `json:"ipAddress"`
	MACAddress    string `json:"macAddress"`
	InterfaceType string `json:"interfaceType"`
}

// Collector gathers system metrics periodically and exposes a thread-safe snapshot.
type Collector struct {
	mu      sync.RWMutex
	current MachineStatus
	version string

	// Cached at init (don't change during runtime)
	hardwareUUID string
	chipType     string
	bitlocker    bool

	netTracker *NetworkTracker
	cpuReader  *CPUReader
}

// NewCollector creates a new metrics collector with the given agent version string.
func NewCollector(version string) *Collector {
	c := &Collector{
		version:      version,
		hardwareUUID: readHardwareUUID(),
		chipType:     readChipType(),
		bitlocker:    checkBitLocker(),
		netTracker:   NewNetworkTracker(),
		cpuReader:    NewCPUReader(),
	}
	c.collect()
	return c
}

// Start runs the collection loop every 5 seconds. Blocks forever.
func (c *Collector) Start() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		c.collect()
	}
}

// CurrentStatus returns the most recent metrics snapshot.
func (c *Collector) CurrentStatus() MachineStatus {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.current
}

func (c *Collector) collect() {
	hostname, _ := os.Hostname()

	status := MachineStatus{
		HardwareUUID:     c.hardwareUUID,
		Hostname:         hostname,
		CPUTempCelsius:   c.cpuReader.ReadTemperature(),
		CPUUsagePercent:  c.cpuReader.ReadUsage(),
		NetworkBytesPS:   c.netTracker.BytesPerSec(),
		UptimeSeconds:    readUptime(),
		OSVersion:        readOSVersion(),
		ChipType:         c.chipType,
		Networks:         readNetworkInterfaces(),
		FileVaultEnabled: c.bitlocker,
		AgentVersion:     c.version,
	}

	c.mu.Lock()
	c.current = status
	c.mu.Unlock()
}
