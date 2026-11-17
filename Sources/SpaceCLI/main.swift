import Foundation
import SpaceCore

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false // «0 KB» en lugar de «Zero KB»
    return formatter.string(fromByteCount: bytes)
}

func output<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write(try encoder.encode(value))
    print()
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

func size(_ bytes: Int64?) -> String {
    bytes.map { formatBytes($0) } ?? "—"
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
}

/// Resumen legible para la terminal: carpetas más grandes y archivos más grandes.
func printText(_ report: ScanReport, folders: Int, files: Int) {
    print("Raíz: \(report.root)")
    print("Total asignado: \(size(report.totalAllocated))\(report.cancelled || !report.issues.isEmpty ? " (mínimo: hubo elementos ilegibles)" : "")")
    if let provider = report.syncedBy { print("Sincronizada con \(provider): solo se mide, nada es accionable.") }
    print("\nCarpetas más grandes")
    for folder in report.folders.filter({ $0.depth > 0 }).prefix(folders) {
        let mark = folder.protection == "sync" ? " [sincronizada]" : folder.protection == "protected" ? " [protegida]" : ""
        let relative = String(folder.path.dropFirst(report.root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        print("\(pad(size(folder.allocatedBytes), 10))  \(relative)\(mark)\(folder.partial ? " (mínimo)" : "")")
    }
    let regular = report.entries.filter { $0.bytes != nil }
    if !regular.isEmpty {
        print("\nArchivos más grandes fuera de carpetas protegidas")
        for entry in regular.prefix(files) {
            let relative = String(entry.path.dropFirst(report.root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            print("\(pad(size(entry.bytes), 10))  \(relative)  · \(entry.classification.category.rawValue)")
        }
    }
    if !report.issues.isEmpty { print("\n\(report.issues.count) incidencias (usa JSON para verlas).") }
}

func printDev(_ report: DevReport) {
    print("Perfiles de desarrollo · \(report.date.formatted(date: .abbreviated, time: .shortened))")
    print("Bajo riesgo (recuperable estimado): \(size(report.lowRiskBytes)) · Para revisar: \(size(report.reviewBytes))")
    print("Nada se ha ejecutado: son propuestas. Proyectos inactivos: \(report.inactiveDays) días o más.\n")
    for profile in report.profiles where profile.detected && !profile.items.isEmpty {
        print("■ \(profile.name) (\(profile.owner)) · bajo riesgo \(size(profile.lowRiskBytes)) · revisar \(size(profile.reviewBytes))")
        for item in profile.items.sorted(by: { ($0.recoverable ?? 0) > ($1.recoverable ?? 0) }) {
            let tag = item.category == .lowRisk ? "BAJO RIESGO" : item.category == .review ? "REVISAR" : "CONSERVAR"
            print("  \(pad(size(item.recoverable ?? item.bytes), 10))  [\(tag)] \(item.title)")
            if item.category != .protected {
                print("              \(item.reason)")
                if let action = item.action {
                    print("              → \(action.command)\(action.preview.map { "  (vista previa: \($0))" } ?? "")\(action.note.map { "  · \($0)" } ?? "")")
                }
            }
        }
        for note in profile.notes { print("  ℹ︎ \(note)") }
        print()
    }
}

func intValue(_ args: inout [String], _ flag: String) -> Int? {
    guard let index = args.firstIndex(of: flag) else { return nil }
    guard index + 1 < args.count, let value = Int(args[index + 1]), value >= 0 else { fail("\(flag) necesita un número entero.") }
    args.removeSubrange(index...index + 1)
    return value
}

var args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "status" where args.count == 1:
        try output(Diagnostics.read())
    case "scan":
        args.removeFirst()
        var options = ScanOptions()
        if let depth = intValue(&args, "--depth") { options.folderDepth = depth }
        if let mb = intValue(&args, "--min-mb") { options.minFolderBytes = Int64(mb) * 1_000_000 }
        if let max = intValue(&args, "--max-files") { options.maxEntries = max }
        let text = args.contains("--text")
        args.removeAll { $0 == "--text" }
        guard args.count == 1 else { fail("Uso: espacio scan /ruta [--depth N] [--min-mb N] [--max-files N] [--text]") }
        let report = try Scanner.scan(root: URL(fileURLWithPath: args[0]), options: options)
        if text { printText(report, folders: 25, files: 15) } else { try output(report) }
    case "dev":
        args.removeFirst()
        var env = DevEnvironment()
        if let days = intValue(&args, "--inactive-days") { env.inactiveDays = days }
        if let index = args.firstIndex(of: "--roots") {
            guard index + 1 < args.count else { fail("--roots necesita rutas separadas por comas.") }
            env.projectRoots = args[index + 1].split(separator: ",").map { URL(fileURLWithPath: NSString(string: String($0)).expandingTildeInPath) }
            args.removeSubrange(index...index + 1)
        }
        let text = args.contains("--text")
        args.removeAll { $0 == "--text" }
        guard args.isEmpty else { fail("Uso: espacio dev [--text] [--inactive-days N] [--roots ruta1,ruta2]") }
        let report = DevProfiles.report(env)
        if text { printDev(report) } else { try output(report) }
    case "help", "--help", nil:
        print("""
        espacio status        Diagnóstico de RAM y volumen en JSON.
        espacio scan /ruta    Totales por carpeta y archivos más grandes en JSON; solo lectura.
            --depth N         Profundidad de carpetas en el informe (por defecto 3).
            --min-mb N        Omite carpetas menores de N MB (por defecto 1).
            --max-files N     Archivos individuales a listar, los más grandes (por defecto 20000).
            --text            Resumen legible en lugar de JSON.
        espacio dev           Perfiles de desarrollo: cachés y artefactos regenerables con su comando oficial.
            --inactive-days N Días sin cambios para considerar inactivo un proyecto (por defecto 30).
            --roots a,b       Carpetas de proyectos (por defecto ~/Developer, ~/git, ~/projects…).
            --text            Resumen legible en lugar de JSON.
        Ningún comando borra nada: dev solo mide y propone.
        Los totales siguen la lógica de du: espacio asignado, enlaces duros una vez, sin seguir enlaces.
        Carpetas protegidas y sincronizadas se miden, pero sus archivos no se listan ni son accionables.
        Los informes incluyen rutas: comparte solo los datos que necesites.
        """)
    default:
        fail("Comando inválido. Usa espacio --help.")
    }
} catch {
    fail(error.localizedDescription)
}
