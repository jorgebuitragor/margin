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
            print("  \(pad(size(item.recoverable ?? item.bytes), 10))  [\(tag)] \(item.title)\(item.canDelete ? "  · id \(item.shortID)" : "")")
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

func baseEnvironment() -> DevEnvironment {
    // MARGEN_HOME permite probar de punta a punta sobre una carpeta personal sintética.
    if let home = DevEnvironment.testSetting("HOME") { return DevEnvironment(home: URL(fileURLWithPath: home)) }
    return DevEnvironment()
}

func roots(_ args: inout [String], _ env: inout DevEnvironment) {
    if let days = intValue(&args, "--inactive-days") { env.inactiveDays = days }
    if let index = args.firstIndex(of: "--roots") {
        guard index + 1 < args.count else { fail("--roots necesita rutas separadas por comas.") }
        env.projectRoots = args[index + 1].split(separator: ",").map { URL(fileURLWithPath: NSString(string: String($0)).expandingTildeInPath).standardizedFileURL }
        args.removeSubrange(index...index + 1)
    }
}

func printPlan(_ plan: Plan, previews: [String: String] = [:]) {
    print("Plan \(plan.id) · \(plan.steps.count) pasos · recuperable estimado \(size(plan.recoverable))")
    for step in plan.steps {
        let tag = step.category == .lowRisk ? "BAJO RIESGO" : "REVISAR"
        print("\n• [\(tag)] \(step.title)  (\(size(step.recoverable)))")
        print("  Por qué: \(step.reason)")
        print("  Si se retira: \(step.regenerate)")
        if step.action.kind == .trash {
            print("  Acción: mover a la Papelera \(step.action.paths.count == 1 ? step.action.paths[0] : "\(step.action.paths.count) rutas")")
        } else {
            print("  Acción: \(step.action.command)")
        }
        if let note = step.action.note { print("  Condición: \(note)") }
        if let preview = previews[step.id], !preview.isEmpty {
            print("  Vista previa:")
            print(preview.split(separator: "\n").prefix(15).map { "    " + $0 }.joined(separator: "\n"))
        }
    }
}

/// Pide escribir una palabra exacta (sin distinguir mayúsculas). La explicación va aparte y la última línea solo
/// muestra lo que hay que escribir, para que no se confunda con el aviso. Si no coincide, dice qué se esperaba.
func confirm(word: String, action: String) -> Bool {
    print("\nPara \(action), escribe \(word) y pulsa Intro. Cualquier otra cosa cancela.")
    print("Escribe \(word): ", terminator: "")
    fflush(stdout)
    let typed = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
    if typed.caseInsensitiveCompare(word) == .orderedSame { return true }
    print(typed.isEmpty ? "Cancelado. No se ha tocado nada." : "Cancelado: se esperaba «\(word)» y se escribió «\(typed)». No se ha tocado nada.")
    return false
}

func readConfirmation(_ code: String) -> Bool {
    confirm(word: code, action: "ejecutar el plan")
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
    case "disco":
        // Desglose del volumen por categorías (lo mismo que la barra de la app). Mide y guarda la caché.
        let env = baseEnvironment()
        guard let breakdown = StorageAnalyzer.measure(env) else { fail("No se pudo leer la capacidad del volumen.") }
        StorageAnalyzer.save(breakdown, env)
        if args.contains("--text") {
            let names: [StorageSegment.Kind: String] = [.apps: "Apps", .personal: "Documentos y archivos", .appData: "Datos de apps y cachés", .development: "Desarrollo", .macOS: "macOS", .trash: "Papelera", .purgeable: "Purgable por macOS", .system: "Otros"]
            print("Disco: \(size(breakdown.total)) · usado \(size(breakdown.used)) · disponible \(size(breakdown.available))")
            for segment in breakdown.segments {
                let pct = Double(segment.bytes) / Double(max(breakdown.total, 1)) * 100
                print("  \((names[segment.kind] ?? segment.kind.rawValue).padding(toLength: 24, withPad: " ", startingAt: 0)) \(size(segment.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(String(format: "%5.1f", pct)) %\(segment.partial ? "  (mínimo: hubo elementos ilegibles)" : "")")
            }
        } else {
            try output(breakdown)
        }
    case "scan":
        args.removeFirst()
        var options = ScanOptions()
        if let depth = intValue(&args, "--depth") { options.folderDepth = depth }
        if let mb = intValue(&args, "--min-mb") { options.minFolderBytes = Int64(mb) * 1_000_000 }
        if let max = intValue(&args, "--max-files") { options.maxEntries = max }
        let text = args.contains("--text")
        args.removeAll { $0 == "--text" }
        guard args.count == 1 else { fail("Uso: margen scan /ruta [--depth N] [--min-mb N] [--max-files N] [--text]") }
        let report = try Scanner.scan(root: URL(fileURLWithPath: args[0]), options: options)
        if text { printText(report, folders: 25, files: 15) } else { try output(report) }
    case "dev":
        args.removeFirst()
        var env = baseEnvironment()
        roots(&args, &env)
        let text = args.contains("--text")
        args.removeAll { $0 == "--text" }
        guard args.isEmpty else { fail("Uso: margen dev [--text] [--inactive-days N] [--roots ruta1,ruta2]") }
        let report = DevProfiles.report(env)
        if text { printDev(report) } else { try output(report) }
    case "plan":
        args.removeFirst()
        var env = baseEnvironment()
        roots(&args, &env)
        var files: [String] = []
        while let index = args.firstIndex(of: "--file") {
            guard index + 1 < args.count else { fail("--file necesita una ruta.") }
            files.append(DevEnvironment.canonical(NSString(string: args[index + 1]).expandingTildeInPath))
            args.removeSubrange(index...index + 1)
        }
        guard !args.isEmpty || !files.isEmpty else { fail("Uso: margen plan <id> [<id>…] [--file /ruta]… — los id salen en `margen dev --text`.") }
        var items: [DevItem] = []
        if !args.isEmpty {
            print("Analizando perfiles para resolver los id…")
            let all = DevProfiles.report(env).profiles.flatMap(\.items)
            for id in args {
                guard let item = all.first(where: { $0.shortID == id }) else { fail("No se encontró el id \(id) en el análisis actual.") }
                items.append(item)
            }
        }
        var entries: [FileEntry] = []
        for path in files {
            let url = URL(fileURLWithPath: path)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { fail("Solo se aceptan archivos normales: \(path)") }
            if let sync = SyncDetector.provider(forDirectoryOrAncestors: url.deletingLastPathComponent()) { fail("\(path) está sincronizado con \(sync.provider); no se ofrece para limpieza.") }
            entries.append(FileEntry(path: path, bytes: values.fileSize.map(Int64.init), allocatedBytes: values.totalFileAllocatedSize.map(Int64.init), modified: nil, classification: Classifier.classify(url)))
        }
        let plan = try Planner.plan(devItems: items, files: entries, env: env)
        try PlanStore.save(plan, env)
        printPlan(plan)
        print("\nNo se ha ejecutado nada. Para aplicarlo (pedirá confirmación): margen apply \(plan.id)")
    case "vaciar-papelera":
        // Única acción de borrado definitivo: terminal interactiva y escribir VACIAR.
        if isatty(STDIN_FILENO) == 0 && DevEnvironment.testSetting("HOME") == nil {
            fail("margen vaciar-papelera necesita una terminal interactiva.")
        }
        let env = baseEnvironment()
        let trash = TrashStatus.read(env)
        if let bytes = trash.bytes, let items = trash.items {
            print("La Papelera tiene \(items) \(items == 1 ? "elemento" : "elementos") (\(size(bytes))).")
        } else {
            print("macOS no deja leer la Papelera sin «Acceso total al disco»: no se puede mostrar su tamaño (para vaciarla no hace falta).")
        }
        print("⚠️  Vaciar la Papelera elimina para siempre lo que contiene. No se puede deshacer.")
        guard confirm(word: "VACIAR", action: "vaciarla") else { exit(0) }
        let result = TrashEmptier.empty(env: env)
        print("\(result.status == .done ? "✓" : "✗") \(result.message)")
        if result.status == .blocked { exit(1) }
        if result.status != .done, let output = result.output { print(output) }
        print("Espacio disponible: antes \(size(result.availableBefore)), después \(size(result.availableAfter))\(result.freedObserved.map { " (\($0 >= 0 ? "+" : "")\(formatBytes($0)))" } ?? "").")
    case "mcp":
        // Servidor MCP por stdio. Nada se escribe en stdout salvo respuestas JSON-RPC.
        let server = MCPServer(env: baseEnvironment())
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let response = server.handle(line) {
                FileHandle.standardOutput.write(Data((response + "\n").utf8))
            }
        }
    case "apply":
        args.removeFirst()
        guard args.count == 1 else { fail("Uso: margen apply <plan>") }
        // La confirmación es del usuario: se exige una terminal interactiva para que un proceso (o un agente)
        // no pueda aplicar un plan enviando el código por una tubería. MARGEN_HOME (modo de prueba) lo permite.
        if isatty(STDIN_FILENO) == 0 && DevEnvironment.testSetting("HOME") == nil {
            fail("margen apply necesita una terminal interactiva: ejecútalo tú y escribe el código del plan.")
        }
        let base = baseEnvironment()
        let plan = try PlanStore.load(args[0], base)
        if PlanStore.isApplied(plan.id, base) { throw PlanError.alreadyApplied }
        let env = plan.environment(from: base)
        print("Revalidando cada paso con el estado actual…")
        var fresh: [String: ProfileResult] = [:]
        let blocked = plan.steps.compactMap { step in Planner.blocker(step, plan: plan, env: env, freshProfiles: &fresh).map { (step.title, $0) } }
        printPlan(plan, previews: Planner.previews(plan, env: env))
        if !blocked.isEmpty {
            print("\nBloqueados ahora (no se tocarán):")
            for (title, reason) in blocked { print("  ✗ \(title): \(reason)") }
            if blocked.count == plan.steps.count { fail("\nNingún paso se puede ejecutar.") }
        }
        print("\nLo que vaya a la Papelera se puede recuperar desde Finder hasta que la vacíes. Los comandos de las herramientas no se pueden deshacer.")
        guard readConfirmation(plan.id) else { exit(0) }
        let report = try Planner.apply(plan, env: env) { result in
            let mark = result.status == .done ? "✓" : result.status == .blocked ? "✗" : "!"
            print("\(mark) \(result.title): \(result.message)")
            for (path, error) in result.failures.sorted(by: { $0.key < $1.key }) { print("    \(path): \(error)") }
            if result.status == .failed, let output = result.output, !output.isEmpty { print(output.split(separator: "\n").suffix(8).map { "    " + $0 }.joined(separator: "\n")) }
        }
        print("\nEspacio disponible: antes \(size(report.availableBefore)), después \(size(report.availableAfter))\(report.freedObserved.map { " (\($0 >= 0 ? "+" : "")\(formatBytes($0)))" } ?? "").")
        if report.usedTrash { print("Lo movido a la Papelera no libera espacio hasta que la vacíes. macOS también puede tardar en reflejarlo (instantáneas locales de Time Machine).") }
        print("Registro: \(env.supportDirectory)/acciones.jsonl")
    case "help", "--help", nil:
        print("""
        margen status         Diagnóstico de RAM y volumen en JSON.
        margen disco          Desglose del disco por categorías (apps, documentos, desarrollo…). --text: legible.
        margen scan /ruta     Totales por carpeta y archivos más grandes en JSON; solo lectura.
            --depth N         Profundidad de carpetas en el informe (por defecto 3).
            --min-mb N        Omite carpetas menores de N MB (por defecto 1).
            --max-files N     Archivos individuales a listar, los más grandes (por defecto 20000).
            --text            Resumen legible en lugar de JSON.
        margen dev            Perfiles de desarrollo: cachés y artefactos regenerables con su comando oficial.
            --inactive-days N Días sin cambios para considerar inactivo un proyecto (por defecto 30).
            --roots a,b       Carpetas de proyectos (por defecto ~/Developer, ~/git, ~/projects…).
            --text            Resumen legible en lugar de JSON.
        margen plan <id>… [--file /ruta]…
                              Crea un plan con elementos de `dev` (id) o archivos revisables. No ejecuta nada.
        margen apply <plan>   Revalida, muestra vista previa y, si escribes el código del plan, ejecuta:
                              mueve a la Papelera o lanza el comando oficial de la herramienta.
        margen vaciar-papelera
                              Vacía la Papelera (a través de Finder) tras escribir VACIAR. Es la única acción
                              de borrado definitivo y no la puede lanzar ningún agente.
        margen mcp            Servidor MCP por stdio para agentes (Claude Code, Codex): mide y crea planes,
                              nunca los aplica.
        El borrado definitivo solo existe en vaciar-papelera. scan, dev, plan y mcp solo miden y proponen.
        Los totales siguen la lógica de du: espacio asignado, enlaces duros una vez, sin seguir enlaces.
        Carpetas protegidas y sincronizadas se miden, pero sus archivos no se listan ni son accionables.
        Los informes incluyen rutas: comparte solo los datos que necesites.
        """)
    default:
        fail("Comando inválido. Usa margen --help.")
    }
} catch {
    fail(error.localizedDescription)
}
