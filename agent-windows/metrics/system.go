package metrics

import (
	"os"

	"github.com/shirou/gopsutil/v4/host"
	"github.com/yusufpapurcu/wmi"
)

// WMI query result structs

type win32ComputerSystemProduct struct {
	UUID string
}

type win32Processor struct {
	Name string
}

type win32EncryptableVolume struct {
	ProtectionStatus uint32
}

// readHardwareUUID gets the SMBIOS machine UUID via WMI.
// This is persistent across OS reinstalls, equivalent to macOS IOPlatformUUID.
func readHardwareUUID() string {
	var products []win32ComputerSystemProduct
	err := wmi.Query("SELECT UUID FROM Win32_ComputerSystemProduct", &products)
	if err != nil || len(products) == 0 {
		hostname, _ := os.Hostname()
		return "unknown-" + hostname
	}
	return products[0].UUID
}

// readChipType gets the CPU name via WMI (e.g., "Intel(R) Core(TM) i7-12700K").
func readChipType() string {
	var processors []win32Processor
	err := wmi.Query("SELECT Name FROM Win32_Processor", &processors)
	if err != nil || len(processors) == 0 {
		return "Unknown"
	}
	return processors[0].Name
}

// readUptime returns system uptime in seconds.
func readUptime() float64 {
	uptime, err := host.Uptime()
	if err != nil {
		return 0
	}
	return float64(uptime)
}

// readOSVersion returns the Windows version string (e.g., "10.0.22631").
func readOSVersion() string {
	info, err := host.Info()
	if err != nil {
		return "Unknown"
	}
	return info.PlatformVersion
}

// checkBitLocker queries WMI for BitLocker protection on the C: drive.
// Requires elevated privileges; returns false if unavailable.
func checkBitLocker() bool {
	var volumes []win32EncryptableVolume
	err := wmi.QueryNamespace(
		"SELECT ProtectionStatus FROM Win32_EncryptableVolume WHERE DriveLetter='C:'",
		&volumes,
		`root\CIMv2\Security\MicrosoftVolumeEncryption`,
	)
	if err != nil || len(volumes) == 0 {
		return false
	}
	// ProtectionStatus: 0=Off, 1=On, 2=Unknown
	return volumes[0].ProtectionStatus == 1
}
