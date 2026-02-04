package server

import (
	"encoding/json"
	"fmt"
	"net"
	"strings"
	"time"
)

func (s *Server) handleConnection(conn net.Conn) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(10 * time.Second))

	buf := make([]byte, 65536)
	n, err := conn.Read(buf)
	if err != nil {
		return
	}
	request := string(buf[:n])

	// Parse first line: "GET /status HTTP/1.1"
	firstLine := request
	if idx := strings.Index(request, "\r\n"); idx >= 0 {
		firstLine = request[:idx]
	}
	parts := strings.Fields(firstLine)
	if len(parts) < 2 {
		writeResponse(conn, 400, "text/plain", []byte("Bad Request"))
		return
	}

	method := parts[0]
	path := parts[1]

	switch {
	case method == "GET" && path == "/status":
		s.handleStatus(conn)
	case method == "POST" && path == "/update":
		s.handleUpdate(conn)
	default:
		writeResponse(conn, 404, "text/plain", []byte("Not Found"))
	}
}

func (s *Server) handleStatus(conn net.Conn) {
	status := s.collector.CurrentStatus()

	body, err := json.Marshal(status)
	if err != nil {
		writeResponse(conn, 500, "text/plain", []byte("Internal Server Error"))
		return
	}

	writeResponse(conn, 200, "application/json", body)

	// Track poll time for dashboard connection detection
	s.lastPollTime.Store(time.Now())
}

func (s *Server) handleUpdate(conn net.Conn) {
	// Accept the request; autonomous self-update handles actual updates.
	writeResponse(conn, 200, "text/plain", []byte("Update accepted"))
}

func writeResponse(conn net.Conn, status int, contentType string, body []byte) {
	statusText := "OK"
	switch status {
	case 400:
		statusText = "Bad Request"
	case 404:
		statusText = "Not Found"
	case 500:
		statusText = "Internal Server Error"
	}

	header := fmt.Sprintf(
		"HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n",
		status, statusText, contentType, len(body),
	)

	conn.Write([]byte(header))
	conn.Write(body)
}
