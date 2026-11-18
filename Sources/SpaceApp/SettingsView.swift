import SwiftUI
import AppKit
import SpaceCore

/// Ajustes: general, análisis, apariencia, idioma, accesibilidad y datos. Todo se guarda al momento.
struct SettingsPane: View {
    @ObservedObject var model: AppModel
    @AppStorage(Pref.startTab) var startTab = "Inicio"
    @AppStorage(Pref.measureOnLaunch) var measureOnLaunch = true
    @AppStorage(Pref.smartOnLaunch) var smartOnLaunch = false
    @AppStorage(Pref.inactiveDays) var inactiveDays = 30
    @AppStorage(Pref.projectRoots) var projectRootsText = ""
    @AppStorage(Pref.theme) var theme = "sistema"
    @AppStorage(Pref.language) var language = "sistema"
    @AppStorage(Pref.colorblind) var colorblind = false
    @AppStorage(Pref.highContrast) var highContrast = false
    @AppStorage(Pref.reduceMotion) var reduceMotion = false
    let palette: Palette

    var roots: [String] {
        let custom = projectRootsText.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        let list = custom.isEmpty ? DevEnvironment.fromProcess().projectRoots.map(\.path) : custom
        // ~/projects y ~/Projects son la misma carpeta en un disco que no distingue mayúsculas: se muestra una vez.
        var seen = Set<[UInt64]>()
        return list.filter { path in
            var info = stat()
            guard stat(path, &info) == 0 else { return true }
            return seen.insert([UInt64(bitPattern: Int64(info.st_dev)), UInt64(info.st_ino)]).inserted
        }
    }

    var body: some View {
        Form {
            Section(t("General")) {
                Picker(t("Pestaña al abrir"), selection: $startTab) {
                    ForEach(ContentView.tabs, id: \.id) { Text(t($0.id)).tag($0.id) }
                }
                Toggle(t("Medir el disco al abrir si la última medición tiene más de 6 horas"), isOn: $measureOnLaunch)
                Toggle(t("Hacer el análisis inteligente al abrir"), isOn: $smartOnLaunch)
            }
            Section {
                Stepper(value: $inactiveDays, in: 7...365, step: 1) {
                    LabeledContent(t("Proyecto inactivo tras"), value: tn(inactiveDays, "día sin cambios", "días sin cambios"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Carpetas de proyectos"))
                    ForEach(roots, id: \.self) { root in
                        HStack {
                            Image(systemName: FileManager.default.fileExists(atPath: root) ? "folder" : "folder.badge.questionmark").foregroundStyle(.secondary)
                            Text(root.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.callout).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(t("Quitar"), systemImage: "minus.circle") { setRoots(roots.filter { $0 != root }) }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                                .disabled(roots.count == 1)
                                .accessibilityLabel(t("Quitar %@", root))
                        }
                    }
                    HStack {
                        Button(t("Añadir carpeta…"), systemImage: "plus") { addRoot() }
                        Button(t("Restablecer")) { projectRootsText = "" }.disabled(projectRootsText.isEmpty)
                    }
                }
            } header: {
                Text(t("Análisis"))
            } footer: {
                Text(t("Los node_modules, build y similares solo se proponen en proyectos de estas carpetas sin commits ni cambios en ese tiempo. Las que no existen se ignoran."))
            }
            Section(t("Apariencia")) {
                Picker(t("Tema"), selection: $theme) {
                    Text(t("Sistema")).tag("sistema")
                    Text(t("Claro")).tag("claro")
                    Text(t("Oscuro")).tag("oscuro")
                }.pickerStyle(.segmented)
            }
            Section {
                Picker(t("Idioma"), selection: $language) {
                    Text(t("Sistema")).tag("sistema")
                    Text("Español").tag("es")
                    Text("English").tag("en")
                }.pickerStyle(.segmented)
            } header: {
                Text(t("Idioma"))
            } footer: {
                Text(t("Cambia la interfaz al momento. Las explicaciones detalladas de cada elemento (por qué se propone, qué pasa si se retira) por ahora están en español."))
            }
            Section {
                Toggle(t("Colores aptos para daltonismo"), isOn: $colorblind)
                Toggle(t("Más contraste en bordes y fondos"), isOn: $highContrast)
                Toggle(t("Reducir movimiento"), isOn: $reduceMotion)
                ColorPreview(palette: palette)
            } header: {
                Text(t("Accesibilidad"))
            } footer: {
                Text(t("La paleta para daltonismo (Okabe e Ito) se distingue con cualquier tipo de daltonismo. Todos los colores llevan además su nombre y su tamaño en texto, y la app respeta «Reducir movimiento» de macOS."))
            }
            Section(t("Datos")) {
                LabeledContent(t("Carpeta de datos"), value: appEnvironment().supportDirectory.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                HStack {
                    Button(t("Mostrar en Finder")) {
                        let url = URL(fileURLWithPath: appEnvironment().supportDirectory)
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button(t("Volver a medir el disco")) { model.measureStorage() }.disabled(model.storageProgress != nil)
                }
                Text(t("Guarda los planes, el registro de acciones y la última medición del disco. No guarda el contenido de tus archivos.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(t("Acerca de")) {
                LabeledContent("Margin", value: t("Versión %@", "0.7"))
                Text(t("Mide tu disco y te ayuda a liberar espacio sin sorpresas: nada se borra sin tu confirmación.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    func setRoots(_ list: [String]) {
        let defaults = DevEnvironment.fromProcess().projectRoots.map(\.path)
        projectRootsText = list == defaults ? "" : list.joined(separator: "\n")
    }

    func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = t("Añadir")
        guard panel.runModal() == .OK else { return }
        var list = roots
        for url in panel.urls where !list.contains(url.path) { list.append(url.path) }
        setRoots(list)
    }
}

/// Muestra de la paleta activa para comprobar que los colores se distinguen.
struct ColorPreview: View {
    let palette: Palette
    var body: some View {
        HStack(spacing: 10) {
            ForEach(StorageSegment.Kind.allCases, id: \.self) { kind in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4).fill(palette.color(kind)).frame(width: 34, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(palette.highContrast ? 0.7 : 0), lineWidth: 1))
                    Text(kind.title).font(.caption2).lineLimit(2).multilineTextAlignment(.center).frame(width: 74)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Muestra de colores de la barra del disco"))
    }
}

extension ContentView {
    var settings: some View { SettingsPane(model: model, palette: palette) }
}
