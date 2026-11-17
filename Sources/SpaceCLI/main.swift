import Foundation
import SpaceCore

func output<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write(try encoder.encode(value))
    print()
}
let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "status" where args.count == 1:
        try output(Diagnostics.read())
    case "scan" where args.count == 2:
        try output(Scanner.scan(root: URL(fileURLWithPath: args[1])))
    case "help", "--help", nil:
        print("""
        espacio status           Diagnóstico de RAM y volumen en JSON.
        espacio scan /ruta       Metadatos y clasificación en JSON; solo lectura.
        Límite: 20.000 elementos. No sigue enlaces ni inspecciona ubicaciones protegidas.
        Los informes incluyen rutas: comparte solo los datos que necesites.
        """)
    default:
        throw NSError(domain: "Espacio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Comando inválido. Usa espacio --help."])
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
