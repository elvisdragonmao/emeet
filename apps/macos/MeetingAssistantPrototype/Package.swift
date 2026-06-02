// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MeetingAssistantPrototype",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MeetingAssistantPrototype", targets: ["MeetingAssistantPrototype"])
    ],
    targets: [
        .executableTarget(name: "MeetingAssistantPrototype")
    ]
)
