import Foundation

/// Desglose del disco por categorías, al estilo de «Almacenamiento» de macOS: cuánto ocupa cada tipo de dato sobre el
/// total del volumen. Solo lee metadatos (tamaño asignado, como du -x) y se guarda en caché porque medir la carpeta
/// personal entera tarda.
public struct StorageSegment: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case apps, personal, appData, development, macOS, swap, trash, purgeable, system
    }
    public let kind: Kind
    public let bytes: Int64
    /// Hubo elementos ilegibles: el tamaño es un mínimo.
    public let partial: Bool
    public var id: String { kind.rawValue }
    public init(kind: Kind, bytes: Int64, partial: Bool = false) {
        self.kind = kind
        self.bytes = bytes
        self.partial = partial
    }
}

public struct StorageBreakdown: Codable, Sendable, Equatable {
    public let date: Date
    public let total: Int64
    public let available: Int64
    /// Partes del espacio usado, en orden fijo; la última es «otros» (lo que no se pudo atribuir).
    public let segments: [StorageSegment]
    public var used: Int64 { max(0, total - available) }

    public func bytes(_ kind: StorageSegment.Kind) -> Int64 { segments.first { $0.kind == kind }?.bytes ?? 0 }
}

/// Capacidad del volumen: total, disponible y lo que macOS puede purgar por sí mismo (cachés de iCloud,
/// instantáneas locales…), que es la diferencia entre «disponible para uso importante» y «disponible».
public struct VolumeCapacity: Sendable, Equatable {
    public let total: Int64
    public let available: Int64
    public let purgeable: Int64

    public static func read(_ url: URL = FileManager.default.homeDirectoryForCurrentUser) -> VolumeCapacity? {
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage ?? Int64(available)
        return VolumeCapacity(total: Int64(total), available: Int64(available), purgeable: max(0, important - Int64(available)))
    }
}

public enum StorageAnalyzer {
    /// Carpetas de la Biblioteca que son de herramientas de desarrollo.
    static let developmentInLibrary: Set<String> = ["Developer", "Android", "pnpm"]
    /// Contenedores de apps de otras apps: macOS puede pedir permiso para leerlos y no se recorren. Docker sí, porque
    /// ya lo mide el perfil de Docker.
    static let skippedInLibrary: Set<String> = ["Containers", "Group Containers"]

    /// Qué se mide y en qué categoría cuenta. Cada ruta se mide una vez; ninguna contiene a otra.
    public static func jobs(_ env: DevEnvironment) -> [(path: String, kind: StorageSegment.Kind)] {
        var jobs: [(String, StorageSegment.Kind)] = [("/Applications", .apps)]
        let fm = FileManager.default
        // Fuera de la carpeta personal, solo lo que se sabe que es de desarrollo (Homebrew, simuladores de Xcode).
        // En modo de prueba no se mide nada del sistema real.
        if DevEnvironment.canonical(env.home.path) == DevEnvironment.canonical(fm.homeDirectoryForCurrentUser.path) {
            for path in ["/opt/homebrew", "/usr/local", "/Library/Developer"] where fm.fileExists(atPath: path) { jobs.append((path, .development)) }
            // Recursos que descarga macOS (modelos, voces, runtimes de simuladores) y datos variables del sistema.
            for path in ["/System/Library/AssetsV2", "/private/var"] where fm.fileExists(atPath: path) { jobs.append((path, .macOS)) }
        } else {
            jobs.removeAll()
        }
        let projectNames = Set(env.projectRoots.filter { $0.deletingLastPathComponent().path == env.home.path }.map(\.lastPathComponent))
        for name in ((try? fm.contentsOfDirectory(atPath: env.home.path)) ?? []).sorted() {
            let path = env.path(name)
            switch name {
            case "Library":
                for child in ((try? fm.contentsOfDirectory(atPath: path)) ?? []).sorted() where !skippedInLibrary.contains(child) {
                    jobs.append(("\(path)/\(child)", developmentInLibrary.contains(child) ? .development : .appData))
                }
                let docker = "\(path)/Containers/com.docker.docker"
                if fm.fileExists(atPath: docker) { jobs.append((docker, .development)) }
            case ".Trash": jobs.append((path, .trash))
            case "Applications": jobs.append((path, .apps))
            default:
                // Las carpetas ocultas grandes de la carpeta personal son casi siempre de herramientas (.gradle,
                // .android, .npm, .cache, .nvm…); las raíces de proyectos también cuentan como desarrollo.
                jobs.append((path, name.hasPrefix(".") || projectNames.contains(name) ? .development : .personal))
            }
        }
        return jobs
    }

    /// Mide en paralelo. `progress` recibe cuántas rutas van terminadas y cuántas hay.
    public static func measure(_ env: DevEnvironment, capacity: VolumeCapacity? = nil, progress: (@Sendable (Int, Int) -> Void)? = nil) -> StorageBreakdown? {
        guard let capacity = capacity ?? VolumeCapacity.read(env.home) else { return nil }
        let list = jobs(env)
        let box = ResultsBox(count: list.count)
        DispatchQueue.concurrentPerform(iterations: list.count) { index in
            let usage = DiskUsage.measure(list[index].path)
            let done = box.store(index, usage)
            progress?(done, list.count)
        }
        var bytes: [StorageSegment.Kind: Int64] = [:]
        var partial = Set<StorageSegment.Kind>()
        // Los volúmenes de macOS (sistema, arranque, recuperación, memoria virtual) comparten el espacio del disco
        // con tus datos: los informa diskutil, sin recorrerlos.
        if !list.isEmpty, list.contains(where: { $0.kind == .macOS }), let system = systemVolumesBytes(total: capacity.total, runner: env.runner) {
            // El intercambio vive en el volumen VM: se muestra aparte y se descuenta de «macOS» para no contarlo dos veces.
            let swap = swapFileBytes() ?? 0
            bytes[.macOS, default: 0] += max(0, system - swap)
            bytes[.swap] = swap
        }
        for (index, job) in list.enumerated() {
            let usage = box.results[index] ?? Usage()
            bytes[job.kind, default: 0] += usage.allocated
            if usage.partial { partial.insert(job.kind) }
        }
        return build(capacity: capacity, measured: bytes, partial: partial)
    }

    /// Reparte lo usado: lo medido, lo purgable y el resto como «sistema y otros». Si lo medido supera lo usado
    /// (clones de APFS, enlaces duros entre carpetas), se recorta proporcionalmente para no pasar del total.
    public static func build(capacity: VolumeCapacity, measured: [StorageSegment.Kind: Int64], partial: Set<StorageSegment.Kind> = [], date: Date = Date()) -> StorageBreakdown {
        let used = max(0, capacity.total - capacity.available)
        let order: [StorageSegment.Kind] = [.apps, .personal, .appData, .development, .macOS, .swap, .trash]
        var values = order.map { max(0, measured[$0] ?? 0) }
        var purgeable = min(capacity.purgeable, used)
        let sum = values.reduce(0, +) + purgeable
        if sum > used, sum > 0 {
            let scale = Double(used) / Double(sum)
            values = values.map { Int64(Double($0) * scale) }
            purgeable = Int64(Double(purgeable) * scale)
        }
        let system = max(0, used - values.reduce(0, +) - purgeable)
        var segments = zip(order, values).map { StorageSegment(kind: $0, bytes: $1, partial: partial.contains($0)) }
        segments.append(StorageSegment(kind: .purgeable, bytes: purgeable))
        segments.append(StorageSegment(kind: .system, bytes: system))
        return StorageBreakdown(date: date, total: capacity.total, available: capacity.available, segments: segments)
    }

    /// Lo que ocupan en el disco los archivos de intercambio (swap): el total reservado según `vm.swapusage`, que crece
    /// cuando la RAM no alcanza y vuelve a bajar al bajar la presión de memoria o al reiniciar.
    public static func swapFileBytes() -> Int64? {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else { return nil }
        return Int64(swap.xsu_total)
    }

    /// Espacio de los volúmenes de macOS del mismo contenedor APFS que tus datos (todo menos el volumen «Data»),
    /// según `diskutil apfs list -plist` (solo lectura).
    public static func systemVolumesBytes(total: Int64, runner: CommandRunner) -> Int64? {
        guard let out = runner.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"], timeout: 20), out.status == 0,
              let plist = try? PropertyListSerialization.propertyList(from: Data(out.output.utf8), format: nil) as? [String: Any],
              let containers = plist["Containers"] as? [[String: Any]] else { return nil }
        func roles(_ volume: [String: Any]) -> [String] { volume["Roles"] as? [String] ?? [] }
        for container in containers {
            let volumes = container["Volumes"] as? [[String: Any]] ?? []
            guard volumes.contains(where: { roles($0).contains("Data") }) else { continue }
            if let ceiling = (container["CapacityCeiling"] as? NSNumber)?.int64Value, ceiling != total { continue }
            return volumes.filter { !roles($0).contains("Data") }.reduce(Int64(0)) { $0 + ((($1["CapacityInUse"] as? NSNumber)?.int64Value) ?? 0) }
        }
        return nil
    }

    // Caché en la carpeta de datos de la app.
    static func cacheURL(_ env: DevEnvironment) -> URL { URL(fileURLWithPath: env.supportDirectory).appendingPathComponent("desglose.json") }

    public static func cached(_ env: DevEnvironment) -> StorageBreakdown? {
        guard let data = try? Data(contentsOf: cacheURL(env)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StorageBreakdown.self, from: data)
    }

    public static func save(_ breakdown: StorageBreakdown, _ env: DevEnvironment) {
        let url = cacheURL(env)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(breakdown).write(to: url, options: .atomic)
    }
}

private final class ResultsBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var results: [Usage?]
    private var done = 0
    init(count: Int) { results = Array(repeating: nil, count: count) }
    func store(_ index: Int, _ usage: Usage) -> Int {
        lock.lock(); defer { lock.unlock() }
        results[index] = usage
        done += 1
        return done
    }
}
