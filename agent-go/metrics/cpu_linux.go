//go:build linux

package metrics

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// ReadTemperature reads CPU temperature from /sys/class/hwmon/.
// Looks for k10temp (AMD) or coretemp (Intel) sensors first,
// falls back to thermal_zone. Returns -1 if unavailable.
func (r *CPUReader) ReadTemperature() float64 {
	hwmonDirs, err := filepath.Glob("/sys/class/hwmon/hwmon*")
	if err != nil {
		return -1
	}

	var maxTemp float64 = -1
	for _, dir := range hwmonDirs {
		nameBytes, err := os.ReadFile(filepath.Join(dir, "name"))
		if err != nil {
			continue
		}
		name := strings.TrimSpace(string(nameBytes))

		// Only read CPU-specific sensors
		if name != "coretemp" && name != "k10temp" && name != "zenpower" {
			continue
		}

		inputs, _ := filepath.Glob(filepath.Join(dir, "temp*_input"))
		for _, input := range inputs {
			data, err := os.ReadFile(input)
			if err != nil {
				continue
			}
			milliC, err := strconv.ParseFloat(strings.TrimSpace(string(data)), 64)
			if err != nil {
				continue
			}
			celsius := milliC / 1000.0
			if celsius > 0 && celsius < 150 && celsius > maxTemp {
				maxTemp = celsius
			}
		}
	}

	// Fallback: try thermal_zone if no CPU-specific sensor found
	if maxTemp < 0 {
		zones, _ := filepath.Glob("/sys/class/thermal/thermal_zone*/temp")
		for _, z := range zones {
			data, err := os.ReadFile(z)
			if err != nil {
				continue
			}
			milliC, err := strconv.ParseFloat(strings.TrimSpace(string(data)), 64)
			if err != nil {
				continue
			}
			celsius := milliC / 1000.0
			if celsius > 0 && celsius < 150 && celsius > maxTemp {
				maxTemp = celsius
			}
		}
	}

	return maxTemp
}
