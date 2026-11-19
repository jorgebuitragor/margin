import SwiftUI
import AppKit
import SpaceCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State var category: SpaceCore.Category?
    @State var search = ""
    @State var selected = Set<String>()
    @State var devChecked = Set<String>()
    @State var acceptReview = false
    var tab: String {
        get { model.tab }
        nonmutating set { model.tab = newValue }
    }
    // MARGIN_VIEW abre la vista de mapa al arrancar (pruebas visuales sin clics).
    @State var folderView = DevEnvironment.testSetting("VIEW") ?? "Lista"
    @State var mapRoot: String?
    @State var devSelection: String?
    @State var hoveredTile: String?
    @State var appSelection: String?
    @State var appChecked = Set<String>()
    @State var appSearch = ""
    @State var appsMode = "Apps"
    @State var appsSort = "Tamaño"
    @State var onlyUnused = false
    @AppStorage(Pref.colorblind) var colorblind = false
    @AppStorage(Pref.highContrast) var highContrast = false
    @AppStorage(Pref.reduceMotion) var reduceMotionSetting = false
    @AppStorage(Pref.permanentDelete) var permanentDelete = false
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion

    var palette: Palette { Palette(colorblind: colorblind, highContrast: highContrast) }
    var accent: Color { palette.accent }
    var reduceMotion: Bool { reduceMotionSetting || systemReduceMotion }

    static let tabs: [(id: String, icon: String)] = [
        ("Inicio", "sparkles"), ("Limpieza", "hammer"), ("Apps", "square.grid.2x2"), ("Carpetas", "folder"), ("Archivos", "doc"), ("Rendimiento", "gauge.with.dots.needle.67percent")
    ]
    /// Contador por pestaña para animar solo el icono de la pestaña recién elegida.
    @State var bounces: [String: Int] = [:]
    var tabIndex: Int { Self.tabs.firstIndex { $0.id == tab } ?? Self.tabs.count }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .tint(accent)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .symbolEffectsRemoved(reduceMotion)
        .onChange(of: model.tab) { bounces[model.tab, default: 0] += 1 }
        // Rendimiento se actualiza solo mientras está a la vista (la CPU se mide entre una muestra y la siguiente).
        .task(id: model.tab) {
            guard model.tab == "Rendimiento" else { return }
            while !Task.isCancelled {
                await model.refreshPerformance()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        // Al volver a Margin (quizá tras vaciar la Papelera en Finder) se relee su tamaño.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshTrash() }
        // Un análisis nuevo (u otra carpeta) invalida la navegación del mapa y la selección: los elementos marcados
        // pertenecían al informe anterior y no deben ir a parar a un plan sin que se vean.
        .onChange(of: model.report?.root) { mapRoot = nil; selected.removeAll() }
        .onChange(of: model.showTabs) {
            if let tabs = model.showTabs, let first = tabs.first, !tabs.contains(tab) { tab = first }
            model.showTabs = nil
        }
        .sheet(item: $model.pendingPlan) { plan in confirmation(plan) }
        .sheet(isPresented: $model.confirmEmpty) {
            DestructiveConfirmation(
                title: t("¿Vaciar la Papelera?"),
                message: (model.trash?.items.map { t("Se borrarán %@ (%@). ", tn($0, "elemento", "elementos"), size(model.trash?.bytes)) } ?? "") + t("Lo que hay en la Papelera se borra para siempre y no se puede recuperar. Finder se encarga de vaciarla; la primera vez macOS te pedirá permiso para que esta app controle Finder."),
                actionTitle: t("Vaciar definitivamente"), danger: palette.danger,
                onCancel: { model.confirmEmpty = false },
                onConfirm: { model.confirmEmpty = false; model.emptyTrash() })
        }
        .alert(model.emptyResult?.status == .done ? t("Papelera vaciada") : t("No se pudo vaciar la Papelera"), isPresented: Binding(get: { model.emptyResult != nil }, set: { if !$0 { model.emptyResult = nil } })) {
            Button(t("Aceptar"), role: .cancel) {}
        } message: {
            if let result = model.emptyResult {
                Text(t(result.message) + " " + t("Espacio disponible: antes %@, después %@.", size(result.availableBefore), size(result.availableAfter)))
            }
        }
        .sheet(item: Binding(get: { model.applyReport.map { ReportBox(report: $0) } }, set: { if $0 == nil { model.applyReport = nil } })) { box in results(box.report) }
        .alert(t("No se pudo preparar el plan"), isPresented: Binding(get: { model.planError != nil }, set: { if !$0 { model.planError = nil } })) {
            Button(t("Aceptar"), role: .cancel) {}
        } message: { Text(model.planError ?? "") }
    }

    /// Barra lateral nativa: en macOS 26 flota como Liquid Glass y la sección elegida ya hace de título.
    var sidebar: some View {
        List(selection: Binding<String?>(get: { model.tab }, set: { if let value = $0 { model.tab = value } })) {
            Section(t("CONOCE TU MAC")) {
                ForEach(Self.tabs, id: \.id) { item in sidebarRow(item.id, item.icon) }
            }
            Section {
                sidebarRow("Ajustes", "gearshape")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(color: accent).frame(width: 30, height: 30)
                Text("Margin").font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 10)
            .accessibilityElement(children: .combine)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                // MARGIN_CAPTURAS oculta la etiqueta solo para las capturas del README (scripts/demo-home.sh).
                if let home = DevEnvironment.testSetting("HOME"), DevEnvironment.testSetting("CAPTURAS") == nil {
                    // Carpeta personal sintética: la barra del disco y los análisis solo ven esa carpeta.
                    Label(t("Modo de prueba"), systemImage: "testtube.2")
                        .font(.caption.weight(.semibold)).foregroundStyle(palette.warning)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .glassEffect(.regular.tint(palette.warning.opacity(0.2)), in: .capsule)
                        .help(t("Margin analiza %@ en lugar de tu carpeta personal: casi todo el disco aparece como «Otros».", home))
                        .padding(.bottom, 6)
                }
                if permanentDelete {
                    // Mientras esté activado se ve siempre, para no olvidar que nada pasa por la Papelera.
                    Button { model.tab = "Ajustes" } label: {
                        Label(t("Borrado definitivo activado"), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(palette.danger)
                    }
                    .buttonStyle(.plain)
                    .help(t("Los planes borran sin pasar por la Papelera. Se desactiva en Ajustes."))
                    .padding(.bottom, 4)
                }
                Label(t("Nada sin tu confirmación"), systemImage: "checkmark.shield.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(accent)
                Text(t("Versión %@", Updater.version)).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .help(permanentDelete
                  ? t("Borrado definitivo activado: los planes borran sin pasar por la Papelera.")
                  : t("Solo Papelera o el comando oficial de cada herramienta. El único borrado definitivo es «Vaciar Papelera»."))
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }

    func sidebarRow(_ id: String, _ icon: String) -> some View {
        Label(t(id), systemImage: icon)
            .symbolEffect(.bounce, value: bounces[id, default: 0])
            .tag(id)
    }

    /// Contenido de la pestaña sobre el fondo de color; al cambiar de pestaña entra con un fundido y un leve desplazamiento.
    var detail: some View {
        ZStack {
            Backdrop(index: tabIndex, accent: accent)
                .ignoresSafeArea()
                .animation(.smooth(duration: 0.9), value: tabIndex)
            Group {
                switch tab {
                case "Inicio": home
                case "Carpetas": folders
                case "Archivos": files
                case "Limpieza": development
                case "Apps": appsView
                case "Ajustes": settings
                default: memory
                }
            }
            .id(tab)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)).combined(with: .scale(scale: 0.99)), removal: .opacity))
        }
        .animation(.smooth(duration: 0.35), value: tab)
        .toolbar(removing: .title)
        .toolbar { toolbarContent }
    }

    /// Las acciones de cada pestaña viven en la barra de herramientas (Liquid Glass en macOS 26).
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if tab == "Inicio" {
            // La Papelera, siempre a la vista en Inicio: con su tamaño cuando macOS deja leerlo.
            ToolbarItem {
                Button(model.trash?.bytes.map { t("Vaciar Papelera (%@)…", size($0)) } ?? t("Vaciar Papelera…"), systemImage: "trash") { model.askEmptyTrash() }
                    .labelStyle(.titleAndIcon)
                    .disabled(model.emptying || model.trash?.items == 0)
                    .help(model.trash?.items == 0 ? t("La Papelera está vacía.") : t("Vacía la Papelera para siempre, con confirmación."))
            }
            ToolbarItem {
                Button(t("Volver a medir el disco"), systemImage: "arrow.clockwise") { model.measureStorage() }
                    .symbolEffect(.rotate, isActive: model.storageProgress != nil)
                    .disabled(model.storageProgress != nil)
                    .help(t("Volver a medir el disco"))
            }
        }
        if tab == "Inicio" || tab == "Limpieza" {
            ToolbarItem {
                Button(model.devBusy ? t("Analizando…") : model.dev == nil ? t("Analizar") : t("Volver a analizar"), systemImage: "sparkles") { model.analyzeDev() }
                    .symbolEffect(.variableColor.iterative, isActive: model.devBusy)
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.glassProminent).tint(accent)
                    .disabled(model.devBusy)
            }
        }
        if tab == "Apps" {
            ToolbarItem {
                Picker(t("Mostrar"), selection: $appsMode.animation(.smooth)) {
                    Text(t("Apps")).tag("Apps")
                    Text(t("Restos de apps borradas")).tag("Restos")
                }.pickerStyle(.segmented)
            }
            ToolbarItem {
                Menu(t("Ordenar"), systemImage: "arrow.up.arrow.down") {
                    Picker(t("Ordenar"), selection: $appsSort.animation(.smooth)) {
                        Text(t("Tamaño")).tag("Tamaño")
                        Text(t("Último uso")).tag("Último uso")
                        Text(t("Nombre")).tag("Nombre")
                    }
                    Toggle(t("Solo las que no usas desde hace 3 meses"), isOn: $onlyUnused.animation(.smooth))
                }
                .help(t("Ordenar"))
                .accessibilityLabel(t("Ordenar"))
            }
            ToolbarItem {
                Button(model.appsBusy ? t("Analizando…") : t("Volver a analizar"), systemImage: "arrow.clockwise") { model.analyzeApps() }
                    .symbolEffect(.rotate, isActive: model.appsBusy)
                    .labelStyle(.titleAndIcon)
                    .disabled(model.appsBusy)
            }
        }
        if tab == "Carpetas" && model.report != nil {
            ToolbarItem {
                Picker(t("Vista"), selection: $folderView.animation(.smooth)) {
                    Image(systemName: "list.bullet.indent").accessibilityLabel(t("Lista")).help(t("Lista")).tag("Lista")
                    Image(systemName: "square.grid.3x3.square").accessibilityLabel(t("Mapa")).help(t("Mapa")).tag("Mapa")
                }.pickerStyle(.segmented).help(t("Vista"))
            }
        }
        if tab == "Carpetas" || tab == "Archivos" {
            ToolbarItem {
                Menu(t("Carpetas frecuentes"), systemImage: "star") {
                    ForEach(AppModel.quickFolders(), id: \.path) { item in
                        Button(item.title, systemImage: "folder") { model.scan(item.url) }
                    }
                }
                .help(t("Carpetas frecuentes"))
                .accessibilityLabel(t("Carpetas frecuentes"))
            }
            ToolbarItem {
                Button(t("Elegir carpeta…"), systemImage: "folder.badge.plus") { model.choose() }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.glassProminent).tint(accent)
            }
        }
        if tab == "Rendimiento" {
            ToolbarItem {
                Button(t("Actualizar"), systemImage: "arrow.clockwise") { Task { await model.refreshPerformance() } }
                    .help(t("Se actualiza solo cada 5 segundos mientras esta sección está abierta."))
            }
        }
    }

    func confirmation(_ plan: Plan) -> some View {
        let runnable = plan.steps.filter { model.blockers[$0.id] == nil }
        let hasReview = runnable.contains { $0.category == .review }
        let permanent = permanentDelete && runnable.contains { $0.action.kind == .trash }
        return VStack(alignment: .leading, spacing: 14) {
            Text(t("Revisa el plan")).font(.title2.bold())
            if permanent {
                Label(t("Borrado definitivo activado: lo que este plan borre no pasará por la Papelera y no se podrá recuperar. Se desactiva en Ajustes."), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(palette.danger)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.danger.opacity(0.12), in: .rect(cornerRadius: 10))
            }
            Text(t("Recuperable estimado %@. Cada paso se vuelve a comprobar justo antes de actuar.", size(plan.recoverable))).foregroundStyle(.secondary)
            List(plan.steps) { step in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: model.blockers[step.id] != nil ? "xmark.octagon" : step.category == .review ? "eye" : "checkmark.circle")
                            .foregroundStyle(model.blockers[step.id] != nil ? palette.danger : step.category == .review ? palette.warning : accent)
                        Text(step.title).font(.headline)
                        Spacer()
                        Text(size(step.recoverable)).monospacedDigit()
                    }
                    let target = step.action.paths.count == 1 ? step.action.paths[0] : tn(step.action.paths.count, "ruta", "rutas")
                    let deletes = permanentDelete && !step.action.paths.contains { $0.hasPrefix("/Applications/") }
                    Text(step.action.kind == .trash ? (deletes ? t("Borrar definitivamente: %@", target) : t("Mover a la Papelera: %@", target)) : t("Ejecutar: %@", step.action.command))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text(t("Si se retira: %@", step.regenerate)).font(.caption).foregroundStyle(.secondary)
                    if let note = step.action.note { Text(note).font(.caption).foregroundStyle(palette.warning) }
                    if let blocker = model.blockers[step.id] { Text(t("No se ejecutará: %@", blocker)).font(.caption).foregroundStyle(palette.danger) }
                }.padding(.vertical, 4)
            }.frame(minHeight: 240)
            Text(permanent
                 ? t("Lo borrado definitivamente no se puede recuperar. Las apps de /Applications van a la Papelera. Los comandos de las herramientas no se pueden deshacer.")
                 : t("Lo que vaya a la Papelera se recupera desde Finder hasta que la vacíes. Los comandos de las herramientas no se pueden deshacer.")).font(.caption)
            if hasReview {
                Toggle(t("Entiendo que hay elementos marcados «Revisar antes de borrar» y los he revisado"), isOn: $acceptReview)
            }
            HStack {
                Spacer()
                Button(t("Cancelar"), role: .cancel) { model.pendingPlan = nil; acceptReview = false }.keyboardShortcut(.cancelAction)
                Button(model.applying ? t("Ejecutando…") : runnable.count == 1 ? t("Ejecutar 1 paso") : t("Ejecutar %@ pasos", "\(runnable.count)"), role: .destructive) { model.applyPending(); acceptReview = false; devChecked.removeAll(); selected.removeAll() }
                    .disabled(runnable.isEmpty || model.applying || (hasReview && !acceptReview))
            }
        }.padding(24).frame(width: 720, height: 560)
    }

    func results(_ report: ApplyReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("Resultado")).font(.title2.bold())
            List(report.results, id: \.stepID) { result in
                VStack(alignment: .leading, spacing: 3) {
                    Label("\(result.title): \(t(result.message))", systemImage: result.status == .done ? "checkmark.circle.fill" : result.status == .blocked ? "xmark.octagon" : "exclamationmark.triangle")
                        .foregroundStyle(result.status == .done ? accent : result.status == .blocked ? .secondary : palette.warning)
                    ForEach(result.failures.sorted(by: { $0.key < $1.key }), id: \.key) { Text("\($0.key): \($0.value)").font(.caption).foregroundStyle(palette.danger) }
                    if result.status == .failed, let output = result.output { Text(output).font(.system(.caption2, design: .monospaced)).lineLimit(6) }
                }
            }.frame(minHeight: 200)
            Text(t("Espacio disponible: antes %@, después %@.", size(report.availableBefore), size(report.availableAfter)) + (report.freedObserved.map { " (\($0 >= 0 ? "+" : "")\(formatBytes($0)))" } ?? ""))
            if report.removedCount > 0 { Text(t("%@ sin pasar por la Papelera.", tn(report.removedCount, "ruta borrada", "rutas borradas"))).foregroundStyle(palette.danger) }
            if report.usedTrash { Text(t("Lo movido a la Papelera no libera espacio hasta que la vacíes.")).foregroundStyle(palette.warning) }
            HStack {
                Spacer()
                if report.usedTrash {
                    // Se cierra el resultado y luego se pregunta: el diálogo no puede abrirse mientras la hoja se va.
                    Button(t("Vaciar Papelera…"), role: .destructive) {
                        model.applyReport = nil
                        Task { try? await Task.sleep(for: .milliseconds(400)); model.askEmptyTrash() }
                    }
                }
                Button(t("Cerrar")) { model.applyReport = nil }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 640, height: 480)
    }

    var status: some View {
        HStack {
            if model.busy { ProgressView().controlSize(.small) }
            Text(model.message).font(.callout)
            Spacer()
            if model.busy {
                Text(t("%@ revisados", "\(model.visited)")).foregroundStyle(.secondary)
                Button(t("Cancelar")) { model.cancel() }
            }
        }.accessibilityElement(children: .combine)
    }

    func metric(_ title: String, _ value: String, _ icon: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(tint ?? .primary)
                .contentTransition(.numericText())
                .animation(.smooth, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .surface(tint: tint?.opacity(0.12), highContrast: highContrast)
        .accessibilityElement(children: .combine)
    }

    /// Métrica de disponible con el total: «20,4 GB de 245,1 GB».
    var availableMetric: some View {
        let capacity = model.capacity
        let value = capacity.map { t("%@ de %@", size($0.available), size($0.total)) } ?? size(model.diagnostics.diskAvailable)
        return metric(t("Disponible en el disco"), value, "internaldrive")
    }

    func card<Actions: View>(_ title: String, _ icon: String, primary: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            Text(primary).font(.title2.weight(.semibold)).monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth, value: primary)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
            actions()
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading).padding(16)
        .surface(interactive: true, highContrast: highContrast)
        .hoverLift(!reduceMotion)
        .accessibilityElement(children: .contain)
    }
}

/// Carpeta personal que se muestra como «~»: la de prueba si hay MARGIN_HOME, para no enseñar rutas reales.
let displayHome = DevEnvironment.testSetting("HOME") ?? NSHomeDirectory()

/// Marca de Margin: una barra de disco con un margen libre a la derecha.
struct BrandMark: View {
    var color: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.24).fill(color.gradient)
                HStack(spacing: w * 0.05) {
                    RoundedRectangle(cornerRadius: w * 0.05).fill(.white).frame(width: w * 0.30)
                    RoundedRectangle(cornerRadius: w * 0.05).fill(.white.opacity(0.75)).frame(width: w * 0.18)
                    RoundedRectangle(cornerRadius: w * 0.05).strokeBorder(.white, style: StrokeStyle(lineWidth: max(1, w * 0.04), dash: [w * 0.06, w * 0.05])).frame(width: w * 0.20)
                }.frame(height: h * 0.30)
            }
        }.accessibilityHidden(true)
    }
}
