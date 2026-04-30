//go:build windows

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
)

// findAgentAsset returns the Windows agent zip from a release's assets.
func findAgentAsset(assets []GitHubAsset) *GitHubAsset {
	for i := range assets {
		if matchesAgentAsset(assets[i].Name, "windows") {
			return &assets[i]
		}
	}
	return nil
}

// applyUpdate extracts the new exe from the zip, writes a batch trampoline
// that replaces the running binary after exit, then terminates this process.
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

	var newExePath string
	for _, f := range reader.File {
		if strings.HasSuffix(strings.ToLower(f.Name), ".exe") {
			rc, err := f.Open()
			if err != nil {
				return err
			}
			newExePath = filepath.Join(tempDir, filepath.Base(f.Name))
			out, err := os.Create(newExePath)
			if err != nil {
				rc.Close()
				return err
			}
			io.Copy(out, rc)
			out.Close()
			rc.Close()
			break
		}
	}

	if newExePath == "" {
		os.RemoveAll(tempDir)
		return fmt.Errorf("no .exe found in update zip")
	}

	pid := os.Getpid()
	batPath := filepath.Join(tempDir, "update.bat")
	batContent := fmt.Sprintf(`@echo off
:waitloop
tasklist /FI "PID eq %d" 2>NUL | find /I "%d" >NUL
if not errorlevel 1 (
    timeout /t 1 /nobreak >NUL
    goto waitloop
)
copy /Y "%s" "%s"
start "" "%s"
rmdir /S /Q "%s"
`, pid, pid, newExePath, currentExe, currentExe, tempDir)

	if err := os.WriteFile(batPath, []byte(batContent), 0755); err != nil {
		return err
	}

	cmd := exec.Command("cmd.exe", "/C", "start", "/B", batPath)
	if err := cmd.Start(); err != nil {
		return err
	}

	os.Exit(0)
	return nil // unreachable
}
