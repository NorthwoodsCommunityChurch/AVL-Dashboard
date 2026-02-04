package metrics

import (
	"github.com/shirou/gopsutil/v4/cpu"
	"github.com/yusufpapurcu/wmi"
)

// CPUReader tracks CPU usage and reads temperature via WMI.
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

// thermalZone maps WMI MSAcpi_ThermalZoneTemperature fields.
type thermalZone struct {
	CurrentTemperature uint32
}

// ReadTemperature reads CPU temperature via WMI MSAcpi_ThermalZoneTemperature.
// Returns -1 if unavailable (common without admin privileges or on unsupported hardware).
// WMI returns tenths of Kelvin; converted to Celsius: (val / 10) - 273.15
func (r *CPUReader) ReadTemperature() float64 {
	var zones []thermalZone
	err := wmi.QueryNamespace(
		"SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature",
		&zones,
		`root\WMI`,
	)
	if err != nil || len(zones) == 0 {
		return -1
	}

	var maxTemp float64 = -1
	for _, z := range zones {
		celsius := float64(z.CurrentTemperature)/10.0 - 273.15
		if celsius > 0 && celsius < 150 && celsius > maxTemp {
			maxTemp = celsius
		}
	}
	return maxTemp
}
