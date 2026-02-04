package server

import (
	"fmt"
	"log"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/NorthwoodsCommunityChurch/AVL-Dashboard/agent-windows/metrics"
)

const (
	defaultPort = 49990
	portRetries = 10
)

// Server is a lightweight HTTP server that exposes system metrics.
type Server struct {
	collector *metrics.Collector
	listener  net.Listener
	port      uint16
	portReady chan struct{}

	lastPollTime atomic.Value // stores time.Time
	mu           sync.RWMutex
}

// New creates a Server backed by the given metrics collector.
func New(collector *metrics.Collector) *Server {
	return &Server{
		collector: collector,
		portReady: make(chan struct{}),
	}
}

// Port returns the bound port. Blocks until the server has started listening.
func (s *Server) Port() uint16 {
	<-s.portReady
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.port
}

// DashboardConnected returns true if a /status poll was received within the last 15 seconds.
func (s *Server) DashboardConnected() bool {
	val := s.lastPollTime.Load()
	if val == nil {
		return false
	}
	t := val.(time.Time)
	return time.Since(t) < 15*time.Second
}

// ListenAndServe binds to a TCP port and accepts connections. Blocks forever.
func (s *Server) ListenAndServe() error {
	var listener net.Listener
	var boundPort uint16

	// Try fixed ports first (49990..50000), then fall back to OS-assigned
	for i := uint16(0); i <= portRetries; i++ {
		port := defaultPort + i
		l, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
		if err == nil {
			listener = l
			boundPort = port
			break
		}
	}

	if listener == nil {
		l, err := net.Listen("tcp", ":0")
		if err != nil {
			close(s.portReady)
			return fmt.Errorf("failed to bind any port: %w", err)
		}
		listener = l
		boundPort = uint16(l.Addr().(*net.TCPAddr).Port)
	}

	s.mu.Lock()
	s.listener = listener
	s.port = boundPort
	s.mu.Unlock()
	close(s.portReady)

	log.Printf("Listening on port %d", boundPort)

	for {
		conn, err := listener.Accept()
		if err != nil {
			continue
		}
		go s.handleConnection(conn)
	}
}
