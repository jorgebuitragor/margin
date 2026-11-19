import Foundation

/// Catálogo versionado de ubicaciones regenerables conocidas. Cada perfil propone el comando oficial de la herramienta
/// dueña cuando existe y explica qué cuesta regenerar. En la 0.3 nada se ejecuta: solo se mide y se propone.
public enum DevProfiles {
    public static let version = 1

    public static let ids = ["android-sdk", "android-avd", "ios-simulators", "xcode", "project-artifacts", "js-packages", "gradle-maven", "docker", "homebrew", "node-versions", "claude-desktop", "vscode", "app-caches", "logs", "downloads", "ios-backups", "whatsapp"]

    /// Recalcula un solo perfil (para revalidar un plan antes de actuar).
    public static func profile(_ id: String, _ env: DevEnvironment) -> ProfileResult? {
        let index = ["android-sdk", "project-artifacts", "gradle-maven"].contains(id) ? ProjectIndex.build(env) : ProjectIndex()
        switch id {
        case AppInventory.profileID: return AppInventory.profile(env)
        case AppInventory.orphanProfileID: return AppInventory.orphanProfile(env)
        case "android-sdk": return androidSDK(env, index)
        case "android-avd": return androidEmulators(env)
        case "ios-simulators": return iosSimulators(env)
        case "xcode": return xcode(env)
        case "project-artifacts": return projectArtifacts(env, index)
        case "js-packages": return jsPackages(env)
        case "gradle-maven": return gradleMaven(env, index)
        case "docker": return docker(env)
        case "homebrew": return homebrew(env)
        case "node-versions": return nodeVersions(env)
        case "claude-desktop": return claudeDesktop(env)
        case "vscode": return vscode(env)
        case "app-caches": return appCaches(env)
        case "logs": return logs(env)
        case "downloads": return downloads(env)
        case "ios-backups": return iosBackups(env)
        case "whatsapp": return whatsapp(env)
        default: return nil
        }
    }

    public static func report(_ env: DevEnvironment = DevEnvironment()) -> DevReport {
        let timing = DevEnvironment.testSetting("TIMING") != nil
        let start = Date()
        let index = ProjectIndex.build(env)
        if timing { FileHandle.standardError.write(Data(String(format: "índice de proyectos: %.1f s\n", Date().timeIntervalSince(start)).utf8)) }
        let builders: [@Sendable () -> ProfileResult] = [
            { androidSDK(env, index) }, { androidEmulators(env) }, { iosSimulators(env) }, { xcode(env) },
            { projectArtifacts(env, index) }, { jsPackages(env) }, { gradleMaven(env, index) }, { docker(env) },
            { homebrew(env) }, { nodeVersions(env) }, { claudeDesktop(env) }, { vscode(env) },
            { appCaches(env) }, { logs(env) }, { downloads(env) }, { iosBackups(env) }, { whatsapp(env) }
        ]
        // Los perfiles son independientes y casi todo es E/S: se miden en paralelo, conservando el orden.
        let box = ResultBox(count: builders.count)
        DispatchQueue.concurrentPerform(iterations: builders.count) { i in
            let t0 = Date()
            let result = builders[i]()
            // MARGIN_TIMING=1: tiempo de cada perfil por la salida de error (diagnóstico de lentitud).
            if timing { FileHandle.standardError.write(Data(String(format: "%@: %.1f s\n", result.id, Date().timeIntervalSince(t0)).utf8)) }
            box.set(i, result)
        }
        let profiles = box.values
        return DevReport(date: env.now, profiles: profiles, projectRoots: env.projectRoots.map(\.path), inactiveDays: env.inactiveDays)
    }

    // MARK: Android

    static func androidSDK(_ env: DevEnvironment, _ index: ProjectIndex) -> ProfileResult {
        let sdk = env.path("Library/Android/sdk")
        var result = ProfileResult(id: "android-sdk", name: loc("SDK de Android", "Android SDK"), owner: "sdkmanager", detected: env.isDirectory(sdk))
        guard result.detected else { return result }
        let sdkmanager = "\(sdk)/cmdline-tools/latest/bin/sdkmanager"
        if env.exists(sdkmanager) {
            result.notes.append(loc("sdkmanager está en \(sdkmanager) (añádelo al PATH o usa la ruta completa).", "sdkmanager is at \(sdkmanager) (add it to PATH or use the full path)."))
        } else {
            result.notes.append(loc("No se encontró sdkmanager en cmdline-tools/latest; usa el SDK Manager de Android Studio.", "sdkmanager wasn't found in cmdline-tools/latest; use Android Studio's SDK Manager."))
        }

        // Imágenes de sistema que usan los emuladores.
        var usedImages: [String: [String]] = [:]
        let avdDir = env.path(".android/avd")
        for avd in env.children(avdDir) where avd.hasSuffix(".avd") {
            if let config = env.read("\(avdDir)/\(avd)/config.ini"),
               let sysdir = ProjectIndex.capture(#"image\.sysdir\.1\s*=\s*(\S+)"#, in: config) {
                usedImages[sysdir.trimmingCharacters(in: CharacterSet(charactersIn: "/")), default: []].append(String(avd.dropLast(4)))
            }
        }
        let images = "\(sdk)/system-images"
        for api in env.children(images) {
            for tag in env.children("\(images)/\(api)") {
                for abi in env.children("\(images)/\(api)/\(tag)") {
                    let rel = "system-images/\(api)/\(tag)/\(abi)"
                    let package = "system-images;\(api);\(tag);\(abi)"
                    if let avds = usedImages[rel] {
                        result.items.append(.measured("android-sdk", loc("Imagen \(api) \(tag) \(abi)", "Image \(api) \(tag) \(abi)"), path: "\(sdk)/\(rel)", category: .protected,
                            reason: loc("La usa el emulador \(avds.joined(separator: ", ")).", "Used by the emulator \(avds.joined(separator: ", "))."), regenerate: loc("Sin ella el emulador no arranca.", "Without it the emulator won't start."), action: nil))
                    } else {
                        result.items.append(.measured("android-sdk", loc("Imagen \(api) \(tag) \(abi)", "Image \(api) \(tag) \(abi)"), path: "\(sdk)/\(rel)", category: .lowRisk,
                            reason: loc("Ningún emulador de ~/.android/avd usa esta imagen.", "No emulator in ~/.android/avd uses this image."), regenerate: loc("Se vuelve a descargar con sdkmanager si creas un emulador con ella.", "sdkmanager downloads it again if you create an emulator with it."),
                            action: .run(["sdkmanager", "--uninstall", package])))
                    }
                }
            }
        }
        versioned(&result, dir: "\(sdk)/ndk", label: "NDK", package: "ndk", refs: index.ndkVersions, keepNewest: false)
        versioned(&result, dir: "\(sdk)/build-tools", label: "Build-tools", package: "build-tools", refs: index.buildToolsVersions, keepNewest: true)
        if result.items.contains(where: { $0.category == .review }) {
            result.notes.append(loc("Las versiones que ningún proyecto pide se marcan para revisar, no como bajo riesgo: solo se revisaron \(env.projectRoots.map { $0.lastPathComponent }.joined(separator: ", ")).", "Versions no project asks for are marked for review, not low risk: only \(env.projectRoots.map { $0.lastPathComponent }.joined(separator: ", ")) were checked."))
        }
        return result
    }

    private static func versioned(_ result: inout ProfileResult, dir: String, label: String, package: String, refs: [String: [String]], keepNewest: Bool) {
        let versions = DevEnvironmentHelpers.sortedVersions(dir)
        for version in versions {
            let path = "\(dir)/\(version)"
            if let projects = refs[version] {
                result.items.append(.measured(result.id, "\(label) \(version)", path: path, category: .protected,
                    reason: loc("Lo pide \(DevEnvironmentHelpers.names(projects)).", "Required by \(DevEnvironmentHelpers.names(projects))."), regenerate: loc("Esos proyectos no compilarían sin él.", "Those projects wouldn't build without it."), action: nil))
            } else if keepNewest && version == versions.last {
                result.items.append(.measured(result.id, "\(label) \(version)", path: path, category: .protected,
                    reason: loc("Versión más reciente instalada; se conserva.", "Newest installed version; kept."), regenerate: loc("Gradle la usa por defecto.", "Gradle uses it by default."), action: nil))
            } else {
                result.items.append(.measured(result.id, "\(label) \(version)", path: path, category: .review,
                    reason: loc("Ningún proyecto revisado lo pide explícitamente, pero puede usarlo uno de otra carpeta o una dependencia.", "No checked project asks for it explicitly, but a project in another folder or a dependency may use it."),
                    regenerate: loc("Si un proyecto lo necesita, Gradle o sdkmanager lo vuelven a descargar.", "If a project needs it, Gradle or sdkmanager downloads it again."),
                    action: .run(["sdkmanager", "--uninstall", "\(package);\(version)"])))
            }
        }
    }

    static func androidEmulators(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path(".android/avd")
        var result = ProfileResult(id: "android-avd", name: loc("Emuladores de Android", "Android emulators"), owner: "avdmanager", detected: env.isDirectory(dir))
        for avd in env.children(dir) where avd.hasSuffix(".avd") {
            let name = String(avd.dropLast(4))
            let path = "\(dir)/\(avd)"
            let usage = DiskUsage.measure(path)
            let days = env.days(since: usage.newest).map { loc("Último uso hace \($0) días.", "Last used \($0) days ago.") } ?? ""
            let snapshots = "\(path)/snapshots"
            var snapshotBytes: Int64 = 0
            if env.isDirectory(snapshots) {
                let snap = DiskUsage.measure(snapshots)
                snapshotBytes = snap.exclusive
                if snap.allocated > 50_000_000 {
                    result.items.append(.measured("android-avd", loc("Instantáneas de \(name)", "Snapshots of \(name)"), path: snapshots, category: .lowRisk,
                        reason: loc("Instantáneas de arranque rápido del emulador.", "Quick-boot snapshots of the emulator."), regenerate: loc("El próximo arranque será en frío (más lento); el emulador crea una nueva al cerrarse.", "The next boot will be a cold boot (slower); the emulator creates a new one when it closes."),
                        action: .trash(snapshots, note: loc("Con el emulador apagado.", "With the emulator off."), closed: [.emulator]), usage: snap))
                }
            }
            var whole = usage
            whole.exclusive -= snapshotBytes
            result.items.append(.measured("android-avd", loc("Emulador \(name)", "Emulator \(name)"), path: path, category: .review,
                reason: loc("Emulador con sus apps y datos instalados. \(days)", "Emulator with its installed apps and data. \(days)"), regenerate: loc("Borrarlo pierde lo instalado en él; se puede recrear desde Android Studio (Device Manager).", "Deleting it loses what's installed on it; you can recreate it from Android Studio (Device Manager)."),
                action: .run(["avdmanager", "delete", "avd", "-n", name], note: loc("Con el emulador apagado.", "With the emulator off."), closed: [.emulator]), usage: whole))
        }
        return result
    }

    // MARK: Apple

    static func iosSimulators(_ env: DevEnvironment) -> ProfileResult {
        let base = env.path("Library/Developer/CoreSimulator")
        var result = ProfileResult(id: "ios-simulators", name: loc("Simuladores de iOS", "iOS simulators"), owner: "xcrun simctl", detected: env.isDirectory(base))
        guard result.detected else { return result }
        let xcrun = env.tool("xcrun", extra: ["/usr/bin"])
        if let xcrun, let list = env.runner.run(xcrun, ["simctl", "list", "devices", "-j"], timeout: 30), list.status == 0,
           let json = try? JSONSerialization.jsonObject(with: Data(list.output.utf8)) as? [String: Any],
           let devices = json["devices"] as? [String: [[String: Any]]] {
            var unavailable: [String] = []
            for (runtime, list) in devices {
                // «com.apple.CoreSimulator.SimRuntime.iOS-26-1» → «iOS 26.1»
                let raw = runtime.split(separator: ".").last.map(String.init) ?? runtime
                let pieces = raw.split(separator: "-")
                let version = pieces.count > 1 ? "\(pieces[0]) \(pieces.dropFirst().joined(separator: "."))" : raw
                for device in list {
                    guard let udid = device["udid"] as? String, let name = device["name"] as? String else { continue }
                    let path = (device["dataPath"] as? String).map { URL(fileURLWithPath: $0).deletingLastPathComponent().path } ?? "\(base)/Devices/\(udid)"
                    if device["isAvailable"] as? Bool == false {
                        unavailable.append(path)
                        continue
                    }
                    result.items.append(.measured("ios-simulators", "\(name) (\(version))", path: path, category: .review,
                        reason: loc("Simulador disponible con sus apps y datos.", "Available simulator with its apps and data."), regenerate: loc("Borrarlo pierde lo instalado; Xcode lo recrea vacío. `erase` lo vacía sin borrarlo.", "Deleting it loses what's installed; Xcode recreates it empty. `erase` empties it without deleting it."),
                        action: .run(["xcrun", "simctl", "delete", udid], note: loc("Alternativa: xcrun simctl erase \(udid)", "Alternative: xcrun simctl erase \(udid)"), closed: [.simulator])))
                }
            }
            if !unavailable.isEmpty {
                var total = Usage()
                for path in unavailable { let u = DiskUsage.measure(path); total.allocated += u.allocated; total.exclusive += u.exclusive }
                result.items.append(DevItem(profile: "ios-simulators", title: loc("\(unavailable.count) simuladores no disponibles", "\(unavailable.count) unavailable simulators"), path: nil, bytes: total.allocated, recoverable: total.exclusive, category: .lowRisk,
                    reason: loc("Su runtime ya no está instalado: no se pueden arrancar.", "Its runtime is no longer installed: they can't boot."), regenerate: loc("Ninguno.", "Nothing."), action: .run(["xcrun", "simctl", "delete", "unavailable"]), key: "unavailable-simulators"))
            }
            if let runtimes = env.runner.run(xcrun, ["simctl", "runtime", "list", "-j"], timeout: 30), runtimes.status == 0,
               let json = try? JSONSerialization.jsonObject(with: Data(runtimes.output.utf8)) as? [String: [String: Any]] {
                let iso = ISO8601DateFormatter()
                for runtime in json.values {
                    guard let id = runtime["identifier"] as? String, let size = (runtime["sizeBytes"] as? NSNumber)?.int64Value else { continue }
                    let version = runtime["version"] as? String ?? "?"
                    let lastUsed = (runtime["lastUsedAt"] as? String).flatMap { iso.date(from: $0) }
                    let days = env.days(since: lastUsed)
                    let inUse = days.map { $0 < env.inactiveDays } ?? false
                    let deletable = runtime["deletable"] as? Bool ?? false
                    result.items.append(DevItem(profile: "ios-simulators", title: loc("Runtime iOS \(version)", "iOS runtime \(version)"), path: runtime["path"] as? String, bytes: size, recoverable: deletable ? size : 0,
                        category: !deletable || inUse ? .protected : .review,
                        reason: !deletable ? loc("El sistema no permite borrarlo.", "The system doesn't allow deleting it.") : inUse ? loc("Usado hace \(days ?? 0) días.", "Used \(days ?? 0) days ago.") : loc("Sin uso en \(days.map { "\($0)" } ?? "?") días. Vive fuera de tu carpeta personal (lo gestiona macOS).", "Unused for \(days.map { "\($0)" } ?? "?") days. It lives outside your home folder (macOS manages it)."),
                        regenerate: loc("Se vuelve a descargar desde Xcode › Settings › Components (varios GB).", "Downloaded again from Xcode › Settings › Components (several GB)."),
                        action: deletable ? .run(["xcrun", "simctl", "runtime", "delete", id], closed: [.simulator]) : nil, lastUsed: lastUsed))
                }
            }
        } else {
            result.notes.append(loc("No se pudo consultar `xcrun simctl` (¿Xcode no instalado?). Solo se mide la carpeta.", "Couldn't query `xcrun simctl` (is Xcode installed?). Only the folder is measured."))
        }
        let caches = "\(base)/Caches"
        if env.isDirectory(caches), case let usage = DiskUsage.measure(caches), usage.allocated > 10_000_000 {
            result.items.append(.measured("ios-simulators", loc("Cachés de simuladores", "Simulator caches"), path: caches, category: .lowRisk,
                reason: loc("Cachés (por ejemplo, de dyld) que CoreSimulator regenera.", "Caches (for example, dyld's) that CoreSimulator regenerates."), regenerate: loc("El primer arranque de cada simulador será más lento.", "Each simulator's first boot will be slower."), action: .trash(caches, note: loc("Con los simuladores apagados.", "With the simulators shut down."), closed: [.simulator]), usage: usage))
        }
        return result
    }

    static func xcode(_ env: DevEnvironment) -> ProfileResult {
        let base = env.path("Library/Developer/Xcode")
        var result = ProfileResult(id: "xcode", name: "Xcode", owner: "Xcode", detected: env.isDirectory(base))
        guard result.detected else { return result }
        let derived = "\(base)/DerivedData"
        if env.isDirectory(derived) {
            let u = DiskUsage.measure(derived)
            if u.allocated > 1_000_000 {
                result.items.append(.measured("xcode", "DerivedData", path: derived, category: .lowRisk, reason: loc("Productos intermedios de compilación e índices.", "Intermediate build products and indexes."),
                    regenerate: loc("Xcode lo regenera; la siguiente compilación e indexado serán más lentos.", "Xcode regenerates it; the next build and indexing will be slower."), action: .trash(derived, note: loc("Con Xcode cerrado.", "With Xcode closed."), closed: [.xcode]), usage: u))
            }
        }
        let support = "\(base)/iOS DeviceSupport"
        let versions = DevEnvironmentHelpers.sortedDeviceSupport(support)
        for (i, version) in versions.enumerated() {
            let newest = i == versions.count - 1
            result.items.append(.measured("xcode", loc("Soporte de dispositivo \(version)", "Device support \(version)"), path: "\(support)/\(version)", category: newest ? .review : .lowRisk,
                reason: newest ? loc("Versión más reciente: probablemente la de tu iPhone actual.", "Newest version: probably your current iPhone's.") : loc("Símbolos de una versión de iOS anterior a la más reciente copiada.", "Symbols for an iOS version older than the newest one copied."),
                regenerate: loc("Xcode lo vuelve a copiar al conectar un dispositivo con esa versión (tarda varios minutos).", "Xcode copies it again when you connect a device with that version (takes several minutes)."), action: .trash("\(support)/\(version)")))
        }
        let archives = "\(base)/Archives"
        if env.isDirectory(archives), case let usage = DiskUsage.measure(archives), usage.allocated > 1_000_000 {
            result.items.append(.measured("xcode", loc("Archivos de publicación (Archives)", "Release archives (Archives)"), path: archives, category: .review,
                reason: loc("Builds publicadas y sus símbolos.", "Published builds and their symbols."), regenerate: loc("No se regeneran: sin ellos no se pueden simbolizar fallos de esas versiones.", "Not regenerated: without them, crashes from those versions can't be symbolicated."), action: .trash(archives), usage: usage))
        }
        let cache = env.path("Library/Caches/com.apple.dt.Xcode")
        if env.isDirectory(cache), case let usage = DiskUsage.measure(cache), usage.allocated > 10_000_000 {
            result.items.append(.measured("xcode", loc("Caché de Xcode", "Xcode cache"), path: cache, category: .lowRisk, reason: loc("Caché de la app.", "App cache."), regenerate: loc("Xcode la regenera.", "Xcode regenerates it."), action: .trash(cache, note: loc("Con Xcode cerrado.", "With Xcode closed."), closed: [.xcode]), usage: usage))
        }
        return result
    }

    // MARK: Proyectos

    static func projectArtifacts(_ env: DevEnvironment, _ index: ProjectIndex) -> ProfileResult {
        var result = ProfileResult(id: "project-artifacts", name: loc("Artefactos de proyectos", "Project artifacts"), owner: loc("Gestor de cada proyecto", "Each project's tooling"), detected: !index.artifacts.isEmpty)
        var activity: [String: Date?] = [:]
        for artifact in index.artifacts {
            let repo = index.repositories[artifact.project]
            let key = repo ?? artifact.project
            if activity[key] == nil {
                let commit = repo.flatMap { ProjectIndex.lastCommit($0, env: env) }
                let touched = DevEnvironmentHelpers.recentTopLevelChange(artifact.project, ignoring: ProjectIndex.skip)
                activity[key] = [commit, touched].compactMap { $0 }.max()
            }
        }
        // Medir node_modules, build… es lo más lento del análisis. Se mide en paralelo con una cola propia: un
        // concurrentPerform dentro del de los perfiles se ejecutaría en serie.
        let usages = UsageBox(count: index.artifacts.count)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "margin.artefactos", qos: .userInitiated, attributes: .concurrent)
        for (i, artifact) in index.artifacts.enumerated() {
            queue.async(group: group) { usages.set(i, DiskUsage.measure(artifact.path)) }
        }
        group.wait()
        for (position, artifact) in index.artifacts.enumerated() {
            let repo = index.repositories[artifact.project]
            let key = repo ?? artifact.project
            let last = activity[key] ?? nil
            let days = env.days(since: last)
            let inactive = days.map { $0 >= env.inactiveDays } ?? false
            let projectName = DevEnvironmentHelpers.relative(artifact.project, env)
            var reason = loc("\(artifact.kind) de \(projectName). ", "\(artifact.kind) of \(projectName). ")
            reason += days.map { loc("Último cambio del proyecto hace \($0) días.", "Project last changed \($0) days ago.") } ?? loc("No se pudo determinar la actividad del proyecto.", "Couldn't determine the project's activity.")
            if artifact.sharedWithStore { reason += loc(" pnpm comparte estos archivos con su store: lo recuperable real es menor y se completa con `pnpm store prune`.", " pnpm shares these files with its store: the real recoverable space is smaller and is completed with `pnpm store prune`.") }
            result.items.append(.measured("project-artifacts", "\(projectName) · \(URL(fileURLWithPath: artifact.path).lastPathComponent)", path: artifact.path,
                category: inactive ? .lowRisk : .protected,
                reason: inactive ? reason : loc("Proyecto activo: no se propone. ", "Active project: not suggested. ") + reason,
                regenerate: artifact.regenerate, action: inactive ? .trash(artifact.path) : nil, lastUsed: last, usage: usages.values[position]))
        }
        let small = result.items.filter { ($0.bytes ?? 0) < 1_000_000 }
        result.items.removeAll { ($0.bytes ?? 0) < 1_000_000 }
        result.items.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        result.notes.append(loc("Inactivo = sin commits ni cambios en los archivos del proyecto en \(env.inactiveDays) días o más.", "Inactive = no commits or changes in the project's files for \(env.inactiveDays) days or more."))
        if !small.isEmpty { result.notes.append(loc("\(small.count) artefactos menores de 1 MB no se muestran.", "\(small.count) artifacts under 1 MB are not shown.")) }
        return result
    }

    // MARK: Paquetes y compiladores

    static func jsPackages(_ env: DevEnvironment) -> ProfileResult {
        var result = ProfileResult(id: "js-packages", name: loc("Cachés de paquetes JavaScript", "JavaScript package caches"), owner: "pnpm / npm / yarn", detected: false)
        pnpmStores(env, into: &result)
        let npm = env.path(".npm/_cacache")
        if env.isDirectory(npm), case let usage = DiskUsage.measure(npm), usage.allocated > 10_000_000 {
            result.detected = true
            result.items.append(.measured("js-packages", loc("Caché de npm", "npm cache"), path: npm, category: .lowRisk, reason: loc("Copias de paquetes descargados por npm.", "Copies of packages downloaded by npm."),
                regenerate: loc("npm los vuelve a descargar al instalar.", "npm downloads them again when installing."), action: .run(["npm", "cache", "clean", "--force"]), usage: usage))
        }
        for (path, title, command) in [(env.path("Library/Caches/Yarn"), loc("Caché de Yarn", "Yarn cache"), ["yarn", "cache", "clean"]), (env.path(".bun/install/cache"), loc("Caché de Bun", "Bun cache"), ["bun", "pm", "cache", "rm"])] {
            if env.isDirectory(path), case let usage = DiskUsage.measure(path), usage.allocated > 10_000_000 {
                result.detected = true
                result.items.append(.measured("js-packages", title, path: path, category: .lowRisk, reason: loc("Paquetes descargados.", "Downloaded packages."), regenerate: loc("Se vuelven a descargar al instalar.", "Downloaded again when installing."), action: .run(command), usage: usage))
            }
        }
        return result
    }

    /// Un elemento por store de pnpm. Cada versión de pnpm usa su propio store (`store/v10`, `store/v11`…) y
    /// `pnpm store prune` solo limpia el suyo; un store que ninguna versión instalada usa se propone retirar entero.
    static func pnpmStores(_ env: DevEnvironment, into result: inout ProfileResult) {
        let root = env.path("Library/pnpm/store")
        var owners: [String: [String]] = [:]   // store → binarios de pnpm que lo usan
        let binaries = env.tools("pnpm")
        var answered = 0
        for binary in binaries {
            guard let out = env.runner.run(binary, ["store", "path"], timeout: 15), out.status == 0 else { continue }
            let path = out.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard env.isDirectory(path) else { continue }
            answered += 1
            owners[DevEnvironment.canonical(path), default: []].append(binary)
        }
        func label(_ binary: String) -> String {
            let parts = binary.split(separator: "/")
            if let i = parts.firstIndex(of: "node"), i + 1 < parts.count, parts.contains(".nvm") { return loc("pnpm de Node \(parts[i + 1])", "pnpm from Node \(parts[i + 1])") }
            return loc("pnpm en \(URL(fileURLWithPath: binary).deletingLastPathComponent().path)", "pnpm at \(URL(fileURLWithPath: binary).deletingLastPathComponent().path)")
        }
        for (store, users) in owners.sorted(by: { $0.key < $1.key }) {
            result.detected = true
            let name = URL(fileURLWithPath: store).lastPathComponent
            result.items.append(.measured("js-packages", loc("Store de pnpm \(name)", "pnpm store \(name)"), path: store, category: .lowRisk,
                reason: loc("Paquetes descargados por pnpm; lo usa \(users.map(label).joined(separator: " y ")). Lo recuperable estimado son los archivos que ningún node_modules enlaza.", "Packages downloaded by pnpm; used by \(users.map(label).joined(separator: " and ")). The estimated recoverable space is the files no node_modules links to."),
                regenerate: loc("pnpm vuelve a descargar los paquetes que pida un proyecto.", "pnpm downloads again the packages a project asks for."), action: .run([users[0], "store", "prune"])))
        }
        // Stores que ninguna versión instalada de pnpm declara como suyo.
        let candidates = env.isDirectory(root) ? env.children(root).map { "\(root)/\($0)" }.filter { env.isDirectory($0) } : []
        for store in candidates where owners[DevEnvironment.canonical(store)] == nil {
            guard DiskUsage.measure(store).allocated > 1_000_000 else { continue }
            result.detected = true
            let name = URL(fileURLWithPath: store).lastPathComponent
            let known = answered > 0
            result.items.append(.measured("js-packages", loc("Store de pnpm \(name) sin uso", "Unused pnpm store \(name)"), path: store, category: known ? .lowRisk : .review,
                reason: known ? loc("Ninguna versión de pnpm instalada usa este store (\(binaries.map(label).joined(separator: ", ")) usan otro): es de una versión anterior. Lo recuperable excluye archivos que aún enlace algún node_modules.", "No installed pnpm version uses this store (\(binaries.map(label).joined(separator: ", ")) use another one): it belongs to an older version. The recoverable space excludes files still linked from a node_modules.")
                              : loc("No se pudo preguntar a ninguna versión de pnpm qué store usa: revisa si este sigue en uso.", "Couldn't ask any pnpm version which store it uses: check whether this one is still in use."),
                regenerate: loc("Si vuelves a instalar esa versión de pnpm, descargará de nuevo los paquetes. Los node_modules ya instalados conservan sus archivos (son enlaces duros).", "If you reinstall that pnpm version, it will download the packages again. Installed node_modules keep their files (they are hard links)."),
                action: .trash(store)))
        }
    }

    static func gradleMaven(_ env: DevEnvironment, _ index: ProjectIndex) -> ProfileResult {
        let gradle = env.path(".gradle")
        var result = ProfileResult(id: "gradle-maven", name: loc("Gradle y Maven", "Gradle and Maven"), owner: "Gradle / Maven", detected: env.isDirectory(gradle) || env.isDirectory(env.path(".m2")))
        let dists = "\(gradle)/wrapper/dists"
        for dist in env.children(dists) {
            guard let match = ProjectIndex.capture(#"^gradle-(.+)-(?:bin|all)$"#, in: dist) else { continue }
            let path = "\(dists)/\(dist)"
            if let projects = index.gradleVersions[match] {
                result.items.append(.measured("gradle-maven", "Gradle \(match) (\(dist.hasSuffix("all") ? "all" : "bin"))", path: path, category: .protected,
                    reason: loc("La pide \(DevEnvironmentHelpers.names(projects)).", "Required by \(DevEnvironmentHelpers.names(projects))."), regenerate: loc("El wrapper la volvería a descargar.", "The wrapper would download it again."), action: nil))
            } else {
                result.items.append(.measured("gradle-maven", "Gradle \(match) (\(dist.hasSuffix("all") ? "all" : "bin"))", path: path, category: .lowRisk,
                    reason: loc("Ningún gradle-wrapper.properties de los proyectos revisados pide esta versión.", "No gradle-wrapper.properties in the checked projects asks for this version."),
                    regenerate: loc("El wrapper la vuelve a descargar (unos 150 MB) si un proyecto la pide.", "The wrapper downloads it again (about 150 MB) if a project asks for it."), action: .trash(path, note: loc("Con los daemons detenidos: gradle --stop.", "With the daemons stopped: gradle --stop."), closed: [.gradle])))
            }
        }
        for (sub, title, category, reason, regen) in [
            ("caches", loc("Cachés de Gradle", "Gradle caches"), Category.lowRisk, loc("Dependencias descargadas y transformaciones de compilación.", "Downloaded dependencies and build transforms."), loc("Las compilaciones vuelven a descargar dependencias (red y tiempo).", "Builds download dependencies again (network and time).")),
            ("daemon", loc("Registros de daemons de Gradle", "Gradle daemon logs"), .lowRisk, loc("Registros y estado de daemons anteriores.", "Logs and state of previous daemons."), "Ninguno."),
            ("jdks", loc("JDK aprovisionados por Gradle", "JDKs provisioned by Gradle"), .review, loc("JDK descargados automáticamente por toolchains de Gradle.", "JDKs downloaded automatically by Gradle toolchains."), loc("Gradle los vuelve a descargar si un proyecto los pide.", "Gradle downloads them again if a project asks for them."))
        ] {
            let path = "\(gradle)/\(sub)"
            if env.isDirectory(path), case let usage = DiskUsage.measure(path), usage.allocated > 10_000_000 {
                result.items.append(.measured("gradle-maven", title, path: path, category: category, reason: reason, regenerate: regen, action: .trash(path, note: loc("Con los daemons detenidos: gradle --stop.", "With the daemons stopped: gradle --stop."), closed: [.gradle]), usage: usage))
            }
        }
        let m2 = env.path(".m2/repository")
        if env.isDirectory(m2) {
            result.items.append(.measured("gradle-maven", loc("Repositorio local de Maven", "Local Maven repository"), path: m2, category: .lowRisk, reason: loc("Dependencias descargadas por Maven.", "Dependencies downloaded by Maven."),
                regenerate: loc("Maven las vuelve a descargar al compilar. Los artefactos instalados con `mvn install` sin publicar se perderían.", "Maven downloads them again when building. Artifacts installed with `mvn install` and not published would be lost."), action: .trash(m2)))
        }
        return result
    }

    static func docker(_ env: DevEnvironment) -> ProfileResult {
        let raw = env.path("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        let dockerBin = env.tool("docker")
        var result = ProfileResult(id: "docker", name: "Docker", owner: "docker", detected: dockerBin != nil || env.exists(raw))
        guard result.detected else { return result }
        if let dockerBin, let out = env.runner.run(dockerBin, ["system", "df", "--format", "{{json .}}"], timeout: 20), out.status == 0 {
            for line in out.output.split(separator: "\n") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let type = obj["Type"] as? String else { continue }
                let reclaimable = DevEnvironmentHelpers.parseDockerSize(obj["Reclaimable"] as? String ?? "")
                let size = DevEnvironmentHelpers.parseDockerSize(obj["Size"] as? String ?? "")
                guard reclaimable > 0 else { continue }
                let (title, category, reason, command): (String, Category, String, [String]) = switch type {
                case "Build Cache": (loc("Caché de compilación", "Build cache"), .lowRisk, loc("Capas de compilación intermedias.", "Intermediate build layers."), ["docker", "builder", "prune", "-f"])
                case "Images": (loc("Imágenes sin usar", "Unused images"), .review, loc("Imágenes que ningún contenedor usa.", "Images no container uses."), ["docker", "image", "prune", "-a", "-f"])
                case "Containers": (loc("Contenedores detenidos", "Stopped containers"), .review, loc("Contenedores parados; pueden tener datos que no están en volúmenes.", "Stopped containers; they may hold data that isn't in volumes."), ["docker", "container", "prune", "-f"])
                case "Local Volumes": (loc("Volúmenes sin usar", "Unused volumes"), .review, loc("Volúmenes sin contenedor: suelen ser datos (bases de datos…).", "Volumes without a container: usually data (databases…)."), ["docker", "volume", "prune", "-f"])
                default: (type, .review, loc("Datos de Docker.", "Docker data."), ["docker", "system", "prune", "-f"])
                }
                result.items.append(DevItem(profile: "docker", title: title, path: nil, bytes: size, recoverable: reclaimable, category: category, reason: reason,
                    regenerate: type == "Local Volumes" ? loc("No se regeneran: es información.", "Not regenerated: it's data.") : loc("Se vuelven a descargar o construir cuando hagan falta.", "Downloaded or built again when needed."), action: .run(command), key: type))
            }
            result.notes.append(loc("El disco virtual de Docker Desktop no se reduce solo: tras limpiar, el espacio se libera dentro de Docker.raw y macOS lo recupera con el tiempo.", "Docker Desktop's virtual disk doesn't shrink on its own: after cleaning, the space is freed inside Docker.raw and macOS reclaims it over time."))
        } else {
            result.notes.append(loc("Docker no está en ejecución: abre Docker Desktop para medir qué se puede limpiar.", "Docker isn't running: open Docker Desktop to measure what can be cleaned."))
        }
        if env.exists(raw) {
            result.items.append(.measured("docker", loc("Disco virtual de Docker Desktop", "Docker Desktop virtual disk"), path: raw, category: .protected,
                reason: loc("Contiene imágenes, contenedores y volúmenes.", "Holds images, containers and volumes."), regenerate: loc("Borrar el archivo elimina todo lo de Docker; usa los comandos de prune o Docker Desktop › Troubleshoot.", "Deleting the file removes everything in Docker; use the prune commands or Docker Desktop › Troubleshoot."), action: nil))
        }
        return result
    }

    static func homebrew(_ env: DevEnvironment) -> ProfileResult {
        let brew = env.tool("brew")
        var result = ProfileResult(id: "homebrew", name: "Homebrew", owner: "brew", detected: brew != nil)
        guard let brew else { return result }
        var cache = env.path("Library/Caches/Homebrew")
        if let out = env.runner.run(brew, ["--cache"], timeout: 15), out.status == 0 {
            let path = out.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if env.isDirectory(path) { cache = path }
        }
        if env.isDirectory(cache) {
            result.items.append(.measured("homebrew", loc("Descargas de Homebrew", "Homebrew downloads"), path: cache, category: .lowRisk, reason: loc("Instaladores y botellas ya descargados.", "Installers and bottles already downloaded."),
                regenerate: loc("Se vuelven a descargar si reinstalas o actualizas.", "Downloaded again if you reinstall or upgrade."), action: .run(["brew", "cleanup", "--prune=all"], preview: ["brew", "cleanup", "--prune=all", "--dry-run"])))
        }
        result.notes.append(loc("`brew cleanup` también retira versiones antiguas de paquetes; su tamaño aparece en la vista previa.", "`brew cleanup` also removes old package versions; their size shows up in the preview."))
        return result
    }

    static func nodeVersions(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path(".nvm/versions/node")
        var result = ProfileResult(id: "node-versions", name: loc("Versiones de Node (nvm)", "Node versions (nvm)"), owner: "nvm", detected: env.isDirectory(dir))
        let versions = DevEnvironmentHelpers.sortedVersions(dir)
        guard versions.count > 1 else { return result }
        var keep = Set<String>()
        // Por cada versión mayor se conserva la más reciente.
        for version in versions { keep = keep.filter { DevEnvironmentHelpers.major($0) != DevEnvironmentHelpers.major(version) }.union([version]) }
        let alias = env.read(env.path(".nvm/alias/default"))?.trimmingCharacters(in: .whitespacesAndNewlines)
        for version in versions {
            let path = "\(dir)/\(version)"
            let globals = env.children("\(path)/bin").filter { !["node", "npm", "npx", "corepack"].contains($0) }
            if keep.contains(version) || alias == version {
                result.items.append(.measured("node-versions", "Node \(version)", path: path, category: .protected, reason: alias == version ? loc("Versión por defecto de nvm.", "nvm's default version.") : loc("Versión más reciente de la serie \(DevEnvironmentHelpers.major(version)).", "Newest version of the \(DevEnvironmentHelpers.major(version)) series."), regenerate: "—", action: nil))
            } else {
                let note = globals.isEmpty ? "" : loc(" Tiene herramientas globales instaladas: \(globals.joined(separator: ", ")); comprueba que estén en otra versión.", " It has global tools installed: \(globals.joined(separator: ", ")); check that they exist in another version.")
                result.items.append(.measured("node-versions", "Node \(version)", path: path, category: .review,
                    reason: loc("Hay una versión más reciente de la serie \(DevEnvironmentHelpers.major(version)).\(note)", "There's a newer version of the \(DevEnvironmentHelpers.major(version)) series.\(note)"), regenerate: loc("Se reinstala con `nvm install \(version)`.", "Reinstalled with `nvm install \(version)`."), action: .trash(path, note: loc("Equivale a `nvm uninstall \(version)` (nvm es una función de la shell y no se puede invocar desde aquí).", "Same as `nvm uninstall \(version)` (nvm is a shell function and can't be called from here)."))))
            }
        }
        return result
    }

    // MARK: Apps

    static func claudeDesktop(_ env: DevEnvironment) -> ProfileResult {
        let base = env.path("Library/Application Support/Claude")
        var result = ProfileResult(id: "claude-desktop", name: "Claude Desktop", owner: "Claude", detected: env.isDirectory(base))
        guard result.detected else { return result }
        let vm = "\(base)/vm_bundles"
        if env.isDirectory(vm), case let usage = DiskUsage.measure(vm), usage.allocated > 100_000_000 {
            result.items.append(.measured("claude-desktop", loc("Máquina virtual de Claude", "Claude virtual machine"), path: vm, category: .review,
                reason: loc("Imagen de la máquina virtual que usa la app para ejecutar tareas en un entorno aislado. No hay comando oficial para retirarla.", "Virtual machine image the app uses to run tasks in an isolated environment. There's no official command to remove it."),
                regenerate: loc("La app la vuelve a descargar (varios GB) la próxima vez que la necesite.", "The app downloads it again (several GB) the next time it needs it."), action: .trash(vm, note: loc("Con Claude cerrado.", "With Claude closed."), closed: [.claude]), usage: usage))
        }
        for (sub, title) in [("Cache", loc("Caché de la app", "App cache")), ("Code Cache", loc("Caché de código de la app", "App code cache"))] {
            let path = "\(base)/\(sub)"
            if env.isDirectory(path), case let usage = DiskUsage.measure(path), usage.allocated > 50_000_000 {
                result.items.append(.measured("claude-desktop", title, path: path, category: .lowRisk, reason: loc("Caché de Electron (recursos web y código compilado).", "Electron cache (web resources and compiled code)."),
                    regenerate: loc("La app la regenera; el primer arranque será algo más lento.", "The app regenerates it; the first launch will be a bit slower."), action: .trash(path, note: loc("Con Claude cerrado.", "With Claude closed."), closed: [.claude]), usage: usage))
            }
        }
        return result
    }

    static func vscode(_ env: DevEnvironment) -> ProfileResult {
        let extensions = env.path(".vscode/extensions")
        var result = ProfileResult(id: "vscode", name: "Visual Studio Code", owner: "VS Code", detected: env.isDirectory(extensions))
        guard result.detected else { return result }
        var obsolete = Set<String>()
        if let text = env.read("\(extensions)/.obsolete"),
           let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Bool] {
            obsolete = Set(json.filter { $0.value }.keys)
        }
        // Versiones antiguas de una misma extensión: VS Code usa la más reciente.
        var byID: [String: [String]] = [:]
        for name in env.children(extensions) {
            guard let match = name.range(of: #"-\d+\.\d+\.\d+.*$"#, options: .regularExpression) else { continue }
            byID[String(name[..<match.lowerBound]), default: []].append(name)
        }
        var stale = obsolete
        for (_, names) in byID where names.count > 1 {
            stale.formUnion(names.sorted(by: DevEnvironment.versionLess).dropLast())
        }
        var total = Usage()
        var stalePaths: [String] = []
        for name in stale.sorted() where env.isDirectory("\(extensions)/\(name)") {
            let u = DiskUsage.measure("\(extensions)/\(name)")
            total.allocated += u.allocated; total.exclusive += u.exclusive; stalePaths.append("\(extensions)/\(name)")
        }
        let count = stalePaths.count
        if count > 0 {
            result.items.append(DevItem(profile: "vscode", title: loc("\(count) versiones antiguas u obsoletas de extensiones", "\(count) old or obsolete extension versions"), path: extensions, bytes: total.allocated, recoverable: total.exclusive, category: .lowRisk,
                reason: loc("VS Code las marcó como obsoletas o existe una versión más reciente de la misma extensión.", "VS Code marked them as obsolete or there's a newer version of the same extension."), regenerate: loc("Ninguno: VS Code usa la versión más reciente.", "None: VS Code uses the newest version."),
                action: .trash(stalePaths, label: loc("\(count) carpetas de extensiones antiguas", "\(count) old extension folders"), note: loc("Con VS Code cerrado. VS Code también las limpia al reiniciar.", "With VS Code closed. VS Code also cleans them up when it restarts."), closed: [.vscode])))
        }
        for sub in ["Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache"] {
            let path = env.path("Library/Application Support/Code/\(sub)")
            if env.isDirectory(path), case let usage = DiskUsage.measure(path), usage.allocated > 50_000_000 {
                result.items.append(.measured("vscode", "VS Code · \(sub)", path: path, category: .lowRisk, reason: loc("Caché de la app.", "App cache."), regenerate: loc("VS Code la regenera.", "VS Code regenerates it."), action: .trash(path, note: loc("Con VS Code cerrado.", "With VS Code closed."), closed: [.vscode]), usage: usage))
            }
        }
        return result
    }
}

final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [ProfileResult?]
    init(count: Int) { slots = Array(repeating: nil, count: count) }
    func set(_ i: Int, _ value: ProfileResult) { lock.withLock { slots[i] = value } }
    var values: [ProfileResult] { lock.withLock { slots.compactMap { $0 } } }
}

enum DevEnvironmentHelpers {
    static func sortedVersions(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { !$0.hasPrefix(".") && $0.first?.isNumber == true || $0.hasPrefix("v") && $0.dropFirst().first?.isNumber == true }
            .sorted(by: DevEnvironment.versionLess)
    }

    /// Carpetas tipo «18.1 (22B83)» o «iPhone15,2 17.0 (21A329)», ordenadas por versión de iOS.
    static func sortedDeviceSupport(_ dir: String) -> [String] {
        func version(_ name: String) -> String { ProjectIndex.capture(#"(\d+\.\d+(?:\.\d+)?) \("#, in: name) ?? "0" }
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }
            .sorted { DevEnvironment.versionLess(version($0), version($1)) }
    }

    static func major(_ version: String) -> String {
        String(version.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber }))
    }

    static func names(_ projects: [String]) -> String {
        let list = Array(Set(projects.map { URL(fileURLWithPath: $0).lastPathComponent })).sorted()
        return list.prefix(3).joined(separator: ", ") + (list.count > 3 ? loc(" y \(list.count - 3) más", " and \(list.count - 3) more") : "")
    }

    static func relative(_ path: String, _ env: DevEnvironment) -> String {
        for root in env.projectRoots.map({ DevEnvironment.canonical($0.path) }) where path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// Fecha más reciente de los elementos de primer nivel del proyecto, ignorando artefactos.
    static func recentTopLevelChange(_ project: String, ignoring: Set<String>) -> Date? {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: project)) ?? []
        return names.filter { !ignoring.contains($0) && $0 != ".DS_Store" }
            .compactMap { (try? fm.attributesOfItem(atPath: "\(project)/\($0)"))?[.modificationDate] as? Date }
            .max()
    }

    /// Convierte «1.2GB», «512.3MB (40%)» a bytes (Docker usa unidades decimales).
    static func parseDockerSize(_ text: String) -> Int64 {
        guard let token = text.split(separator: " ").first else { return 0 }
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (unit, factor) in units where token.hasSuffix(unit) {
            return Int64((Double(token.dropLast(unit.count)) ?? 0) * factor)
        }
        return 0
    }
}

private final class UsageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Usage?]
    init(count: Int) { storage = Array(repeating: nil, count: count) }
    func set(_ index: Int, _ value: Usage) { lock.withLock { storage[index] = value } }
    var values: [Usage?] { lock.withLock { storage } }
}
