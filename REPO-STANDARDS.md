# Repository Standards

Standards for all repositories under NorthwoodsCommunityChurch with `avl-tools` or `lighting-tools` topics.

---

## Required Files

Every repository must include the following files before its first release.

### README.md

The README is the front page of the project. It must include these sections in order:

1. **Project title** as an H1
2. **One-line description** of what the app does
3. **Screenshot(s)** — At least one image showing the app in use (see [Screenshots](#screenshots))
4. **Features** — Bullet list of key capabilities
5. **Requirements** — macOS version, architecture (Apple Silicon, Intel, Universal)
6. **Installation** — Step-by-step:
   - Download the `.zip` from Releases
   - Extract and move `.app` to `/Applications`
   - First launch instructions (right-click > Open or `xattr -cr` for unsigned apps)
7. **Usage / Quick Start** — How to actually use the app after install
8. **Configuration** — Any setup required (network, external apps, ports, etc.)
9. **Building from Source** — Clone, prerequisites, build command
10. **Project Structure** — Directory tree showing key files
11. **License** — One-line reference to LICENSE file
12. **Credits** — One-line reference to CREDITS.md

Optional sections (include when relevant):
- **API Reference** — For apps that expose HTTP/WebSocket/OSC endpoints
- **Network Architecture** — ASCII diagram for multi-device or client-server apps
- **Security** — Brief note for apps running network servers, linking to SECURITY.md if present
- **Troubleshooting** — Common issues (Gatekeeper, port conflicts, etc.)

### LICENSE

MIT License. All repos use MIT unless a dependency requires otherwise.

Copy the standard MIT text with:
```
Copyright (c) 2025 Northwoods Community Church
```

Update the year to match the repo creation year.

### CREDITS.md

Every repo must include a credits file acknowledging third-party work. This applies even when using only Apple frameworks — credit the tools, fonts, icons, or libraries that made the project possible.

Structure:

```markdown
# Credits & Acknowledgments

## Frameworks & Libraries

| Dependency | Description | License |
|------------|-------------|---------|
| [Name](url) | What it does | License type |

## Fonts

- **[Font Name](url)** by Author — License

## Icons & Assets

- **[SF Symbols](https://developer.apple.com/sf-symbols/)** — Apple system icons
- Any other icon sources

## Tools

- **[Tool Name](url)** — What role it played (e.g., "Build tooling", "Code generation")

## Inspiration

- Links to projects, articles, or prior art that influenced the design

---

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
```

Rules:
- List every non-Apple-framework dependency (SPM packages, npm modules, Cargo crates, CDN scripts)
- Include fonts, even system fonts if a specific typeface was chosen intentionally
- Include tools used in the build pipeline (Tauri CLI, SwiftPM, XcodeGen, etc.)
- Link to each dependency's homepage or repo
- State the license for each entry
- Credit prior art or inspiration at the bottom

### .gitignore

Must exclude at minimum:
- Build artifacts (`.build/`, `build/`, `DerivedData/`, `target/`)
- IDE metadata (`*.xcuserdata/`, `.vscode/` settings that aren't shared configs)
- macOS system files (`.DS_Store`)
- Debug symbols (`*.dSYM`)
- Package manager lockfiles when appropriate (`Package.resolved` for libraries)
- **Release archives** — `.zip`, `.dmg`, `.app` files must never be committed to the tree

---

## Screenshots

Every repo must include at least one screenshot or image showing the app running. For dashboard-style or visual apps, include multiple views.

Storage:
- Place images in a `docs/images/` directory (not the repo root)
- Use PNG format for screenshots, SVG for diagrams
- Name descriptively: `dashboard-grid.png`, `menu-bar-dropdown.png`
- Reference from README using relative paths: `![Dashboard](docs/images/dashboard-grid.png)`

For menu bar apps, capture both the menu bar icon area and the dropdown content.

---

## GitHub Repository Settings

Before the first release, configure these on the GitHub repo page:

- **Description** — One sentence explaining what the app does (shown in search results and org page)
- **Topics** — Must include `macos` and at least one of `avl-tools` or `lighting-tools`
- **Website** — Link to the README or leave blank (do not link to unrelated sites)
- **Wiki** — Disable unless actively used
- **Issues** — Enable

---

## Releases

### Versioning

Use [Semantic Versioning](https://semver.org/): `vMAJOR.MINOR.PATCH`

- **MAJOR** — Breaking changes or major redesigns
- **MINOR** — New features, backward-compatible
- **PATCH** — Bug fixes, minor tweaks

Pre-release tags: append `-alpha`, `-beta`, or `-rc.N` (e.g., `v1.0.0-alpha`, `v1.2.0-beta`, `v2.0.0-rc.1`).

### First Release Rule

When a repo is pushed to GitHub for the first time, it must have a release created before it is considered published. If the app is not yet stable or feature-complete:

- Create a **pre-release** tagged `v1.0.0-alpha`
- Mark it as **Pre-release** in GitHub (not Latest)
- Title it: `v1.0.0-alpha`
- Body should note: "Initial alpha release. May contain bugs or incomplete features."

When the app is stable:
- Create a full release tagged `v1.0.0`
- Mark it as **Latest**

Do not leave a repo with commits but no release. Every published repo gets at least an alpha.

### Release Assets

Every release **must** include the app as a `.zip` file. This is required because:

- Apps are ad-hoc signed (no Apple Developer certificate)
- macOS Gatekeeper quarantines downloaded `.app` bundles
- Distributing as `.zip` allows users to extract and right-click > Open to bypass Gatekeeper
- `.dmg` files are optional but not required

Naming convention for zip files:
```
{AppName}-v{version}-{arch}.zip
```

Examples:
- `ComputerDashboard-v1.0.0-alpha-universal.zip`
- `DashboardAgent-v1.0.0-alpha-universal.zip`
- `MA3-Cue-Display-v1.1.0-aarch64.zip`
- `NetworkHistory-v1.0.0-universal.zip`

For projects with multiple apps (e.g., Dashboard + Agent), include a separate zip for each app in the same release.

Architecture labels:
- `aarch64` — Apple Silicon only
- `x86_64` — Intel only
- `universal` — Universal Binary (both architectures)

### Release Notes

Every release must include:
- **What's New** or **Changes** section
- **Installation** one-liner referencing the README
- **Known Issues** if any (especially for alpha/beta)
- **Full Changelog** link (GitHub auto-generates this)

Template:
```markdown
## What's New

- Feature or fix description
- Another change

## Installation

See [README](README.md#installation) for setup instructions.

## Known Issues

- Any known problems

**Full Changelog**: https://github.com/NorthwoodsCommunityChurch/repo/compare/v0.0.0...v1.0.0
```

### Release Artifacts Must Not Be Committed

Release `.zip` and `.dmg` files belong **only** in GitHub Releases, not in the repo tree. If a `releases/` folder or loose `.zip` exists in the repo, remove it and add the pattern to `.gitignore`.

---

## Conditional Files

Include these when the criteria apply.

### SECURITY.md

**Required when:** The app runs a network server, listens on ports, or accepts external connections.

Applies to: AVL-Dashboard (Agent), MA3-Cue-Display, MA3-Spotter, SMPTE-Notes, SMPTE-MIDI, Northwoods-Wayfind, Northwoods-Display-Central.

Must cover:
- Intended deployment environment (local network, trusted LAN, etc.)
- What ports are opened and why
- Authentication model (or lack thereof, with justification)
- What data is exposed
- Recommendations for network isolation
- How to report vulnerabilities

### CONTRIBUTING.md

**Required when:** The project accepts outside contributions or has complex development setup.

Not required for internal-only tools, but recommended for any public repo.

### docs/ Directory

**Required when:** The project has setup guides, protocol specs, or architecture docs beyond what fits in the README.

Examples: `docs/SETUP.md`, `docs/ARCHITECTURE.md`, `docs/API-REFERENCE.md`

### .env.example

**Required when:** The project uses environment variables for configuration. List all variables with placeholder values and comments.

---

## Build & Development

### Build Script

Projects built with SPM, Tauri, or custom build steps should include a documented build script (e.g., `Scripts/build.sh` or `Makefile`).

The script must:
- Build the release binary
- Create the `.app` bundle (if macOS app)
- Apply ad-hoc code signing
- Output to a predictable location (e.g., `./build/`)
- Print usage instructions or the output path on success

### Building from Source

The README must document how to build from source with exact commands. Assume the reader has:
- Xcode or Swift toolchain installed
- Homebrew (if additional tools are needed)
- No other prerequisites unless documented

---

## Current Repo Audit

Status of each repo against these standards as of February 2026.

| Repo | README | LICENSE | CREDITS | Release | Screenshots | Description | Topics |
|------|--------|---------|---------|---------|-------------|-------------|--------|
| AVL-Dashboard | -- | -- | -- | -- | -- | Yes | Yes |
| MacOS-Network-History | -- | -- | -- | v1.0.0 | -- | Yes | Yes |
| Davinci-Project-Server-Backup | Yes | Yes | -- | v1.0.4 | -- | Yes | Yes |
| Northwoods-Wayfind | Yes | -- | -- | v1.0.0 | logo | Yes | Yes |
| Northwoods-Display-Central | -- | -- | -- | -- | -- | Yes | Yes |
| MA3-Cue-Display | Yes | Yes | Yes | v1.1.0 | 2 PNGs | -- | Yes |
| SMPTE-Notes | Yes | Yes | -- | v0.2.0-alpha | -- | Yes | Yes |
| SMPTE-MIDI | Yes | Yes | -- | -- | -- | -- | Yes |
| MA3-Spotter | Yes | Yes | -- | -- | -- | -- | Yes |

### Issues to Resolve

**Missing LICENSE (3 repos):**
- AVL-Dashboard
- MacOS-Network-History
- Northwoods-Wayfind

**Missing README (3 repos):**
- AVL-Dashboard
- MacOS-Network-History
- Northwoods-Display-Central

**Missing CREDITS.md (8 repos):**
- All except MA3-Cue-Display

**Missing releases (3 repos):**
- AVL-Dashboard — Needs v1.0.0-alpha with Dashboard.zip + DashboardAgent.zip
- Northwoods-Display-Central — Needs v1.0.0-alpha
- SMPTE-MIDI — Needs v1.0.0-alpha
- MA3-Spotter — Needs v1.0.0-alpha

**Empty GitHub description (3 repos):**
- MA3-Cue-Display
- SMPTE-MIDI
- MA3-Spotter

**Committed release artifacts (2 repos):**
- Northwoods-Wayfind — `.zip` in repo root
- SMPTE-Notes — `releases/` directory with zips

**Missing screenshots (7 repos):**
- All except MA3-Cue-Display and Northwoods-Wayfind
