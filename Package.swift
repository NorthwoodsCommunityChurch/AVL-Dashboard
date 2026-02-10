// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComputerDashboard",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "Shared",
            path: "Sources/Shared"
        ),
        .executableTarget(
            name: "Dashboard",
            dependencies: [
                "Shared",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Dashboard"
        ),
        .executableTarget(
            name: "Agent",
            dependencies: [
                "Shared",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Agent",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN")
            ]
        ),
    ]
)
