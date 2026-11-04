// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AC",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "AC", path: "Sources/AC")]
)
