import Foundation

/// Decide si avisar de poco espacio. Se comprueba cada hora (agente de inicio de macOS, solo si lo activas en Ajustes)
/// y avisa como mucho una vez al día, salvo que el espacio libre siga bajando de forma clara.
public enum SpaceAlert {
    /// Bajada (en bytes) desde el último aviso que justifica avisar antes de que pase un día.
    public static let furtherDrop: Int64 = 2_000_000_000
    public static let quietPeriod: TimeInterval = 24 * 3600

    public static func shouldNotify(available: Int64, threshold: Int64, lastAlert: Date?, lastAvailable: Int64?, now: Date = Date()) -> Bool {
        guard available < threshold else { return false }
        guard let lastAlert else { return true }
        if now.timeIntervalSince(lastAlert) >= quietPeriod { return true }
        if let lastAvailable, lastAvailable - available >= furtherDrop { return true }
        return false
    }
}
