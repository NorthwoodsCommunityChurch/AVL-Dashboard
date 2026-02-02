# Credits & Acknowledgments

## Frameworks

This project uses only Apple-provided frameworks with no external dependencies.

| Framework | Description | Usage |
|-----------|-------------|-------|
| [SwiftUI](https://developer.apple.com/xcode/swiftui/) | Declarative UI framework | Dashboard grid, cards, settings views |
| [Network.framework](https://developer.apple.com/documentation/network) | Modern networking library | NWListener (HTTP server), NWBrowser (Bonjour), NWConnection (polling) |
| [IOKit](https://developer.apple.com/documentation/iokit) | Hardware access framework | CPU temperature via HID thermal sensors |
| [Observation](https://developer.apple.com/documentation/observation) | State management | View models and reactive data flow |

## Icons & Assets

- **[SF Symbols](https://developer.apple.com/sf-symbols/)** — Apple system icons used throughout the UI (gauge, thermometer, network, lock icons)

## Tools

- **[Swift Package Manager](https://www.swift.org/documentation/package-manager/)** — Build system and dependency management
- **[Claude Code](https://claude.ai/claude-code)** — AI-assisted development

## Technical References

- **[Mach Kernel APIs](https://developer.apple.com/documentation/kernel)** — `host_statistics` for CPU usage tick counters
- **[getifaddrs](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/getifaddrs.3.html)** — Network interface enumeration for throughput and IP address
- **[sysctl](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/sysctl.3.html)** — Kernel boot time (uptime) and CPU model string

---

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
