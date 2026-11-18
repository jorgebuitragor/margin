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
        DiskBar(capacity: model.capacity, storage: model.storage, progress: model.storageProgress, palette: palette, reduceMotion: reduceMotion) { model.measureStorage() }
            .padding(20)
            .surface(cornerRadius: 22, highContrast: highContrast)
    }

    var lowRiskItems: [DevItem] {
        (model.dev?.profiles.flatMap(\.items) ?? []).filter { $0.category == .lowRisk && $0.canDelete }
    }

    var home: some View {
        let lowRisk = lowRiskItems
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                diskCard
                if let report = model.dev {
                    GlassEffectContainer(spacing: 14) {
                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                metric(t("Recuperable sin riesgo"), size(report.lowRiskBytes), "checkmark.circle", tint: accent)
                                metric(t("Para revisar"), size(report.reviewBytes), "eye", tint: palette.warning)
                            }
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                                ForEach(Array(Self.groups.enumerated()), id: \.element.title) { index, group in
                                    let groupItems = report.profiles.filter { group.ids.contains($0.id) }.flatMap(\.items)
                                    let low = groupItems.filter { $0.category == .lowRisk }.reduce(Int64(0)) { $0 + ($1.recoverable ?? 0) }
                                    let review = groupItems.filter { $0.category == .review }.reduce(Int64(0)) { $0 + ($1.recoverable ?? 0) }
                                    card(t(group.title), group.icon, primary: size(low), detail: review > 0 ? t("y %@ para revisar", size(review)) : (groupItems.isEmpty ? t("Nada que proponer") : t("Nada para revisar"))) {
                                        Button(t("Ver detalle"), systemImage: "arrow.right") { tab = "Limpieza" }
                                            .buttonStyle(.borderless).labelStyle(.titleAndIcon).font(.callout)
                                    }
                                    .transition(.opacity.combined(with: .scale(scale: 0.94)).animation(.smooth(duration: 0.4).delay(Double(index) * 0.05)))
                                }
                                trashCard
                                    .transition(.opacity.combined(with: .scale(scale: 0.94)).animation(.smooth(duration: 0.4).delay(0.25)))
                            }
                        }
                    }
                    Text(t("«Revisar y limpiar» incluye solo lo de bajo riesgo (%@). Lo marcado «para revisar» se elige uno por uno en Limpieza. Antes de ejecutar verás el plan completo.", tn(lowRisk.count, "elemento", "elementos")))
                        .font(.caption).foregroundStyle(.secondary)
                } else if model.devBusy {
                    loadingCards
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles").font(.system(size: 46)).foregroundStyle(accent.gradient)
                            .symbolEffect(.breathe, options: .repeat(.continuous))
                        Text(t("Análisis inteligente")).font(.title2.bold())
                        Text(t("Revisa en menos de un minuto los lugares donde se acumula espacio: cachés de apps, registros, instaladores viejos, herramientas de desarrollo y la Papelera. No borra nada sin tu confirmación."))
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 520)
                        Button(t("Analizar ahora"), systemImage: "sparkles") { model.analyzeDev() }
                            .buttonStyle(.glassProminent).tint(accent).controlSize(.large)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 36)
                    .surface(cornerRadius: 22, highContrast: highContrast)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 90)
            .animation(.smooth(duration: 0.4), value: model.dev == nil)
            .animation(.smooth(duration: 0.4), value: model.devBusy)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.dev != nil && !lowRisk.isEmpty {
                ActionBar(highContrast: highContrast) {
                    Image(systemName: "sparkles").foregroundStyle(accent)
                    Text(t("%@ sin riesgo, listos para revisar", tn(lowRisk.count, "elemento", "elementos"))).font(.callout)
                    Spacer()
                    if model.preparing { ProgressView().controlSize(.small) }
                    Button(t("Revisar y limpiar (%@)…", size(lowRisk.reduce(Int64(0)) { $0 + ($1.recoverable ?? 0) }))) {
                        model.prepare(devItems: lowRisk)
                    }
                    .buttonStyle(.glassProminent).tint(accent).controlSize(.large)
                    .disabled(model.preparing || model.applying)
                }
            }
        }
        .animation(.smooth(duration: 0.4), value: model.dev != nil && !lowRisk.isEmpty)
    }

    var trashCard: some View {
        card(t("Papelera"), "trash", primary: model.trash?.bytes.map { size($0) } ?? t("Tamaño desconocido"),
             detail: model.trash?.items.map { t("%@ · se libera al vaciarla", tn($0, "elemento", "elementos")) } ?? t("macOS no deja leerla sin «Acceso total al disco»")) {
            HStack {
                Button(model.emptying ? t("Vaciando…") : t("Vaciar Papelera…"), systemImage: "trash", role: .destructive) { confirmEmpty = true }
                    .symbolEffect(.bounce, value: model.emptyResult?.date)
                    .disabled(model.emptying || model.trash?.items == 0)
                if model.trash?.bytes == nil {
                    Button(t("Ver tamaño…")) { openFullDiskAccessSettings() }
                        .buttonStyle(.borderless).font(.callout)
                        .help(t("Para leer la Papelera, macOS pide dar a Margin «Acceso total al disco» en Ajustes del Sistema."))
                }
            }
        }
    }

    /// Mientras corre el análisis inteligente: tarjetas de carga con un pulso suave.
    var loadingCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(t("Revisando cachés, registros, descargas, herramientas de desarrollo y la Papelera…"), systemImage: "sparkles")
                .symbolEffect(.variableColor.iterative, options: .repeat(.continuous))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.25)).frame(width: 110, height: 14)
                        RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.3)).frame(width: 80, height: 22)
                        RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.2)).frame(height: 10)
                    }
                    .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading).padding(16)
                    .surface(highContrast: highContrast)
                    .modifier(Pulse(active: !reduceMotion))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Analizando…"))
        .transition(.opacity)
    }

    var development: some View {
        let items = model.dev?.profiles.filter { $0.detected && !$0.items.isEmpty } ?? []
        let checked = items.flatMap(\.items).filter { devChecked.contains($0.id) && $0.canDelete }
        return VStack(alignment: .leading, spacing: 14) {
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    metric(t("Bajo riesgo · recuperable estimado"), model.dev.map { size($0.lowRiskBytes) } ?? "—", "checkmark.circle", tint: model.dev == nil ? nil : accent)
                    metric(t("Para revisar"), model.dev.map { size($0.reviewBytes) } ?? "—", "eye", tint: model.dev == nil ? nil : palette.warning)
                    availableMetric
                }
            }
            if model.devBusy {
                Label(t("Midiendo cachés y proyectos… (unos 30 s)"), systemImage: "sparkles")
                    .symbolEffect(.variableColor.iterative, options: .repeat(.continuous))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            if model.dev != nil {
                List(selection: $devSelection) {
                    ForEach(items) { profile in
                        Section("\(profile.name) · \(profile.owner)") {
                            ForEach(profile.items) { item in
                                HStack(spacing: 10) {
                                    Toggle("", isOn: Binding(get: { devChecked.contains(item.id) }, set: { on in withAnimation(.smooth) { if on { devChecked.insert(item.id) } else { devChecked.remove(item.id) } } }))
                                        .toggleStyle(.checkbox).labelsHidden().disabled(!item.canDelete)
                                        .accessibilityLabel(t("Incluir %@ en el plan", item.title))
                                    Image(systemName: item.category == .lowRisk ? "checkmark.circle.fill" : item.category == .review ? "eye.fill" : "lock.fill")
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
                }
                .scrollContentBackground(.hidden)
                .frame(minHeight: 240)
                .surface(cornerRadius: 20, highContrast: highContrast)
                if let item = items.flatMap(\.items).first(where: { $0.id == devSelection }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.title).font(.headline)
                            Spacer()
                            if let path = item.path, FileManager.default.fileExists(atPath: path) {
                                Button(t("Mostrar en Finder"), systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
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
                    }
                    .padding(16)
                    .surface(tint: accent.opacity(0.1), highContrast: highContrast)
                    .id(item.id)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                Text(t("Marca elementos y revisa el plan antes de ejecutar. «Recuperable estimado» excluye archivos con enlaces duros compartidos."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if !model.devBusy {
                ContentUnavailableView {
                    Label(t("Analiza qué se puede limpiar"), systemImage: "hammer").symbolEffect(.wiggle, options: .nonRepeating)
                } description: {
                    Text(t("Cachés de apps, registros, descargas, Android SDK y emuladores, simuladores y Xcode, node_modules de proyectos inactivos, pnpm, Gradle, Docker, Homebrew…"))
                } actions: {
                    Button(t("Analizar ahora"), systemImage: "sparkles") { model.analyzeDev() }.buttonStyle(.glassProminent).tint(accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 12)
        .animation(.smooth(duration: 0.3), value: devSelection)
        .animation(.smooth(duration: 0.3), value: model.devBusy)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !checked.isEmpty {
                ActionBar(highContrast: highContrast) {
                    Image(systemName: "checklist").foregroundStyle(accent)
                    Text(t("%@ en el plan · %@", tn(checked.count, "elemento", "elementos"), size(checked.reduce(Int64(0)) { $0 + ($1.recoverable ?? 0) }))).font(.callout).contentTransition(.numericText())
                    Spacer()
                    if model.preparing { ProgressView().controlSize(.small) }
                    Button(t("Revisar plan (%@)…", "\(checked.count)"), systemImage: "list.bullet.clipboard") { model.prepare(devItems: checked) }
                        .buttonStyle(.glassProminent).tint(accent).controlSize(.large)
                        .disabled(model.preparing || model.applying)
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: checked.isEmpty)
    }
}
