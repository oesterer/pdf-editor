// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "pdf-editor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "pdf-editor",
            targets: ["pdf-editor"]
        )
    ],
    targets: [
        .executableTarget(
            name: "pdf-editor",
            path: "Sources"
        )
    ]
)
