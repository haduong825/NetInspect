// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetInspect",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "NetInspectCore", targets: ["NetInspectCore"]),
        .library(name: "NetInspectURLSession", targets: ["NetInspectURLSession"]),
        .library(name: "NetInspectTransport", targets: ["NetInspectTransport"]),
        .library(name: "NetInspectUI", targets: ["NetInspectUI"])
    ],
    dependencies: [],
    targets: [
        .target(name: "NetInspectCore"),
        .target(name: "NetInspectURLSession", dependencies: ["NetInspectCore"]),
        .target(name: "NetInspectTransport", dependencies: ["NetInspectCore"]),
        .target(name: "NetInspectUI", dependencies: ["NetInspectCore"], path: "Sources/NetInspectUI"),
        .testTarget(
            name: "NetInspectTests",
            dependencies: [
                "NetInspectCore",
                "NetInspectURLSession",
                "NetInspectTransport"
            ]
        ),
        .testTarget(
            name: "NetInspectUITests",
            dependencies: ["NetInspectCore", "NetInspectUI"]
        )
    ]
)
