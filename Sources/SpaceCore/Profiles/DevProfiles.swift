import Foundation

/// Catálogo versionado de ubicaciones regenerables conocidas. Cada perfil propone el comando oficial de la herramienta
/// dueña cuando existe y explica qué cuesta regenerar. En la 0.3 nada se ejecuta: solo se mide y se propone.
public enum DevProfiles {
    public static let version = 1

    public static func report(_ env: DevEnvironment = DevEnvironment()) -> DevReport {
        let index = ProjectIndex.build(env)
        let profiles: [ProfileResult] = [
            androidSDK(env, index), androidEmulators(env), iosSimulators(env), xcode(env),
            projectArtifacts(env, index), jsPackages(env), gradleMaven(env, index), docker(env),
            homebrew(env), nodeVersions(env), claudeDesktop(env), vscode(env)
        ]
        return DevReport(date: env.now, profiles: profiles, projectRoots: env.projectRoots.map(\.path), inactiveDays: env.inactiveDays)
    }

    // MARK: Android

    static func androidSDK(_ env: DevEnvironment, _ index: ProjectIndex) -> ProfileResult {
        let sdk = env.path("Library/Android/sdk")
        var result = ProfileResult(id: "android-sdk", name: "SDK de Android", owner: "sdkmanager", detected: env.isDirectory(sdk))
        guard result.detected else { return result }
        let sdkmanager = "\(sdk)/cmdline-tools/latest/bin/sdkmanager"
        if env.exists(sdkmanager) {
            result.notes.append("sdkmanager está en \(sdkmanager) (añádelo al PATH o usa la ruta completa).")
        } else {
            result.notes.append("No se encontró sdkmanager en cmdline-tools/latest; usa el SDK Manager de Android Studio.")
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
                        result.items.append(.measured("android-sdk", "Imagen \(api) \(tag) \(abi)", path: "\(sdk)/\(rel)", category: .protected,
                            reason: "La usa el emulador \(avds.joined(separator: ", ")).", regenerate: "Sin ella el emulador no arranca.", action: nil))
                    } else {
                        result.items.append(.measured("android-sdk", "Imagen \(api) \(tag) \(abi)", path: "\(sdk)/\(rel)", category: .lowRisk,
                            reason: "Ningún emulador de ~/.android/avd usa esta imagen.", regenerate: "Se vuelve a descargar con sdkmanager si creas un emulador con ella.",
                            action: .run("sdkmanager --uninstall \"\(package)\"")))
                    }
                }
            }
        }
        versioned(&result, dir: "\(sdk)/ndk", label: "NDK", package: "ndk", refs: index.ndkVersions, keepNewest: false)
        versioned(&result, dir: "\(sdk)/build-tools", label: "Build-tools", package: "build-tools", refs: index.buildToolsVersions, keepNewest: true)
        if result.items.contains(where: { $0.category == .review }) {
            result.notes.append("Las versiones que ningún proyecto pide se marcan para revisar, no como bajo riesgo: solo se revisaron \(env.projectRoots.map { $0.lastPathComponent }.joined(separator: ", ")).")
        }
        return result
    }

    private static func versioned(_ result: inout ProfileResult, dir: String, label: String, package: String, refs: [String: [String]], keepNewest: Bool) {
        let versions = DevEnvironmentHelpers.sortedVersions(dir)
        for version in versions {
            let path = "\(dir)/\(version)"
            if let projects = refs[version] {
                result.items.append(.measured(result.id, "\(label) \(version)", path: path, category: .protected,
                    reason: "Lo pide \(DevEnvironmentHelpers.names(projects)).", regenerate: "Esos proyectos no compilarían sin él.", action: nil))
            } else if keepNewest && version == versions.last {
                result.items.append(.measured(result.id, "\(label) \(version)", path: path, category: .protected,
                    reason: "Versión más reciente instalada; se conserva.", regenerate: "Gradle la usa por defecto.", action: nil))
            } else {
                result.items.append(.measured(result.id, "\(label) \(version)", path: path, category: .review,
                    reason: "Ningún proyecto revisado lo pide explícitamente, pero puede usarlo uno de otra carpeta o una dependencia.",
                    regenerate: "Si un proyecto lo necesita, Gradle o sdkmanager lo vuelven a descargar.",
                    action: .run("sdkmanager --uninstall \"\(package);\(version)\"")))
            }
        }
    }

    static func androidEmulators(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path(".android/avd")
        var result = ProfileResult(id: "android-avd", name: "Emuladores de Android", owner: "avdmanager", detected: env.isDirectory(dir))
        for avd in env.children(dir) where avd.hasSuffix(".avd") {
            let name = String(avd.dropLast(4))
            let path = "\(dir)/\(avd)"
            let usage = DiskUsage.measure(path)
            let days = env.days(since: usage.newest).map { "Último uso hace \($0) días." } ?? ""
            let snapshots = "\(path)/snapshots"
            var snapshotBytes: Int64 = 0
            if env.isDirectory(snapshots) {
                let snap = DiskUsage.measure(snapshots)
                snapshotBytes = snap.exclusive
                if snap.allocated > 50_000_000 {
                    result.items.append(.measured("android-avd", "Instantáneas de \(name)", path: snapshots, category: .lowRisk,
                        reason: "Instantáneas de arranque rápido del emulador.", regenerate: "El próximo arranque será en frío (más lento); el emulador crea una nueva al cerrarse.",
                        action: .trash(snapshots, note: "Con el emulador apagado."), usage: snap))
                }
            }
            var whole = usage
            whole.exclusive -= snapshotBytes
            result.items.append(.measured("android-avd", "Emulador \(name)", path: path, category: .review,
                reason: "Emulador con sus apps y datos instalados. \(days)", regenerate: "Borrarlo pierde lo instalado en él; se puede recrear desde Android Studio (Device Manager).",
                action: .run("avdmanager delete avd -n \"\(name)\"", note: "Con el emulador apagado."), usage: whole))
        }
        return result
    }

    // MARK: Apple

    static func iosSimulators(_ env: DevEnvironment) -> ProfileResult {
        let base = env.path("Library/Developer/CoreSimulator")
        var result = ProfileResult(id: "ios-simulators", name: "Simuladores de iOS", owner: "xcrun simctl", detected: env.isDirectory(base))
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
                        reason: "Simulador disponible con sus apps y datos.", regenerate: "Borrarlo pierde lo instalado; Xcode lo recrea vacío. `erase` lo vacía sin borrarlo.",
                        action: .run("xcrun simctl delete \(udid)", preview: nil, note: "Alternativa: xcrun simctl erase \(udid)")))
                }
            }
            if !unavailable.isEmpty {
                var total = Usage()
                for path in unavailable { let u = DiskUsage.measure(path); total.allocated += u.allocated; total.exclusive += u.exclusive }
                result.items.append(DevItem(profile: "ios-simulators", title: "\(unavailable.count) simuladores no disponibles", path: nil, bytes: total.allocated, recoverable: total.exclusive, category: .lowRisk,
                    reason: "Su runtime ya no está instalado: no se pueden arrancar.", regenerate: "Ninguno.", action: .run("xcrun simctl delete unavailable")))
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
                    result.items.append(DevItem(profile: "ios-simulators", title: "Runtime iOS \(version)", path: runtime["path"] as? String, bytes: size, recoverable: deletable ? size : 0,
                        category: !deletable || inUse ? .protected : .review,
                        reason: !deletable ? "El sistema no permite borrarlo." : inUse ? "Usado hace \(days ?? 0) días." : "Sin uso en \(days.map { "\($0)" } ?? "?") días. Vive fuera de tu carpeta personal (lo gestiona macOS).",
                        regenerate: "Se vuelve a descargar desde Xcode › Settings › Components (varios GB).",
                        action: deletable ? .run("xcrun simctl runtime delete \(id)") : nil, lastUsed: lastUsed))
                }
            }
        } else {
            result.notes.append("No se pudo consultar `xcrun simctl` (¿Xcode no instalado?). Solo se mide la carpeta.")
        }
        let caches = "\(base)/Caches"
        if env.isDirectory(caches), DiskUsage.measure(caches).allocated > 10_000_000 {
            result.items.append(.measured("ios-simulators", "Cachés de simuladores", path: caches, category: .lowRisk,
                reason: "Cachés (por ejemplo, de dyld) que CoreSimulator regenera.", regenerate: "El primer arranque de cada simulador será más lento.", action: .trash(caches, note: "Con los simuladores apagados.")))
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
                result.items.append(.measured("xcode", "DerivedData", path: derived, category: .lowRisk, reason: "Productos intermedios de compilación e índices.",
                    regenerate: "Xcode lo regenera; la siguiente compilación e indexado serán más lentos.", action: .trash(derived, note: "Con Xcode cerrado."), usage: u))
            }
        }
        let support = "\(base)/iOS DeviceSupport"
        let versions = DevEnvironmentHelpers.sortedDeviceSupport(support)
        for (i, version) in versions.enumerated() {
            let newest = i == versions.count - 1
            result.items.append(.measured("xcode", "Soporte de dispositivo \(version)", path: "\(support)/\(version)", category: newest ? .review : .lowRisk,
                reason: newest ? "Versión más reciente: probablemente la de tu iPhone actual." : "Símbolos de una versión de iOS anterior a la más reciente copiada.",
                regenerate: "Xcode lo vuelve a copiar al conectar un dispositivo con esa versión (tarda varios minutos).", action: .trash("\(support)/\(version)")))
        }
        let archives = "\(base)/Archives"
        if env.isDirectory(archives), DiskUsage.measure(archives).allocated > 1_000_000 {
            result.items.append(.measured("xcode", "Archivos de publicación (Archives)", path: archives, category: .review,
                reason: "Builds publicadas y sus símbolos.", regenerate: "No se regeneran: sin ellos no se pueden simbolizar fallos de esas versiones.", action: .trash(archives)))
        }
        let cache = env.path("Library/Caches/com.apple.dt.Xcode")
        if env.isDirectory(cache), DiskUsage.measure(cache).allocated > 10_000_000 {
            result.items.append(.measured("xcode", "Caché de Xcode", path: cache, category: .lowRisk, reason: "Caché de la app.", regenerate: "Xcode la regenera.", action: .trash(cache, note: "Con Xcode cerrado.")))
        }
        return result
    }

    // MARK: Proyectos

    static func projectArtifacts(_ env: DevEnvironment, _ index: ProjectIndex) -> ProfileResult {
        var result = ProfileResult(id: "project-artifacts", name: "Artefactos de proyectos", owner: "Gestor de cada proyecto", detected: !index.artifacts.isEmpty)
        var activity: [String: Date?] = [:]
        for artifact in index.artifacts {
            let repo = index.repositories[artifact.project]
            let key = repo ?? artifact.project
            if activity[key] == nil {
                let commit = repo.flatMap { ProjectIndex.lastCommit($0, env: env) }
                let touched = DevEnvironmentHelpers.recentTopLevelChange(artifact.project, ignoring: ProjectIndex.skip)
                activity[key] = [commit, touched].compactMap { $0 }.max()
            }
            let last = activity[key] ?? nil
            let days = env.days(since: last)
            let inactive = days.map { $0 >= env.inactiveDays } ?? false
            let projectName = DevEnvironmentHelpers.relative(artifact.project, env)
            var reason = "\(artifact.kind) de \(projectName). "
            reason += days.map { "Último cambio del proyecto hace \($0) días." } ?? "No se pudo determinar la actividad del proyecto."
            if artifact.sharedWithStore { reason += " pnpm comparte estos archivos con su store: lo recuperable real es menor y se completa con `pnpm store prune`." }
            result.items.append(.measured("project-artifacts", "\(projectName) · \(URL(fileURLWithPath: artifact.path).lastPathComponent)", path: artifact.path,
                category: inactive ? .lowRisk : .protected,
                reason: inactive ? reason : "Proyecto activo: no se propone. " + reason,
                regenerate: artifact.regenerate, action: inactive ? .trash(artifact.path) : nil, lastUsed: last))
        }
        let small = result.items.filter { ($0.bytes ?? 0) < 1_000_000 }
        result.items.removeAll { ($0.bytes ?? 0) < 1_000_000 }
        result.items.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        result.notes.append("Inactivo = sin commits ni cambios en los archivos del proyecto en \(env.inactiveDays) días o más.")
        if !small.isEmpty { result.notes.append("\(small.count) artefactos menores de 1 MB no se muestran.") }
        return result
    }

    // MARK: Paquetes y compiladores

    static func jsPackages(_ env: DevEnvironment) -> ProfileResult {
        var result = ProfileResult(id: "js-packages", name: "Cachés de paquetes JavaScript", owner: "pnpm / npm / yarn", detected: false)
        var store = env.path("Library/pnpm/store")
        if let pnpm = env.tool("pnpm"), let out = env.runner.run(pnpm, ["store", "path"], timeout: 15), out.status == 0 {
            let path = out.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if env.isDirectory(path) { store = path }
        }
        if env.isDirectory(store) {
            result.detected = true
            result.items.append(.measured("js-packages", "Store de pnpm", path: store, category: .lowRisk,
                reason: "Paquetes descargados por pnpm. Lo recuperable estimado son los archivos que ningún node_modules enlaza.",
                regenerate: "pnpm vuelve a descargar los paquetes que pida un proyecto.", action: .run("pnpm store prune")))
        }
        let npm = env.path(".npm/_cacache")
        if env.isDirectory(npm), DiskUsage.measure(npm).allocated > 10_000_000 {
            result.detected = true
            result.items.append(.measured("js-packages", "Caché de npm", path: npm, category: .lowRisk, reason: "Copias de paquetes descargados por npm.",
                regenerate: "npm los vuelve a descargar al instalar.", action: .run("npm cache clean --force", preview: "npm cache verify")))
        }
        for (path, title, command) in [(env.path("Library/Caches/Yarn"), "Caché de Yarn", "yarn cache clean"), (env.path(".bun/install/cache"), "Caché de Bun", "bun pm cache rm")] {
            if env.isDirectory(path), DiskUsage.measure(path).allocated > 10_000_000 {
                result.detected = true
                result.items.append(.measured("js-packages", title, path: path, category: .lowRisk, reason: "Paquetes descargados.", regenerate: "Se vuelven a descargar al instalar.", action: .run(command)))
            }
        }
        return result
    }

    static func gradleMaven(_ env: DevEnvironment, _ index: ProjectIndex) -> ProfileResult {
        let gradle = env.path(".gradle")
        var result = ProfileResult(id: "gradle-maven", name: "Gradle y Maven", owner: "Gradle / Maven", detected: env.isDirectory(gradle) || env.isDirectory(env.path(".m2")))
        let dists = "\(gradle)/wrapper/dists"
        for dist in env.children(dists) {
            guard let match = ProjectIndex.capture(#"^gradle-(.+)-(?:bin|all)$"#, in: dist) else { continue }
            let path = "\(dists)/\(dist)"
            if let projects = index.gradleVersions[match] {
                result.items.append(.measured("gradle-maven", "Gradle \(match) (\(dist.hasSuffix("all") ? "all" : "bin"))", path: path, category: .protected,
                    reason: "La pide \(DevEnvironmentHelpers.names(projects)).", regenerate: "El wrapper la volvería a descargar.", action: nil))
            } else {
                result.items.append(.measured("gradle-maven", "Gradle \(match) (\(dist.hasSuffix("all") ? "all" : "bin"))", path: path, category: .lowRisk,
                    reason: "Ningún gradle-wrapper.properties de los proyectos revisados pide esta versión.",
                    regenerate: "El wrapper la vuelve a descargar (unos 150 MB) si un proyecto la pide.", action: .trash(path, note: "Con los daemons detenidos: gradle --stop.")))
            }
        }
        for (sub, title, category, reason, regen) in [
            ("caches", "Cachés de Gradle", Category.lowRisk, "Dependencias descargadas y transformaciones de compilación.", "Las compilaciones vuelven a descargar dependencias (red y tiempo)."),
            ("daemon", "Registros de daemons de Gradle", .lowRisk, "Registros y estado de daemons anteriores.", "Ninguno."),
            ("jdks", "JDK aprovisionados por Gradle", .review, "JDK descargados automáticamente por toolchains de Gradle.", "Gradle los vuelve a descargar si un proyecto los pide.")
        ] {
            let path = "\(gradle)/\(sub)"
            if env.isDirectory(path), DiskUsage.measure(path).allocated > 10_000_000 {
                result.items.append(.measured("gradle-maven", title, path: path, category: category, reason: reason, regenerate: regen, action: .trash(path, note: "Con los daemons detenidos: gradle --stop.")))
            }
        }
        let m2 = env.path(".m2/repository")
        if env.isDirectory(m2) {
            result.items.append(.measured("gradle-maven", "Repositorio local de Maven", path: m2, category: .lowRisk, reason: "Dependencias descargadas por Maven.",
                regenerate: "Maven las vuelve a descargar al compilar. Los artefactos instalados con `mvn install` sin publicar se perderían.", action: .trash(m2)))
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
                let (title, category, reason, command): (String, Category, String, String) = switch type {
                case "Build Cache": ("Caché de compilación", .lowRisk, "Capas de compilación intermedias.", "docker builder prune")
                case "Images": ("Imágenes sin usar", .review, "Imágenes que ningún contenedor usa.", "docker image prune -a")
                case "Containers": ("Contenedores detenidos", .review, "Contenedores parados; pueden tener datos que no están en volúmenes.", "docker container prune")
                case "Local Volumes": ("Volúmenes sin usar", .review, "Volúmenes sin contenedor: suelen ser datos (bases de datos…).", "docker volume prune")
                default: (type, .review, "Datos de Docker.", "docker system prune")
                }
                result.items.append(DevItem(profile: "docker", title: title, path: nil, bytes: size, recoverable: reclaimable, category: category, reason: reason,
                    regenerate: type == "Local Volumes" ? "No se regeneran: es información." : "Se vuelven a descargar o construir cuando hagan falta.", action: .run(command)))
            }
            result.notes.append("El disco virtual de Docker Desktop no se reduce solo: tras limpiar, el espacio se libera dentro de Docker.raw y macOS lo recupera con el tiempo.")
        } else {
            result.notes.append("Docker no está en ejecución: abre Docker Desktop para medir qué se puede limpiar.")
        }
        if env.exists(raw) {
            result.items.append(.measured("docker", "Disco virtual de Docker Desktop", path: raw, category: .protected,
                reason: "Contiene imágenes, contenedores y volúmenes.", regenerate: "Borrar el archivo elimina todo lo de Docker; usa los comandos de prune o Docker Desktop › Troubleshoot.", action: nil))
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
            result.items.append(.measured("homebrew", "Descargas de Homebrew", path: cache, category: .lowRisk, reason: "Instaladores y botellas ya descargados.",
                regenerate: "Se vuelven a descargar si reinstalas o actualizas.", action: .run("brew cleanup --prune=all", preview: "brew cleanup --prune=all --dry-run")))
        }
        result.notes.append("`brew cleanup` también retira versiones antiguas de paquetes; su tamaño aparece en la vista previa.")
        return result
    }

    static func nodeVersions(_ env: DevEnvironment) -> ProfileResult {
        let dir = env.path(".nvm/versions/node")
        var result = ProfileResult(id: "node-versions", name: "Versiones de Node (nvm)", owner: "nvm", detected: env.isDirectory(dir))
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
                result.items.append(.measured("node-versions", "Node \(version)", path: path, category: .protected, reason: alias == version ? "Versión por defecto de nvm." : "Versión más reciente de la serie \(DevEnvironmentHelpers.major(version)).", regenerate: "—", action: nil))
            } else {
                let note = globals.isEmpty ? "" : " Tiene herramientas globales instaladas: \(globals.joined(separator: ", ")); comprueba que estén en otra versión."
                result.items.append(.measured("node-versions", "Node \(version)", path: path, category: .review,
                    reason: "Hay una versión más reciente de la serie \(DevEnvironmentHelpers.major(version)).\(note)", regenerate: "Se reinstala con `nvm install \(version)`.", action: .run("nvm uninstall \(version)")))
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
        if env.isDirectory(vm), DiskUsage.measure(vm).allocated > 100_000_000 {
            result.items.append(.measured("claude-desktop", "Máquina virtual de Claude", path: vm, category: .review,
                reason: "Imagen de la máquina virtual que usa la app para ejecutar tareas en un entorno aislado. No hay comando oficial para retirarla.",
                regenerate: "La app la vuelve a descargar (varios GB) la próxima vez que la necesite.", action: .trash(vm, note: "Con Claude cerrado.")))
        }
        for (sub, title) in [("Cache", "Caché de la app"), ("Code Cache", "Caché de código de la app")] {
            let path = "\(base)/\(sub)"
            if env.isDirectory(path), DiskUsage.measure(path).allocated > 50_000_000 {
                result.items.append(.measured("claude-desktop", title, path: path, category: .lowRisk, reason: "Caché de Electron (recursos web y código compilado).",
                    regenerate: "La app la regenera; el primer arranque será algo más lento.", action: .trash(path, note: "Con Claude cerrado.")))
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
        var count = 0
        for name in stale.sorted() where env.isDirectory("\(extensions)/\(name)") {
            let u = DiskUsage.measure("\(extensions)/\(name)")
            total.allocated += u.allocated; total.exclusive += u.exclusive; count += 1
        }
        if count > 0 {
            result.items.append(DevItem(profile: "vscode", title: "\(count) versiones antiguas u obsoletas de extensiones", path: extensions, bytes: total.allocated, recoverable: total.exclusive, category: .lowRisk,
                reason: "VS Code las marcó como obsoletas o existe una versión más reciente de la misma extensión.", regenerate: "Ninguno: VS Code usa la versión más reciente.",
                action: .trash(extensions + "/<versiones antiguas>", note: "Con VS Code cerrado. VS Code también las limpia al reiniciar.")))
        }
        for sub in ["Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache"] {
            let path = env.path("Library/Application Support/Code/\(sub)")
            if env.isDirectory(path), DiskUsage.measure(path).allocated > 50_000_000 {
                result.items.append(.measured("vscode", "VS Code · \(sub)", path: path, category: .lowRisk, reason: "Caché de la app.", regenerate: "VS Code la regenera.", action: .trash(path, note: "Con VS Code cerrado.")))
            }
        }
        return result
    }
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
        return list.prefix(3).joined(separator: ", ") + (list.count > 3 ? " y \(list.count - 3) más" : "")
    }

    static func relative(_ path: String, _ env: DevEnvironment) -> String {
        for root in env.projectRoots where path.hasPrefix(root.standardizedFileURL.path + "/") {
            return String(path.dropFirst(root.standardizedFileURL.path.count + 1))
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
