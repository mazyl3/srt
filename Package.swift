// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SRTForge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SRTForge", targets: ["SRTForge"])
    ],
    targets: [
        .executableTarget(
            name: "SRTForge",
            path: "Sources/SRTForge"
        )
    ]
)

