import Foundation
import UserNotifications
import SpaceCore

/// Aviso de poco espacio. Si lo activas en Ajustes, un agente de inicio de macOS (`~/Library/LaunchAgents`) abre
/// Margin sin ventana cada hora con `--aviso-espacio`: mide el espacio libre, avisa si está por debajo del umbral y
/// termina. No mide carpetas ni ejecuta nada más. Al desactivarlo se retira el agente.
enum SpaceAlertAgent {
    static let label = "local.margin.aviso"
    static let argument = "--aviso-espacio"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    struct AgentError: LocalizedError { let errorDescription: String? }

    /// Instala (o reinstala) el agente apuntando al ejecutable de esta copia de Margin.
    static func install() throws {
        guard DevEnvironment.testSetting("HOME") == nil else { throw AgentError(errorDescription: t("No disponible en modo de prueba.")) }
        guard let executable = Bundle.main.executablePath else { throw AgentError(errorDescription: t("No se encontró el ejecutable de Margin.")) }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, argument],
            "StartInterval": 3600,
            "RunAtLoad": false,
            "ProcessType": "Background",
            "LowPriorityIO": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try data.write(to: plistURL, options: .atomic)
        guard launchctl(["bootstrap", "gui/\(getuid())", plistURL.path]) == 0 else {
            throw AgentError(errorDescription: t("macOS no aceptó el agente de inicio (launchctl)."))
        }
    }

    static func uninstall() {
        _ = launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func requestAuthorization(_ completion: @escaping @Sendable (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in completion(granted) }
    }

    /// Lo que hace el agente cada hora. Se ejecuta antes de crear ninguna ventana y termina el proceso.
    static func runCheckAndExit() -> Never {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Pref.alertEnabled), let capacity = VolumeCapacity.read() {
            let threshold = Int64(max(1, defaults.integer(forKey: Pref.alertThreshold))) * 1_000_000_000
            let last = defaults.object(forKey: Pref.alertLastDate) as? Date
            let lastAvailable = (defaults.object(forKey: Pref.alertLastAvailable) as? NSNumber)?.int64Value
            if SpaceAlert.shouldNotify(available: capacity.available, threshold: threshold, lastAlert: last, lastAvailable: lastAvailable) {
                post(available: capacity.available, total: capacity.total)
                defaults.set(Date(), forKey: Pref.alertLastDate)
                defaults.set(NSNumber(value: capacity.available), forKey: Pref.alertLastAvailable)
            }
        }
        exit(0)
    }

    /// Publica la notificación y espera a que macOS la acepte (como mucho 5 s).
    static func post(available: Int64, total: Int64, test: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = test ? t("Aviso de prueba de Margin") : t("Queda poco espacio en el disco")
        content.body = t("%@ disponibles de %@. Abre Margin para ver qué puedes liberar.", size(available), size(total))
        content.sound = .default
        let request = UNNotificationRequest(identifier: test ? "margin.aviso.prueba" : "margin.aviso", content: content, trigger: nil)
        let done = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request) { _ in done.signal() }
        _ = done.wait(timeout: .now() + 5)
    }
}
