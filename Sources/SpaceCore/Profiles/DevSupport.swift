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
        env["PATH"] = (env["PATH"].map { $0 + ":" } ?? "") + "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let box = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        do { try process.run() } catch { return nil }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            return nil
        }
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: String(decoding: box.data, as: UTF8.self))
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
        var dirs = extra + toolDirectories
        let nvm = path(".nvm/versions/node")
        dirs += children(nvm).sorted { Self.versionLess($1, $0) }.map { "\(nvm)/\($0)/bin" }
        return dirs.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Ruta del ejecutable para una acción: las herramientas de Android viven en el SDK y xcrun en /usr/bin.
    public func executable(for name: String) -> String? {
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
        guard let pgrep = tool("pgrep", extra: ["/usr/bin"]) else { return false }
        return runner.run(pgrep, ["-f", check.pattern], timeout: 10)?.status == 0
    }

    /// Ruta real (sin enlaces ni el atajo /tmp → /private/tmp), la misma forma que exige la revalidación.
    public static func canonical(_ path: String) -> String {
        guard let real = realpath(path, nil) else { return URL(fileURLWithPath: path).standardizedFileURL.path }
        defer { free(real) }
        return String(cString: real)
    }

    public var supportDirectory: String { path("Library/Application Support/GestorEspacio") }

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
