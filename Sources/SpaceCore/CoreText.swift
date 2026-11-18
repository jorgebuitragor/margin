import Foundation

/// Idioma de los textos que genera el núcleo (motivos, consecuencias, notas, mensajes de los planes).
/// La app lo pone en inglés si así lo eliges en Ajustes; la CLI y el MCP siguen en español, que es como los leen
/// los agentes y la skill.
public enum CoreText {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var english = false

    public static var isEnglish: Bool {
        get { lock.withLock { english } }
        set { lock.withLock { english = newValue } }
    }
}

/// Texto en español o en inglés según `CoreText.isEnglish`. La traducción solo se evalúa si hace falta.
@inline(__always)
func loc(_ spanish: @autoclosure () -> String, _ english: @autoclosure () -> String) -> String {
    CoreText.isEnglish ? english() : spanish()
}
