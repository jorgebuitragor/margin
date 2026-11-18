import Foundation
import Darwin

// MARK: Modelo

/// Identidad de un archivo o carpeta en el momento de planificar. Si cambia, la acción se bloquea.
public struct FileIdentity: Codable, Sendable, Equatable {
    public let device: Int64
    public let inode: UInt64
    public let isDirectory: Bool
    public let size: Int64
    public let modified: TimeInterval

    public static func of(_ path: String) -> FileIdentity? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let type = st.st_mode & S_IFMT
        guard type == S_IFDIR || type == S_IFREG else { return nil } // Nunca enlaces ni dispositivos.
        return FileIdentity(device: Int64(st.st_dev), inode: UInt64(st.st_ino), isDirectory: type == S_IFDIR, size: Int64(st.st_size),
                            modified: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
    }

    /// Para carpetas basta con que sea el mismo objeto (su fecha cambia con cualquier escritura dentro y la revalidación
    /// del perfil ya decide si sigue siendo candidata). Para archivos además deben coincidir tamaño y fecha.
    func sameObject(as other: FileIdentity) -> Bool {
        guard device == other.device, inode == other.inode, isDirectory == other.isDirectory else { return false }
        return isDirectory || (size == other.size && abs(modified - other.modified) < 0.001)
    }
}

public struct PlanStep: Codable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable { case profile, file }
    public let id: String
    public let shortID: String
    public let source: Source
    public let profile: String?
    public let title: String
    public let category: Category
    public let reason: String
    public let regenerate: String
    public let action: DevAction
    public let identities: [String: FileIdentity]
    public let bytes: Int64?
    public let recoverable: Int64?
}

public struct Plan: Codable, Sendable, Identifiable {
    public let id: String
    public let created: Date
    public let home: String
    public let steps: [PlanStep]
    /// Configuración del análisis con que se creó: la revalidación usa la misma.
    public let inactiveDays: Int
    public let projectRoots: [String]
    public var recoverable: Int64 { steps.reduce(0) { $0 + ($1.recoverable ?? 0) } }

    /// Entorno equivalente al de creación, para revalidar.
    public func environment(from base: DevEnvironment) -> DevEnvironment {
        var env = base
        env.inactiveDays = inactiveDays
        env.projectRoots = projectRoots.map { URL(fileURLWithPath: $0) }
        return env
    }
}

public struct StepResult: Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case done = "hecho"
        case partial = "parcial"
        case failed = "falló"
        case blocked = "bloqueado"
    }
    public let stepID: String
    public let title: String
    public let status: Status
    public let message: String
    public var trashed: [String] = []
    public var failures: [String: String] = [:]
    /// Últimas líneas de la salida del comando (máx. 4 KB).
    public var output: String?
}

public struct ApplyReport: Codable, Sendable {
    public let planID: String
    public let started: Date
    public var finished: Date
    public var availableBefore: Int64?
    public var availableAfter: Int64?
    public var results: [StepResult]
    /// Algo fue a la Papelera: ese espacio no se libera hasta vaciarla.
    public var usedTrash: Bool { results.contains { !$0.trashed.isEmpty } }
    public var freedObserved: Int64? {
        guard let before = availableBefore, let after = availableAfter else { return nil }
        return after - before
    }
}

public enum PlanError: LocalizedError {
    case notEligible(String)
    case missing(String)
    case notFound(String)
    case expired
    case alreadyApplied
    case wrongHome
    public var errorDescription: String? {
        switch self {
        case .notEligible(let title): return loc("«\(title)» no se puede incluir en un plan (protegido, sin acción o no revisable).", "“\(title)” can't be included in a plan (protected, no action or not reviewable).")
        case .missing(let path): return loc("No existe o no es un archivo o carpeta normal: \(path)", "Doesn't exist or isn't a regular file or folder: \(path)")
        case .notFound(let id): return loc("No se encontró \(id).", "\(id) wasn't found.")
        case .expired: return loc("El plan tiene más de 24 horas. Vuelve a crearlo para trabajar con datos actuales.", "The plan is more than 24 hours old. Create it again to work with current data.")
        case .alreadyApplied: return loc("Este plan ya se aplicó. Crea uno nuevo.", "This plan was already applied. Create a new one.")
        case .wrongHome: return loc("El plan se creó para otra carpeta personal.", "The plan was created for another home folder.")
        }
    }
}

// MARK: Ejecutor

/// Las dos únicas operaciones de escritura del programa. No existe borrado permanente.
public protocol ActionExecutor: Sendable {
    /// Mueve a la Papelera. Devuelve la ruta resultante dentro de la Papelera.
    func trash(_ path: String) throws -> String?
    func run(_ executable: String, _ arguments: [String]) -> CommandResult?
}

public struct SystemExecutor: ActionExecutor {
    public init() {}
    public func trash(_ path: String) throws -> String? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
        return resulting?.path
    }
    public func run(_ executable: String, _ arguments: [String]) -> CommandResult? {
        ProcessRunner().run(executable, arguments, timeout: 30 * 60)
    }
}

// MARK: Almacén y registro

public enum PlanStore {
    static func directory(_ env: DevEnvironment) -> String { "\(env.supportDirectory)/planes" }

    public static func save(_ plan: Plan, _ env: DevEnvironment) throws {
        try FileManager.default.createDirectory(atPath: directory(env), withIntermediateDirectories: true)
        try encoder.encode(plan).write(to: URL(fileURLWithPath: "\(directory(env))/\(plan.id).json"), options: .atomic)
    }

    public static func load(_ id: String, _ env: DevEnvironment) throws -> Plan {
        guard id.range(of: #"^[0-9a-f]{8}$"#, options: .regularExpression) != nil,
              let data = FileManager.default.contents(atPath: "\(directory(env))/\(id).json") else { throw PlanError.notFound(loc("el plan \(id)", "plan \(id)")) }
        return try decoder.decode(Plan.self, from: data)
    }

    static func resultPath(_ id: String, _ env: DevEnvironment) -> String { "\(directory(env))/\(id).resultado.json" }

    public static func isApplied(_ id: String, _ env: DevEnvironment) -> Bool { FileManager.default.fileExists(atPath: resultPath(id, env)) }

    static func saveResult(_ report: ApplyReport, _ env: DevEnvironment) {
        try? encoder.encode(report).write(to: URL(fileURLWithPath: resultPath(report.planID, env)), options: .atomic)
    }

    /// Registro local de acciones, una línea JSON por paso. Sin contenido de archivos.
    static func log(_ result: StepResult, plan: Plan, availableBefore: Int64?, _ env: DevEnvironment) {
        struct Line: Encodable { let date: Date; let plan: String; let step: String; let title: String; let status: String; let message: String; let trashed: [String]; let failures: [String: String]; let availableBefore: Int64? }
        let line = Line(date: Date(), plan: plan.id, step: result.stepID, title: result.title, status: result.status.rawValue, message: result.message, trashed: result.trashed, failures: result.failures, availableBefore: availableBefore)
        let compact = JSONEncoder()
        compact.dateEncodingStrategy = .iso8601
        compact.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? compact.encode(line) else { return }
        data.append(0x0A)
        let path = "\(env.supportDirectory)/acciones.jsonl"
        try? FileManager.default.createDirectory(atPath: env.supportDirectory, withIntermediateDirectories: true)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e
    }
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

// MARK: Planificación, revalidación y ejecución

public enum Planner {
    public static let maxAge: TimeInterval = 24 * 3600

    /// Crea un plan con identidades capturadas ahora. Rechaza lo protegido, desconocido o sin acción.
    public static func plan(devItems: [DevItem] = [], files: [FileEntry] = [], env: DevEnvironment) throws -> Plan {
        var steps: [PlanStep] = []
        for item in devItems {
            guard item.canDelete, let action = item.action else { throw PlanError.notEligible(item.title) }
            var identities: [String: FileIdentity] = [:]
            for path in action.paths {
                guard let identity = FileIdentity.of(path) else { throw PlanError.missing(path) }
                identities[path] = identity
            }
            steps.append(PlanStep(id: item.id, shortID: item.shortID, source: .profile, profile: item.profile, title: item.title, category: item.category, reason: item.reason, regenerate: item.regenerate, action: action, identities: identities, bytes: item.bytes, recoverable: item.recoverable))
        }
        for original in files {
            guard original.classification.category == .review, original.bytes != nil else { throw PlanError.notEligible(original.name) }
            // Se actúa siempre sobre la ruta real (por ejemplo /tmp → /private/tmp): la identidad garantiza que es el mismo archivo.
            let entry = FileEntry(path: DevEnvironment.canonical(original.path), bytes: original.bytes, allocatedBytes: original.allocatedBytes, modified: original.modified, classification: original.classification)
            guard let identity = FileIdentity.of(entry.path), !identity.isDirectory else { throw PlanError.missing(entry.path) }
            let id = "file:\(entry.path)"
            steps.append(PlanStep(id: id, shortID: DevItem(profile: "file", title: entry.name, path: entry.path, bytes: nil, recoverable: nil, category: .review, reason: "", regenerate: "", action: nil).shortID,
                                  source: .file, profile: nil, title: entry.name, category: .review, reason: entry.classification.reason, regenerate: entry.classification.consequence,
                                  action: .trash(entry.path), identities: [entry.path: identity], bytes: entry.allocatedBytes, recoverable: entry.allocatedBytes))
        }
        guard !steps.isEmpty else { throw PlanError.notFound(loc("ningún elemento para el plan", "no item for the plan")) }
        let id = String(format: "%08x", UInt32.random(in: 0...UInt32.max))
        return Plan(id: id, created: env.now, home: env.home.path, steps: steps, inactiveDays: env.inactiveDays, projectRoots: env.projectRoots.map(\.path))
    }

    /// Vistas previas (dry-run) de los comandos que las ofrecen. Solo lectura.
    public static func previews(_ plan: Plan, env: DevEnvironment) -> [String: String] {
        var out: [String: String] = [:]
        for step in plan.steps {
            guard let argv = step.action.previewArgv, let first = argv.first, let exe = env.executable(for: first),
                  let result = env.runner.run(exe, Array(argv.dropFirst()), timeout: 120) else { continue }
            out[step.id] = tail(result.output)
        }
        return out
    }

    /// Comprueba un paso justo antes de actuar. Devuelve el motivo del bloqueo o nil si se puede ejecutar.
    public static func blocker(_ step: PlanStep, plan: Plan, env: DevEnvironment, freshProfiles: inout [String: ProfileResult]) -> String? {
        if env.now.timeIntervalSince(plan.created) > maxAge { return PlanError.expired.localizedDescription }
        if plan.home != env.home.path { return PlanError.wrongHome.localizedDescription }
        for check in step.action.requiresClosed where env.isRunning(check) { return loc("Cierra \(check.label) antes de continuar.", "Quit \(check.label) before continuing.") }
        switch step.source {
        case .profile:
            guard let profileID = step.profile else { return loc("Paso sin perfil.", "Step without a profile.") }
            if freshProfiles[profileID] == nil { freshProfiles[profileID] = DevProfiles.profile(profileID, env) }
            guard let fresh = freshProfiles[profileID]?.items.first(where: { $0.id == step.id }) else {
                return loc("Ya no aparece en el análisis actual (puede que ya se haya limpiado).", "It no longer shows up in the current scan (it may already have been cleaned).")
            }
            guard fresh.canDelete, fresh.category == step.category else {
                return loc("Cambió de categoría (ahora: \(fresh.category.rawValue)). Vuelve a crear el plan.", "Its category changed (now: \(fresh.category.rawValue)). Create the plan again.")
            }
            guard fresh.action == step.action else { return loc("La acción propuesta cambió. Vuelve a crear el plan.", "The suggested action changed. Create the plan again.") }
        case .file:
            for path in step.action.paths {
                let url = URL(fileURLWithPath: path)
                if Classifier.classify(url).category != .review { return loc("Ya no se clasifica como archivo revisable.", "It's no longer classified as a reviewable file.") }
                if let reason = Classifier.protectedReason(url) { return reason }
                if let sync = SyncDetector.provider(forDirectoryOrAncestors: url.deletingLastPathComponent()) {
                    return loc("Está en una carpeta sincronizada con \(sync.provider).", "It's in a folder synced with \(sync.provider).")
                }
            }
        }
        if step.action.kind == .trash {
            for path in step.action.paths {
                if let problem = pathProblem(path, env: env) { return problem }
                guard let now = FileIdentity.of(path), let planned = step.identities[path], now.sameObject(as: planned) else {
                    return loc("Cambió desde que se planificó: \(path)", "Changed since it was planned: \(path)")
                }
            }
        }
        if step.action.kind == .command {
            guard let name = step.action.argv?.first, env.executable(for: name) != nil else { return loc("No se encontró la herramienta \(step.action.argv?.first ?? "?").", "The tool \(step.action.argv?.first ?? "?") wasn't found.") }
        }
        if step.action.kind == .manual { return loc("Esta acción solo se puede hacer a mano.", "This action can only be done by hand.") }
        return nil
    }

    /// Reglas de seguridad independientes de los perfiles para cualquier ruta que se mueva a la Papelera.
    static func pathProblem(_ path: String, env: DevEnvironment) -> String? {
        let home = env.home.path
        guard path.hasPrefix(home + "/") else { return loc("Fuera de tu carpeta personal: \(path)", "Outside your home folder: \(path)") }
        let below = path.dropFirst(home.count + 1).split(separator: "/")
        guard below.count >= 2, !below.contains("..") else { return loc("Ruta demasiado general para retirarla: \(path)", "Path too general to remove: \(path)") }
        // Ningún componente puede ser un enlace: realpath debe coincidir con la ruta pedida.
        guard let real = realpath(path, nil) else { return loc("No existe: \(path)", "Doesn't exist: \(path)") }
        defer { free(real) }
        guard String(cString: real) == path else { return loc("La ruta pasa por un enlace simbólico: \(path)", "The path goes through a symbolic link: \(path)") }
        return nil
    }

    /// Ejecuta un plan ya confirmado por el usuario. Cada paso se revalida justo antes de actuar.
    public static func apply(_ plan: Plan, env: DevEnvironment, executor: ActionExecutor = SystemExecutor(), progress: (StepResult) -> Void = { _ in }) throws -> ApplyReport {
        if PlanStore.isApplied(plan.id, env) { throw PlanError.alreadyApplied }
        if env.now.timeIntervalSince(plan.created) > maxAge { throw PlanError.expired }
        var report = ApplyReport(planID: plan.id, started: Date(), finished: Date(), availableBefore: available(env), availableAfter: nil, results: [])
        var fresh: [String: ProfileResult] = [:]
        for step in plan.steps {
            let result: StepResult
            if let reason = blocker(step, plan: plan, env: env, freshProfiles: &fresh) {
                result = StepResult(stepID: step.id, title: step.title, status: .blocked, message: reason)
            } else if step.action.kind == .trash {
                result = trash(step, executor: executor)
            } else {
                result = command(step, env: env, executor: executor)
            }
            // Tras actuar, los perfiles cambian: se recalculan para el siguiente paso.
            if result.status != .blocked, let profile = step.profile { fresh[profile] = nil }
            report.results.append(result)
            PlanStore.log(result, plan: plan, availableBefore: report.availableBefore, env)
            progress(result)
        }
        report.availableAfter = available(env)
        report.finished = Date()
        PlanStore.saveResult(report, env)
        return report
    }

    static func trash(_ step: PlanStep, executor: ActionExecutor) -> StepResult {
        var result = StepResult(stepID: step.id, title: step.title, status: .done, message: "")
        for path in step.action.paths {
            // Última comprobación inmediatamente antes de mover.
            guard let now = FileIdentity.of(path), let planned = step.identities[path], now.sameObject(as: planned) else {
                result.failures[path] = loc("Cambió justo antes de moverlo; no se tocó.", "Changed right before moving it; it wasn't touched.")
                continue
            }
            do {
                _ = try executor.trash(path)
                result.trashed.append(path)
            } catch {
                result.failures[path] = error.localizedDescription // Nunca se recurre al borrado permanente.
            }
        }
        let status: StepResult.Status = result.failures.isEmpty ? .done : result.trashed.isEmpty ? .failed : .partial
        let message = status == .done ? loc("Movido a la Papelera (\(result.trashed.count)).", "Moved to the Trash (\(result.trashed.count)).") : loc("\(result.trashed.count) movidos, \(result.failures.count) con error.", "\(result.trashed.count) moved, \(result.failures.count) with errors.")
        return StepResult(stepID: step.id, title: step.title, status: status, message: message, trashed: result.trashed, failures: result.failures)
    }

    static func command(_ step: PlanStep, env: DevEnvironment, executor: ActionExecutor) -> StepResult {
        guard let argv = step.action.argv, let name = argv.first, let exe = env.executable(for: name) else {
            return StepResult(stepID: step.id, title: step.title, status: .blocked, message: loc("Sin comando ejecutable.", "No executable command."))
        }
        // Los comandos de las herramientas (brew, docker, sdkmanager…) actúan sobre todo el Mac, no sobre la carpeta
        // personal: con una carpeta sintética (modo de prueba) no se ejecutan de verdad.
        if executor is SystemExecutor && DevEnvironment.canonical(env.home.path) != DevEnvironment.canonical(FileManager.default.homeDirectoryForCurrentUser.path) {
            return StepResult(stepID: step.id, title: step.title, status: .blocked, message: loc("Modo de prueba: los comandos de las herramientas actúan sobre todo el Mac y no se ejecutan con una carpeta personal sintética.", "Test mode: tool commands act on the whole Mac and don't run with a synthetic home folder."))
        }
        guard let result = executor.run(exe, Array(argv.dropFirst())) else {
            return StepResult(stepID: step.id, title: step.title, status: .failed, message: loc("No se pudo ejecutar o superó el tiempo máximo.", "Couldn't run it or it exceeded the time limit."))
        }
        return StepResult(stepID: step.id, title: step.title, status: result.status == 0 ? .done : .failed,
                          message: result.status == 0 ? loc("Comando terminado.", "Command finished.") : loc("El comando terminó con código \(result.status).", "The command ended with code \(result.status)."),
                          output: tail([result.output, result.error].filter { !$0.isEmpty }.joined(separator: "\n")))
    }

    static func available(_ env: DevEnvironment) -> Int64? {
        (try? env.home.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
    }

    static func tail(_ text: String) -> String {
        let data = Data(text.utf8)
        return data.count <= 4096 ? text : "…" + String(decoding: data.suffix(4096), as: UTF8.self)
    }
}
