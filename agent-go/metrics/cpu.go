package metrics

import (
	"github.com/shirou/gopsutil/v4/cpu"
)

// CPUReader tracks CPU usage and reads temperature.
// ReadTemperature is implemented in platform-specific files.
type CPUReader struct{}

// NewCPUReader creates a CPUReader and primes the usage tracker.
func NewCPUReader() *CPUReader {
	// First call to cpu.Percent primes the counter (returns 0).
	// Subsequent calls return usage since the previous call.
	cpu.Percent(0, false)
	return &CPUReader{}
}

// ReadUsage returns aggregate CPU usage as 0-100, or -1 on error.
func (r *CPUReader) ReadUsage() float64 {
	percents, err := cpu.Percent(0, false)
	if err != nil || len(percents) == 0 {
		return -1
	}
	return percents[0]
}
