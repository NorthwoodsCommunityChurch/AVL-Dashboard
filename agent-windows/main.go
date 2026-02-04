package main

import (
	_ "embed"
	"fmt"
	"log"
	"os"
	"time"

	"fyne.io/systray"

	"github.com/NorthwoodsCommunityChurch/AVL-Dashboard/agent-windows/mdns"
	"github.com/NorthwoodsCommunityChurch/AVL-Dashboard/agent-windows/metrics"
	"github.com/NorthwoodsCommunityChurch/AVL-Dashboard/agent-windows/server"
	"github.com/NorthwoodsCommunityChurch/AVL-Dashboard/agent-windows/update"
)

// version is injected at build time via -ldflags "-X main.version=..."
var version = "dev"

//go:embed icon.ico
var iconData []byte

func main() {
	systray.Run(onReady, onExit)
}

func onReady() {
	systray.SetIcon(iconData)
	systray.SetTitle("AVL Dashboard Agent")
	systray.SetTooltip("AVL Dashboard Agent")

	hostname, _ := os.Hostname()

	mHostname := systray.AddMenuItem(hostname, "Machine hostname")
	mHostname.Disable()

	mPort := systray.AddMenuItem("Starting...", "Listening port")
	mPort.Disable()

	mConn := systray.AddMenuItem("No Dashboard Connected", "Dashboard connection status")
	mConn.Disable()

	systray.AddSeparator()

	mVersion := systray.AddMenuItem(fmt.Sprintf("Agent v%s", version), "Agent version")
	mVersion.Disable()

	mUpdate := systray.AddMenuItem("Check for Updates", "Check GitHub for new releases")

	systray.AddSeparator()
	mQuit := systray.AddMenuItem("Quit", "Quit the agent")

	// Start subsystems
	collector := metrics.NewCollector(version)
	go collector.Start()

	srv := server.New(collector)
	go srv.ListenAndServe()

	// Wait for server to bind, then update menu and start mDNS
	go func() {
		port := srv.Port() // blocks until ready
		mPort.SetTitle(fmt.Sprintf("Port: %d", port))
		log.Printf("Server ready on port %d", port)

		go mdns.Advertise(hostname, port)
	}()

	updater := update.NewUpdater(version)
	go updater.StartPeriodicChecks()

	// Track dashboard connection status in the menu
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			if srv.DashboardConnected() {
				mConn.SetTitle("Dashboard Connected")
			} else {
				mConn.SetTitle("No Dashboard Connected")
			}
		}
	}()

	// Event loop for menu clicks
	for {
		select {
		case <-mUpdate.ClickedCh:
			go updater.ForceCheck()
		case <-mQuit.ClickedCh:
			systray.Quit()
		}
	}
}

func onExit() {
	log.Println("Agent shutting down")
}
