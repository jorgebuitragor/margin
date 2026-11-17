import Foundation
import Darwin

/// Artefacto regenerable dentro de un proyecto (node_modules, .build, build de Gradle…).
public struct ProjectArtifact: Sendable {
    public let path: String
    public let kind: String
    public let project: String
    public let regenerate: String
    public let sharedWithStore: Bool
}

/// Recorrido de las carpetas de proyectos: encuentra artefactos y qué versiones de herramientas piden los proyectos.
public struct ProjectIndex: Sendable {
    public var artifacts: [ProjectArtifact] = []
    /// Versión de Gradle → proyectos que la piden en gradle-wrapper.properties.
    public var gradleVersions: [String: [String]] = [:]
    public var ndkVersions: [String: [String]] = [:]
    public var buildToolsVersions: [String: [String]] = [:]
    /// Proyecto → raíz del repositorio git.
    public var repositories: [String: String] = [:]

    static let maxDepth = 6
    /// Carpetas en las que no se entra: artefactos, metadatos y dependencias.
    static let skip: Set<String> = ["node_modules", ".git", ".build", "build", "Pods", "target", ".gradle", ".next", ".turbo", ".cxx", "DerivedData", ".expo", "dist", ".venv", "venv", "vendor", ".swiftpm", "Library"]

    public static func build(_ env: DevEnvironment) -> ProjectIndex {
        var index = ProjectIndex()
        // En APFS sin distinción de mayúsculas, ~/projects y ~/Projects son la misma carpeta: se deduplica por inodo.
        var seenRoots = Set<[UInt64]>()
        for root in env.projectRoots where env.isDirectory(root.path) {
            var st = stat()
            guard lstat(root.path, &st) == 0, seenRoots.insert([UInt64(bitPattern: Int64(st.st_dev)), UInt64(st.st_ino)]).inserted else { continue }
            // Las carpetas sincronizadas (por ejemplo Documentos con Google Drive) no se proponen para limpieza.
            if SyncDetector.provider(forDirectoryOrAncestors: root) != nil { continue }
            index.walk(root.standardizedFileURL.path, depth: 0, repo: nil, env: env)
        }
        return index
    }

    private mutating func walk(_ dir: String, depth: Int, repo: String?, env: DevEnvironment) {
        guard depth <= Self.maxDepth else { return }
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
        if names.isEmpty { return }
        let repo = names.contains(".git") ? dir : repo
        let project = dir
        if let repo { repositories[project] = repo }
        func has(_ n: String) -> Bool { names.contains(n) }
        func artifact(_ name: String, _ kind: String, _ regenerate: String, shared: Bool = false) {
            let path = "\(dir)/\(name)"
            guard has(name), env.isDirectory(path), !isLink(path) else { return }
            artifacts.append(ProjectArtifact(path: path, kind: kind, project: project, regenerate: regenerate, sharedWithStore: shared))
        }

        if has("package.json") {
            let (cmd, pnpm) = has("pnpm-lock.yaml") ? ("pnpm install", true) : has("yarn.lock") ? ("yarn install", false) : has("bun.lockb") || has("bun.lock") ? ("bun install", false) : ("npm install", false)
            artifact("node_modules", "Dependencias de Node", "Se reinstala con `\(cmd)` (descarga de red).", shared: pnpm)
            if names.contains(where: { $0.hasPrefix("next.config.") }) { artifact(".next", "Compilación de Next.js", "Se regenera al compilar o arrancar Next.js.") }
            artifact(".turbo", "Caché de Turborepo", "Se regenera en la siguiente ejecución de turbo.")
            artifact(".expo", "Caché local de Expo", "Expo la regenera al arrancar.")
            readReactNativeVersions(dir)
        }
        if has("Package.swift") { artifact(".build", "Compilación de SwiftPM", "Se regenera con `swift build`.") }
        let gradleProject = has("build.gradle") || has("build.gradle.kts") || has("settings.gradle") || has("settings.gradle.kts")
        if gradleProject {
            artifact("build", "Compilación de Gradle", "Se regenera al compilar con Gradle.")
            artifact(".gradle", "Caché de Gradle del proyecto", "Gradle la regenera al compilar.")
            artifact(".cxx", "Compilación nativa (CMake/NDK)", "Se regenera al compilar código nativo.")
            for file in ["build.gradle", "build.gradle.kts", "gradle.properties", "app/build.gradle", "app/build.gradle.kts"] {
                if let text = env.read("\(dir)/\(file)") { readAndroidVersions(text, project: project) }
            }
        }
        if let wrapper = env.read("\(dir)/gradle/wrapper/gradle-wrapper.properties"),
           let match = wrapper.range(of: #"gradle-([0-9][0-9A-Za-z.\-]*?)-(bin|all)\.zip"#, options: .regularExpression) {
            let text = String(wrapper[match])
            let version = text.replacingOccurrences(of: "gradle-", with: "").replacingOccurrences(of: #"-(bin|all)\.zip"#, with: "", options: .regularExpression)
            gradleVersions[version, default: []].append(project)
        }
        if has("Cargo.toml") { artifact("target", "Compilación de Rust", "Se regenera con `cargo build`.") }
        else if has("pom.xml") { artifact("target", "Compilación de Maven", "Se regenera con `mvn package`.") }
        if has("Podfile") { artifact("Pods", "Dependencias de CocoaPods", "Se reinstala con `pod install` (descarga de red).") }

        for name in names.sorted() where !Self.skip.contains(name) && !name.hasPrefix(".") {
            let child = "\(dir)/\(name)"
            guard env.isDirectory(child), !isLink(child), URL(fileURLWithPath: child).pathExtension.isEmpty else { continue }
            walk(child, depth: depth + 1, repo: repo, env: env)
        }
    }

    private func isLink(_ path: String) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private mutating func readReactNativeVersions(_ dir: String) {
        // React Native fija la versión de NDK y build-tools en su catálogo de Gradle.
        guard let toml = try? String(contentsOfFile: "\(dir)/node_modules/react-native/gradle/libs.versions.toml", encoding: .utf8) else { return }
        for (key, target) in [("ndkVersion", \ProjectIndex.ndkVersions), ("buildTools", \ProjectIndex.buildToolsVersions)] {
            if let version = Self.capture(#"(?m)^\s*"# + key + #"\s*=\s*"([0-9.]+)""#, in: toml) {
                self[keyPath: target][version, default: []].append(dir)
            }
        }
    }

    private mutating func readAndroidVersions(_ text: String, project: String) {
        if let v = Self.capture(#"ndkVersion\s*[=:]?\s*["']([0-9.]+)["']"#, in: text) { ndkVersions[v, default: []].append(project) }
        if let v = Self.capture(#"buildToolsVersion\s*[=:]?\s*["']([0-9.]+)["']"#, in: text) { buildToolsVersions[v, default: []].append(project) }
    }

    static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Fecha del último commit del repositorio, o nil si no hay git o falla.
    public static func lastCommit(_ repo: String, env: DevEnvironment) -> Date? {
        guard let git = env.tool("git", extra: ["/usr/bin"]),
              let result = env.runner.run(git, ["-C", repo, "log", "-1", "--format=%ct"], timeout: 10),
              result.status == 0, let seconds = TimeInterval(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
