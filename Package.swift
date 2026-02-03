// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComputerDashboard",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "Shared",
            path: "Sources/Shared"
        ),
        .executableTarget(
            name: "Dashboard",
            dependencies: ["Shared"],
            path: "Sources/Dashboard"
        ),
        .executableTarget(
            name: "Agent",
            dependencies: ["Shared"],
            path: "Sources/Agent",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN")
            ]
        ),
    ]
)
