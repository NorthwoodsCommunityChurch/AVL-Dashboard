package update

import (
	"strconv"
	"strings"
)

// SemanticVersion represents a parsed semver string (e.g., "1.2.3-beta").
type SemanticVersion struct {
	Major      int
	Minor      int
	Patch      int
	Prerelease string // empty for release versions
}

// ParseVersion parses a version string like "v1.2.3" or "1.2.3-alpha" into components.
// Returns nil if the string is not a valid version.
func ParseVersion(s string) *SemanticVersion {
	s = strings.TrimPrefix(s, "v")
	if s == "" {
		return nil
	}

	// Split off pre-release tag
	var prerelease string
	if idx := strings.Index(s, "-"); idx >= 0 {
		prerelease = s[idx+1:]
		s = s[:idx]
	}

	parts := strings.Split(s, ".")
	if len(parts) < 1 || len(parts) > 3 {
		return nil
	}

	major, err := strconv.Atoi(parts[0])
	if err != nil {
		return nil
	}

	var minor, patch int
	if len(parts) >= 2 {
		minor, err = strconv.Atoi(parts[1])
		if err != nil {
			return nil
		}
	}
	if len(parts) >= 3 {
		patch, err = strconv.Atoi(parts[2])
		if err != nil {
			return nil
		}
	}

	return &SemanticVersion{
		Major:      major,
		Minor:      minor,
		Patch:      patch,
		Prerelease: prerelease,
	}
}

// GreaterThan returns true if v is a newer version than other.
// Release versions beat pre-release of the same version (1.0.0 > 1.0.0-beta).
func (v SemanticVersion) GreaterThan(other SemanticVersion) bool {
	if v.Major != other.Major {
		return v.Major > other.Major
	}
	if v.Minor != other.Minor {
		return v.Minor > other.Minor
	}
	if v.Patch != other.Patch {
		return v.Patch > other.Patch
	}

	// Same major.minor.patch — compare pre-release tags
	// Release (no tag) beats any pre-release
	if v.Prerelease == "" && other.Prerelease != "" {
		return true
	}
	if v.Prerelease != "" && other.Prerelease == "" {
		return false
	}
	// Both have pre-release tags: alphabetical comparison
	return v.Prerelease > other.Prerelease
}

// String returns the version as "major.minor.patch[-prerelease]".
func (v SemanticVersion) String() string {
	s := strconv.Itoa(v.Major) + "." + strconv.Itoa(v.Minor) + "." + strconv.Itoa(v.Patch)
	if v.Prerelease != "" {
		s += "-" + v.Prerelease
	}
	return s
}
