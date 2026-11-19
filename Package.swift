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
    dependencies: [
        // Actualizaciones automáticas desde GitHub Releases (appcast firmado con EdDSA).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(name: "SpaceCore"),
        .executableTarget(name: "SpaceApp", dependencies: ["SpaceCore", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "SpaceCLI", dependencies: ["SpaceCore"]),
        .testTarget(name: "SpaceCoreTests", dependencies: ["SpaceCore"])
    ]
)
