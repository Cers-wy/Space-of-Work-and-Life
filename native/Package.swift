// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Space",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Space", targets: ["OrbitApp"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "OrbitCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "OrbitApp", dependencies: ["OrbitCore"]),
        .testTarget(name: "OrbitCoreTests", dependencies: ["OrbitCore"]),
        .testTarget(name: "OrbitAppTests", dependencies: ["OrbitApp", "OrbitCore"])
    ],
    swiftLanguageModes: [.v5]
)
