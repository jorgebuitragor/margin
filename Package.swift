// swift-tools-version: 6.0
import PackageDescription

// Margen (antes «Gestor Espacio»). La app se llama MargenApp como producto para no chocar con el binario `margen`
// de la terminal en un sistema de archivos que no distingue mayúsculas.
let package = Package(
    name: "Margen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MargenApp", targets: ["SpaceApp"]),
        .executable(name: "margen", targets: ["SpaceCLI"])
    ],
    targets: [
        .target(name: "SpaceCore"),
        .executableTarget(name: "SpaceApp", dependencies: ["SpaceCore"]),
        .executableTarget(name: "SpaceCLI", dependencies: ["SpaceCore"]),
        .testTarget(name: "SpaceCoreTests", dependencies: ["SpaceCore"])
    ]
)
