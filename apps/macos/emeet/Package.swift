// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "emeet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "emeet", targets: ["emeet"])
    ],
    targets: [
        .executableTarget(name: "emeet")
    ]
)
