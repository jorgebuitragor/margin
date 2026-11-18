import SwiftUI
import AppKit
import SpaceCore

extension ContentView {
    /// Mapa de áreas de un nivel; un clic en una carpeta con subcarpetas entra en ella.
    func treemap(_ report: ScanReport) -> some View {
        let root = URL(fileURLWithPath: report.root).standardizedFileURL.path
        let current = mapRoot.flatMap { path in report.folders.contains { $0.path == path } ? path : nil } ?? root
        let items = Treemap.children(of: current, in: report)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(t("Subir"), systemImage: "arrow.up") {
                    let parent = URL(fileURLWithPath: current).deletingLastPathComponent().standardizedFileURL.path
                    withAnimation(.smooth(duration: 0.4)) { mapRoot = parent.count >= root.count ? parent : root }
                }
                .buttonStyle(.glass)
                .disabled(current == root)
                Text(current == root ? t("Carpeta analizada") : String(current.dropFirst(root.count + 1))).font(.callout).lineLimit(1).truncationMode(.head)
                Spacer()
                Text(t("Clic para entrar en una carpeta · solo se ven las del informe (≥ 1 MB, hasta 3 niveles)")).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let rects = Treemap.layout(items.map { Double($0.allocatedBytes) }, in: CGRect(origin: .zero, size: geo.size))
                ZStack(alignment: .topLeading) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, folder in
                        let rect = rects[index]
                        let isRest = folder.path.hasSuffix("/…")
                        // Solo se entra si hay subcarpetas en el informe; si no, el nivel sería una única pieza «Otros».
                        let canEnter = !isRest && Treemap.children(of: folder.path, in: report).contains { !$0.path.hasSuffix("/…") }
                        let color: Color = isRest ? .gray : folder.protection == "sync" ? palette.synced : folder.protection == "protected" ? .secondary : accent
                        Button {
                            if canEnter { withAnimation(.smooth(duration: 0.4)) { mapRoot = folder.path } }
                        } label: {
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(isRest ? 0.18 : highContrast ? 0.5 : 0.35).gradient)
                                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(color.opacity(palette.borderOpacity), lineWidth: palette.borderWidth)
                                if canEnter {
                                    Image(systemName: "arrow.down.right.circle.fill").font(.caption).foregroundStyle(color).opacity(hoveredTile == folder.path ? 1 : 0)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(6)
                                }
                                if rect.width > 70 && rect.height > 34 {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            if folder.protection == "protected" { Image(systemName: "lock.fill").font(.caption2) }
                                            if folder.protection == "sync" { Image(systemName: "icloud.fill").font(.caption2) }
                                            Text(isRest ? t("Otros") : folder.name).font(.caption.weight(.semibold)).lineLimit(1)
                                        }
                                        Text(size(folder.allocatedBytes)).font(.caption2).monospacedDigit()
                                    }.padding(6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .brightness(hoveredTile == folder.path ? 0.08 : 0)
                        .scaleEffect(hoveredTile == folder.path && canEnter ? 0.985 : 1)
                        .onHover { inside in withAnimation(.smooth(duration: 0.2)) { hoveredTile = inside ? folder.path : (hoveredTile == folder.path ? nil : hoveredTile) } }
                        .frame(width: max(rect.width - 3, 0), height: max(rect.height - 3, 0))
                        .offset(x: rect.minX + 1.5, y: rect.minY + 1.5)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .help("\(isRest ? t("Archivos sueltos y carpetas pequeñas") : folder.path) · \(size(folder.allocatedBytes))\(folder.reason.map { " · " + $0 } ?? "")\(!isRest && !canEnter && folder.protection == nil ? " · " + t("Este análisis no tiene más detalle: clic derecho › «Analizar esta carpeta».") : "")")
                        .contextMenu {
                            if !isRest {
                                Button(t("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)]) }
                                if folder.protection == nil { Button(t("Analizar esta carpeta")) { model.scan(URL(fileURLWithPath: folder.path)) } }
                            }
                        }
                        .accessibilityLabel("\(isRest ? t("Otros") : folder.name), \(size(folder.allocatedBytes))\(folder.protection == "protected" ? ", " + t("protegida") : folder.protection == "sync" ? ", " + t("sincronizada") : "")\(canEnter ? ", " + t("se puede abrir") : "")")
                    }
                }
            }
            .frame(minHeight: 300)
            .id(current)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        .padding(12)
        .surface(cornerRadius: 20, highContrast: highContrast)
    }

    var folders: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    availableMetric
                    metric(t("Total de la carpeta analizada"), model.report.map { size($0.totalAllocated) } ?? "—", "folder")
                    metric(t("Archivos revisados"), "\(model.report?.visited ?? 0)", "doc.on.doc")
                }
            }
            status
            if let report = model.report {
                Label(report.root, systemImage: "folder").font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                let total = max(report.totalAllocated, 1)
                if folderView == "Mapa" {
                    treemap(report).transition(.opacity)
                } else {
                    List(FolderNode.tree(report), children: \.children) { node in
                        let folder = node.folder
                        HStack(spacing: 10) {
                            Image(systemName: folder.protection == "sync" ? "icloud" : folder.protection == "protected" ? "lock" : "folder")
                                .foregroundStyle(folder.protection == nil ? accent : .secondary)
                                .help(folder.reason ?? t("Carpeta analizable"))
                            Text(folder.name).lineLimit(1).help(folder.path)
                            Spacer()
                            ProgressView(value: Double(folder.allocatedBytes), total: Double(total)).frame(width: 120)
                            Text(size(folder.allocatedBytes) + (folder.partial ? "+" : "")).monospacedDigit().frame(width: 90, alignment: .trailing)
                        }
                        .contextMenu {
                            Button(t("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)]) }
                            Button(t("Analizar esta carpeta")) { model.scan(URL(fileURLWithPath: folder.path)) }.disabled(folder.protection != nil)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(folder.name), \(size(folder.allocatedBytes))\(folder.protection == "sync" ? ", " + t("sincronizada") : folder.protection == "protected" ? ", " + t("protegida") : "")")
                    }
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 260)
                    .surface(cornerRadius: 20, highContrast: highContrast)
                    .transition(.opacity)
                }
                Text(t("Candado: protegida (sistema, configuración, dependencias). Nube: sincronizada. Ambas se miden pero no se ofrecen para limpieza. «+» indica que hubo elementos ilegibles y el total es un mínimo."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if !model.busy {
                ContentUnavailableView {
                    Label(t("Empieza por una carpeta"), systemImage: "folder.badge.questionmark")
                } description: {
                    Text(t("Elige una carpeta o usa un atajo. Verás cuánto ocupa cada carpeta, también las de Library y las dependencias de proyectos. Analizar la carpeta personal completa tarda unos 3 minutos."))
                } actions: {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(AppModel.quickFolders(), id: \.path) { item in
                                Button(item.title, systemImage: "folder") { model.scan(item.url) }.buttonStyle(.glass)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 16)
        .animation(.smooth(duration: 0.35), value: folderView)
        .animation(.smooth(duration: 0.35), value: model.report?.root)
    }

    var filtered: [FileEntry] {
        (model.report?.entries ?? []).filter {
            (category == nil || $0.classification.category == category) && (search.isEmpty || $0.path.localizedCaseInsensitiveContains(search))
        }
    }
    var chosen: FileEntry? { selected.count == 1 ? model.report?.entries.first { selected.contains($0.id) } : nil }
    var trashableSelection: [FileEntry] {
        (model.report?.entries ?? []).filter { selected.contains($0.id) && $0.classification.category == .review && $0.bytes != nil }
    }
    /// Resumen de la selección; avisa si hay elementos marcados que el filtro oculta (también irían al plan).
    var selectionSummary: String {
        let count = selected.count
        guard count > 0 else { return t("Marca las casillas (o usa ⌘/⇧ y clic) para elegir varios archivos «Revisar antes de borrar».") }
        let visible = Set(filtered.map(\.id))
        let hidden = selected.filter { !visible.contains($0) }.count
        let movable = trashableSelection.count
        var text = tn(count, "seleccionado", "seleccionados")
        if hidden > 0 { text += " " + t("(%@ por el filtro)", tn(hidden, "oculto", "ocultos")) }
        if movable < count { text += " · " + t("%@ a la Papelera: solo los «Revisar antes de borrar»", tn(movable, "puede ir", "pueden ir")) }
        return text + "."
    }

    var files: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    availableMetric
                    metric(t("Elementos listados"), "\(model.report?.entries.count ?? 0)", "doc.on.doc")
                    metric(t("Omitidos / sin inspeccionar"), "\(model.report?.omitted ?? 0)", "shield")
                }
            }
            status
            HStack {
                if let report = model.report {
                    Label(report.root, systemImage: "folder").font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Picker(t("Clasificación"), selection: $category.animation(.smooth)) {
                    Text(t("Todas")).tag(nil as SpaceCore.Category?)
                    ForEach(SpaceCore.Category.allCases, id: \.self) { Text(t($0.rawValue)).tag(Optional($0)) }
                }.frame(width: 300)
            }
            if model.report == nil && !model.busy {
                ContentUnavailableView(t("Empieza por una carpeta"), systemImage: "folder.badge.questionmark", description: Text(t("Elige, por ejemplo, Descargas. Verás tamaños y razones para revisar o conservar cada elemento.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filtered, selection: $selected) {
                    TableColumn("") { entry in
                        Toggle("", isOn: Binding(get: { selected.contains(entry.id) }, set: { on in if on { selected.insert(entry.id) } else { selected.remove(entry.id) } }))
                            .toggleStyle(.checkbox).labelsHidden()
                            .disabled(entry.classification.category != .review || entry.bytes == nil)
                            .accessibilityLabel(t("Seleccionar %@", entry.name))
                    }.width(24)
                    TableColumn(t("Archivo")) { entry in
                        // La carpeta contenedora distingue elementos homónimos (por ejemplo, varios node_modules).
                        HStack(spacing: 6) {
                            Text(entry.name)
                            Text(URL(fileURLWithPath: entry.path).deletingLastPathComponent().lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        }.help(entry.path)
                    }
                    TableColumn(t("Tamaño")) { entry in Text(size(entry.bytes ?? entry.allocatedBytes)).monospacedDigit() }.width(100)
                    TableColumn(t("Clasificación")) { entry in
                        Label(t(entry.classification.category.rawValue), systemImage: entry.classification.category == .protected ? "lock" : "questionmark.circle")
                    }.width(190)
                }
                .alternatingRowBackgrounds(.disabled)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .surface(cornerRadius: 20, highContrast: highContrast)
                if filtered.isEmpty { Text(t("No hay resultados para mostrar con estos filtros.")).foregroundStyle(.secondary) }
            }
            if selected.isEmpty {
                Text(selectionSummary).font(.caption).foregroundStyle(.secondary)
            }
            if let entry = chosen {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(t("Por qué · %@", entry.name)).font(.headline)
                        Spacer()
                        Button(t("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) }
                    }
                    Text(entry.classification.reason)
                    Text(entry.classification.consequence).foregroundStyle(.secondary)
                    Text(t("Asignado en disco: %@ · Regla: %@", size(entry.allocatedBytes), entry.classification.rule)).font(.caption)
                    Text(entry.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(16)
                .surface(tint: accent.opacity(0.1), highContrast: highContrast)
                .id(entry.id)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let issues = model.report?.issues, !issues.isEmpty {
                DisclosureGroup(t("Incidencias (%@, máximo 100 mostradas)", "\(issues.count)")) {
                    ScrollView { Text(issues.joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90)
                }
            }
            Text(t("Se listan los archivos más grandes y las carpetas protegidas con su total. Los tamaños no equivalen a espacio recuperable. No se recomienda borrar por edad o tamaño. No se inspecciona el contenido de archivos ni se detectan duplicados."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 16)
        .animation(.smooth(duration: 0.3), value: chosen?.id)
        .searchable(text: $search, placement: .toolbar, prompt: t("Buscar por nombre o ubicación"))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selected.isEmpty {
                ActionBar(highContrast: highContrast) {
                    Image(systemName: "checklist").foregroundStyle(accent)
                    Text(selectionSummary).font(.callout).lineLimit(2)
                    Spacer()
                    Button(t("Mover a la Papelera (%@)…", "\(trashableSelection.count)"), systemImage: "trash") { model.prepare(files: trashableSelection) }
                        .buttonStyle(.glassProminent).tint(accent).controlSize(.large)
                        .disabled(trashableSelection.isEmpty || model.preparing || model.applying)
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: selected.isEmpty)
    }

    var memory: some View {
        let d = model.diagnostics
        let pressureColor: Color = d.pressureLevel == 4 ? palette.danger : d.pressureLevel == 2 ? palette.warning : accent
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(t("Presión de memoria"), systemImage: "gauge.with.dots.needle.67percent").font(.caption).foregroundStyle(.secondary)
                        Text(d.pressure.map { t($0) } ?? t("No disponible")).font(.title2.weight(.semibold)).foregroundStyle(pressureColor)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .surface(tint: pressureColor.opacity(highContrast ? 0.3 : 0.18), highContrast: highContrast)
                        .accessibilityElement(children: .combine)
                    metric(t("RAM instalada"), size(Int64(d.physicalMemory)), "memorychip")
                    metric(t("Intercambio en disco"), size(d.swapUsed.map(Int64.init)), "internaldrive")
                }
                HStack(spacing: 14) {
                    metric(t("Memoria cableada"), size(d.wiredMemory.map(Int64.init)), "lock")
                    metric(t("RAM ocupada por el compresor"), size(d.compressedMemory.map(Int64.init)), "arrow.down.right.and.arrow.up.left")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("Apps que más memoria usan")).font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        let maxBytes = Double(d.apps.first?.bytes ?? 1)
                        ForEach(Array(d.apps.enumerated()), id: \.element.id) { index, app in
                            HStack(spacing: 10) {
                                Text(app.name).lineLimit(1).frame(width: 220, alignment: .leading)
                                MemoryBar(fraction: Double(app.bytes) / maxBytes, color: index == 0 && d.pressureLevel != 1 ? pressureColor : accent, delay: Double(index) * 0.03, reduceMotion: reduceMotion)
                                Text(size(Int64(app.bytes))).monospacedDigit().frame(width: 90, alignment: .trailing)
                                Text(tn(app.processes, "proceso", "procesos")).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                            }.accessibilityElement(children: .combine)
                        }
                        Text(t("Huella física por app, sumando sus procesos auxiliares (como la columna «Memoria» de Monitor de Actividad). %@ del sistema no se pueden inspeccionar sin privilegios.", tn(d.hiddenProcesses, "proceso", "procesos")))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .surface(cornerRadius: 20, highContrast: highContrast)
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("Cómo interpretar estos datos")).font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("La presión es la señal que usa macOS: «Normal» significa que hay memoria suficiente aunque parezca casi toda ocupada; «Advertencia», que comprime y usa disco a menudo; «Crítica», que falta memoria y el Mac puede ir lento."))
                        Text(t("Si la presión no es normal, cerrar las apps de la lista que no estés usando es lo que más ayuda. Esta app no cierra procesos ni «libera RAM»: eso no acelera el Mac."))
                        Button(t("Abrir Monitor de Actividad"), systemImage: "waveform.path.ecg") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                        }.buttonStyle(.glass)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .surface(cornerRadius: 20, highContrast: highContrast)
                Text(t("Muestra: %@", d.date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(Localizer.locale)))).font(.caption).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                ForEach(d.errors, id: \.self) { Text($0).foregroundStyle(palette.warning) }
            }
            .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 20)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

/// Barra de memoria que crece al aparecer y se anima al actualizar.
struct MemoryBar: View {
    var fraction: Double
    var color: Color
    var delay: Double
    var reduceMotion: Bool
    @State private var shown = false
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.gradient).frame(width: max(4, geo.size.width * CGFloat(shown ? min(max(fraction, 0), 1) : 0)))
            }
        }
        .frame(height: 8)
        .animation(.smooth(duration: 0.5), value: fraction)
        .onAppear { if reduceMotion { shown = true } else { withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.1 + delay)) { shown = true } } }
        .accessibilityHidden(true)
    }
}
