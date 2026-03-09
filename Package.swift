// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VaporVectorHub",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "VaporVectorHub", targets: ["VaporVectorHub"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.115.0")
    ],
    targets: [
        .target(
            name: "VaporVectorHub",
            dependencies: [
                .product(name: "Vapor", package: "vapor")
            ],
            path: "Sources/VaporVectorHub",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "VaporVectorHubTests",
            dependencies: ["VaporVectorHub"],
            path: "Tests/VaporVectorHubTests"
        ),
    ]
)
