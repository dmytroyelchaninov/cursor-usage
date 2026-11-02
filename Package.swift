// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CursorUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CCommonCrypto",
            path: "Sources/CCommonCrypto"
        ),
        .executableTarget(
            name: "CursorUsage",
            dependencies: ["CCommonCrypto"],
            path: "Sources/CursorUsage"
        )
    ]
)
