package metrics

import (
	"github.com/shirou/gopsutil/v4/mem"
)

// readMemory returns RAM usage percentage and total RAM in gigabytes.
// Returns -1, 0 if unavailable.
func readMemory() (usagePercent float64, totalGB float64) {
	v, err := mem.VirtualMemory()
	if err != nil {
		return -1, 0
	}
	return v.UsedPercent, float64(v.Total) / (1024 * 1024 * 1024)
}
