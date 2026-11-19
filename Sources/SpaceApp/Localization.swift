import Foundation

/// Idioma de la interfaz. El texto fuente está en español y sirve de clave; `english` tiene la traducción.
/// Se cambia en caliente desde Ajustes (la vista raíz se reconstruye al cambiar el ajuste).
enum Localizer {
    /// Se calcula una vez y se recalcula con `refresh()` al cambiar el idioma. Leerlo de UserDefaults en cada `t()`
    /// (cientos por dibujo) era lo que más CPU gastaba al actualizar Rendimiento.
    nonisolated(unsafe) private(set) static var isEnglish = computeIsEnglish()
    nonisolated(unsafe) private(set) static var locale = Locale(identifier: isEnglish ? "en_US" : "es_ES")

    /// `language` es el valor del ajuste si ya se conoce (al dibujar); si no, se lee de UserDefaults.
    static func refresh(_ language: String? = nil) {
        let english = computeIsEnglish(language)
        guard english != isEnglish || language == nil else { return }
        isEnglish = english
        locale = Locale(identifier: english ? "en_US" : "es_ES")
    }

    private static func computeIsEnglish(_ language: String? = nil) -> Bool {
        switch language ?? UserDefaults.standard.string(forKey: Pref.language) ?? "sistema" {
        case "es": return false
        case "en": return true
        default: return !(Locale.preferredLanguages.first ?? "es").hasPrefix("es")
        }
    }
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
