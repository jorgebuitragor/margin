import SwiftUI
import AppKit
import SpaceCore

extension AppEntry.Source {
    var title: String {
        switch self {
        case .appStore: return t("App Store")
        case .homebrew: return "Homebrew"
        case .user: return t("Instalada por ti")
        case .admin: return t("Instalada por un administrador")
        }
    }
}

extension ContentView {
    static let unusedDays = 90.0

    var visibleApps: [AppEntry] {
        var list = model.apps?.apps ?? []
        if !appSearch.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(appSearch) || ($0.bundleID ?? "").localizedCaseInsensitiveContains(appSearch) } }
        if onlyUnused {
            let limit = Date().addingTimeInterval(-Self.unusedDays * 86_400)
            list = list.filter { ($0.lastUsed ?? .distantPast) < limit && $0.protectedReason == nil }
        }
        switch appsSort {
        case "Nombre": return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "Último uso": return list.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        default: return list.sorted { $0.totalBytes > $1.totalBytes }
        }
    }

    var checkedAppItems: [DevItem] {
        guard let report = model.apps else { return [] }
        return (report.apps.flatMap(\.items) + report.orphans).filter { appChecked.contains($0.id) && $0.canDelete }
    }

    var appsView: some View {
        let report = model.apps
        let checked = checkedAppItems
        return VStack(alignment: .leading, spacing: 14) {
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    metric(t("Apps instaladas"), report.map { "\($0.apps.count)" } ?? "—", "square.grid.2x2")
                    metric(t("Ocupan con sus restos"), report.map { size($0.apps.reduce(Int64(0)) { $0 + $1.totalBytes }) } ?? "—", "shippingbox")
                    metric(t("Restos de apps borradas"), report.map { size($0.orphans.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }) } ?? "—", "trash.slash", tint: (report?.orphans.isEmpty ?? true) ? nil : palette.warning)
                }
            }
            if report == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(t("Buscando apps y sus restos…")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appsMode == "Restos" {
                orphanList
            } else {
                HStack(alignment: .top, spacing: 14) {
                    appList.frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
                    appDetail.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 12)
        .searchable(text: $appSearch, placement: .toolbar, prompt: t("Buscar apps"))
        .task { if model.apps == nil && !model.appsBusy { model.analyzeApps() } }
        .animation(.smooth(duration: 0.3), value: appSelection)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !checked.isEmpty {
                ActionBar(highContrast: highContrast) {
                    Image(systemName: "checklist").foregroundStyle(accent)
                    Text(t("%@ en el plan · %@", tn(checked.count, "elemento", "elementos"), size(checked.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }))).font(.callout)
                    Spacer()
                    Button(t("Quitar selección")) { withAnimation(.smooth) { appChecked.removeAll() } }.buttonStyle(.borderless)
                    if model.preparing { ProgressView().controlSize(.small) }
                    Button(t("Revisar plan (%@)…", "\(checked.count)"), systemImage: "list.bullet.clipboard") { model.prepare(devItems: checked) }
                        .buttonStyle(.glassProminent).tint(accent).controlSize(.large)
                        .disabled(model.preparing || model.applying)
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: checked.isEmpty)
        .onChange(of: model.applyReport == nil) { if model.applyReport != nil { appChecked.removeAll() } }
    }

    var appList: some View {
        List(selection: $appSelection) {
            ForEach(visibleApps) { app in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(app.name).lineLimit(1)
                            if app.protectedReason != nil { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                        }
                        Text(app.lastUsed.map { t("Usada %@", $0.formatted(.relative(presentation: .named).locale(Localizer.locale))) } ?? app.source.title)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(size(app.totalBytes)).monospacedDigit().font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(app.id)
                .accessibilityElement(children: .combine)
            }
        }
        .scrollContentBackground(.hidden)
        .surface(cornerRadius: 20, highContrast: highContrast)
        .overlay { if visibleApps.isEmpty { Text(t("Ninguna app coincide.")).foregroundStyle(.secondary) } }
    }

    @ViewBuilder
    var appDetail: some View {
        if let app = model.apps?.apps.first(where: { $0.id == appSelection }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).font(.title2.bold())
                            Text([app.version.map { t("Versión %@", $0) }, app.source.title, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(app.lastUsed.map { t("Usada por última vez %@", $0.formatted(.relative(presentation: .named).locale(Localizer.locale))) } ?? t("Spotlight no sabe cuándo la usaste por última vez."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(size(app.totalBytes)).font(.title2.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
                            Text(t("con sus restos")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let reason = app.protectedReason {
                        Label(reason, systemImage: "lock.fill").foregroundStyle(.secondary)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .surface(cornerRadius: 14, highContrast: highContrast)
                    } else {
                        HStack {
                            Text(t("Elige qué retirar. Todo va a la Papelera (o al comando de Homebrew) con un plan que revisas antes.")).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(t("App y restos sin riesgo")) {
                                withAnimation(.smooth) {
                                    for item in app.items where item.canDelete && (item.id == app.items.first?.id || item.category == .lowRisk) { appChecked.insert(item.id) }
                                }
                            }
                            .buttonStyle(.glass)
                        }
                        VStack(spacing: 0) {
                            ForEach(app.items) { item in
                                appItemRow(item, isApp: item.id == app.items.first?.id)
                                if item.id != app.items.last?.id { Divider().opacity(0.4) }
                            }
                        }
                        .padding(.vertical, 4)
                        .surface(cornerRadius: 16, highContrast: highContrast)
                    }
                    if !app.systemLeftovers.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(t("Fuera de tu carpeta personal (necesitan permisos de administrador; Margin no los toca)"), systemImage: "info.circle").font(.caption.weight(.semibold))
                            ForEach(app.systemLeftovers, id: \.self) { Text($0).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                    }
                    HStack {
                        Button(t("Mostrar en Finder"), systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }
                    }
                }
                .padding(18)
            }
            .surface(cornerRadius: 20, highContrast: highContrast)
            .id(app.id)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2").font(.system(size: 40)).foregroundStyle(.secondary)
                Text(t("Elige una app")).font(.title3.bold())
                Text(t("Verás la app y lo que deja en tu Biblioteca: cachés, datos, preferencias… con lo que ocupa cada cosa y si se puede quitar sin riesgo."))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .surface(cornerRadius: 20, highContrast: highContrast)
        }
    }

    func appItemRow(_ item: DevItem, isApp: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { appChecked.contains(item.id) }, set: { on in withAnimation(.smooth) { if on { appChecked.insert(item.id) } else { appChecked.remove(item.id) } } }))
                .toggleStyle(.checkbox).labelsHidden().disabled(!item.canDelete)
                .accessibilityLabel(t("Incluir %@ en el plan", item.title))
            Image(systemName: isApp ? "app.fill" : item.category == .lowRisk ? "checkmark.circle.fill" : "eye.fill")
                .foregroundStyle(isApp ? accent : item.category == .lowRisk ? accent : palette.warning)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(isApp ? t("La app") : item.title.components(separatedBy: " · ").dropFirst().joined(separator: " · ")).font(.callout.weight(.medium))
                    Spacer()
                    Text(item.bytes.map { size($0) } ?? t("sin medir")).monospacedDigit().font(.callout).foregroundStyle(.secondary)
                }
                Text(item.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let path = item.path {
                    Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).help(path)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    var orphanList: some View {
        let orphans = (model.apps?.orphans ?? []).filter { appSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(appSearch) }
        return Group {
            if orphans.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal").font(.system(size: 40)).foregroundStyle(accent)
                    Text(t("No hay restos de apps borradas")).font(.title3.bold())
                    Text(t("Ninguna carpeta de tu Biblioteca de más de 1 MB pertenece a una app que ya no esté instalada.")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("Carpetas con el identificador de una app que no está instalada. Suelen ser restos, pero algunas herramientas sin app guardan datos así: revisa cada una.")).font(.caption).foregroundStyle(.secondary)
                        selectAllOrphans(orphans)
                        VStack(spacing: 0) {
                            ForEach(orphans) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Toggle("", isOn: Binding(get: { appChecked.contains(item.id) }, set: { on in withAnimation(.smooth) { if on { appChecked.insert(item.id) } else { appChecked.remove(item.id) } } }))
                                        .toggleStyle(.checkbox).labelsHidden()
                                        .accessibilityLabel(t("Incluir %@ en el plan", item.title))
                                    Image(systemName: "eye.fill").foregroundStyle(palette.warning)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(item.title).font(.callout.weight(.medium)).textSelection(.enabled)
                                            Spacer()
                                            Text(size(item.bytes)).monospacedDigit().font(.callout).foregroundStyle(.secondary)
                                        }
                                        Text(item.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                        ForEach(item.action?.paths ?? [], id: \.self) { path in
                                            Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                                        }
                                    }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .accessibilityElement(children: .combine)
                                if item.id != orphans.last?.id { Divider().opacity(0.4) }
                            }
                        }
                        .surface(cornerRadius: 18, highContrast: highContrast)
                    }
                    .padding(.bottom, 80)
                }
            }
        }
        .transition(.opacity)
    }

    /// Marca o desmarca de una vez los restos visibles (respeta la búsqueda). Con `sources`, macOS dibuja la casilla en
    /// estado mixto (guion) cuando solo hay algunos marcados, y al pulsarla los marca todos.
    func selectAllOrphans(_ orphans: [DevItem]) -> some View {
        let selectable = orphans.filter(\.canDelete)
        let total = selectable.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
        let marks = selectable.map { item in
            Binding(get: { appChecked.contains(item.id) }, set: { on in
                withAnimation(.smooth) { if on { appChecked.insert(item.id) } else { appChecked.remove(item.id) } }
            })
        }
        return HStack(spacing: 10) {
            Toggle(sources: marks, isOn: \.self) {
                Text(appSearch.isEmpty ? t("Marcar todos") : t("Marcar todos los que coinciden"))
                    .font(.callout.weight(.medium))
            }
            .toggleStyle(.checkbox)
            Spacer()
            Text("\(tn(selectable.count, "resto", "restos")) · \(size(total))")
                .monospacedDigit().font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .surface(cornerRadius: 14, highContrast: highContrast)
        .disabled(selectable.isEmpty)
    }
}
