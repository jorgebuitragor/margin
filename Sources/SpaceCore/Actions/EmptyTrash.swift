import Foundation

/// Vaciar la Papelera: la **única** acción de borrado definitivo del programa, autorizada expresamente por el usuario
/// para la 0.6. Va aparte de los planes, nunca la propone un perfil ni la expone el servidor MCP, y exige su propia
/// confirmación (en la app, un diálogo destructivo; en la CLI, escribir VACIAR en una terminal interactiva).
///
/// Se delega en Finder (`tell application "Finder" to empty trash`): respeta los permisos de macOS, las papeleras de
/// otros volúmenes y los elementos bloqueados, y el programa no necesita leer ni borrar archivos por su cuenta.
public enum TrashEmptier {
    public static let argv = ["/usr/bin/osascript", "-e", "tell application \"Finder\" to empty trash"]

    public struct Result: Codable, Sendable {
        public let date: Date
        public let status: StepResult.Status
        public let message: String
        public let availableBefore: Int64?
        public let availableAfter: Int64?
        public let output: String?
        public var freedObserved: Int64? {
            guard let before = availableBefore, let after = availableAfter else { return nil }
            return after - before
        }
    }

    public static func empty(env: DevEnvironment, executor: ActionExecutor = SystemExecutor()) -> Result {
        // Finder solo conoce la Papelera real: con una carpeta personal de prueba (ESPACIO_HOME) nunca se vacía.
        if executor is SystemExecutor && DevEnvironment.canonical(env.home.path) != DevEnvironment.canonical(FileManager.default.homeDirectoryForCurrentUser.path) {
            return Result(date: Date(), status: .blocked, message: "Modo de prueba: la Papelera real no se vacía con una carpeta personal sintética.", availableBefore: nil, availableAfter: nil, output: nil)
        }
        let before = Planner.available(env)
        let run = executor.run(argv[0], Array(argv.dropFirst()))
        let after = Planner.available(env)
        let status: StepResult.Status
        let message: String
        switch run?.status {
        case 0?:
            status = .done
            message = "Papelera vaciada."
        case nil:
            status = .failed
            message = "No se pudo pedir a Finder que vacíe la Papelera (o tardó demasiado)."
        default:
            status = .failed
            let detail = [run?.output, run?.error].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            message = detail.contains("-1743") || detail.lowercased().contains("not authorized")
                ? "macOS no dio permiso para controlar Finder. Actívalo en Ajustes del Sistema › Privacidad y seguridad › Automatización."
                : "Finder no pudo vaciar la Papelera (¿elementos bloqueados o en uso?)."
        }
        let output = [run?.output ?? "", run?.error ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
        let result = Result(date: Date(), status: status, message: message, availableBefore: before, availableAfter: after, output: output.isEmpty ? nil : Planner.tail(output))
        log(result, env)
        return result
    }

    static func log(_ result: Result, _ env: DevEnvironment) {
        struct Line: Encodable { let date: Date; let plan: String; let title: String; let status: String; let message: String; let availableBefore: Int64?; let availableAfter: Int64? }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(Line(date: result.date, plan: "vaciar-papelera", title: "Vaciar Papelera", status: result.status.rawValue, message: result.message, availableBefore: result.availableBefore, availableAfter: result.availableAfter)) else { return }
        data.append(0x0A)
        let path = "\(env.supportDirectory)/acciones.jsonl"
        try? FileManager.default.createDirectory(atPath: env.supportDirectory, withIntermediateDirectories: true)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
