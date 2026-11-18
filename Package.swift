// swift-tools-version: 6.0
import PackageDescription

// Margin (antes «Gestor Espacio»). La app se llama MarginApp como producto para no chocar con el binario `margin`
// de la terminal en un sistema de archivos que no distingue mayúsculas.
let package = Package(
    name: "Margin",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "MarginApp", targets: ["SpaceApp"]),
        .executable(name: "margin", targets: ["SpaceCLI"])
    ],
    targets: [
        .target(name: "SpaceCore"),
        .executableTarget(name: "SpaceApp", dependencies: ["SpaceCore"]),
        .executableTarget(name: "SpaceCLI", dependencies: ["SpaceCore"]),
        .testTarget(name: "SpaceCoreTests", dependencies: ["SpaceCore"])
    ]
)
