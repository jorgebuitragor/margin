import Foundation

/// Proceso que debe estar cerrado antes de actuar (se comprueba con `pgrep -f patrón`).
public struct ProcessCheck: Codable, Sendable, Equatable {
    public let label: String
    public let pattern: String
    /// Si se indica, se comprueba la app por su identificador (`lsappinfo find bundleid=…`) en lugar de `pgrep`.
    public var bundleID: String? = nil
    public static let xcode = ProcessCheck(label: "Xcode", pattern: "Xcode.app/Contents/MacOS/Xcode")
    public static let simulator = ProcessCheck(label: "Simulator", pattern: "Simulator.app/Contents/MacOS/Simulator")
    public static let emulator = ProcessCheck(label: "el emulador de Android", pattern: "qemu-system-")
    public static let gradle = ProcessCheck(label: "los daemons de Gradle (gradle --stop)", pattern: "GradleDaemon")
    public static let claude = ProcessCheck(label: "Claude", pattern: "Claude.app/Contents/MacOS/Claude")
    public static let vscode = ProcessCheck(label: "VS Code", pattern: "Visual Studio Code.app/Contents/MacOS/")
}

/// Acción propuesta para un elemento. Se ejecuta solo mediante un plan confirmado por el usuario (ver Actions/).
public struct DevAction: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// Comando oficial de la herramienta dueña.
        case command
        /// Mover a la Papelera (cuando la herramienta no ofrece comando).
        case trash
        /// Solo se puede hacer a mano (por ejemplo, desde la app dueña).
        case manual
    }
    public let kind: Kind
    /// Texto para mostrar: el comando o la descripción de la acción.
    public let command: String
    /// Vista previa (dry-run) si la herramienta la ofrece, en texto.
    public let preview: String?
    /// Condición previa, por ejemplo «cierra la app antes».
    public let note: String?
    /// Ejecutable (nombre de herramienta) y argumentos. Nunca se pasa por una shell.
    public var argv: [String]? = nil
    public var previewArgv: [String]? = nil
    /// Rutas exactas que se moverían a la Papelera.
    public var paths: [String] = []
    /// Procesos que deben estar cerrados.
    public var requiresClosed: [ProcessCheck] = []

    public static func run(_ argv: [String], preview: [String]? = nil, note: String? = nil, closed: [ProcessCheck] = []) -> DevAction {
        DevAction(kind: .command, command: display(argv), preview: preview.map(display), note: note, argv: argv, previewArgv: preview, paths: [], requiresClosed: closed)
    }
    public static func trash(_ path: String, note: String? = nil, closed: [ProcessCheck] = []) -> DevAction {
        trash([path], label: path, note: note, closed: closed)
    }
    public static func trash(_ paths: [String], label: String, note: String? = nil, closed: [ProcessCheck] = []) -> DevAction {
        DevAction(kind: .trash, command: "Mover a la Papelera: \(label)", preview: nil, note: note, argv: nil, previewArgv: nil, paths: paths, requiresClosed: closed)
    }

    static func display(_ argv: [String]) -> String {
        argv.map { arg in arg.rangeOfCharacter(from: CharacterSet(charactersIn: " ;\"'$&|<>*?()")) == nil ? arg : "\"" + arg.replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            .joined(separator: " ")
    }
}

public struct DevItem: Codable, Sendable, Identifiable {
    public var id: String { "\(profile):\(path ?? title)" }
    /// Identificador corto y estable (FNV-1a de `id`) para la CLI.
    public var shortID: String {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return String(format: "%08x", hash)
    }
    public let profile: String
    public let title: String
    public let path: String?
    /// Espacio asignado en disco (como du -x).
    public let bytes: Int64?
    /// Estimación conservadora de lo que se recuperaría: excluye archivos con enlaces duros compartidos
    /// (por ejemplo, paquetes de pnpm que siguen en su store). nil si no se puede estimar.
    public let recoverable: Int64?
    public let category: Category
    /// Por qué está en esta categoría, con la evidencia observada.
    public let reason: String
    /// Qué cuesta regenerarlo o qué deja de funcionar.
    public let regenerate: String
    public let action: DevAction?
    public let lastUsed: Date?
    /// Se puede incluir en un plan: tiene acción ejecutable y no está protegido. La ejecución exige confirmación.
    public var canDelete: Bool { category != .protected && category != .unknown && action.map { $0.kind != .manual } == true }

    public init(profile: String, title: String, path: String?, bytes: Int64?, recoverable: Int64?, category: Category, reason: String, regenerate: String, action: DevAction?, lastUsed: Date? = nil) {
        self.profile = profile
        self.title = title
        self.path = path
        self.bytes = bytes
        self.recoverable = recoverable
        self.category = category
        self.reason = reason
        self.regenerate = regenerate
        self.action = action
        self.lastUsed = lastUsed
    }
}

public struct ProfileResult: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// Herramienta dueña de estos datos.
    public let owner: String
    /// Se encontró la herramienta o sus datos en este Mac.
    public var detected: Bool
    public var items: [DevItem] = []
    public var notes: [String] = []
    public var issues: [String] = []

    public var lowRiskBytes: Int64 { items.filter { $0.category == .lowRisk }.reduce(0) { $0 + ($1.recoverable ?? 0) } }
    public var reviewBytes: Int64 { items.filter { $0.category == .review }.reduce(0) { $0 + ($1.recoverable ?? 0) } }
}

public struct DevReport: Codable, Sendable {
    public let date: Date
    public var profiles: [ProfileResult]
    public var projectRoots: [String]
    public var inactiveDays: Int
    /// Suma de lo recuperable en candidatos de bajo riesgo.
    public var lowRiskBytes: Int64 { profiles.reduce(0) { $0 + $1.lowRiskBytes } }
    /// Suma de lo recuperable en elementos para revisar.
    public var reviewBytes: Int64 { profiles.reduce(0) { $0 + $1.reviewBytes } }

    enum CodingKeys: String, CodingKey { case date, profiles, projectRoots, inactiveDays, lowRiskBytes, reviewBytes }
    public init(date: Date, profiles: [ProfileResult], projectRoots: [String], inactiveDays: Int) {
        self.date = date
        self.profiles = profiles
        self.projectRoots = projectRoots
        self.inactiveDays = inactiveDays
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        profiles = try c.decode([ProfileResult].self, forKey: .profiles)
        projectRoots = try c.decode([String].self, forKey: .projectRoots)
        inactiveDays = try c.decode(Int.self, forKey: .inactiveDays)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(profiles, forKey: .profiles)
        try c.encode(projectRoots, forKey: .projectRoots)
        try c.encode(inactiveDays, forKey: .inactiveDays)
        try c.encode(lowRiskBytes, forKey: .lowRiskBytes)
        try c.encode(reviewBytes, forKey: .reviewBytes)
    }
}
