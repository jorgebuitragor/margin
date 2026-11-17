import SwiftUI
import AppKit
import SpaceCore

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false // «0 KB» en lugar de «Zero KB»
    return formatter.string(fromByteCount: bytes)
}

func size(_ bytes: Int64?) -> String {
    bytes.map { formatBytes($0) } ?? "No disponible"
}

/// ESPACIO_HOME permite probar la app de punta a punta sobre una carpeta personal sintética (igual que la CLI).
func appEnvironment() -> DevEnvironment {
    if let home = ProcessInfo.processInfo.environment["ESPACIO_HOME"] { return DevEnvironment(home: URL(fileURLWithPath: home)) }
    return DevEnvironment()
}

struct ReportBox: Identifiable { let report: ApplyReport; var id: String { report.planID } }

/// Nodo del árbol de carpetas, construido a partir de la lista plana del informe.
struct FolderNode: Identifiable {
    let folder: FolderTotal
    var children: [FolderNode]?
    var id: String { folder.path }

    static func tree(_ report: ScanReport) -> [FolderNode] {
        let byParent = Dictionary(grouping: report.folders.filter { $0.depth > 0 }) {
            URL(fileURLWithPath: $0.path).deletingLastPathComponent().standardizedFileURL.path
        }
        func build(_ path: String) -> [FolderNode]? {
            guard let list = byParent[path] else { return nil }
            return list.sorted { $0.allocatedBytes > $1.allocatedBytes }.map { FolderNode(folder: $0, children: build($0.path)) }
        }
        return build(URL(fileURLWithPath: report.root).standardizedFileURL.path) ?? []
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var report: ScanReport?
    @Published var busy = false
    @Published var visited = 0
    @Published var message = "Elige una carpeta para empezar. El análisis no modifica tus archivos."
    @Published var diagnostics = Diagnostics.read()
    private var cancellation: ScanCancellation?
    private var session = UUID()

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analizar carpeta"
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }
    func scan(_ url: URL) {
        cancellation?.cancel()
        let token = ScanCancellation()
        cancellation = token
        let current = UUID()
        session = current
        report = nil
        visited = 0
        busy = true
        message = "Analizando metadatos…"
        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try Scanner.scan(root: url, cancellation: token) { count in
                        Task { @MainActor [weak self] in
                            guard let self, self.session == current, self.busy else { return }
                            self.visited = count
                        }
                    }
                }.value
                guard session == current else { return }
                report = output
                visited = output.visited
                message = output.cancelled ? "Cancelado · totales parciales" : !output.issues.isEmpty ? "Terminado con elementos ilegibles · los totales son un mínimo" : output.limited ? "Análisis terminado · se listan los 20.000 archivos más grandes" : "Análisis terminado"
                if let provider = output.syncedBy { message += " · carpeta sincronizada con \(provider): solo se mide" }
            } catch {
                guard session == current else { return }
                message = error.localizedDescription
            }
            busy = false
        }
    }
    func cancel() { cancellation?.cancel(); message = "Cancelando…" }

    @Published var dev: DevReport?
    @Published var devBusy = false

    // Acciones (0.4): plan → confirmación → ejecución → resultado.
    @Published var pendingPlan: Plan?
    @Published var blockers: [String: String] = [:]
    @Published var preparing = false
    @Published var applying = false
    @Published var applyReport: ApplyReport?
    @Published var planError: String?

    func prepare(devItems: [DevItem] = [], files: [FileEntry] = []) {
        preparing = true
        planError = nil
        Task {
            let outcome: Result<(Plan, [String: String]), Error> = await Task.detached(priority: .userInitiated) {
                let env = appEnvironment()
                return Result {
                    let plan = try Planner.plan(devItems: devItems, files: files, env: env)
                    try PlanStore.save(plan, env)
                    var fresh: [String: ProfileResult] = [:]
                    var blocked: [String: String] = [:]
                    for step in plan.steps { blocked[step.id] = Planner.blocker(step, plan: plan, env: env, freshProfiles: &fresh) }
                    return (plan, blocked)
                }
            }.value
            switch outcome {
            case .success(let (plan, blocked)): pendingPlan = plan; blockers = blocked
            case .failure(let error): planError = error.localizedDescription
            }
            preparing = false
        }
    }

    func applyPending() {
        guard let plan = pendingPlan else { return }
        applying = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try Planner.apply(plan, env: plan.environment(from: appEnvironment())) }
            }.value
            pendingPlan = nil
            applying = false
            switch outcome {
            case .success(let report): applyReport = report
            case .failure(let error): planError = error.localizedDescription
            }
            diagnostics = Diagnostics.read()
            if dev != nil { analyzeDev() }
        }
    }
    func analyzeDev() {
        devBusy = true
        Task {
            let report = await Task.detached(priority: .userInitiated) { DevProfiles.report(appEnvironment()) }.value
            dev = report
            devBusy = false
        }
    }
}

@main
struct SpaceApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Espacio · Tu Mac, con claridad") {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 650)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    // ESPACIO_SCAN analiza una carpeta al arrancar (pruebas de interfaz sin el selector del sistema).
                    if let path = ProcessInfo.processInfo.environment["ESPACIO_SCAN"], model.report == nil {
                        model.scan(URL(fileURLWithPath: path))
                    }
                }
        }
        .defaultSize(width: 1180, height: 780)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var category: SpaceCore.Category?
    @State private var search = ""
    @State private var selected = Set<String>()
    @State private var devChecked = Set<String>()
    @State private var acceptReview = false
    @State private var tab = "Carpetas"
    private let accent = Color(red: 0.12, green: 0.58, blue: 0.48)
    var filtered: [FileEntry] {
        (model.report?.entries ?? []).filter {
            (category == nil || $0.classification.category == category) && (search.isEmpty || $0.path.localizedCaseInsensitiveContains(search))
        }
    }
    var chosen: FileEntry? { selected.count == 1 ? model.report?.entries.first { selected.contains($0.id) } : nil }
    var trashableSelection: [FileEntry] {
        (model.report?.entries ?? []).filter { selected.contains($0.id) && $0.classification.category == .review && $0.bytes != nil }
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 26) {
                Label("Espacio", systemImage: "internaldrive.fill")
                    .font(.largeTitle.bold()).foregroundStyle(accent).padding(.top, 24)
                Text("CONOCE TU MAC").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(["Carpetas", "Archivos", "Desarrollo", "Memoria RAM"], id: \.self) { item in
                    Button { tab = item } label: {
                        Label(item, systemImage: item == "Carpetas" ? "folder" : item == "Archivos" ? "doc" : item == "Desarrollo" ? "hammer" : "memorychip")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(tab == item ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Label("Nada sin tu confirmación", systemImage: "checkmark.shield").foregroundStyle(accent)
                Text("Solo Papelera o el comando oficial de cada herramienta; nunca borrado permanente.\nVersión local 0.4").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
            .navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tab == "Memoria RAM" ? "Entiende tu memoria" : "Entiende qué ocupa espacio").font(.title.bold())
                        Text(tab == "Carpetas" ? "Cuánto ocupa cada carpeta, incluidas las protegidas." : tab == "Desarrollo" ? "Cachés y artefactos regenerables, con el comando oficial de cada herramienta." : tab == "Archivos" ? "Revisa cada archivo con contexto antes de decidir." : "Mediciones reales, sin promesas de aceleración.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if tab == "Desarrollo" {
                        Button(model.dev == nil ? "Analizar" : "Volver a analizar", systemImage: "hammer") { model.analyzeDev() }.buttonStyle(.borderedProminent).tint(accent).disabled(model.devBusy)
                    } else if tab != "Memoria RAM" {
                        Button("Elegir carpeta…", systemImage: "folder.badge.plus") { model.choose() }.buttonStyle(.borderedProminent).tint(accent)
                    } else {
                        Button("Actualizar", systemImage: "arrow.clockwise") { model.diagnostics = Diagnostics.read() }
                    }
                }
                if tab == "Carpetas" { folders } else if tab == "Archivos" { files } else if tab == "Desarrollo" { development } else { memory }
            }.padding(28)
        }
        .tint(accent)
        .sheet(item: $model.pendingPlan) { plan in confirmation(plan) }
        .sheet(item: Binding(get: { model.applyReport.map { ReportBox(report: $0) } }, set: { if $0 == nil { model.applyReport = nil } })) { box in results(box.report) }
        .alert("No se pudo preparar el plan", isPresented: Binding(get: { model.planError != nil }, set: { if !$0 { model.planError = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text(model.planError ?? "") }
    }

    func confirmation(_ plan: Plan) -> some View {
        let runnable = plan.steps.filter { model.blockers[$0.id] == nil }
        let hasReview = runnable.contains { $0.category == .review }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Revisa el plan").font(.title2.bold())
            Text("Recuperable estimado \(size(plan.recoverable)). Cada paso se vuelve a comprobar justo antes de actuar.").foregroundStyle(.secondary)
            List(plan.steps) { step in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: model.blockers[step.id] != nil ? "xmark.octagon" : step.category == .review ? "eye" : "checkmark.circle")
                            .foregroundStyle(model.blockers[step.id] != nil ? .red : step.category == .review ? .orange : accent)
                        Text(step.title).font(.headline)
                        Spacer()
                        Text(size(step.recoverable)).monospacedDigit()
                    }
                    Text(step.action.kind == .trash ? "Mover a la Papelera: \(step.action.paths.count == 1 ? step.action.paths[0] : "\(step.action.paths.count) rutas")" : "Ejecutar: \(step.action.command)")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text("Si se retira: \(step.regenerate)").font(.caption).foregroundStyle(.secondary)
                    if let note = step.action.note { Text(note).font(.caption).foregroundStyle(.orange) }
                    if let blocker = model.blockers[step.id] { Text("No se ejecutará: \(blocker)").font(.caption).foregroundStyle(.red) }
                }.padding(.vertical, 4)
            }.frame(minHeight: 240)
            Text("Lo que vaya a la Papelera se recupera desde Finder hasta que la vacíes. Los comandos de las herramientas no se pueden deshacer.").font(.caption)
            if hasReview {
                Toggle("Entiendo que hay elementos marcados «Revisar antes de borrar» y los he revisado", isOn: $acceptReview)
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { model.pendingPlan = nil; acceptReview = false }.keyboardShortcut(.cancelAction)
                Button(model.applying ? "Ejecutando…" : runnable.count == 1 ? "Ejecutar 1 paso" : "Ejecutar \(runnable.count) pasos", role: .destructive) { model.applyPending(); acceptReview = false; devChecked.removeAll(); selected.removeAll() }
                    .disabled(runnable.isEmpty || model.applying || (hasReview && !acceptReview))
            }
        }.padding(24).frame(width: 720, height: 560)
    }

    func results(_ report: ApplyReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resultado").font(.title2.bold())
            List(report.results, id: \.stepID) { result in
                VStack(alignment: .leading, spacing: 3) {
                    Label("\(result.title): \(result.message)", systemImage: result.status == .done ? "checkmark.circle.fill" : result.status == .blocked ? "xmark.octagon" : "exclamationmark.triangle")
                        .foregroundStyle(result.status == .done ? accent : result.status == .blocked ? .secondary : .orange)
                    ForEach(result.failures.sorted(by: { $0.key < $1.key }), id: \.key) { Text("\($0.key): \($0.value)").font(.caption).foregroundStyle(.red) }
                    if result.status == .failed, let output = result.output { Text(output).font(.system(.caption2, design: .monospaced)).lineLimit(6) }
                }
            }.frame(minHeight: 200)
            Text("Espacio disponible: antes \(size(report.availableBefore)), después \(size(report.availableAfter))\(report.freedObserved.map { " (\($0 >= 0 ? "+" : "")\(formatBytes($0)))" } ?? "").")
            if report.usedTrash { Text("Lo movido a la Papelera no libera espacio hasta que la vacíes.").foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Cerrar") { model.applyReport = nil }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 640, height: 480)
    }
    var status: some View {
        HStack {
            if model.busy { ProgressView().controlSize(.small) }
            Text(model.message).font(.callout)
            Spacer()
            if model.busy {
                Text("\(model.visited) revisados").foregroundStyle(.secondary)
                Button("Cancelar") { model.cancel() }
            }
        }.accessibilityElement(children: .combine)
    }
    var folders: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                metric("Disponible en el volumen del usuario", size(model.diagnostics.diskAvailable), "internaldrive")
                metric("Total de la carpeta analizada", model.report.map { size($0.totalAllocated) } ?? "—", "folder")
                metric("Archivos revisados", "\(model.report?.visited ?? 0)", "doc.on.doc")
            }
            status
            if let report = model.report {
                Text(report.root).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                let total = max(report.totalAllocated, 1)
                List(FolderNode.tree(report), children: \.children) { node in
                    let folder = node.folder
                    HStack(spacing: 10) {
                        Image(systemName: folder.protection == "sync" ? "icloud" : folder.protection == "protected" ? "lock" : "folder")
                            .foregroundStyle(folder.protection == nil ? accent : .secondary)
                            .help(folder.reason ?? "Carpeta analizable")
                        Text(folder.name).lineLimit(1).help(folder.path)
                        Spacer()
                        ProgressView(value: Double(folder.allocatedBytes), total: Double(total)).frame(width: 120)
                        Text(size(folder.allocatedBytes) + (folder.partial ? "+" : "")).monospacedDigit().frame(width: 90, alignment: .trailing)
                    }
                    .contextMenu {
                        Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)]) }
                        Button("Analizar esta carpeta") { model.scan(URL(fileURLWithPath: folder.path)) }.disabled(folder.protection != nil)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(folder.name), \(size(folder.allocatedBytes))\(folder.protection == "sync" ? ", sincronizada" : folder.protection == "protected" ? ", protegida" : "")")
                }.frame(minHeight: 260)
                Text("Candado: protegida (sistema, configuración, dependencias). Nube: sincronizada. Ambas se miden pero no se ofrecen para limpieza. «+» indica que hubo elementos ilegibles y el total es un mínimo.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !model.busy {
                ContentUnavailableView("Empieza por una carpeta", systemImage: "folder.badge.questionmark", description: Text("Elige, por ejemplo, tu carpeta personal. Verás cuánto ocupa cada carpeta, también las de Library y las dependencias de proyectos."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    @State private var devSelection: String?
    var development: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                metric("Bajo riesgo · recuperable estimado", model.dev.map { size($0.lowRiskBytes) } ?? "—", "checkmark.circle")
                metric("Para revisar", model.dev.map { size($0.reviewBytes) } ?? "—", "eye")
                metric("Disponible en el volumen", size(model.diagnostics.diskAvailable), "internaldrive")
            }
            if model.devBusy {
                HStack { ProgressView().controlSize(.small); Text("Midiendo cachés y proyectos… (unos 30 s)") }
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
                                        .accessibilityLabel("Incluir \(item.title) en el plan")
                                    Image(systemName: item.category == .lowRisk ? "checkmark.circle" : item.category == .review ? "eye" : "lock")
                                        .foregroundStyle(item.category == .lowRisk ? accent : item.category == .review ? .orange : .secondary)
                                    Text(item.title).lineLimit(1)
                                    Spacer()
                                    Text(item.category.rawValue).font(.caption).foregroundStyle(.secondary)
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
                                Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                            }
                        }
                        Text(item.reason)
                        Text("Si se retira: \(item.regenerate)").foregroundStyle(.secondary)
                        Text("Ocupa \(size(item.bytes)) · recuperable estimado \(size(item.recoverable))").font(.caption)
                        if let action = item.action {
                            HStack {
                                Text(action.command).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                Spacer()
                                Button("Copiar", systemImage: "doc.on.doc") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(action.kind == .command ? action.command : (item.path ?? ""), forType: .string)
                                }
                            }
                            if let preview = action.preview { Text("Vista previa: \(preview)").font(.caption).textSelection(.enabled) }
                            if let note = action.note { Text(note).font(.caption).foregroundStyle(.orange) }
                        }
                    }.padding(16).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                let checked = items.flatMap(\.items).filter { devChecked.contains($0.id) && $0.canDelete }
                HStack {
                    Text("Marca elementos y revisa el plan antes de ejecutar. «Recuperable estimado» excluye archivos con enlaces duros compartidos.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.preparing { ProgressView().controlSize(.small) }
                    Button("Revisar plan (\(checked.count))…", systemImage: "list.bullet.clipboard") { model.prepare(devItems: checked) }
                        .disabled(checked.isEmpty || model.preparing || model.applying)
                }
            } else if !model.devBusy {
                ContentUnavailableView("Analiza tus herramientas de desarrollo", systemImage: "hammer", description: Text("Android SDK y emuladores, simuladores y Xcode, node_modules de proyectos inactivos, pnpm, Gradle, Docker, Homebrew…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    var files: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                metric("Disponible en el volumen del usuario", size(model.diagnostics.diskAvailable), "internaldrive")
                metric("Elementos listados", "\(model.report?.entries.count ?? 0)", "doc.on.doc")
                metric("Omitidos / sin inspeccionar", "\(model.report?.omitted ?? 0)", "shield")
            }
            status
            if let report = model.report {
                Text(report.root).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                TextField("Buscar por nombre o ubicación", text: $search).textFieldStyle(.roundedBorder)
                Picker("Clasificación", selection: $category) {
                    Text("Todas").tag(nil as SpaceCore.Category?)
                    ForEach(SpaceCore.Category.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }.frame(width: 280)
            }
            if model.report == nil && !model.busy {
                ContentUnavailableView("Empieza por una carpeta", systemImage: "folder.badge.questionmark", description: Text("Elige, por ejemplo, Descargas. Verás tamaños y razones para revisar o conservar cada elemento."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filtered, selection: $selected) {
                    TableColumn("Archivo") { entry in
                        // La carpeta contenedora distingue elementos homónimos (por ejemplo, varios node_modules).
                        HStack(spacing: 6) {
                            Text(entry.name)
                            Text(URL(fileURLWithPath: entry.path).deletingLastPathComponent().lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        }.help(entry.path)
                    }
                    TableColumn("Tamaño") { entry in Text(size(entry.bytes ?? entry.allocatedBytes)).monospacedDigit() }.width(100)
                    TableColumn("Clasificación") { entry in
                        Label(entry.classification.category.rawValue, systemImage: entry.classification.category == .protected ? "lock" : "questionmark.circle")
                    }.width(190)
                }.frame(minHeight: 180)
                if filtered.isEmpty { Text("No hay resultados para mostrar con estos filtros.").foregroundStyle(.secondary) }
            }
            HStack {
                Text(selected.count > 1 ? "\(selected.count) seleccionados; solo los «Revisar antes de borrar» pueden ir a la Papelera." : "Selecciona varios con ⌘ o ⇧.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Mover a la Papelera (\(trashableSelection.count))…", systemImage: "trash") { model.prepare(files: trashableSelection) }
                    .disabled(trashableSelection.isEmpty || model.preparing || model.applying)
            }
            if let entry = chosen {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Por qué · \(entry.name)").font(.headline)
                        Spacer()
                        Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) }
                    }
                    Text(entry.classification.reason)
                    Text(entry.classification.consequence).foregroundStyle(.secondary)
                    Text("Asignado en disco: \(size(entry.allocatedBytes)) · Regla: \(entry.classification.rule)").font(.caption)
                    Text(entry.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }.padding(16).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
            if let issues = model.report?.issues, !issues.isEmpty {
                DisclosureGroup("Incidencias (\(issues.count), máximo 100 mostradas)") {
                    ScrollView { Text(issues.joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90)
                }
            }
            Text("Se listan los archivos más grandes y las carpetas protegidas con su total. Los tamaños no equivalen a espacio recuperable. No se recomienda borrar por edad o tamaño. No se inspecciona el contenido de archivos ni se detectan duplicados.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    var memory: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                metric("RAM instalada", size(Int64(model.diagnostics.physicalMemory)), "memorychip")
                metric("Memoria cableada", size(model.diagnostics.wiredMemory.map(Int64.init)), "lock")
            }
            HStack {
                metric("RAM ocupada por el compresor", size(model.diagnostics.compressedMemory.map(Int64.init)), "arrow.down.right.and.arrow.up.left")
                metric("Intercambio en disco", size(model.diagnostics.swapUsed.map(Int64.init)), "internaldrive")
            }
            GroupBox("Cómo interpretar estos datos") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("La memoria cableada debe permanecer en RAM. El compresor reduce el espacio necesario para almacenar algunas páginas. El intercambio utiliza disco para apoyar la memoria virtual.")
                    Text("Estas cifras son componentes, no deben sumarse como uso total. El intercambio acumulado por sí solo no demuestra lentitud.")
                    Text("La presión de memoria no se calcula aquí. Para consultar su gráfica y el consumo por aplicación, abre Monitor de Actividad.")
                    Button("Abrir Monitor de Actividad", systemImage: "waveform.path.ecg") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Muestra: \(model.diagnostics.date.formatted(date: .abbreviated, time: .standard))").font(.caption).foregroundStyle(.secondary)
            ForEach(model.diagnostics.errors, id: \.self) { Text($0).foregroundStyle(.orange) }
            Spacer()
        }
    }
    func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}
