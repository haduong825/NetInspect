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
        .library(name: "NetInspectAlamofire", targets: ["NetInspectAlamofire"]),
        .library(name: "NetInspectTransport", targets: ["NetInspectTransport"]),
        .library(name: "NetInspectUI", targets: ["NetInspectUI"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/Alamofire/Alamofire.git",
            "5.10.2"..<"5.11.0"
        )
    ],
    targets: [
        .target(name: "NetInspectCore"),
        .target(name: "NetInspectURLSession", dependencies: ["NetInspectCore"]),
        .target(
            name: "NetInspectAlamofire",
            dependencies: [
                "NetInspectURLSession",
                .product(name: "Alamofire", package: "Alamofire")
            ]
        ),
        .target(name: "NetInspectTransport", dependencies: ["NetInspectCore"]),
        .target(name: "NetInspectUI", dependencies: ["NetInspectCore"], path: "Sources/NetInspectUI"),
        .testTarget(
            name: "NetInspectTests",
            dependencies: [
                "NetInspectCore",
                "NetInspectURLSession",
                "NetInspectAlamofire",
                "NetInspectTransport",
                .product(name: "Alamofire", package: "Alamofire")
            ]
        ),
        .testTarget(
            name: "NetInspectUITests",
            dependencies: ["NetInspectCore", "NetInspectUI"]
        )
    ]
)
