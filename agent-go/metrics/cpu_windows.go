//go:build windows

package metrics

import (
	"github.com/yusufpapurcu/wmi"
)

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
