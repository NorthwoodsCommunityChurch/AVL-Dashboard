package update

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
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

	// Find platform-specific agent asset
	targetAsset := findAgentAsset(bestRelease.Assets)
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

// matchesAgentAsset checks if an asset name matches a platform keyword.
func matchesAgentAsset(name, platform string) bool {
	lower := strings.ToLower(name)
	return strings.Contains(lower, platform) &&
		strings.Contains(lower, "agent") &&
		strings.HasSuffix(lower, ".zip")
}
