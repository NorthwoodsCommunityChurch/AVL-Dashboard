package update

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	owner         = "NorthwoodsCommunityChurch"
	repo          = "AVL-Dashboard"
	checkInterval = 30 * time.Minute
	cacheDuration = 15 * time.Minute
)

// GitHubRelease represents a release from the GitHub API.
type GitHubRelease struct {
	TagName    string        `json:"tag_name"`
	Name       string        `json:"name"`
	Prerelease bool          `json:"prerelease"`
	Assets     []GitHubAsset `json:"assets"`
}

// GitHubAsset represents a downloadable file attached to a release.
type GitHubAsset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
	Size               int    `json:"size"`
}

// Updater checks GitHub for new agent releases and applies them.
type Updater struct {
	currentVersion string
	lastCheck      time.Time
}

// NewUpdater creates an Updater for the given current version.
func NewUpdater(version string) *Updater {
	return &Updater{currentVersion: version}
}

// StartPeriodicChecks runs update checks on a schedule. Blocks forever.
func (u *Updater) StartPeriodicChecks() {
	// Initial check after short delay
	time.Sleep(5 * time.Second)
	u.checkAndUpdate()

	ticker := time.NewTicker(checkInterval)
	defer ticker.Stop()
	for range ticker.C {
		u.checkAndUpdate()
	}
}

// ForceCheck clears the cache and checks immediately.
func (u *Updater) ForceCheck() {
	u.lastCheck = time.Time{}
	u.checkAndUpdate()
}

func (u *Updater) checkAndUpdate() {
	if !u.lastCheck.IsZero() && time.Since(u.lastCheck) < cacheDuration {
		return
	}

	releases, err := u.fetchReleases()
	if err != nil {
		log.Printf("Update check failed: %v", err)
		return
	}
	u.lastCheck = time.Now()

	// Find the newest version across all releases
	var bestRelease *GitHubRelease
	var bestVersion *SemanticVersion
	for i := range releases {
		v := ParseVersion(releases[i].TagName)
		if v == nil {
			continue
		}
		if bestVersion == nil || v.GreaterThan(*bestVersion) {
			bestRelease = &releases[i]
			bestVersion = v
		}
	}

	if bestRelease == nil || bestVersion == nil {
		return
	}

	current := ParseVersion(u.currentVersion)
	if current == nil || !bestVersion.GreaterThan(*current) {
		return
	}

	// Find Windows agent asset
	var targetAsset *GitHubAsset
	for i, asset := range bestRelease.Assets {
		lower := strings.ToLower(asset.Name)
		if strings.Contains(lower, "windows") &&
			strings.Contains(lower, "agent") &&
			strings.HasSuffix(lower, ".zip") {
			targetAsset = &bestRelease.Assets[i]
			break
		}
	}
	if targetAsset == nil {
		return
	}

	log.Printf("Updating from %s to %s...", u.currentVersion, bestVersion)
	zipData, err := u.downloadAsset(targetAsset.BrowserDownloadURL)
	if err != nil {
		log.Printf("Download failed: %v", err)
		return
	}

	if err := u.applyUpdate(zipData); err != nil {
		log.Printf("Update apply failed: %v", err)
	}
}

func (u *Updater) fetchReleases() ([]GitHubRelease, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases", owner, repo)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Accept", "application/vnd.github+json")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("GitHub API returned %d", resp.StatusCode)
	}

	var releases []GitHubRelease
	if err := json.NewDecoder(resp.Body).Decode(&releases); err != nil {
		return nil, err
	}
	return releases, nil
}

func (u *Updater) downloadAsset(url string) ([]byte, error) {
	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("download returned %d", resp.StatusCode)
	}

	return io.ReadAll(resp.Body)
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

	// Extract zip to temp directory
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

	// Write batch trampoline that waits for this process to exit,
	// replaces the exe, relaunches, and cleans up.
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

	// Launch trampoline detached and exit
	cmd := exec.Command("cmd.exe", "/C", "start", "/B", batPath)
	if err := cmd.Start(); err != nil {
		return err
	}

	os.Exit(0)
	return nil // unreachable
}
