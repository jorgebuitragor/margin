import Foundation
import Darwin

/// Medición de una ruta con la lógica de du -x. Solo metadatos.
public struct Usage: Sendable, Equatable {
    public var allocated: Int64 = 0
    /// Bytes de archivos sin otros enlaces duros (más carpetas): lo que se libera con seguridad al retirar la ruta.
    public var exclusive: Int64 = 0
    public var files = 0
    public var partial = false
    /// Fecha de modificación más reciente encontrada (archivos y carpetas).
    public var newest: Date?
}

public enum DiskUsage {
    public static func measure(_ path: String) -> Usage {
        var usage = Usage()
        var seen = Set<[UInt64]>()
        guard let cPath = strdup(path) else { usage.partial = true; return usage }
        defer { free(cPath) }
        var paths: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { usage.partial = true; return usage }
        defer { fts_close(fts) }
        var newest: Int = 0
        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            if info == FTS_DP || info == FTS_DOT || info == FTS_DC { continue }
            if info == FTS_DNR || info == FTS_ERR || info == FTS_NS { usage.partial = true; continue }
            guard let st = entry.pointee.fts_statp?.pointee else { continue }
            newest = max(newest, st.st_mtimespec.tv_sec)
            let blocks = Int64(st.st_blocks) * 512
            if info == FTS_D {
                usage.allocated += blocks
                usage.exclusive += blocks
                continue
            }
            usage.files += 1
            if st.st_nlink > 1 && info != FTS_SL && info != FTS_SLNONE {
                if seen.insert([UInt64(bitPattern: Int64(st.st_dev)), UInt64(st.st_ino)]).inserted { usage.allocated += blocks }
            } else {
                usage.allocated += blocks
                usage.exclusive += blocks
            }
        }
        if newest > 0 { usage.newest = Date(timeIntervalSince1970: TimeInterval(newest)) }
        return usage
    }
}

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
    /// Salida de error, separada para no romper las consultas que leen JSON de la salida estándar.
    public var error: String = ""
    public init(status: Int32, output: String, error: String = "") {
        self.status = status
        self.output = output
        self.error = error
    }
}

/// Ejecuta consultas de solo lectura de las herramientas (simctl list, docker system df, git log…).
/// Nunca se usa para comandos que modifican datos.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult?
}

public struct ProcessRunner: CommandRunner {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        // La carpeta del ejecutable va primero: una herramienta de nvm (pnpm, yarn…) debe usar el node de su misma
        // versión, no el que tenga la terminal. Así pnpm de Node 24 no se ejecuta con Node 20.
        let ownDir = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        env["PATH"] = ownDir + ":" + (env["PATH"].map { $0 + ":" } ?? "") + "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        process.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice
        let out = DataBox(), err = DataBox()
        let group = DispatchGroup()
        for (pipe, box) in [(outPipe, out), (errPipe, err)] {
            group.enter()
            DispatchQueue.global().async {
                box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }
        do { try process.run() } catch { return nil }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            return nil
        }
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: String(decoding: out.data, as: UTF8.self), error: String(decoding: err.data, as: UTF8.self))
    }
}

private final class DataBox: @unchecked Sendable { var data = Data() }

/// Todo lo que los perfiles necesitan del entorno, inyectable para pruebas.
public struct DevEnvironment: Sendable {
    public var home: URL
    public var projectRoots: [URL]
    public var inactiveDays: Int
    public var now: Date
    public var runner: CommandRunner
    /// Rutas donde buscar ejecutables, además de las conocidas por perfil.
    public var toolDirectories: [String]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, projectRoots: [URL]? = nil, inactiveDays: Int = 30, now: Date = Date(), runner: CommandRunner = ProcessRunner(), toolDirectories: [String]? = nil) {
        self.home = home
        self.projectRoots = projectRoots ?? ["Developer", "git", "projects", "AndroidStudioProjects", "NetBeansProjects", "Projects", "src"].map { home.appendingPathComponent($0) }
        self.inactiveDays = inactiveDays
        self.now = now
        self.runner = runner
        self.toolDirectories = toolDirectories ?? ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", home.appendingPathComponent(".local/bin").path, home.appendingPathComponent(".cargo/bin").path]
    }

    public func path(_ relative: String) -> String { home.appendingPathComponent(relative).path }

    public func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    public func isDirectory(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }

    public func children(_ path: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    public func read(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path), data.count < 2_000_000 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Busca un ejecutable en las rutas conocidas. Las de nvm se revisan de la versión más nueva a la más antigua.
    public func tool(_ name: String, extra: [String] = []) -> String? {
        tools(name, extra: extra).first
    }

    /// Todas las copias instaladas de una herramienta (por ejemplo, un pnpm por cada versión de Node en nvm),
    /// sin duplicados por enlace.
    public func tools(_ name: String, extra: [String] = []) -> [String] {
        var dirs = extra + toolDirectories
        let nvm = path(".nvm/versions/node")
        dirs += children(nvm).sorted { Self.versionLess($1, $0) }.map { "\(nvm)/\($0)/bin" }
        var seen = Set<String>()
        return dirs.map { "\($0)/\(name)" }
            .filter { FileManager.default.isExecutableFile(atPath: $0) && seen.insert(Self.canonical($0)).inserted }
    }

    /// Ruta del ejecutable para una acción: las herramientas de Android viven en el SDK y xcrun en /usr/bin.
    public func executable(for name: String) -> String? {
        // Ruta absoluta: la fija el perfil (por ejemplo, el pnpm concreto que usa un store) y la revalidación
        // comprueba que el perfil recalculado propone exactamente la misma.
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        switch name {
        case "sdkmanager", "avdmanager":
            let path = self.path("Library/Android/sdk/cmdline-tools/latest/bin/\(name)")
            return FileManager.default.isExecutableFile(atPath: path) ? path : tool(name)
        case "xcrun": return tool("xcrun", extra: ["/usr/bin"])
        default: return tool(name)
        }
    }

    /// Hay un proceso cuya línea de comandos contiene el patrón (consulta de solo lectura con pgrep).
    public func isRunning(_ check: ProcessCheck) -> Bool {
        if let bundle = check.bundleID, let lsappinfo = tool("lsappinfo", extra: ["/usr/bin"]) {
            let out = runner.run(lsappinfo, ["find", "bundleid=\(bundle)"], timeout: 10)
            return out?.status == 0 && !(out?.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        guard let pgrep = tool("pgrep", extra: ["/usr/bin"]) else { return false }
        return runner.run(pgrep, ["-f", check.pattern], timeout: 10)?.status == 0
    }

    /// Ruta real (sin enlaces ni el atajo /tmp → /private/tmp), la misma forma que exige la revalidación.
    public static func canonical(_ path: String) -> String {
        guard let real = realpath(path, nil) else { return URL(fileURLWithPath: path).standardizedFileURL.path }
        defer { free(real) }
        return String(cString: real)
    }

    /// Carpeta de datos (planes, registro, caché). La app se llamó «Gestor Espacio» hasta la 0.6 y «Margen» durante
    /// la 0.7: si solo existe una carpeta antigua, se renombra para conservar planes y registro.
    public var supportDirectory: String {
        let current = path("Library/Application Support/Margin")
        let fm = FileManager.default
        if !fm.fileExists(atPath: current),
           let legacy = ["Margen", "GestorEspacio"].map({ path("Library/Application Support/\($0)") }).first(where: { fm.fileExists(atPath: $0) }) {
            try? fm.moveItem(atPath: legacy, toPath: current)
        }
        return current
    }

    /// Variable de prueba `MARGIN_<nombre>` (o las antiguas `MARGEN_<nombre>` y `ESPACIO_<nombre>`).
    public static func testSetting(_ name: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        return env["MARGIN_\(name)"] ?? env["MARGEN_\(name)"] ?? env["ESPACIO_\(name)"]
    }

    /// Entorno real, o una carpeta personal sintética con MARGIN_HOME para probar de punta a punta.
    public static func fromProcess(projectRoots: [URL]? = nil, inactiveDays: Int = 30) -> DevEnvironment {
        if let home = testSetting("HOME") { return DevEnvironment(home: URL(fileURLWithPath: home), projectRoots: projectRoots, inactiveDays: inactiveDays) }
        return DevEnvironment(projectRoots: projectRoots, inactiveDays: inactiveDays)
    }

    func days(since date: Date?) -> Int? {
        date.map { Int(now.timeIntervalSince($0) / 86_400) }
    }

    /// Compara versiones tipo «v20.11.0», «8.14.1», «25.1.8937393».
    public static func versionLess(_ a: String, _ b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y }
        }
        return a < b
    }
}

extension DevItem {
    /// Crea un elemento midiendo su ruta.
    static func measured(_ profile: String, _ title: String, path: String, category: Category, reason: String, regenerate: String, action: DevAction?, lastUsed: Date? = nil, usage: Usage? = nil) -> DevItem {
        let u = usage ?? DiskUsage.measure(path)
        let partialNote = u.partial ? " Hubo elementos ilegibles: el tamaño es un mínimo." : ""
        return DevItem(profile: profile, title: title, path: path, bytes: u.allocated, recoverable: u.exclusive, category: category, reason: reason + partialNote, regenerate: regenerate, action: action, lastUsed: lastUsed ?? u.newest)
    }
}
