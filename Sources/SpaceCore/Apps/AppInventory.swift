import Foundation
import CoreServices

/// Una app instalada y todo lo que deja en tu Biblioteca. Desinstalar es mover la app y los restos que elijas a la
/// Papelera con un plan (o, si vino de Homebrew, su comando oficial), igual que cualquier otra limpieza.
public struct AppEntry: Codable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable { case appStore, homebrew, user, admin }
    public var id: String { path }
    public let path: String
    public let name: String
    public let bundleID: String?
    public let version: String?
    public let source: Source
    public let caskToken: String?
    /// Última vez que la abriste, según Spotlight (puede faltar).
    public let lastUsed: Date?
    /// Motivo por el que no se ofrece desinstalarla (app de Apple incluida con macOS, la propia Margin).
    public let protectedReason: String?
    public let bundleBytes: Int64?
    /// La app (o su comando de Homebrew) primero y después sus restos en tu Biblioteca. Vacío si está protegida.
    public let items: [DevItem]
    /// Restos fuera de tu carpeta personal (ayudantes con privilegios, demonios): solo se informan.
    public let systemLeftovers: [String]
    public var totalBytes: Int64 { items.reduce(0) { $0 + ($1.bytes ?? 0) } }
}

public struct AppsReport: Codable, Sendable {
    public let date: Date
    public let apps: [AppEntry]
    /// Restos de apps que ya no están instaladas (siempre «revisar»).
    public let orphans: [DevItem]
}

public enum AppInventory {
    public static let profileID = "apps"
    public static let orphanProfileID = "app-leftovers"
    static let ownBundleID = "local.margin.mac"

    /// Carpetas de apps. Con una carpeta personal sintética (pruebas) solo se mira la suya: nunca /Applications.
    public static func applicationDirectories(_ env: DevEnvironment) -> [String] {
        isRealHome(env) ? ["/Applications", env.path("Applications")] : [env.path("Applications")]
    }

    static func isRealHome(_ env: DevEnvironment) -> Bool {
        DevEnvironment.canonical(env.home.path) == DevEnvironment.canonical(FileManager.default.homeDirectoryForCurrentUser.path)
    }

    // MARK: Apps instaladas

    struct Bundle {
        let path: String
        let name: String
        let bundleID: String?
        let version: String?
        let isAppStore: Bool
        let ownedByRoot: Bool
    }

    static func info(_ path: String) -> [String: Any]? {
        NSDictionary(contentsOfFile: "\(path)/Contents/Info.plist") as? [String: Any]
    }

    static func bundles(_ env: DevEnvironment) -> [Bundle] {
        let fm = FileManager.default
        var out: [Bundle] = []
        for dir in applicationDirectories(env) {
            for file in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted() where file.hasSuffix(".app") {
                let path = "\(dir)/\(file)"
                let plist = info(path)
                let name = (plist?["CFBundleDisplayName"] as? String) ?? (plist?["CFBundleName"] as? String) ?? String(file.dropLast(4))
                let owner = (try? fm.attributesOfItem(atPath: path))?[.ownerAccountName] as? String
                out.append(Bundle(path: path, name: name, bundleID: plist?["CFBundleIdentifier"] as? String,
                                  version: plist?["CFBundleShortVersionString"] as? String,
                                  isAppStore: fm.fileExists(atPath: "\(path)/Contents/_MASReceipt"), ownedByRoot: owner == "root"))
            }
        }
        return out
    }

    /// Apps instaladas con `brew install --cask`: nombre del .app → token del cask (consulta de solo lectura).
    static func casks(_ env: DevEnvironment) -> [String: String] {
        guard let brew = env.tool("brew"), let out = env.runner.run(brew, ["info", "--installed", "--cask", "--json=v2"], timeout: 90), out.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(out.output.utf8)) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]] else { return [:] }
        var map: [String: String] = [:]
        for cask in casks {
            guard let token = cask["token"] as? String else { continue }
            for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
                for app in artifact["app"] as? [Any] ?? [] { if let name = app as? String { map[name] = token } }
            }
        }
        return map
    }

    /// Última apertura según Spotlight (`kMDItemLastUsedDate`), sin lanzar procesos.
    static func lastUsed(_ path: String) -> Date? {
        guard let item = MDItemCreateWithURL(nil, URL(fileURLWithPath: path) as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    // MARK: Informe

    public static func report(_ env: DevEnvironment, measure: Bool = true) -> AppsReport {
        let installed = bundles(env)
        let caskMap = casks(env)
        let results = AppBox(count: installed.count)
        DispatchQueue.concurrentPerform(iterations: installed.count) { i in
            results.set(i, entry(installed[i], cask: caskMap[URL(fileURLWithPath: installed[i].path).lastPathComponent], env: env, measure: measure))
        }
        let apps = results.values.compactMap { $0 }
        return AppsReport(date: env.now, apps: apps, orphans: orphans(env, installed: installed, measure: measure))
    }

    /// Perfil para revalidar planes: los mismos elementos (sin medir, que no hace falta para comprobarlos).
    public static func profile(_ env: DevEnvironment) -> ProfileResult {
        var result = ProfileResult(id: profileID, name: loc("Apps", "Apps"), owner: "Finder / Homebrew", detected: true)
        let installed = bundles(env)
        let caskMap = casks(env)
        result.items = installed.flatMap { entry($0, cask: caskMap[URL(fileURLWithPath: $0.path).lastPathComponent], env: env, measure: false).items }
        return result
    }

    public static func orphanProfile(_ env: DevEnvironment) -> ProfileResult {
        var result = ProfileResult(id: orphanProfileID, name: loc("Restos de apps ya borradas", "Leftovers of deleted apps"), owner: "Finder", detected: true)
        result.items = orphans(env, installed: bundles(env), measure: false)
        return result
    }

    static func entry(_ bundle: Bundle, cask: String?, env: DevEnvironment, measure: Bool) -> AppEntry {
        let source: AppEntry.Source = cask != nil ? .homebrew : bundle.isAppStore ? .appStore : bundle.ownedByRoot ? .admin : .user
        let usage = measure ? DiskUsage.measure(bundle.path) : nil
        let used = measure ? lastUsed(bundle.path) : nil
        let protectedReason: String?
        if bundle.bundleID == ownBundleID {
            protectedReason = loc("Es Margin.", "It's Margin.")
        } else if bundle.bundleID?.hasPrefix("com.apple.") == true && !bundle.isAppStore {
            protectedReason = loc("App de Apple incluida con macOS: el sistema la necesita.", "Apple app included with macOS: the system needs it.")
        } else if bundle.bundleID == nil {
            protectedReason = loc("No tiene identificador: no se pueden buscar sus restos con seguridad.", "It has no identifier: its leftovers can't be found safely.")
        } else {
            protectedReason = nil
        }
        guard protectedReason == nil, let bundleID = bundle.bundleID else {
            return AppEntry(path: bundle.path, name: bundle.name, bundleID: bundle.bundleID, version: bundle.version, source: source, caskToken: cask,
                            lastUsed: used, protectedReason: protectedReason, bundleBytes: usage?.allocated, items: [], systemLeftovers: [])
        }
        let check = ProcessCheck(label: bundle.name, pattern: "\(bundle.path)/Contents/MacOS/", bundleID: bundleID)
        var items: [DevItem] = []
        let appItem: DevItem
        if let cask {
            appItem = DevItem(profile: profileID, title: loc("\(bundle.name) (Homebrew)", "\(bundle.name) (Homebrew)"), path: bundle.path,
                              bytes: usage?.allocated, recoverable: usage?.exclusive, category: .review,
                              reason: loc("Instalada con Homebrew: se desinstala con su comando oficial, que retira la app.", "Installed with Homebrew: it's uninstalled with its official command, which removes the app."),
                              regenerate: loc("Se reinstala con `brew install --cask \(cask)`.", "Reinstall it with `brew install --cask \(cask)`."),
                              action: .run(["brew", "uninstall", "--cask", cask], note: loc("Con \(bundle.name) cerrada.", "With \(bundle.name) closed."), closed: [check]), lastUsed: used)
        } else {
            let reason: String
            switch source {
            case .appStore: reason = loc("App de la App Store: puedes volver a descargarla desde la App Store (Comprado). macOS puede pedirte tu contraseña para moverla.", "App Store app: you can download it again from the App Store (Purchased). macOS may ask for your password to move it.")
            case .admin: reason = loc("Instalada por un administrador: Finder te pedirá tu contraseña para moverla a la Papelera.", "Installed by an administrator: Finder will ask for your password to move it to the Trash.")
            default: reason = loc("App instalada por ti.", "App you installed.")
            }
            appItem = DevItem(profile: profileID, title: bundle.name, path: bundle.path, bytes: usage?.allocated, recoverable: usage?.exclusive,
                              category: .review, reason: reason,
                              regenerate: loc("Para volver a usarla, reinstálala desde su web o la App Store.", "To use it again, reinstall it from its website or the App Store."),
                              action: .trash(bundle.path, note: loc("Con \(bundle.name) cerrada.", "With \(bundle.name) closed."), closed: [check]), lastUsed: used)
        }
        items.append(appItem)
        for leftover in leftovers(bundleID: bundleID, name: bundle.name, env: env) {
            let usage = measure && leftover.kind.measurable ? DiskUsage.measure(leftover.path) : nil
            items.append(DevItem(profile: profileID, title: "\(bundle.name) · \(leftover.title)", path: leftover.path,
                                 bytes: usage?.allocated, recoverable: usage?.exclusive, category: leftover.byName ? .review : leftover.kind.category,
                                 reason: leftover.kind.reason + (leftover.byName ? " " + loc("Coincide por el nombre de la app, no por su identificador: comprueba que es suya.", "It matches the app's name, not its identifier: check that it's really its.") : ""),
                                 regenerate: leftover.kind.regenerate, action: .trash(leftover.path, closed: [check])))
        }
        return AppEntry(path: bundle.path, name: bundle.name, bundleID: bundleID, version: bundle.version, source: source, caskToken: cask,
                        lastUsed: used, protectedReason: nil, bundleBytes: usage?.allocated, items: items,
                        systemLeftovers: isRealHome(env) ? systemLeftovers(bundleID: bundleID, name: bundle.name) : [])
    }

    // MARK: Restos

    enum LeftoverKind: CaseIterable {
        case cache, savedState, webData, cookies, logs, support, preferences, container, groupContainer, launchAgent, scripts

        var category: Category {
            switch self {
            case .cache, .savedState, .webData, .logs: return .lowRisk
            default: return .review
            }
        }
        /// macOS protege el contenido de los contenedores de otras apps: no se recorren (pediría permiso).
        var measurable: Bool { self != .container && self != .groupContainer }

        var title: String {
            switch self {
            case .cache: return loc("caché", "cache")
            case .savedState: return loc("estado de ventanas", "window state")
            case .webData: return loc("datos web", "web data")
            case .cookies: return loc("cookies", "cookies")
            case .logs: return loc("registros", "logs")
            case .support: return loc("datos", "data")
            case .preferences: return loc("preferencias", "preferences")
            case .container: return loc("contenedor", "container")
            case .groupContainer: return loc("contenedor compartido", "shared container")
            case .launchAgent: return loc("agente de inicio", "launch agent")
            case .scripts: return loc("scripts", "scripts")
            }
        }
        var reason: String {
            switch self {
            case .cache: return loc("Caché de la app: se regenera.", "App cache: it regenerates.")
            case .savedState: return loc("Ventanas abiertas que macOS guarda para restaurarlas.", "Open windows macOS saves to restore them.")
            case .webData: return loc("Caché y almacenamiento del navegador interno de la app.", "Cache and storage of the app's internal browser.")
            case .cookies: return loc("Cookies de la app: al quitarlas se cierran las sesiones que tengas iniciadas en ella.", "App cookies: removing them signs you out of sessions in it.")
            case .logs: return loc("Registros de la app.", "App logs.")
            case .support: return loc("Datos de la app: pueden incluir documentos, bases de datos o ajustes que solo están aquí.", "App data: it may hold documents, databases or settings that only exist here.")
            case .preferences: return loc("Preferencias de la app.", "App preferences.")
            case .container: return loc("Contenedor de la app con sus datos y documentos internos. macOS protege su contenido: no se mide.", "App container with its internal data and documents. macOS protects its contents: it isn't measured.")
            case .groupContainer: return loc("Datos que comparten las apps del mismo desarrollador; si tienes otra app suya, puede necesitarlos. No se mide.", "Data shared by apps from the same developer; another app of theirs may need it. It isn't measured.")
            case .launchAgent: return loc("Agente de inicio: ejecuta parte de la app en segundo plano (actualizaciones, ayudantes). Tras moverlo sigue activo hasta que cierres sesión.", "Launch agent: it runs part of the app in the background (updates, helpers). After moving it, it stays active until you log out.")
            case .scripts: return loc("Scripts de la app (Application Scripts).", "App scripts (Application Scripts).")
            }
        }
        var regenerate: String {
            switch self {
            case .cache, .savedState, .logs: return loc("La app lo vuelve a crear si la sigues usando.", "The app creates it again if you keep using it.")
            case .webData, .cookies: return loc("Tendrás que volver a iniciar sesión dentro de la app.", "You'll have to sign in again inside the app.")
            case .support, .container, .groupContainer: return loc("No se regenera: si reinstalas la app, empezará de cero.", "Not regenerated: if you reinstall the app, it starts from scratch.")
            case .preferences: return loc("Si la reinstalas, volverá a su configuración inicial.", "If you reinstall it, it goes back to its default settings.")
            case .launchAgent, .scripts: return loc("La app lo vuelve a instalar si la reinstalas.", "The app installs it again if you reinstall it.")
            }
        }
    }

    struct Leftover {
        let path: String
        let kind: LeftoverKind
        var byName = false
        /// Distingue restos del mismo tipo (por ejemplo, datos web de HTTPStorages y de WebKit).
        var detail: String? = nil
        var title: String { detail.map { "\(kind.title) (\($0))" } ?? kind.title }
    }

    /// Restos en tu Biblioteca por identificador exacto (y por nombre exacto solo en Application Support, como «revisar»).
    static func leftovers(bundleID id: String, name: String, env: DevEnvironment) -> [Leftover] {
        let fm = FileManager.default
        let lib = env.path("Library")
        var found: [Leftover] = []
        func add(_ relative: String, _ kind: LeftoverKind, byName: Bool = false, detail: String? = nil) {
            let path = "\(lib)/\(relative)"
            if fm.fileExists(atPath: path), !found.contains(where: { $0.path == path }) { found.append(Leftover(path: path, kind: kind, byName: byName, detail: detail)) }
        }
        add("Caches/\(id)", .cache)
        add("Caches/\(id).ShipIt", .cache, detail: loc("actualizador", "updater"))
        add("Saved Application State/\(id).savedState", .savedState)
        add("HTTPStorages/\(id)", .webData, detail: "HTTPStorages")
        add("HTTPStorages/\(id).binarycookies", .cookies, detail: "HTTPStorages")
        add("WebKit/\(id)", .webData, detail: "WebKit")
        add("Cookies/\(id).binarycookies", .cookies)
        add("Logs/\(id)", .logs)
        add("Application Support/\(id)", .support, detail: "Application Support")
        add("Preferences/\(id).plist", .preferences)
        add("Containers/\(id)", .container)
        add("Application Scripts/\(id)", .scripts)
        for file in (try? fm.contentsOfDirectory(atPath: "\(lib)/Preferences/ByHost")) ?? [] where file.hasPrefix(id + ".") && file.hasSuffix(".plist") {
            add("Preferences/ByHost/\(file)", .preferences, detail: loc("de este Mac", "this Mac"))
        }
        for folder in (try? fm.contentsOfDirectory(atPath: "\(lib)/Group Containers")) ?? [] where folder == "group.\(id)" || folder.hasSuffix(".\(id)") {
            add("Group Containers/\(folder)", .groupContainer, detail: folder)
        }
        for file in (try? fm.contentsOfDirectory(atPath: "\(lib)/LaunchAgents")) ?? [] where file.hasPrefix(id) && file.hasSuffix(".plist") {
            add("LaunchAgents/\(file)", .launchAgent, detail: String(file.dropLast(".plist".count)))
        }
        // Por nombre: solo nombres propios (no genéricos) y nunca carpetas de Apple.
        if name.count >= 4, !["Google", "Microsoft", "Adobe", "Apple", "Java", "Electron"].contains(name) {
            add("Application Support/\(name)", .support, byName: true, detail: loc("Application Support, por nombre", "Application Support, by name"))
        }
        return found
    }

    /// Restos fuera de tu carpeta personal: necesitan permisos de administrador y Margin no los toca.
    static func systemLeftovers(bundleID id: String, name: String) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for dir in ["/Library/LaunchDaemons", "/Library/LaunchAgents", "/Library/PrivilegedHelperTools"] {
            for file in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where file.hasPrefix(id) { out.append("\(dir)/\(file)") }
        }
        for candidate in ["/Library/Application Support/\(id)", "/Library/Application Support/\(name)"] where fm.fileExists(atPath: candidate) && name.count >= 4 {
            out.append(candidate)
        }
        return out
    }

    // MARK: Restos de apps ya borradas

    /// Identificadores de todas las apps del Mac (Spotlight), no solo de /Applications: así una app instalada en otra
    /// carpeta no hace pasar sus datos por restos.
    static func knownBundleIDs(_ env: DevEnvironment, installed: [Bundle]) -> Set<String> {
        var ids = Set(installed.compactMap(\.bundleID))
        if isRealHome(env), let mdfind = env.tool("mdfind", extra: ["/usr/bin"]),
           let out = env.runner.run(mdfind, ["kMDItemContentType == 'com.apple.application-bundle'"], timeout: 60), out.status == 0 {
            for path in out.output.split(separator: "\n") {
                if let id = info(String(path))?["CFBundleIdentifier"] as? String { ids.insert(id) }
            }
        }
        return ids
    }

    static func isBundleLike(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+){2,}$"#, options: .regularExpression) != nil && !name.hasPrefix("com.apple.")
    }

    static func related(_ candidate: String, to known: Set<String>) -> Bool {
        let lower = candidate.lowercased()
        return known.contains { id in
            let other = id.lowercased()
            return lower == other || lower.hasPrefix(other + ".") || other.hasPrefix(lower + ".")
        }
    }

    static func orphans(_ env: DevEnvironment, installed: [Bundle], measure: Bool) -> [DevItem] {
        let fm = FileManager.default
        let lib = env.path("Library")
        let known = knownBundleIDs(env, installed: installed)
        var groups: [String: [String]] = [:]
        let places: [(dir: String, suffix: String)] = [("Caches", ""), ("Application Support", ""), ("HTTPStorages", ""), ("WebKit", ""),
                                                       ("Saved Application State", ".savedState"), ("Logs", ""), ("Preferences", ".plist")]
        for place in places {
            for name in (try? fm.contentsOfDirectory(atPath: "\(lib)/\(place.dir)")) ?? [] where place.suffix.isEmpty || name.hasSuffix(place.suffix) {
                let id = place.suffix.isEmpty ? name : String(name.dropLast(place.suffix.count))
                guard isBundleLike(id), !related(id, to: known) else { continue }
                groups[id, default: []].append("\(lib)/\(place.dir)/\(name)")
            }
        }
        var items: [DevItem] = []
        for (id, paths) in groups {
            let sorted = paths.sorted()
            var total = Usage()
            if measure {
                for path in sorted { let u = DiskUsage.measure(path); total.allocated += u.allocated; total.exclusive += u.exclusive; if let n = u.newest { total.newest = max(total.newest ?? n, n) } }
                // Solo lo que merece la pena: las preferencias sueltas ocupan unos pocos KB.
                guard total.allocated >= 1_000_000 else { continue }
            }
            let places = Set(sorted.map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent }).sorted().joined(separator: ", ")
            items.append(DevItem(profile: orphanProfileID, title: id, path: nil, bytes: measure ? total.allocated : nil, recoverable: measure ? total.exclusive : nil,
                                 category: .review,
                                 reason: loc("Ninguna app instalada usa el identificador \(id) (\(places)): suelen ser restos de una app que ya borraste. Algunas herramientas sin app guardan datos así: comprueba el nombre antes.", "No installed app uses the identifier \(id) (\(places)): it's usually what's left of an app you already deleted. Some tools without an app store data like this: check the name first."),
                                 regenerate: loc("Si vuelves a instalar esa app, empezará de cero.", "If you install that app again, it starts from scratch."),
                                 action: .trash(sorted, label: id), lastUsed: total.newest, key: "orphan:\(id)"))
        }
        return items.sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
    }
}

private final class AppBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AppEntry?]
    init(count: Int) { storage = Array(repeating: nil, count: count) }
    func set(_ index: Int, _ value: AppEntry) { lock.withLock { storage[index] = value } }
    var values: [AppEntry?] { lock.withLock { storage } }
}
