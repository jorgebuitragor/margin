import SwiftUI
import AppKit
import SpaceCore

extension ContentView {
    /// Grupos del análisis inteligente: qué perfiles suma cada tarjeta.
    static let groups: [(title: String, icon: String, ids: Set<String>)] = [
        ("Desarrollo", "hammer", Set(DevProfiles.ids).subtracting(DevProfiles.generalIDs)),
        ("Cachés de apps", "square.stack.3d.up", ["app-caches"]),
        ("Registros", "doc.text", ["logs"]),
        ("Descargas", "arrow.down.circle", ["downloads"]),
        ("Copias de iPhone", "iphone", ["ios-backups"])
    ]

    var diskCard: some View {
        DiskBar(capacity: model.capacity, storage: model.storage, progress: model.storageProgress, palette: palette) { model.measureStorage() }
            .padding(18)
            .background(palette.cardFill, in: RoundedRectangle(cornerRadius: 12))
            .overlay { if highContrast { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.35)) } }
    }

    var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                diskCard
                if let report = model.dev {
                    let items = report.profiles.flatMap(\.items)
                    let lowRisk = items.filter { $0.category == .lowRisk && $0.canDelete }
                    HStack(spacing: 14) {
                        metric(t("Recuperable sin riesgo"), size(report.lowRiskBytes), "checkmark.circle")
                        metric(t("Para revisar"), size(report.reviewBytes), "eye")
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Self.groups, id: \.title) { group in
                            let groupItems = report.profiles.filter { group.ids.contains($0.id) }.flatMap(\.items)
                            let low = groupItems.filter { $0.category == .lowRisk }.reduce(Int64(0)) { $0 + ($1.recoverable ?? 0) }
                            let review = groupItems.filter { $0.category == .review }.reduce(Int64(0)) { $0 + ($1.recoverable ?? 0) }
                            card(t(group.title), group.icon, primary: size(low), detail: review > 0 ? t("y %@ para revisar", size(review)) : (groupItems.isEmpty ? t("Nada que proponer") : t("Nada para revisar"))) {
                                Button(t("Ver detalle")) { tab = "Limpieza" }.buttonStyle(.link)
                            }
                        }
                        card(t("Papelera"), "trash", primary: model.trash?.bytes.map { size($0) } ?? t("Tamaño desconocido"),
                             detail: model.trash?.items.map { t("%@ · se libera al vaciarla", tn($0, "elemento", "elementos")) } ?? t("macOS no deja leerla sin «Acceso total al disco»")) {
                            Button(model.emptying ? t("Vaciando…") : t("Vaciar Papelera…"), role: .destructive) { confirmEmpty = true }
                                .disabled(model.emptying || model.trash?.items == 0)
                        }
                    }
                    HStack {
                        Text(t("«Revisar y limpiar» incluye solo lo de bajo riesgo (%@). Lo marcado «para revisar» se elige uno por uno en Limpieza. Antes de ejecutar verás el plan completo.", tn(lowRisk.count, "elemento", "elementos")))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if model.preparing { ProgressView().controlSize(.small) }
                        Button(t("Revisar y limpiar (%@)…", size(lowRisk.reduce(Int64(0)) { $0 + ($1.recoverable ?? 0) })), systemImage: "sparkles") {
                            model.prepare(devItems: lowRisk)
                        }.buttonStyle(.borderedProminent).tint(accent).disabled(lowRisk.isEmpty || model.preparing || model.applying)
                    }
                } else if model.devBusy {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text(t("Revisando cachés, registros, descargas, herramientas de desarrollo y la Papelera…")).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 60)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(accent)
                        Text(t("Análisis inteligente")).font(.title2.bold())
                        Text(t("Revisa en menos de un minuto los lugares donde se acumula espacio: cachés de apps, registros, instaladores viejos, herramientas de desarrollo y la Papelera. No borra nada sin tu confirmación."))
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 520)
                        Button(t("Analizar ahora"), systemImage: "sparkles") { model.analyzeDev() }.buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
                    }.frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
        }
    }

    var development: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                metric(t("Bajo riesgo · recuperable estimado"), model.dev.map { size($0.lowRiskBytes) } ?? "—", "checkmark.circle")
                metric(t("Para revisar"), model.dev.map { size($0.reviewBytes) } ?? "—", "eye")
                availableMetric
            }
            if model.devBusy {
                HStack { ProgressView().controlSize(.small); Text(t("Midiendo cachés y proyectos… (unos 30 s)")) }
            }
            if let report = model.dev {
                let items = report.profiles.filter { $0.detected && !$0.items.isEmpty }
                List(selection: $devSelection) {
                    ForEach(items) { profile in
                        Section("\(profile.name) · \(profile.owner)") {
                            ForEach(profile.items) { item in
                                HStack(spacing: 10) {
                                    Toggle("", isOn: Binding(get: { devChecked.contains(item.id) }, set: { on in if on { devChecked.insert(item.id) } else { devChecked.remove(item.id) } }))
                                        .toggleStyle(.checkbox).labelsHidden().disabled(!item.canDelete)
                                        .accessibilityLabel(t("Incluir %@ en el plan", item.title))
                                    Image(systemName: item.category == .lowRisk ? "checkmark.circle" : item.category == .review ? "eye" : "lock")
                                        .foregroundStyle(item.category == .lowRisk ? accent : item.category == .review ? palette.warning : .secondary)
                                    Text(item.title).lineLimit(1)
                                    Spacer()
                                    Text(t(item.category.rawValue)).font(.caption).foregroundStyle(.secondary)
                                    Text(size(item.recoverable ?? item.bytes)).monospacedDigit().frame(width: 90, alignment: .trailing)
                                }
                                .tag(item.id)
                                .accessibilityElement(children: .combine)
                            }
                            ForEach(profile.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }.frame(minHeight: 260)
                if let item = items.flatMap(\.items).first(where: { $0.id == devSelection }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.title).font(.headline)
                            Spacer()
                            if let path = item.path, FileManager.default.fileExists(atPath: path) {
                                Button(t("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                            }
                        }
                        Text(item.reason)
                        Text(t("Si se retira: %@", item.regenerate)).foregroundStyle(.secondary)
                        Text(t("Ocupa %@ · recuperable estimado %@", size(item.bytes), size(item.recoverable))).font(.caption)
                        if let action = item.action {
                            HStack {
                                Text(action.command).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                Spacer()
                                Button(t("Copiar"), systemImage: "doc.on.doc") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(action.kind == .command ? action.command : (item.path ?? ""), forType: .string)
                                }
                            }
                            if let preview = action.preview { Text(t("Vista previa: %@", preview)).font(.caption).textSelection(.enabled) }
                            if let note = action.note { Text(note).font(.caption).foregroundStyle(palette.warning) }
                        }
                    }.padding(16).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                let checked = items.flatMap(\.items).filter { devChecked.contains($0.id) && $0.canDelete }
                HStack {
                    Text(t("Marca elementos y revisa el plan antes de ejecutar. «Recuperable estimado» excluye archivos con enlaces duros compartidos."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.preparing { ProgressView().controlSize(.small) }
                    Button(t("Revisar plan (%@)…", "\(checked.count)"), systemImage: "list.bullet.clipboard") { model.prepare(devItems: checked) }
                        .disabled(checked.isEmpty || model.preparing || model.applying)
                }
            } else if !model.devBusy {
                ContentUnavailableView(t("Analiza qué se puede limpiar"), systemImage: "hammer", description: Text(t("Cachés de apps, registros, descargas, Android SDK y emuladores, simuladores y Xcode, node_modules de proyectos inactivos, pnpm, Gradle, Docker, Homebrew…")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
