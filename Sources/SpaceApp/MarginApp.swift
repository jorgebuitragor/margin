import SwiftUI
import AppKit
import SpaceCore

@main
struct MarginApp: App {
    @StateObject private var model = AppModel()
    @AppStorage(Pref.language) private var language = "sistema"
    @AppStorage(Pref.theme) private var theme = "sistema"

    init() {
        Preferences.register()
        CoreText.isEnglish = Localizer.isEnglish
        // Lanzada por el agente de aviso de poco espacio: comprueba, avisa si hace falta y termina sin abrir ventana.
        if CommandLine.arguments.contains(SpaceAlertAgent.argument) { SpaceAlertAgent.runCheckAndExit() }
    }

    var body: some Scene {
        WindowGroup("Margin") {
            ContentView(model: model)
                // Cambiar el idioma reconstruye toda la interfaz con los textos nuevos.
                .id(language)
                .frame(minWidth: 980, minHeight: 650)
                .preferredColorScheme(theme == "claro" ? .light : theme == "oscuro" ? .dark : nil)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    Preferences.applyTheme(theme)
                    let defaults = UserDefaults.standard
                    model.loadStorage(measureIfOld: defaults.bool(forKey: Pref.measureOnLaunch))
                    // MARGIN_SCAN analiza una carpeta al arrancar (pruebas de interfaz sin el selector del sistema).
                    if let path = DevEnvironment.testSetting("SCAN"), model.report == nil {
                        model.scan(URL(fileURLWithPath: path))
                    } else if defaults.bool(forKey: Pref.smartOnLaunch), model.dev == nil {
                        model.analyzeDev()
                    }
                }
                .onChange(of: theme) { Preferences.applyTheme(theme) }
                .onChange(of: language) {
                    // Las explicaciones del análisis se generan en el idioma elegido: se rehace el análisis inteligente
                    // (unos 8 s) para que también cambien. Los análisis de carpetas se traducen al repetirlos.
                    CoreText.isEnglish = Localizer.isEnglish
                    if model.dev != nil, !model.devBusy { model.analyzeDev() }
                }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(t("Ajustes…")) { model.tab = "Ajustes" }.keyboardShortcut(",", modifiers: .command)
            }
            // ⌘1…⌘5 saltan entre secciones sin tocar el ratón.
            CommandGroup(before: .sidebar) {
                ForEach(Array(ContentView.tabs.enumerated()), id: \.element.id) { index, item in
                    Button(t(item.id)) { model.tab = item.id }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
            }
            // Carpetas frecuentes sin pasar por el selector del sistema (también accesibles por teclado).
            CommandMenu(t("Analizar")) {
                ForEach(AppModel.quickFolders(), id: \.path) { item in
                    Button(item.title) { model.scan(item.url); model.showTabs = ["Carpetas", "Archivos"] }
                        .keyboardShortcut(item.shortcut, modifiers: [.command, .shift])
                }
                Divider()
                Button(t("Elegir carpeta…")) { model.choose(); if model.report != nil || model.busy { model.showTabs = ["Carpetas", "Archivos"] } }.keyboardShortcut("o", modifiers: .command)
                Button(t("Análisis inteligente")) { model.analyzeDev(); model.showTabs = ["Inicio", "Limpieza"] }.keyboardShortcut("r", modifiers: .command)
                Button(t("Volver a medir el disco")) { model.measureStorage(); model.showTabs = ["Inicio"] }.keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}
