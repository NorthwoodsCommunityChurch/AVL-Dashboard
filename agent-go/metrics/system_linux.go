//go:build linux

package metrics

import (
	"os"
	"strings"

	"github.com/shirou/gopsutil/v4/host"
)

// readHardwareUUID reads the SMBIOS UUID from DMI data (requires root).
// Falls back to /etc/machine-id if DMI is unavailable.
func readHardwareUUID() string {
	data, err := os.ReadFile("/sys/class/dmi/id/product_uuid")
	if err == nil {
		uuid := strings.TrimSpace(string(data))
		if uuid != "" && uuid != "Not Settable" {
			return uuid
		}
	}

	data, err = os.ReadFile("/etc/machine-id")
	if err == nil {
		return strings.TrimSpace(string(data))
	}

	hostname, _ := os.Hostname()
	return "unknown-" + hostname
}

// readChipType reads the CPU model name from /proc/cpuinfo.
func readChipType() string {
	data, err := os.ReadFile("/proc/cpuinfo")
	if err != nil {
		return "Unknown"
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "model name") {
			parts := strings.SplitN(line, ":", 2)
			if len(parts) == 2 {
				return strings.TrimSpace(parts[1])
			}
		}
	}
	return "Unknown"
}

// readUptime returns system uptime in seconds.
func readUptime() float64 {
	uptime, err := host.Uptime()
	if err != nil {
		return 0
	}
	return float64(uptime)
}

// readOSVersion reads the pretty name from /etc/os-release (e.g., "Rocky Linux 9.3 (Blue Onyx)").
func readOSVersion() string {
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return "Linux"
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "PRETTY_NAME=") {
			val := strings.TrimPrefix(line, "PRETTY_NAME=")
			return strings.Trim(val, "\"")
		}
	}
	return "Linux"
}

// checkDiskEncryption checks if any LUKS-encrypted volumes are mounted.
func checkDiskEncryption() bool {
	data, err := os.ReadFile("/proc/mounts")
	if err != nil {
		return false
	}
	return strings.Contains(string(data), "/dev/mapper/")
}
