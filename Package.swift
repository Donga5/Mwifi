// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Mwifi",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Mwifi", targets: ["Mwifi"])
    ],
    targets: [
        .executableTarget(
            name: "Mwifi",
            linkerSettings: [
                .linkedFramework("Charts"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(name: "MwifiTests", dependencies: ["Mwifi"])
    ]
)
