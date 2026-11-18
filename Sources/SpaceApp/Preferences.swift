import SwiftUI
import AppKit
import SpaceCore

/// Claves de los ajustes (UserDefaults). Se leen con @AppStorage en las vistas y con `Preferences` fuera de ellas.
enum Pref {
    static let language = "idioma"          // sistema | es | en
    static let theme = "tema"               // sistema | claro | oscuro
    static let startTab = "pestanaInicial"
    static let measureOnLaunch = "medirDiscoAlAbrir"
    static let smartOnLaunch = "analisisAlAbrir"
    static let inactiveDays = "diasInactividad"
    static let projectRoots = "carpetasProyectos" // rutas separadas por saltos de línea; vacío = las de siempre
    static let colorblind = "coloresDaltonismo"
    static let highContrast = "masContraste"
    static let reduceMotion = "reducirMovimiento"
}

enum Preferences {
    static var defaults: UserDefaults { .standard }

    static func register() {
        defaults.register(defaults: [
            Pref.language: "sistema", Pref.theme: "sistema", Pref.startTab: "Inicio", Pref.measureOnLaunch: true,
            Pref.smartOnLaunch: false, Pref.inactiveDays: 30, Pref.projectRoots: "", Pref.colorblind: false,
            Pref.highContrast: false, Pref.reduceMotion: false
        ])
    }

    static var customProjectRoots: [String] {
        (defaults.string(forKey: Pref.projectRoots) ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Entorno de análisis con los ajustes del usuario (días de inactividad y carpetas de proyectos).
    /// MARGIN_HOME (o ESPACIO_HOME) permite probar de punta a punta sobre una carpeta personal sintética.
    static func environment() -> DevEnvironment {
        let roots = customProjectRoots
        let days = max(1, defaults.integer(forKey: Pref.inactiveDays))
        return DevEnvironment.fromProcess(projectRoots: roots.isEmpty ? nil : roots.map { URL(fileURLWithPath: $0) }, inactiveDays: days)
    }

    static func applyTheme(_ value: String) {
        NSApp.appearance = value == "claro" ? NSAppearance(named: .aqua) : value == "oscuro" ? NSAppearance(named: .darkAqua) : nil
    }
}

func appEnvironment() -> DevEnvironment { Preferences.environment() }

/// Colores de la app. Con «colores aptos para daltonismo» se usa la paleta de Okabe e Ito, que se distingue con
/// cualquier tipo de daltonismo; «más contraste» refuerza bordes y fondos.
struct Palette {
    var colorblind = false
    var highContrast = false

    var accent: Color { colorblind ? Color(hex: 0x009E73) : Color(red: 0.12, green: 0.58, blue: 0.48) }
    var warning: Color { colorblind ? Color(hex: 0xE69F00) : .orange }
    var danger: Color { colorblind ? Color(hex: 0xD55E00) : .red }
    var synced: Color { colorblind ? Color(hex: 0x56B4E9) : .blue }
    var cardFill: Color { Color.primary.opacity(highContrast ? 0.08 : 0.035) }
    var borderWidth: CGFloat { highContrast ? 1.5 : 1 }
    var borderOpacity: Double { highContrast ? 1 : 0.8 }

    func color(_ kind: StorageSegment.Kind) -> Color {
        switch kind {
        case .apps: return colorblind ? Color(hex: 0x0072B2) : Color(hex: 0x3B82F6)
        case .personal: return colorblind ? Color(hex: 0x009E73) : Color(hex: 0x1F9479)
        case .appData: return colorblind ? Color(hex: 0xE69F00) : Color(hex: 0xF59E0B)
        case .development: return colorblind ? Color(hex: 0xCC79A7) : Color(hex: 0x8B5CF6)
        case .macOS: return colorblind ? Color(hex: 0xF0E442) : Color(hex: 0xEC4899)
        case .trash: return colorblind ? Color(hex: 0xD55E00) : Color(hex: 0xEF4444)
        case .purgeable: return colorblind ? Color(hex: 0x56B4E9) : Color(hex: 0x7DD3FC)
        case .system: return colorblind ? Color(hex: 0x8C8C8C) : Color(hex: 0x6B7280)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Tamaño en unidades decimales (como Finder: 1 GB = 1000³ bytes) con el separador decimal del idioma elegido.
/// ByteCountFormatter no deja elegir idioma: usaría siempre el del sistema.
func formatBytes(_ bytes: Int64) -> String {
    let magnitude = abs(Double(bytes))
    let sign = bytes < 0 ? "-" : ""
    if magnitude < 1000 { return "\(sign)\(abs(bytes)) bytes" }
    let units = ["KB", "MB", "GB", "TB", "PB"]
    var value = magnitude / 1000
    var index = 0
    while value >= 999.995 && index < units.count - 1 { value /= 1000; index += 1 }
    let digits = index == 0 ? 0 : index == 1 ? 1 : 2
    let number = value.formatted(.number.precision(.fractionLength(0...digits)).locale(Localizer.locale))
    return "\(sign)\(number) \(units[index])"
}

func size(_ bytes: Int64?) -> String {
    bytes.map { formatBytes($0) } ?? t("No disponible")
}

/// Porcentaje con el separador decimal del idioma elegido.
func percent(_ part: Int64, of total: Int64) -> String {
    let value = Double(part) / Double(max(total, 1))
    return value.formatted(.percent.precision(.fractionLength(value < 0.1 ? 1 : 0)).locale(Localizer.locale))
}
