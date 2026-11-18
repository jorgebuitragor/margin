import Foundation

/// Idioma de la interfaz. El texto fuente está en español y sirve de clave; `english` tiene la traducción.
/// Se cambia en caliente desde Ajustes (la vista raíz se reconstruye al cambiar el ajuste).
enum Localizer {
    static var isEnglish: Bool {
        switch UserDefaults.standard.string(forKey: Pref.language) ?? "sistema" {
        case "es": return false
        case "en": return true
        default: return !(Locale.preferredLanguages.first ?? "es").hasPrefix("es")
        }
    }
    static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "es_ES") }
}

/// Traduce un texto de la interfaz. Con argumentos, el texto es un formato con `%@`.
func t(_ key: String) -> String {
    guard Localizer.isEnglish else { return key }
    return english[key] ?? key
}

func t(_ key: String, _ args: String...) -> String {
    String(format: t(key), arguments: args)
}

/// Singular o plural según la cantidad: `tn(3, "elemento", "elementos")` → «3 elementos».
func tn(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(t(count == 1 ? singular : plural))"
}
