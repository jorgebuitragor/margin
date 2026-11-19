import SwiftUI
import AppKit
import UserNotifications
import SpaceCore

/// Estado de un permiso de macOS que Margin usa.
enum PermissionState: Equatable {
    case granted, denied, notAsked, unknown
}

/// Ajustes › Permisos: los tres permisos de macOS que Margin puede usar, con su estado y una forma de activarlos.
///
/// macOS no deja que una app se conceda «Acceso total al disco»: lo más que puede hacer es abrir el panel correcto.
/// Las notificaciones y el control de Finder sí se pueden pedir desde aquí con el diálogo del sistema.
struct PermissionsSection: View {
    let palette: Palette
    @State private var fullDisk = PermissionState.unknown
    @State private var notifications = PermissionState.unknown
    @State private var finder = PermissionState.unknown

    var body: some View {
        Section {
            row(t("Acceso total al disco"), "internaldrive", fullDisk,
                detail: t("Para medir la Papelera, las copias del iPhone y carpetas protegidas de otras apps. macOS no deja pedirlo desde una app: se activa en Ajustes del Sistema y después hay que cerrar y abrir Margin."),
                action: (t("Abrir Ajustes del Sistema…"), { openFullDiskAccessSettings() }))
            row(t("Notificaciones"), "bell.badge", notifications,
                detail: t("Para el aviso de poco espacio."),
                action: notifications == .notAsked ? (t("Permitir…"), { requestNotifications() })
                    : (t("Abrir Ajustes del Sistema…"), { open("x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "local.margin.mac")") }))
            row(t("Controlar Finder"), "folder.badge.gearshape", finder,
                detail: t("Para vaciar la Papelera: Margin se lo pide a Finder. Si no lo permites ahora, macOS lo preguntará la primera vez que la vacíes."),
                action: finder == .notAsked || finder == .unknown ? (t("Permitir…"), { requestFinder() })
                    : (t("Abrir Ajustes del Sistema…"), { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") }))
        } header: {
            Text(t("Permisos"))
        } footer: {
            Text(t("Ninguno es obligatorio: sin ellos Margin funciona, pero mide menos o no puede avisarte ni vaciar la Papelera. Se comprueban otra vez cada vez que vuelves a Margin."))
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    func row(_ title: String, _ icon: String, _ state: PermissionState, detail: String, action: (String, () -> Void)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                HStack(spacing: 10) {
                    Label(label(state), systemImage: state == .granted ? "checkmark.circle.fill" : state == .denied ? "xmark.circle" : "circle.dashed")
                        .foregroundStyle(state == .granted ? palette.accent : state == .denied ? palette.warning : .secondary)
                    if state != .granted { Button(action.0, action: action.1) }
                }
            } label: {
                Label(title, systemImage: icon)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    func label(_ state: PermissionState) -> String {
        switch state {
        case .granted: return t("Concedido")
        case .denied: return t("Denegado")
        case .notAsked: return t("Sin pedir")
        case .unknown: return t("No concedido")
        }
    }

    func refresh() {
        fullDisk = TrashStatus.read(appEnvironment()).bytes != nil ? .granted : .unknown
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let state: PermissionState = switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: .granted
            case .denied: .denied
            case .notDetermined: .notAsked
            @unknown default: .unknown
            }
            Task { @MainActor in notifications = state }
        }
        Task.detached(priority: .utility) {
            let state = FinderAutomation.state(ask: false)
            await MainActor.run { finder = state }
        }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in refresh() }
        }
    }

    func requestFinder() {
        Task.detached(priority: .userInitiated) {
            let state = FinderAutomation.state(ask: true)
            await MainActor.run { finder = state }
        }
    }

    func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}

/// Permiso de Automatización para enviar eventos a Finder (lo usa «Vaciar Papelera»).
enum FinderAutomation {
    /// Con `ask`, macOS muestra su diálogo si aún no se ha decidido. Bloquea hasta que el usuario responde: no llamar
    /// desde el hilo principal.
    static func state(ask: Bool) -> PermissionState {
        // Finder siempre está abierto; si no, AEDeterminePermission… devuelve procNotFound y el estado queda desconocido.
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        guard let desc = target.aeDesc else { return .unknown }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        default: return .unknown
        }
    }
}
