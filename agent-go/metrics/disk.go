package metrics

import (
	"time"

	"github.com/shirou/gopsutil/v4/disk"
)

// DiskTracker tracks combined read+write bytes for delta-based throughput calculation.
type DiskTracker struct {
	prevBytes uint64
	prevTime  time.Time
}

// NewDiskTracker creates a new disk throughput tracker.
func NewDiskTracker() *DiskTracker {
	return &DiskTracker{}
}

// BytesPerSec returns combined read+write bytes/sec across all disk devices.
func (t *DiskTracker) BytesPerSec() float64 {
	counters, err := disk.IOCounters()
	if err != nil || len(counters) == 0 {
		return 0
	}

	var totalBytes uint64
	for _, c := range counters {
		totalBytes += c.ReadBytes + c.WriteBytes
	}

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
