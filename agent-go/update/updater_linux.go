//go:build linux

package update

import (
	"archive/zip"
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

// findAgentAsset returns the Linux agent zip from a release's assets.
func findAgentAsset(assets []GitHubAsset) *GitHubAsset {
	for i := range assets {
		if matchesAgentAsset(assets[i].Name, "linux") {
			return &assets[i]
		}
	}
	return nil
}

// applyUpdate extracts the new binary from the zip, writes a shell trampoline
// that replaces the running binary and restarts the systemd service.
func (u *Updater) applyUpdate(zipData []byte) error {
	currentExe, err := os.Executable()
	if err != nil {
		return err
	}
	currentExe, err = filepath.EvalSymlinks(currentExe)
	if err != nil {
		return err
	}

	tempDir, err := os.MkdirTemp("", "avl-agent-update-*")
	if err != nil {
		return err
	}

	reader, err := zip.NewReader(bytes.NewReader(zipData), int64(len(zipData)))
	if err != nil {
		return err
	}

	// Extract the first non-directory file from the zip (the binary)
	var newBinPath string
	for _, f := range reader.File {
		if f.FileInfo().IsDir() || strings.HasPrefix(f.Name, ".") {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		newBinPath = filepath.Join(tempDir, filepath.Base(f.Name))
		out, err := os.Create(newBinPath)
		if err != nil {
			rc.Close()
			return err
		}
		io.Copy(out, rc)
		out.Close()
		rc.Close()
		os.Chmod(newBinPath, 0755)
		break
	}

	if newBinPath == "" {
		os.RemoveAll(tempDir)
		return fmt.Errorf("no binary found in update zip")
	}

	// Write shell trampoline that waits for this process to exit,
	// replaces the binary, restarts the service, and cleans up.
	scriptPath := filepath.Join(tempDir, "update.sh")
	scriptContent := fmt.Sprintf(`#!/bin/bash
sleep 2
cp -f "%s" "%s"
chmod +x "%s"
systemctl restart dashboard-agent 2>/dev/null || true
rm -rf "%s"
`, newBinPath, currentExe, currentExe, tempDir)

	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		return err
	}

	// Launch trampoline detached (new session so it survives our exit)
	cmd := exec.Command("bash", scriptPath)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return err
	}

	os.Exit(0)
	return nil // unreachable
}
