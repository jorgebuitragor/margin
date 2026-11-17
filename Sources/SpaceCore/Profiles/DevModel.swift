import Foundation

/// Acción propuesta para un elemento. En la 0.3 es solo una propuesta: nada se ejecuta.
public struct DevAction: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// Comando oficial de la herramienta dueña.
        case command
        /// Mover a la Papelera (cuando la herramienta no ofrece comando).
        case trash
    }
    public let kind: Kind
    /// Comando a ejecutar, o descripción de la acción de Papelera.
    public let command: String
    /// Variante de vista previa (dry-run) si la herramienta la ofrece.
    public let preview: String?
    /// Condición previa, por ejemplo «cierra la app antes».
    public let note: String?

    public static func run(_ command: String, preview: String? = nil, note: String? = nil) -> DevAction {
        DevAction(kind: .command, command: command, preview: preview, note: note)
    }
    public static func trash(_ path: String, note: String? = nil) -> DevAction {
        DevAction(kind: .trash, command: "Mover a la Papelera: \(path)", preview: nil, note: note)
    }
}

public struct DevItem: Codable, Sendable, Identifiable {
    public var id: String { "\(profile):\(path ?? title)" }
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
    /// La 0.3 no ejecuta nada.
    public private(set) var canDelete = false

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
