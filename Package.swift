// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lumos",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LumosCore", targets: ["LumosCore"]),
        .executable(name: "lumos", targets: ["lumos"])
    ],
    targets: [
        .target(
            name: "LumosCore"
        ),
        .executableTarget(
            name: "lumos",
            dependencies: ["LumosCore"]
        ),
        .testTarget(
            name: "LumosCoreTests",
            dependencies: ["LumosCore"]
        )
    ]
)
