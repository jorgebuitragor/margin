import SwiftUI
import AppKit
import SpaceCore

func size(_ bytes: Int64?) -> String {
    bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "No disponible"
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
                message = output.cancelled ? "Cancelado · resultados parciales" : output.limited ? "Análisis parcial · límite de 20.000 elementos" : output.issues.isEmpty ? "Análisis terminado" : "Terminado con errores · resultados parciales"
            } catch {
                guard session == current else { return }
                message = error.localizedDescription
            }
            busy = false
        }
    }
    func cancel() { cancellation?.cancel(); message = "Cancelando…" }
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
                }
        }
        .defaultSize(width: 1180, height: 780)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var category: SpaceCore.Category?
    @State private var search = ""
    @State private var selected: String?
    @State private var tab = "Archivos"
    private let accent = Color(red: 0.12, green: 0.58, blue: 0.48)
    var filtered: [FileEntry] {
        (model.report?.entries ?? []).filter {
            (category == nil || $0.classification.category == category) && (search.isEmpty || $0.path.localizedCaseInsensitiveContains(search))
        }
    }
    var chosen: FileEntry? { model.report?.entries.first { $0.id == selected } }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 26) {
                Label("Espacio", systemImage: "internaldrive.fill")
                    .font(.largeTitle.bold()).foregroundStyle(accent).padding(.top, 24)
                Text("CONOCE TU MAC").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(["Archivos", "Memoria RAM"], id: \.self) { item in
                    Button { tab = item } label: {
                        Label(item, systemImage: item == "Archivos" ? "folder" : "memorychip")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(tab == item ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Label("Solo lectura", systemImage: "checkmark.shield").foregroundStyle(accent)
                Text("Tus archivos permanecen intactos.\nVersión local 0.1").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
            .navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tab == "Archivos" ? "Entiende qué ocupa espacio" : "Entiende tu memoria").font(.title.bold())
                        Text(tab == "Archivos" ? "Revisa cada archivo con contexto antes de decidir." : "Mediciones reales, sin promesas de aceleración.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if tab == "Archivos" {
                        Button("Elegir carpeta…", systemImage: "folder.badge.plus") { model.choose() }.buttonStyle(.borderedProminent).tint(accent)
                    } else {
                        Button("Actualizar", systemImage: "arrow.clockwise") { model.diagnostics = Diagnostics.read() }
                    }
                }
                if tab == "Archivos" { files } else { memory }
            }.padding(28)
        }
        .tint(accent)
    }
    var files: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                metric("Disponible en el volumen del usuario", size(model.diagnostics.diskAvailable), "internaldrive")
                metric("Elementos listados", "\(model.report?.entries.count ?? 0)", "doc.on.doc")
                metric("Omitidos / sin inspeccionar", "\(model.report?.omitted ?? 0)", "shield")
            }
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.message).font(.callout)
                Spacer()
                if model.busy {
                    Text("\(model.visited) revisados").foregroundStyle(.secondary)
                    Button("Cancelar") { model.cancel() }
                }
            }.accessibilityElement(children: .combine)
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
                    TableColumn("Archivo") { entry in Text(entry.name).help(entry.path) }
                    TableColumn("Tamaño") { entry in Text(size(entry.bytes)).monospacedDigit() }.width(100)
                    TableColumn("Clasificación") { entry in
                        Label(entry.classification.category.rawValue, systemImage: entry.classification.category == .protected ? "lock" : "questionmark.circle")
                    }.width(190)
                }.frame(minHeight: 180)
                if filtered.isEmpty { Text("No hay resultados para mostrar con estos filtros.").foregroundStyle(.secondary) }
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
            Text("Los tamaños no equivalen a espacio recuperable. No se recomienda borrar por edad o tamaño. No se inspecciona el contenido de archivos ni se detectan duplicados.")
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
