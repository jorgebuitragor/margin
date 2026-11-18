import SwiftUI
import AppKit
import SpaceCore

@main
struct MargenApp: App {
    @StateObject private var model = AppModel()
    @AppStorage(Pref.language) private var language = "sistema"
    @AppStorage(Pref.theme) private var theme = "sistema"

    init() { Preferences.register() }

    var body: some Scene {
        WindowGroup("Margen") {
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
                    // MARGEN_SCAN analiza una carpeta al arrancar (pruebas de interfaz sin el selector del sistema).
                    if let path = DevEnvironment.testSetting("SCAN"), model.report == nil {
                        model.scan(URL(fileURLWithPath: path))
                    } else if defaults.bool(forKey: Pref.smartOnLaunch), model.dev == nil {
                        model.analyzeDev()
                    }
                }
                .onChange(of: theme) { Preferences.applyTheme(theme) }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(t("Ajustes…")) { model.showTabs = ["Ajustes"] }.keyboardShortcut(",", modifiers: .command)
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
