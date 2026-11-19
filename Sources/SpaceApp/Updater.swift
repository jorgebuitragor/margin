import SwiftUI
import Combine
import Sparkle
import SpaceCore

/// Actualizaciones con Sparkle desde GitHub Releases (`SUFeedURL` y `SUPublicEDKey` en el Info.plist).
///
/// Cada release publica `appcast.xml` y un ZIP firmado con la clave EdDSA de Sparkle; la app comprueba la firma y que
/// la nueva versión esté firmada con la misma identidad («Margin Local») antes de instalarla, así que macOS conserva
/// los permisos. No se envía ningún dato del Mac (`SUEnableSystemProfiling` queda desactivado).
@MainActor
final class Updater: ObservableObject {
    /// Nil al compilar sin Info.plist (swift run), en modo de prueba o como agente de aviso: ahí no se busca nada.
    private let controller: SPUStandardUpdaterController?
    @Published private(set) var canCheck = false
    @Published var automaticChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticChecks }
    }
    @Published var automaticDownloads: Bool {
        didSet { controller?.updater.automaticallyDownloadsUpdates = automaticDownloads }
    }
    private var observation: AnyCancellable?

    var isAvailable: Bool { controller != nil }

    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        let enabled = configured && DevEnvironment.testSetting("HOME") == nil
        controller = enabled ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
        automaticChecks = controller?.updater.automaticallyChecksForUpdates ?? false
        automaticDownloads = controller?.updater.automaticallyDownloadsUpdates ?? false
        observation = controller?.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).sink { [weak self] in self?.canCheck = $0 }
    }

    func checkNow() { controller?.checkForUpdates(nil) }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    /// Versión visible («0.10.0»), del Info.plist; «dev» al ejecutar sin empaquetar.
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
}

/// Ajustes › Actualizaciones.
struct UpdatesSection: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Section {
            if updater.isAvailable {
                Toggle(t("Buscar actualizaciones automáticamente"), isOn: $updater.automaticChecks)
                Toggle(t("Descargar e instalar las actualizaciones sin preguntar"), isOn: $updater.automaticDownloads)
                    .disabled(!updater.automaticChecks)
                HStack {
                    Button(t("Buscar ahora"), systemImage: "arrow.down.circle") { updater.checkNow() }
                        .disabled(!updater.canCheck)
                    Spacer()
                    Text(updater.lastCheck.map { t("Última comprobación: %@", $0.formatted(.relative(presentation: .named).locale(Localizer.locale))) } ?? t("Aún no se ha comprobado."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(t("Esta copia no se actualiza sola: está compilada sin la configuración de actualizaciones o en modo de prueba.")).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text(t("Actualizaciones"))
        } footer: {
            Text(t("Margin consulta las versiones publicadas en GitHub (github.com/jorgebuitragor/margin) una vez al día. Cada actualización está firmada y solo se instala si la firma coincide; no se envía ningún dato de tu Mac."))
        }
    }
}
