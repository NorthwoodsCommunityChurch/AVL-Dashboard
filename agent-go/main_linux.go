//go:build linux

package main

import (
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/NorthwoodsCommunityChurch/AVL-Dashboard/agent-go/mdns"
	"github.com/NorthwoodsCommunityChurch/AVL-Dashboard/agent-go/metrics"
	"github.com/NorthwoodsCommunityChurch/AVL-Dashboard/agent-go/server"
	"github.com/NorthwoodsCommunityChurch/AVL-Dashboard/agent-go/update"
)

// version is injected at build time via -ldflags "-X main.version=..."
var version = "dev"

func main() {
	hostname, _ := os.Hostname()
	log.Printf("AVL Dashboard Agent v%s starting on %s", version, hostname)

	collector := metrics.NewCollector(version)
	go collector.Start()

	updater := update.NewUpdater(version)

	srv := server.New(collector, updater)
	go srv.ListenAndServe()

	// Wait for server to bind, then start mDNS
	go func() {
		port := srv.Port() // blocks until ready
		log.Printf("Server ready on port %d", port)
		go mdns.Advertise(hostname, port)
	}()

	go updater.StartPeriodicChecks()

	// Block until SIGINT or SIGTERM (systemd sends SIGTERM on stop)
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	received := <-sig
	log.Printf("Received %s, shutting down", received)
}
