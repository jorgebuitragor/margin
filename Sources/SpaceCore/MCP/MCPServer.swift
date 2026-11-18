import Foundation

/// Servidor MCP (JSON-RPC 2.0 por stdio, un mensaje por línea) para agentes como Claude Code o Codex.
///
/// Regla central: **ninguna herramienta ejecuta nada**. Los agentes pueden medir, analizar y crear planes;
/// aplicarlos exige que el usuario escriba el código del plan en su propia terminal (`margin apply`).
public final class MCPServer {
    public static let protocolVersion = "2025-06-18"
    public static let toolNames = ["disk_status", "scan_folder", "dev_report", "apps_report", "propose_cleanup", "plan_result"]

    var env: DevEnvironment
    /// Último análisis de perfiles: permite resolver los id que propone el agente sin volver a medir todo.
    private var lastDev: DevReport?
    private var lastApps: AppsReport?

    public init(env: DevEnvironment = DevEnvironment()) { self.env = env }

    /// Procesa una línea JSON-RPC y devuelve la respuesta (nil para notificaciones).
    public func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "JSON inválido"]])
        }
        let id = message["id"]
        guard let method = message["method"] as? String else {
            return id == nil ? nil : encode(["jsonrpc": "2.0", "id": id!, "error": ["code": -32600, "message": "Petición inválida"]])
        }
        // Las notificaciones (sin id) no llevan respuesta.
        guard let id else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            return reply(id, [
                "protocolVersion": requested ?? Self.protocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "margin", "version": "0.7.0"],
                "instructions": "Mide el disco y propone limpiezas seguras. Ninguna herramienta borra ni ejecuta nada: propose_cleanup crea un plan y el usuario lo aplica en su terminal con `margin apply <id>`. No intentes aplicarlo tú."
            ])
        case "ping":
            return reply(id, [:])
        case "tools/list":
            return reply(id, ["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try call(name, args)
                return reply(id, ["content": [["type": "text", "text": text]], "isError": false])
            } catch {
                return reply(id, ["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Método no soportado: \(method)"]])
        }
    }

    // MARK: Herramientas

    struct ToolError: LocalizedError { let errorDescription: String? }

    func call(_ name: String, _ args: [String: Any]) throws -> String {
        switch name {
        case "disk_status":
            // Con el desglose por categorías de la última medición (la app o `margin disco`), si existe.
            struct Status: Encodable { let diagnostics: Diagnostics; let breakdown: StorageBreakdown? }
            let cached = StorageAnalyzer.cached(env)
            let breakdown = cached.flatMap { old in VolumeCapacity.read(env.home).map { StorageAnalyzer.build(capacity: $0, measured: Dictionary(uniqueKeysWithValues: old.segments.filter { $0.kind != .system && $0.kind != .purgeable }.map { ($0.kind, $0.bytes) }), date: old.date) } }
            return try json(Status(diagnostics: Diagnostics.read(), breakdown: breakdown ?? cached))
        case "scan_folder":
            guard let raw = args["path"] as? String, !raw.isEmpty else { throw ToolError(errorDescription: "Falta `path`.") }
            let path = NSString(string: raw).expandingTildeInPath
            var options = ScanOptions(maxEntries: int(args["max_files"]) ?? 30, folderDepth: int(args["depth"]) ?? 2,
                                      minFolderBytes: Int64(int(args["min_mb"]) ?? 100) * 1_000_000)
            options.maxEntries = min(max(options.maxEntries, 1), 500)
            let report = try Scanner.scan(root: URL(fileURLWithPath: path), options: options)
            return try json(ScanSummary(report, maxFiles: options.maxEntries))
        case "dev_report":
            var devEnv = env
            if let days = int(args["inactive_days"]) { devEnv.inactiveDays = max(days, 1) }
            let report = DevProfiles.report(devEnv)
            lastDev = report
            return try json(DevSummary(report))
        case "apps_report":
            let report = AppInventory.report(env)
            lastApps = report
            return try json(AppsSummary(report, limit: int(args["limit"]) ?? 25))
        case "propose_cleanup":
            let ids = (args["ids"] as? [String]) ?? []
            let files = (args["files"] as? [String]) ?? []
            guard !ids.isEmpty || !files.isEmpty else { throw ToolError(errorDescription: "Indica `ids` (de dev_report) o `files`.") }
            var items: [DevItem] = []
            if !ids.isEmpty {
                var all = (lastDev ?? DevProfiles.report(env)).profiles.flatMap(\.items)
                let apps = lastApps ?? AppInventory.report(env, measure: false)
                all += apps.apps.flatMap(\.items) + apps.orphans
                for id in ids {
                    guard let item = all.first(where: { $0.shortID == id }) else { throw ToolError(errorDescription: "No existe el id \(id). Llama antes a dev_report o apps_report.") }
                    items.append(item)
                }
            }
            var entries: [FileEntry] = []
            for raw in files {
                let path = DevEnvironment.canonical(NSString(string: raw).expandingTildeInPath)
                let url = URL(fileURLWithPath: path)
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true else { throw ToolError(errorDescription: "Solo archivos normales: \(path)") }
                entries.append(FileEntry(path: path, bytes: values.fileSize.map(Int64.init), allocatedBytes: values.totalFileAllocatedSize.map(Int64.init), modified: nil, classification: Classifier.classify(url)))
            }
            let plan = try Planner.plan(devItems: items, files: entries, env: env)
            try PlanStore.save(plan, env)
            return try json(PlanSummary(plan))
        case "plan_result":
            guard let id = args["plan"] as? String else { throw ToolError(errorDescription: "Falta `plan`.") }
            let plan = try PlanStore.load(id, env)
            if let data = FileManager.default.contents(atPath: PlanStore.resultPath(plan.id, env)),
               let report = try? PlanStore.decoder.decode(ApplyReport.self, from: data) {
                return try json(report)
            }
            return try json(["plan": plan.id, "estado": "pendiente", "aplicar": "El usuario debe ejecutar en su terminal: margin apply \(plan.id)"])
        default:
            throw ToolError(errorDescription: "Herramienta desconocida: \(name)")
        }
    }

    static var tools: [[String: Any]] { [
        tool("disk_status", "Espacio total y disponible del volumen, métricas de memoria (RAM, compresor, intercambio) y, si hay una medición previa, el desglose del disco por categorías (apps, documentos, datos de apps, desarrollo, Papelera, purgable, sistema) con su fecha. Solo lectura.", [:]),
        tool("scan_folder", "Totales por carpeta (como du -x) y archivos más grandes de una carpeta, con su clasificación. Solo lectura; carpetas protegidas y sincronizadas se miden pero no se listan. Analizar la carpeta personal entera tarda unos 3 minutos.", [
            "path": ["type": "string", "description": "Carpeta a analizar, admite ~."],
            "depth": ["type": "integer", "description": "Profundidad de carpetas (por defecto 2)."],
            "min_mb": ["type": "integer", "description": "Omitir carpetas menores de N MB (por defecto 100)."],
            "max_files": ["type": "integer", "description": "Archivos más grandes a devolver (por defecto 30, máximo 500)."]
        ], required: ["path"]),
        tool("dev_report", "Perfiles de desarrollo (Android, Xcode, simuladores, node_modules inactivos, pnpm, Gradle, Docker, Homebrew, nvm, Claude, VS Code): qué se puede retirar, cuánto se recupera, por qué y con qué comando oficial. Devuelve un `id` por elemento accionable. Solo lectura; tarda unos 30 s.", [
            "inactive_days": ["type": "integer", "description": "Días sin cambios para considerar inactivo un proyecto (por defecto 30)."]
        ]),
        tool("apps_report", "Apps instaladas (de mayor a menor, con sus restos en ~/Library) y restos de apps ya borradas. Cada elemento trae `id` para propose_cleanup. Desinstalar es mover la app y los restos elegidos a la Papelera (o `brew uninstall --cask` si vino de Homebrew); las apps de Apple y Margin están protegidas. Solo lectura; tarda unos segundos.", [
            "limit": ["type": "integer", "description": "Máximo de apps a devolver (por defecto 25)."]
        ]),
        tool("propose_cleanup", "Crea un plan con elementos de dev_report (`ids`) y/o archivos revisables (`files`). NO ejecuta nada: devuelve el código del plan para que el usuario lo aplique en su terminal con `margin apply <plan>`.", [
            "ids": ["type": "array", "items": ["type": "string"], "description": "Identificadores de dev_report."],
            "files": ["type": "array", "items": ["type": "string"], "description": "Rutas de archivos «Revisar antes de borrar»."]
        ]),
        tool("plan_result", "Resultado de un plan: si el usuario ya lo aplicó, el estado de cada paso y el espacio antes/después; si no, que está pendiente.", [
            "plan": ["type": "string", "description": "Código del plan (8 caracteres)."]
        ], required: ["plan"])
    ] }

    static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema, "annotations": ["readOnlyHint": name != "propose_cleanup", "destructiveHint": false]]
    }

    // MARK: Utilidades

    private func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue ?? (value as? String).flatMap(Int.init) }

    private func reply(_ id: Any, _ result: [String: Any]) -> String? { encode(["jsonrpc": "2.0", "id": id, "result": result]) }

    private func encode(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

// MARK: Resúmenes compactos para agentes

struct ScanSummary: Encodable {
    struct Folder: Encodable { let path: String; let bytes: Int64; let protection: String?; let partial: Bool }
    struct File: Encodable { let path: String; let bytes: Int64?; let category: String; let reason: String }
    let root: String
    let totalAllocated: Int64
    let syncedBy: String?
    let complete: Bool
    let folders: [Folder]
    let largestFiles: [File]
    let note = "Tamaños asignados (como du -x). Lo protegido o sincronizado no es accionable. Para retirar archivos «Revisar antes de borrar», usa propose_cleanup con `files`."

    init(_ r: ScanReport, maxFiles: Int) {
        root = r.root
        totalAllocated = r.totalAllocated
        syncedBy = r.syncedBy
        complete = !r.cancelled && r.issues.isEmpty
        folders = r.folders.filter { $0.depth > 0 }.prefix(60).map { Folder(path: $0.path, bytes: $0.allocatedBytes, protection: $0.protection, partial: $0.partial) }
        largestFiles = r.entries.prefix(maxFiles).map { File(path: $0.path, bytes: $0.bytes ?? $0.allocatedBytes, category: $0.classification.category.rawValue, reason: $0.classification.reason) }
    }
}

struct AppsSummary: Encodable {
    struct Item: Encodable {
        let id: String; let title: String; let category: String; let bytes: Int64?; let reason: String; let regenerate: String; let action: String?
        init(_ i: DevItem) {
            id = i.shortID; title = i.title; category = i.category.rawValue; bytes = i.bytes; reason = i.reason; regenerate = i.regenerate; action = i.action?.command
        }
    }
    struct App: Encodable {
        let name: String; let bundleID: String?; let source: String; let totalBytes: Int64; let lastUsed: Date?; let protectedReason: String?
        let items: [Item]; let systemLeftovers: [String]
    }
    let apps: [App]
    let orphans: [Item]
    let next = "Para desinstalar, llama a propose_cleanup con el id de la app y los de los restos que el usuario elija. Los «Revisar antes de borrar» (datos, preferencias, contenedores, restos de apps borradas) solo si los confirma uno por uno. El usuario lo aplica con `margin apply`."

    init(_ r: AppsReport, limit: Int) {
        apps = r.apps.sorted { $0.totalBytes > $1.totalBytes }.prefix(max(limit, 1)).map {
            App(name: $0.name, bundleID: $0.bundleID, source: $0.source.rawValue, totalBytes: $0.totalBytes, lastUsed: $0.lastUsed,
                protectedReason: $0.protectedReason, items: $0.items.map(Item.init), systemLeftovers: $0.systemLeftovers)
        }
        orphans = r.orphans.map(Item.init)
    }
}

struct DevSummary: Encodable {
    struct Item: Encodable {
        let id: String; let profile: String; let title: String; let category: String
        let recoverable: Int64?; let reason: String; let regenerate: String; let action: String?; let condition: String?
    }
    struct Kept: Encodable { let title: String; let bytes: Int64?; let reason: String }
    let lowRiskBytes: Int64
    let reviewBytes: Int64
    let actionable: [Item]
    let kept: [Kept]
    let notes: [String]
    let next = "Para crear un plan, llama a propose_cleanup con los `id` elegidos. Confirma con el usuario los de categoría «Revisar antes de borrar»."

    init(_ r: DevReport) {
        lowRiskBytes = r.lowRiskBytes
        reviewBytes = r.reviewBytes
        let items = r.profiles.flatMap(\.items)
        actionable = items.filter(\.canDelete).sorted { ($0.recoverable ?? 0) > ($1.recoverable ?? 0) }.map {
            Item(id: $0.shortID, profile: $0.profile, title: $0.title, category: $0.category.rawValue, recoverable: $0.recoverable,
                 reason: $0.reason, regenerate: $0.regenerate, action: $0.action?.command, condition: $0.action?.note)
        }
        kept = items.filter { !$0.canDelete && ($0.bytes ?? 0) > 100_000_000 }.map { Kept(title: $0.title, bytes: $0.bytes, reason: $0.reason) }
        notes = r.profiles.flatMap { p in p.notes.map { "\(p.name): \($0)" } }
    }
}

struct PlanSummary: Encodable {
    struct Step: Encodable { let title: String; let category: String; let action: String; let recoverable: Int64? }
    let plan: String
    let recoverable: Int64
    let steps: [Step]
    let expires: Date
    let apply: String
    let important = "Este plan NO se ha ejecutado. Solo el usuario puede aplicarlo, escribiendo el código del plan en su terminal. No ejecutes `margin apply` tú mismo."

    init(_ p: Plan) {
        plan = p.id
        recoverable = p.recoverable
        steps = p.steps.map { Step(title: $0.title, category: $0.category.rawValue, action: $0.action.kind == .trash ? "Mover a la Papelera: \($0.action.paths.joined(separator: ", "))" : $0.action.command, recoverable: $0.recoverable) }
        expires = p.created.addingTimeInterval(Planner.maxAge)
        apply = "margin apply \(p.id)"
    }
}
