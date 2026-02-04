package mdns

import (
	"log"

	"github.com/grandcat/zeroconf"
)

const (
	serviceType   = "_computerdash._tcp"
	serviceDomain = "local."
)

// Advertise registers the agent as an mDNS service so the macOS dashboard
// can discover it via NWBrowser. Blocks until the process exits.
func Advertise(hostname string, port uint16) {
	server, err := zeroconf.Register(
		hostname,      // instance name (machine hostname)
		serviceType,   // "_computerdash._tcp"
		serviceDomain, // "local."
		int(port),
		nil, // no TXT records (matches macOS agent)
		nil, // all network interfaces
	)
	if err != nil {
		log.Printf("mDNS registration failed: %v", err)
		return
	}
	defer server.Shutdown()

	log.Printf("mDNS: advertising %s on port %d", serviceType, port)

	// Block forever; the mDNS responder runs in background goroutines.
	select {}
}
