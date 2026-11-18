import Foundation

/// Perfiles generales del «Análisis inteligente»: lugares conocidos donde se acumula espacio en cualquier Mac,
/// no solo en uno de desarrollo. Igual que los perfiles de desarrollo: miden, explican y proponen; no ejecutan.
extension DevProfiles {
    public static let generalIDs: Set<String> = ["app-caches", "logs", "downloads", "ios-backups"]

    /// Cachés con dueño conocido: título, proceso que debe estar cerrado y comando oficial si existe.
    static let knownCaches: [String: (title: String, check: ProcessCheck?, command: [String]?)] = [
        "Firefox": ("Caché de Firefox", ProcessCheck(label: "Firefox", pattern: "Firefox.app/Contents/MacOS/firefox"), nil),
        "Google": ("Caché de Google Chrome", ProcessCheck(label: "Google Chrome", pattern: "Google Chrome.app/Contents/MacOS/Google Chrome"), nil),
        "go-build": ("Caché de compilación de Go", nil, ["go", "clean", "-cache"]),
        "Codex": ("Caché de Codex", ProcessCheck(label: "Codex", pattern: "Codex.app/Contents/MacOS/"), nil),
        "JetBrains": ("Caché de JetBrains", ProcessCheck(label: "los IDE de JetBrains", pattern: ".app/Contents/MacOS/idea"), nil),
        "Docker Desktop": ("Caché de Docker Desktop", ProcessCheck(label: "Docker Desktop", pattern: "Docker.app/Contents/MacOS/"), nil),
        "CocoaPods": ("Caché de CocoaPods", nil, ["pod", "cache", "clean", "--all"]),
        // DotSlash descarga bajo demanda los binarios que piden algunas herramientas (por ejemplo, Codex).
        "dotslash": ("Caché de DotSlash", ProcessCheck(label: "Codex", pattern: "Codex.app/Contents/MacOS/"), nil)
    ]
    /// Cachés que gestionan otros perfiles o el propio sistema.
    static let skippedCaches: Set<String> = ["Homebrew", "Yarn", "pnpm", "TemporaryItems", "CloudKit", "GeoServices", "PassKit", "GameKit", "FamilyCircle", "Animoji"]

    static func appCaches(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path("Library/Caches")
        var result = ProfileResult(id: "app-caches", name: "Cachés de apps", owner: "Cada app", detected: env.isDirectory(dir))
        for name in env.children(dir) where !name.hasPrefix("com.apple.") && !skippedCaches.contains(name) {
            let path = "\(dir)/\(name)"
            guard env.isDirectory(path) else { continue }
            let usage = DiskUsage.measure(path)
            guard usage.allocated > 50_000_000 else { continue }
            if let known = knownCaches[name] {
                let action: DevAction = known.command.map { .run($0) } ?? .trash(path, note: known.check.map { "Con \($0.label) cerrado." }, closed: known.check.map { [$0] } ?? [])
                result.items.append(.measured("app-caches", known.title, path: path, category: .lowRisk,
                    reason: "Datos temporales que la app vuelve a generar.", regenerate: "La app o la herramienta la regenera; la primera vez irá algo más lenta.", action: action, usage: usage))
            } else if name.split(separator: ".").count >= 3 {
                // Nombre con forma de identificador de app (com.empresa.app): se comprueba que esa app esté cerrada.
                let check = ProcessCheck(label: name, pattern: name, bundleID: name)
                result.items.append(.measured("app-caches", "Caché de \(name)", path: path, category: .lowRisk,
                    reason: "Caché de la app \(name).", regenerate: "La app la regenera; la primera vez irá algo más lenta.",
                    action: .trash(path, note: "Con la app cerrada.", closed: [check]), usage: usage))
            } else {
                result.items.append(.measured("app-caches", "Caché «\(name)»", path: path, category: .review,
                    reason: "No se sabe qué app o herramienta la usa. Las cachés suelen regenerarse, pero comprueba antes de quién es.",
                    regenerate: "Normalmente se regenera; si es de una herramienta de línea de comandos, volverá a descargar lo que necesite.",
                    action: .trash(path, note: "Cierra antes la app o herramienta que la use."), usage: usage))
            }
        }
        result.items.sort { ($0.recoverable ?? 0) > ($1.recoverable ?? 0) }
        if result.detected { result.notes.append("Las cachés de macOS (com.apple.*) no se tocan: las gestiona el sistema.") }
        return result
    }

    static func logs(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path("Library/Logs")
        var result = ProfileResult(id: "logs", name: "Registros", owner: "Cada app y macOS", detected: env.isDirectory(dir))
        guard result.detected else { return result }
        var paths: [String] = []
        var total = Usage()
        for name in env.children(dir) {
            let path = "\(dir)/\(name)"
            let usage = DiskUsage.measure(path)
            guard usage.allocated > 0, FileIdentity.of(path) != nil else { continue }
            paths.append(path)
            total.allocated += usage.allocated
            total.exclusive += usage.exclusive
        }
        if total.allocated > 20_000_000 {
            result.items.append(DevItem(profile: "logs", title: "Registros de apps (\(paths.count) \(paths.count == 1 ? "carpeta" : "carpetas"))", path: dir, bytes: total.allocated, recoverable: total.exclusive, category: .lowRisk,
                reason: "Historial de actividad y de errores de las apps. Solo sirve para diagnosticar fallos pasados.",
                regenerate: "Las apps crean registros nuevos; se pierde el historial para diagnosticar fallos anteriores.",
                action: .trash(paths, label: "\(paths.count) carpetas de ~/Library/Logs")))
        }
        return result
    }

    static func downloads(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path("Downloads")
        var result = ProfileResult(id: "downloads", name: "Instaladores en Descargas", owner: "Tú", detected: env.isDirectory(dir))
        guard result.detected, SyncDetector.provider(forDirectoryOrAncestors: URL(fileURLWithPath: dir)) == nil else {
            if result.detected { result.notes.append("Descargas está sincronizada con la nube: no se propone nada.") }
            return result
        }
        let installers: Set<String> = ["dmg", "pkg", "iso", "xip", "zip"]
        var paths: [String] = []
        var total = Usage()
        for name in env.children(dir) {
            let path = "\(dir)/\(name)"
            guard installers.contains(URL(fileURLWithPath: name).pathExtension.lowercased()),
                  let identity = FileIdentity.of(path), !identity.isDirectory else { continue }
            let age = env.now.timeIntervalSince1970 - identity.modified
            guard age > Double(env.inactiveDays) * 86_400 else { continue }
            let usage = DiskUsage.measure(path)
            paths.append(path)
            total.allocated += usage.allocated
            total.exclusive += usage.exclusive
        }
        if !paths.isEmpty {
            result.items.append(DevItem(profile: "downloads", title: paths.count == 1 ? "1 instalador o comprimido de hace más de \(env.inactiveDays) días" : "\(paths.count) instaladores y comprimidos de hace más de \(env.inactiveDays) días", path: dir, bytes: total.allocated, recoverable: total.exclusive, category: .review,
                reason: "Archivos .dmg, .pkg, .iso, .xip o .zip descargados hace tiempo. Si ya instalaste la app o extrajiste el contenido, sobran; pero puede ser tu única copia.",
                regenerate: "Se pueden volver a descargar si sigue disponible el original.",
                action: .trash(paths, label: "\(paths.count) archivos de Descargas")))
        }
        return result
    }

    static func iosBackups(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path("Library/Application Support/MobileSync/Backup")
        var result = ProfileResult(id: "ios-backups", name: "Copias de seguridad de iPhone/iPad", owner: "Finder", detected: env.exists(dir))
        guard result.detected else { return result }
        guard (try? FileManager.default.contentsOfDirectory(atPath: dir)) != nil else {
            result.notes.append("macOS no permite leer las copias de seguridad sin «Acceso total al disco». Puedes gestionarlas desde Finder › tu iPhone › Gestionar copias.")
            return result
        }
        for name in env.children(dir) {
            let path = "\(dir)/\(name)"
            let usage = DiskUsage.measure(path)
            guard usage.allocated > 100_000_000 else { continue }
            let days = env.days(since: usage.newest).map { "Última copia hace \($0) días." } ?? ""
            result.items.append(.measured("ios-backups", "Copia de seguridad \(name.prefix(8))…", path: path, category: .review,
                reason: "Copia de un iPhone o iPad. \(days) Puede ser la única copia de ese dispositivo.",
                regenerate: "No se regenera: haz antes una copia nueva o confirma que tienes copia en iCloud.", action: .trash(path), usage: usage))
        }
        return result
    }
}

/// Estado de la Papelera para la pantalla de inicio. Vaciarla es la única acción de borrado definitivo y va aparte
/// de los planes, con su propia confirmación (ver EmptyTrash.swift).
public struct TrashStatus: Codable, Sendable {
    /// nil cuando macOS no deja leerla (sin «Acceso total al disco»).
    public let bytes: Int64?
    public let items: Int?
    public static func read(_ env: DevEnvironment) -> TrashStatus {
        let path = env.path(".Trash")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return TrashStatus(bytes: nil, items: nil) }
        let usage = DiskUsage.measure(path)
        return TrashStatus(bytes: usage.allocated, items: names.filter { $0 != ".DS_Store" }.count)
    }
}
