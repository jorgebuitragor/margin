import Foundation

/// Perfiles generales del «Análisis inteligente»: lugares conocidos donde se acumula espacio en cualquier Mac,
/// no solo en uno de desarrollo. Igual que los perfiles de desarrollo: miden, explican y proponen; no ejecutan.
extension DevProfiles {
    public static let generalIDs: Set<String> = ["app-caches", "logs", "downloads", "ios-backups"]

    /// Cachés con dueño conocido: título, proceso que debe estar cerrado y comando oficial si existe.
    static var knownCaches: [String: (title: String, check: ProcessCheck?, command: [String]?)] { [
        "Firefox": (loc("Caché de Firefox", "Firefox cache"), ProcessCheck(label: "Firefox", pattern: "Firefox.app/Contents/MacOS/firefox"), nil),
        "Google": (loc("Caché de Google Chrome", "Google Chrome cache"), ProcessCheck(label: "Google Chrome", pattern: "Google Chrome.app/Contents/MacOS/Google Chrome"), nil),
        "go-build": (loc("Caché de compilación de Go", "Go build cache"), nil, ["go", "clean", "-cache"]),
        "Codex": (loc("Caché de Codex", "Codex cache"), ProcessCheck(label: "Codex", pattern: "Codex.app/Contents/MacOS/"), nil),
        "JetBrains": (loc("Caché de JetBrains", "JetBrains cache"), ProcessCheck(label: loc("los IDE de JetBrains", "the JetBrains IDEs"), pattern: ".app/Contents/MacOS/idea"), nil),
        "Docker Desktop": (loc("Caché de Docker Desktop", "Docker Desktop cache"), ProcessCheck(label: "Docker Desktop", pattern: "Docker.app/Contents/MacOS/"), nil),
        "CocoaPods": (loc("Caché de CocoaPods", "CocoaPods cache"), nil, ["pod", "cache", "clean", "--all"]),
        // DotSlash descarga bajo demanda los binarios que piden algunas herramientas (por ejemplo, Codex).
        "dotslash": (loc("Caché de DotSlash", "DotSlash cache"), ProcessCheck(label: "Codex", pattern: "Codex.app/Contents/MacOS/"), nil)
    ] }
    /// Cachés que gestionan otros perfiles o el propio sistema.
    static let skippedCaches: Set<String> = ["Homebrew", "Yarn", "pnpm", "TemporaryItems", "CloudKit", "GeoServices", "PassKit", "GameKit", "FamilyCircle", "Animoji"]

    static func appCaches(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path("Library/Caches")
        var result = ProfileResult(id: "app-caches", name: loc("Cachés de apps", "App caches"), owner: loc("Cada app", "Each app"), detected: env.isDirectory(dir))
        for name in env.children(dir) where !name.hasPrefix("com.apple.") && !skippedCaches.contains(name) {
            let path = "\(dir)/\(name)"
            guard env.isDirectory(path) else { continue }
            let usage = DiskUsage.measure(path)
            guard usage.allocated > 50_000_000 else { continue }
            if let known = knownCaches[name] {
                let action: DevAction = known.command.map { .run($0) } ?? .trash(path, note: known.check.map { loc("Con \($0.label) cerrado.", "With \($0.label) closed.") }, closed: known.check.map { [$0] } ?? [])
                result.items.append(.measured("app-caches", known.title, path: path, category: .lowRisk,
                    reason: loc("Datos temporales que la app vuelve a generar.", "Temporary data the app generates again."), regenerate: loc("La app o la herramienta la regenera; la primera vez irá algo más lenta.", "The app or tool regenerates it; the first time will be a bit slower."), action: action, usage: usage))
            } else if name.split(separator: ".").count >= 3 {
                // Nombre con forma de identificador de app (com.empresa.app): se comprueba que esa app esté cerrada.
                let check = ProcessCheck(label: name, pattern: name, bundleID: name)
                result.items.append(.measured("app-caches", loc("Caché de \(name)", "\(name) cache"), path: path, category: .lowRisk,
                    reason: loc("Caché de la app \(name).", "Cache of the \(name) app."), regenerate: loc("La app la regenera; la primera vez irá algo más lenta.", "The app regenerates it; the first time will be a bit slower."),
                    action: .trash(path, note: loc("Con la app cerrada.", "With the app closed."), closed: [check]), usage: usage))
            } else {
                result.items.append(.measured("app-caches", loc("Caché «\(name)»", "“\(name)” cache"), path: path, category: .review,
                    reason: loc("No se sabe qué app o herramienta la usa. Las cachés suelen regenerarse, pero comprueba antes de quién es.", "It's unknown which app or tool uses it. Caches usually regenerate, but check whose it is first."),
                    regenerate: loc("Normalmente se regenera; si es de una herramienta de línea de comandos, volverá a descargar lo que necesite.", "It usually regenerates; if it belongs to a command-line tool, the tool will download what it needs again."),
                    action: .trash(path, note: loc("Cierra antes la app o herramienta que la use.", "Quit the app or tool that uses it first.")), usage: usage))
            }
        }
        result.items.sort { ($0.recoverable ?? 0) > ($1.recoverable ?? 0) }
        if result.detected { result.notes.append(loc("Las cachés de macOS (com.apple.*) no se tocan: las gestiona el sistema.", "macOS caches (com.apple.*) are never touched: the system manages them.")) }
        return result
    }

    static func logs(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path("Library/Logs")
        var result = ProfileResult(id: "logs", name: "Registros", owner: loc("Cada app y macOS", "Each app and macOS"), detected: env.isDirectory(dir))
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
            result.items.append(DevItem(profile: "logs", title: loc("Registros de apps (\(paths.count) \(paths.count == 1 ? "carpeta" : "carpetas"))", "App logs (\(paths.count) \(paths.count == 1 ? "folder" : "folders"))"), path: dir, bytes: total.allocated, recoverable: total.exclusive, category: .lowRisk,
                reason: loc("Historial de actividad y de errores de las apps. Solo sirve para diagnosticar fallos pasados.", "Apps' activity and error history. Only useful to diagnose past failures."),
                regenerate: loc("Las apps crean registros nuevos; se pierde el historial para diagnosticar fallos anteriores.", "Apps create new logs; the history for diagnosing earlier failures is lost."),
                action: .trash(paths, label: loc("\(paths.count) carpetas de ~/Library/Logs", "\(paths.count) folders in ~/Library/Logs"))))
        }
        return result
    }

    static func downloads(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path("Downloads")
        var result = ProfileResult(id: "downloads", name: loc("Instaladores en Descargas", "Installers in Downloads"), owner: "Tú", detected: env.isDirectory(dir))
        guard result.detected, SyncDetector.provider(forDirectoryOrAncestors: URL(fileURLWithPath: dir)) == nil else {
            if result.detected { result.notes.append(loc("Descargas está sincronizada con la nube: no se propone nada.", "Downloads is synced with the cloud: nothing is suggested.")) }
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
            result.items.append(DevItem(profile: "downloads", title: paths.count == 1 ? loc("1 instalador o comprimido de hace más de \(env.inactiveDays) días", "1 installer or archive older than \(env.inactiveDays) days") : loc("\(paths.count) instaladores y comprimidos de hace más de \(env.inactiveDays) días", "\(paths.count) installers and archives older than \(env.inactiveDays) days"), path: dir, bytes: total.allocated, recoverable: total.exclusive, category: .review,
                reason: loc("Archivos .dmg, .pkg, .iso, .xip o .zip descargados hace tiempo. Si ya instalaste la app o extrajiste el contenido, sobran; pero puede ser tu única copia.", ".dmg, .pkg, .iso, .xip or .zip files downloaded a while ago. If you already installed the app or extracted the contents, they're not needed; but this may be your only copy."),
                regenerate: loc("Se pueden volver a descargar si sigue disponible el original.", "They can be downloaded again if the original is still available."),
                action: .trash(paths, label: loc("\(paths.count) archivos de Descargas", "\(paths.count) files in Downloads"))))
        }
        return result
    }

    static func iosBackups(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path("Library/Application Support/MobileSync/Backup")
        var result = ProfileResult(id: "ios-backups", name: loc("Copias de seguridad de iPhone/iPad", "iPhone/iPad backups"), owner: "Finder", detected: env.exists(dir))
        guard result.detected else { return result }
        guard (try? FileManager.default.contentsOfDirectory(atPath: dir)) != nil else {
            result.notes.append(loc("macOS no permite leer las copias de seguridad sin «Acceso total al disco». Puedes gestionarlas desde Finder › tu iPhone › Gestionar copias.", "macOS doesn't allow reading backups without “Full Disk Access”. You can manage them from Finder › your iPhone › Manage Backups."))
            return result
        }
        for name in env.children(dir) {
            let path = "\(dir)/\(name)"
            let usage = DiskUsage.measure(path)
            guard usage.allocated > 100_000_000 else { continue }
            let days = env.days(since: usage.newest).map { loc("Última copia hace \($0) días.", "Last backup \($0) days ago.") } ?? ""
            result.items.append(.measured("ios-backups", loc("Copia de seguridad \(name.prefix(8))…", "Backup \(name.prefix(8))…"), path: path, category: .review,
                reason: loc("Copia de un iPhone o iPad. \(days) Puede ser la única copia de ese dispositivo.", "Backup of an iPhone or iPad. \(days) It may be the only backup of that device."),
                regenerate: loc("No se regenera: haz antes una copia nueva o confirma que tienes copia en iCloud.", "Not regenerated: make a new backup first or confirm you have one in iCloud."), action: .trash(path), usage: usage))
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
