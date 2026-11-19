import SwiftUI
import AppKit
import SpaceCore

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
    @Published var message = t("Elige una carpeta para empezar. El análisis no modifica tus archivos.")
    @Published var diagnostics = Diagnostics.read()
    /// Pestañas a las que lleva una orden del menú «Analizar», para que su resultado se vea (la primera es el destino
    /// si la pestaña actual no es ninguna de ellas).
    @Published var showTabs: [String]?
    /// Pestaña visible. Vive en el modelo para conservarse cuando la interfaz se reconstruye al cambiar el idioma.
    /// MARGIN_TAB abre una pestaña al arrancar (pruebas visuales sin clics).
    /// «Memoria RAM» se llama «Rendimiento» desde la 0.10: un ajuste o una variable con el nombre antiguo siguen valiendo.
    @Published var tab = AppModel.currentTabName(DevEnvironment.testSetting("TAB") ?? UserDefaults.standard.string(forKey: Pref.startTab) ?? "Inicio")
    static func currentTabName(_ name: String) -> String { name == "Memoria RAM" ? "Rendimiento" : name }

    // Rendimiento: CPU entre dos muestras, temperatura, batería y tiempo encendido.
    @Published var vitals: SystemVitals?
    private let sampler = VitalsSampler()
    /// Una muestra de memoria y de CPU fuera del hilo principal (recorrer los procesos tarda unos milisegundos).
    func refreshPerformance() async {
        let sampler = sampler
        let (read, vitals) = await Task.detached(priority: .utility) { (Diagnostics.read(includeApps: false), sampler.sample()) }.value
        var diagnostics = read
        diagnostics.apps = vitals.topMemory
        diagnostics.hiddenProcesses = vitals.hiddenProcesses
        // Sin animación: redibujar las tarjetas de cristal y animar ~20 barras cada 3 s costaba el 15–20 % de un núcleo.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.diagnostics = diagnostics
            self.vitals = vitals
        }
    }
    private var cancellation: ScanCancellation?
    private var session = UUID()

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = t("Analizar carpeta")
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
        message = t("Analizando metadatos…")
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
                message = output.cancelled ? t("Cancelado · totales parciales") : !output.issues.isEmpty ? t("Terminado con elementos ilegibles · los totales son un mínimo") : output.limited ? t("Análisis terminado · se listan los 20.000 archivos más grandes") : t("Análisis terminado")
                if let provider = output.syncedBy { message += t(" · carpeta sincronizada con %@: solo se mide", provider) }
            } catch {
                guard session == current else { return }
                message = error.localizedDescription
            }
            busy = false
        }
    }
    func cancel() { cancellation?.cancel(); message = t("Cancelando…") }

    struct QuickFolder { let title: String; let url: URL; let shortcut: KeyEquivalent; var path: String { url.path } }
    /// Carpetas habituales que existen en esta carpeta personal (respeta MARGIN_HOME en pruebas).
    static func quickFolders() -> [QuickFolder] {
        let home = appEnvironment().home
        let candidates: [QuickFolder] = [
            QuickFolder(title: t("Carpeta personal"), url: home, shortcut: "h"),
            QuickFolder(title: t("Descargas"), url: home.appendingPathComponent("Downloads"), shortcut: "l"),
            QuickFolder(title: t("Escritorio"), url: home.appendingPathComponent("Desktop"), shortcut: "d"),
            QuickFolder(title: "Developer", url: home.appendingPathComponent("Developer"), shortcut: "p")
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    @Published var dev: DevReport?
    @Published var devBusy = false

    // Apps instaladas y sus restos (sección Apps). Solo lectura hasta que confirmes un plan.
    @Published var apps: AppsReport?
    @Published var appsBusy = false
    func analyzeApps() {
        guard !appsBusy else { return }
        appsBusy = true
        Task {
            let env = appEnvironment()
            apps = await Task.detached(priority: .userInitiated) { AppInventory.report(env) }.value
            appsBusy = false
        }
    }

    // Acciones: plan → confirmación → ejecución → resultado.
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
        let permanent = UserDefaults.standard.bool(forKey: Pref.permanentDelete)
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try Planner.apply(plan, env: plan.environment(from: appEnvironment()), permanent: permanent) }
            }.value
            pendingPlan = nil
            applying = false
            switch outcome {
            case .success(let report): applyReport = report
            case .failure(let error): planError = error.localizedDescription
            }
            refreshCapacity()
            if dev != nil { analyzeDev() }
            if apps != nil { analyzeApps() }
        }
    }
    func analyzeDev() {
        devBusy = true
        Task {
            let env = appEnvironment()
            let (report, trashStatus) = await Task.detached(priority: .userInitiated) { (DevProfiles.report(env), TrashStatus.read(env)) }.value
            dev = report
            trash = trashStatus
            diagnostics = Diagnostics.read()
            devBusy = false
        }
    }

    // Papelera: única acción de borrado definitivo, con diálogo propio.
    @Published var trash: TrashStatus?
    @Published var emptying = false
    @Published var emptyResult: TrashEmptier.Result?
    /// Muestra el diálogo «¿Vaciar la Papelera?». Lo piden la tarjeta de Inicio, el menú (⇧⌘⌫) y el resultado de un plan.
    @Published var confirmEmpty = false

    /// Pide confirmación para vaciar la Papelera, con su tamaño recién leído para que el diálogo diga qué se borra.
    func askEmptyTrash() {
        guard !emptying else { return }
        refreshTrash()
        confirmEmpty = true
    }

    /// Relee el tamaño de la Papelera (al abrir y antes de vaciarla), sin esperar al análisis inteligente.
    func refreshTrash() {
        Task {
            let env = appEnvironment()
            trash = await Task.detached(priority: .userInitiated) { TrashStatus.read(env) }.value
            refreshCapacity()
        }
    }
    func emptyTrash() {
        emptying = true
        Task {
            let env = appEnvironment()
            let result = await Task.detached(priority: .userInitiated) { TrashEmptier.empty(env: env) }.value
            emptyResult = result
            trash = TrashStatus.read(env)
            if result.status == .done, let storage {
                // Lo que había en la Papelera ya no existe: se descuenta sin volver a medir todo el disco.
                var measured = Self.measured(storage)
                measured[.trash] = 0
                self.storage = VolumeCapacity.read(env.home).map { StorageAnalyzer.build(capacity: $0, measured: measured, date: storage.date) } ?? storage
            } else {
                refreshCapacity()
            }
            diagnostics = Diagnostics.read()
            emptying = false
        }
    }

    // Desglose del disco (barra de colores). Se guarda en caché porque medir la carpeta personal tarda.
    @Published var storage: StorageBreakdown?
    @Published var storageProgress: (done: Int, total: Int)?
    @Published var capacity = VolumeCapacity.read()

    func loadStorage(measureIfOld: Bool) {
        let env = appEnvironment()
        capacity = VolumeCapacity.read(env.home)
        refreshTrash()
        if let cached = StorageAnalyzer.cached(env) {
            storage = cached
            refreshCapacity()
            if measureIfOld && Date().timeIntervalSince(cached.date) > 6 * 3600 { measureStorage() }
        } else if measureIfOld {
            measureStorage()
        }
    }

    func measureStorage() {
        guard storageProgress == nil else { return }
        storageProgress = (0, 1)
        Task {
            let env = appEnvironment()
            let result = await Task.detached(priority: .utility) {
                StorageAnalyzer.measure(env) { done, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.storageProgress != nil else { return }
                        self.storageProgress = (done, total)
                    }
                }
            }.value
            if let result {
                StorageAnalyzer.save(result, env)
                storage = result
            }
            capacity = VolumeCapacity.read(env.home)
            storageProgress = nil
        }
    }

    /// Actualiza total y disponible (cambian al limpiar) conservando lo medido por categoría.
    func refreshCapacity() {
        let env = appEnvironment()
        capacity = VolumeCapacity.read(env.home)
        diagnostics = Diagnostics.read()
        guard let storage, let capacity else { return }
        var measured = Self.measured(storage)
        // El intercambio cambia de un minuto a otro: se relee en vivo (solo si la medición ya lo separaba de macOS).
        if measured[.swap] != nil, let swap = StorageAnalyzer.swapFileBytes() { measured[.swap] = swap }
        // La Papelera, con su tamaño actual si macOS deja leerla: así su tramo y su porcentaje aparecen en cuanto tiene
        // algo y desaparecen al vaciarla, sin esperar a la próxima medición del disco.
        if let bytes = trash?.bytes { measured[.trash] = bytes }
        self.storage = StorageAnalyzer.build(capacity: capacity, measured: measured, partial: Set(storage.segments.filter(\.partial).map(\.kind)), date: storage.date)
    }

    static func measured(_ storage: StorageBreakdown) -> [StorageSegment.Kind: Int64] {
        Dictionary(uniqueKeysWithValues: storage.segments.filter { $0.kind != .system && $0.kind != .purgeable }.map { ($0.kind, $0.bytes) })
    }
}
