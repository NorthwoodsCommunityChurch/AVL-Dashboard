package metrics

import (
	"os/exec"
	"strconv"
	"strings"
)

// GPUStatus describes a single GPU's live metrics.
// Field names mirror the Swift GPUStatus struct.
type GPUStatus struct {
	Name               string  `json:"name"`
	TemperatureCelsius float64 `json:"temperatureCelsius"`
	UsagePercent       float64 `json:"usagePercent"`
}

// readGPUs returns metrics for all NVIDIA GPUs visible to nvidia-smi.
// Returns nil if nvidia-smi is missing or fails (no NVIDIA GPU, no driver, etc.).
func readGPUs() []GPUStatus {
	out, err := exec.Command(
		"nvidia-smi",
		"--query-gpu=name,temperature.gpu,utilization.gpu",
		"--format=csv,noheader,nounits",
	).Output()
	if err != nil {
		return nil
	}

	var gpus []GPUStatus
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		parts := strings.Split(line, ",")
		if len(parts) != 3 {
			continue
		}
		temp, _ := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
		usage, _ := strconv.ParseFloat(strings.TrimSpace(parts[2]), 64)
		gpus = append(gpus, GPUStatus{
			Name:               strings.TrimSpace(parts[0]),
			TemperatureCelsius: temp,
			UsagePercent:       usage,
		})
	}
	return gpus
}
