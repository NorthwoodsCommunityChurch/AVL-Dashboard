package metrics

import (
	"fmt"
	"net"
	"sort"
	"strings"
	"time"

	psnet "github.com/shirou/gopsutil/v4/net"
)

// NetworkTracker tracks combined in+out bytes for delta-based throughput calculation.
type NetworkTracker struct {
	prevBytes uint64
	prevTime  time.Time
}

// NewNetworkTracker creates a new throughput tracker.
func NewNetworkTracker() *NetworkTracker {
	return &NetworkTracker{}
}

// BytesPerSec returns combined in+out bytes/sec across all active interfaces.
func (t *NetworkTracker) BytesPerSec() float64 {
	counters, err := psnet.IOCounters(false) // false = aggregate all interfaces
	if err != nil || len(counters) == 0 {
		return 0
	}

	totalBytes := counters[0].BytesSent + counters[0].BytesRecv
	now := time.Now()

	defer func() {
		t.prevBytes = totalBytes
		t.prevTime = now
	}()

	if t.prevTime.IsZero() || t.prevBytes == 0 {
		return 0
	}

	elapsed := now.Sub(t.prevTime).Seconds()
	if elapsed <= 0 {
		return 0
	}

	delta := totalBytes - t.prevBytes
	if totalBytes < t.prevBytes {
		delta = 0 // counter wrapped
	}
	return float64(delta) / elapsed
}

// readNetworkInterfaces enumerates active non-loopback interfaces with IPv4 addresses.
// Sorted with Ethernet before Wi-Fi, matching the macOS agent behavior.
func readNetworkInterfaces() []NetworkInfo {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}

	var results []NetworkInfo
	for _, iface := range ifaces {
		if iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		if iface.Flags&net.FlagUp == 0 {
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil || len(addrs) == 0 {
			continue
		}

		// Find first IPv4 address
		var ipv4 string
		for _, addr := range addrs {
			if ipNet, ok := addr.(*net.IPNet); ok {
				if ip4 := ipNet.IP.To4(); ip4 != nil {
					ipv4 = ip4.String()
					break
				}
			}
		}
		if ipv4 == "" {
			continue
		}

		mac := formatMAC(iface.HardwareAddr)
		ifType := classifyInterface(iface.Name)

		results = append(results, NetworkInfo{
			InterfaceName: iface.Name,
			IPAddress:     ipv4,
			MACAddress:    mac,
			InterfaceType: ifType,
		})
	}

	// Sort: Ethernet first, then alphabetical by name
	sort.Slice(results, func(i, j int) bool {
		if results[i].InterfaceType != "Wi-Fi" && results[j].InterfaceType == "Wi-Fi" {
			return true
		}
		if results[i].InterfaceType == "Wi-Fi" && results[j].InterfaceType != "Wi-Fi" {
			return false
		}
		return results[i].InterfaceName < results[j].InterfaceName
	})

	return results
}

func formatMAC(hw net.HardwareAddr) string {
	if len(hw) == 0 {
		return "Unknown"
	}
	parts := make([]string, len(hw))
	for i, b := range hw {
		parts[i] = fmt.Sprintf("%02X", b)
	}
	return strings.Join(parts, ":")
}

func classifyInterface(name string) string {
	lower := strings.ToLower(name)
	if strings.Contains(lower, "wi-fi") || strings.Contains(lower, "wifi") ||
		strings.Contains(lower, "wireless") || strings.Contains(lower, "wlan") {
		return "Wi-Fi"
	}
	if strings.Contains(lower, "vpn") || strings.Contains(lower, "tailscale") {
		return "VPN"
	}
	if strings.Contains(lower, "bridge") {
		return "Bridge"
	}
	// Default to Ethernet for physical adapters
	return "Ethernet"
}
