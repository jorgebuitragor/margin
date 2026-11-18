import SwiftUI

/// Confirmación de una acción que no se puede deshacer (vaciar la Papelera, activar el borrado definitivo).
///
/// No es un `.alert` del sistema: en macOS el primer botón no cancelador de un alert es el predeterminado, así que
/// Retorno ejecutaría la acción destructiva. Aquí Retorno y Escape cancelan; el botón rojo solo se pulsa a propósito.
struct DestructiveConfirmation: View {
    let title: String
    let message: String
    let actionTitle: String
    let danger: Color
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(danger)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.title3.bold())
                    Text(message).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button(actionTitle, role: .destructive, action: onConfirm)
                    .tint(danger)
                Button(t("Cancelar"), action: onCancel)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onExitCommand(perform: onCancel)
    }
}
