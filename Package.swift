// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "QuickCopy",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "QuickCopy",
            path: "Sources/QuickCopy"
        )
    ]
)
