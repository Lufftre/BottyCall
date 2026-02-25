// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BottyCallUI",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BottyCallUI", path: "Sources")
    ]
)
