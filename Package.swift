// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GestorEspacio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GestorEspacio", targets: ["SpaceApp"]),
        .executable(name: "espacio", targets: ["SpaceCLI"])
    ],
    targets: [
        .target(name: "SpaceCore"),
        .executableTarget(name: "SpaceApp", dependencies: ["SpaceCore"]),
        .executableTarget(name: "SpaceCLI", dependencies: ["SpaceCore"]),
        .testTarget(name: "SpaceCoreTests", dependencies: ["SpaceCore"])
    ]
)
