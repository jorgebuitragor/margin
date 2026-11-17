import Foundation
import Darwin

public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.withLock { cancelled = true } }
    public var isCancelled: Bool { lock.withLock { cancelled } }
}

public struct FileEntry: Identifiable, Codable, Sendable {
    public var id: String { path }
    public let path: String
    /// Tamaño lógico. Es nil en carpetas protegidas y enlaces: su contenido no se lista.
    public let bytes: Int64?
    /// Espacio asignado en disco. En carpetas protegidas es el total medido de todo su contenido.
    public let allocatedBytes: Int64?
    public let modified: Date?
    public let classification: Classification
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public init(path: String, bytes: Int64?, allocatedBytes: Int64?, modified: Date?, classification: Classification) {
        self.path = path
        self.bytes = bytes
        self.allocatedBytes = allocatedBytes
        self.modified = modified
        self.classification = classification
    }
}

/// Total de una carpeta, como lo calcularía `du`: espacio asignado, enlaces duros contados una vez,
/// sin seguir enlaces simbólicos ni cruzar a otros volúmenes.
public struct FolderTotal: Identifiable, Codable, Sendable {
    public var id: String { path }
    public let path: String
    /// Profundidad respecto a la raíz analizada (0 = la raíz).
    public let depth: Int
    public let allocatedBytes: Int64
    public let files: Int
    /// Hubo elementos ilegibles dentro: el total es un mínimo.
    public let partial: Bool
    /// `protected`, `sync` o nil. Una carpeta protegida se mide pero nunca es accionable.
    public let protection: String?
    public let reason: String?
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct ScanOptions: Sendable {
    /// Máximo de archivos individuales en `entries` (los más grandes). Los totales por carpeta no tienen límite.
    public var maxEntries: Int
    /// Profundidad máxima de las carpetas incluidas en `folders`.
    public var folderDepth: Int
    /// Tamaño mínimo para incluir una carpeta en `folders` (la raíz siempre se incluye).
    public var minFolderBytes: Int64
    public init(maxEntries: Int = 20_000, folderDepth: Int = 3, minFolderBytes: Int64 = 1_000_000) {
        self.maxEntries = maxEntries
        self.folderDepth = folderDepth
        self.minFolderBytes = minFolderBytes
    }
}

public struct ScanReport: Codable, Sendable {
    public let root: String
    public let date: Date
    public var entries: [FileEntry] = []
    public var folders: [FolderTotal] = []
    /// Espacio asignado de toda la raíz. Si `cancelled` o hay incidencias, es un mínimo.
    public var totalAllocated: Int64 = 0
    /// Proveedor de sincronización que cubre la raíz entera, si lo hay.
    public var syncedBy: String?
    public var issues: [String] = []
    public var visited = 0
    public var omitted = 0
    public var cancelled = false
    /// Había más archivos que `maxEntries`: `entries` solo contiene los más grandes. Los totales siguen completos.
    public var limited = false
}

public enum ScanError: LocalizedError {
    case invalidRoot, protectedRoot(String)
    public var errorDescription: String? {
        switch self {
        case .invalidRoot: return "Selecciona una carpeta local válida, sin enlaces ni alias."
        case .protectedRoot(let reason): return reason
        }
    }
}

public enum Scanner {
    public static func scan(root input: URL, cancellation: ScanCancellation = ScanCancellation(), limit: Int = 20_000, progress: @Sendable (Int) -> Void = { _ in }) throws -> ScanReport {
        try scan(root: input, options: ScanOptions(maxEntries: limit), cancellation: cancellation, progress: progress)
    }

    public static func scan(root input: URL, options: ScanOptions, cancellation: ScanCancellation = ScanCancellation(), progress: @Sendable (Int) -> Void = { _ in }) throws -> ScanReport {
        let root = input.standardizedFileURL
        guard root.path != "/" else { throw ScanError.protectedRoot("Elige una carpeta de usuario, no la raíz del sistema.") }
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .isPackageKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true, rootValues.isAliasFile != true else { throw ScanError.invalidRoot }
        if let reason = Classifier.protectedReason(root.resolvingSymlinksInPath(), isPackage: rootValues.isPackage == true) {
            throw ScanError.protectedRoot(reason)
        }
        var walker = Walker(rootPath: root.path, options: options)
        if let sync = SyncDetector.provider(forDirectoryOrAncestors: root) {
            walker.report.syncedBy = sync.provider
            walker.rootProtection = Protection(kind: "sync", classification: Classifier.synced(sync.provider))
        }
        try walker.run(cancellation: cancellation, progress: progress)
        return walker.report
    }
}

struct Protection {
    let kind: String
    let classification: Classification
}

/// Recorrido único con fts(3): suma por carpeta y conserva los archivos más grandes.
struct Walker {
    struct Frame {
        let path: String
        let depth: Int
        var allocated: Int64 = 0
        var files = 0
        var partial = false
        /// Protección heredada o propia; `startsHere` indica que esta carpeta es la que la origina.
        let protection: Protection?
        let startsHere: Bool
    }
    struct InodeKey: Hashable { let device: Int32; let inode: UInt64 }

    let rootPath: String
    let options: ScanOptions
    var report: ScanReport
    var rootProtection: Protection?
    private var stack: [Frame] = []
    private var seenInodes = Set<InodeKey>()
    private var candidates: [FileEntry] = []
    private var threshold: Int64 = .min

    init(rootPath: String, options: ScanOptions) {
        self.rootPath = rootPath
        self.options = options
        self.report = ScanReport(root: rootPath, date: Date())
    }

    mutating func run(cancellation: ScanCancellation, progress: (Int) -> Void) throws {
        guard let cPath = strdup(rootPath) else { throw ScanError.invalidRoot }
        defer { free(cPath) }
        var paths: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { throw ScanError.invalidRoot }
        defer { fts_close(fts) }

        while let entry = fts_read(fts) {
            if cancellation.isCancelled { report.cancelled = true; break }
            let info = Int32(entry.pointee.fts_info)
            let path = String(cString: entry.pointee.fts_path)
            let depth = Int(entry.pointee.fts_level)
            let st = entry.pointee.fts_statp?.pointee
            switch info {
            case FTS_D:
                visit(progress)
                enterDirectory(path: path, depth: depth, info: st)
            case FTS_DP:
                leaveDirectory(path: path, partial: false)
            case FTS_DNR, FTS_ERR:
                issue(path, errno: entry.pointee.fts_errno)
                if stack.last?.path == path {
                    report.omitted += 1
                    leaveDirectory(path: path, partial: true)
                } else {
                    markPartial()
                }
            case FTS_NS:
                visit(progress)
                issue(path, errno: entry.pointee.fts_errno)
                markPartial()
            case FTS_SL, FTS_SLNONE:
                visit(progress)
                addFile(path: path, info: st, isLink: true)
            case FTS_F, FTS_DEFAULT:
                visit(progress)
                addFile(path: path, info: st, isLink: false)
            default:
                break // FTS_DC (ciclo), FTS_DOT: no aportan tamaño.
            }
        }
        // Si se canceló, cerrar las carpetas abiertas para que los totales parciales queden registrados.
        while let open = stack.last { leaveDirectory(path: open.path, partial: true) }
        finishEntries()
        report.folders.sort { $0.allocatedBytes == $1.allocatedBytes ? $0.path < $1.path : $0.allocatedBytes > $1.allocatedBytes }
        progress(report.visited)
    }

    private mutating func visit(_ progress: (Int) -> Void) {
        report.visited += 1
        if report.visited % 100 == 0 { progress(report.visited) }
    }

    private mutating func enterDirectory(path: String, depth: Int, info: Darwin.stat?) {
        let ownBytes = info.map { Int64($0.st_blocks) * 512 } ?? 0
        if let parent = stack.last, let protection = parent.protection {
            stack.append(Frame(path: path, depth: depth, allocated: ownBytes, protection: protection, startsHere: false))
            return
        }
        if depth == 0 {
            stack.append(Frame(path: path, depth: depth, allocated: ownBytes, protection: rootProtection, startsHere: false))
            return
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var protection: Protection?
        if let reason = Classifier.protectedReason(url, isPackage: isPackage(url)) {
            protection = Protection(kind: "protected", classification: Classification(category: .protected, reason: reason, consequence: "Eliminarlo podría impedir funcionamiento o recuperación de datos.", rule: "protected"))
        } else if let provider = SyncDetector.provider(forDirectory: url) {
            protection = Protection(kind: "sync", classification: Classifier.synced(provider))
        }
        stack.append(Frame(path: path, depth: depth, allocated: ownBytes, protection: protection, startsHere: protection != nil))
    }

    private func isPackage(_ url: URL) -> Bool {
        // Consultar el sistema solo cuando hay extensión: los paquetes la tienen y así se evita una llamada por carpeta.
        guard !url.pathExtension.isEmpty else { return false }
        return (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
    }

    private mutating func leaveDirectory(path: String, partial: Bool) {
        guard var frame = stack.popLast() else { return }
        frame.partial = frame.partial || partial
        if !stack.isEmpty {
            stack[stack.count - 1].allocated += frame.allocated
            stack[stack.count - 1].files += frame.files
            if frame.partial { stack[stack.count - 1].partial = true }
        } else {
            report.totalAllocated = frame.allocated
        }
        if frame.depth == 0 || (frame.depth <= options.folderDepth && frame.allocated >= options.minFolderBytes) {
            report.folders.append(FolderTotal(path: frame.path, depth: frame.depth, allocatedBytes: frame.allocated, files: frame.files, partial: frame.partial, protection: frame.protection?.kind, reason: frame.protection?.classification.reason))
        }
        if frame.startsHere, let protection = frame.protection {
            report.omitted += 1
            consider(FileEntry(path: frame.path, bytes: nil, allocatedBytes: frame.allocated, modified: nil, classification: protection.classification), rank: frame.allocated)
        }
    }

    private mutating func addFile(path: String, info: Darwin.stat?, isLink: Bool) {
        guard let stat = info else { markPartial(); return }
        let allocated = Int64(stat.st_blocks) * 512
        // Para los totales, un inodo con varios enlaces duros cuenta una sola vez (como du).
        var counted = allocated
        if stat.st_nlink > 1 && !isLink {
            if !seenInodes.insert(InodeKey(device: stat.st_dev, inode: UInt64(stat.st_ino))).inserted { counted = 0 }
        }
        if !stack.isEmpty {
            stack[stack.count - 1].allocated += counted
            stack[stack.count - 1].files += 1
            if stack[stack.count - 1].protection != nil { return } // Se mide, pero no se lista.
        }
        let url = URL(fileURLWithPath: path)
        if isLink {
            report.omitted += 1
            consider(FileEntry(path: path, bytes: nil, allocatedBytes: nil, modified: nil, classification: Classifier.classify(url, isLink: true)), rank: -1)
            return
        }
        guard (stat.st_mode & S_IFMT) == S_IFREG else { report.omitted += 1; return }
        let size = Int64(stat.st_size)
        guard candidates.count < options.maxEntries * 2 || size > threshold else { report.limited = true; return }
        let classification = Classifier.classify(url)
        if classification.category == .protected {
            consider(FileEntry(path: path, bytes: nil, allocatedBytes: allocated, modified: nil, classification: classification), rank: size)
        } else {
            let modified = Date(timeIntervalSince1970: TimeInterval(stat.st_mtimespec.tv_sec))
            consider(FileEntry(path: path, bytes: size, allocatedBytes: allocated, modified: modified, classification: classification), rank: size)
        }
    }

    private mutating func consider(_ entry: FileEntry, rank: Int64) {
        guard candidates.count < options.maxEntries * 2 || rank > threshold else { report.limited = true; return }
        candidates.append(entry)
        if candidates.count >= max(2, options.maxEntries * 2) { trim() }
    }

    private static func rank(_ entry: FileEntry) -> Int64 { entry.bytes ?? entry.allocatedBytes ?? -1 }

    private mutating func trim() {
        candidates.sort { Self.ordered($0, $1) }
        let keep = max(1, options.maxEntries)
        if candidates.count > keep {
            report.limited = true
            candidates.removeLast(candidates.count - keep)
        }
        threshold = candidates.last.map(Self.rank) ?? .min
    }

    private static func ordered(_ a: FileEntry, _ b: FileEntry) -> Bool {
        let ra = rank(a), rb = rank(b)
        return ra == rb ? a.path < b.path : ra > rb
    }

    private mutating func finishEntries() {
        candidates.sort { Self.ordered($0, $1) }
        if candidates.count > options.maxEntries {
            report.limited = true
            candidates.removeLast(candidates.count - options.maxEntries)
        }
        report.entries = candidates
    }

    private mutating func markPartial() {
        report.omitted += 1
        if !stack.isEmpty { stack[stack.count - 1].partial = true }
    }

    private mutating func issue(_ path: String, errno code: Int32) {
        guard report.issues.count < 100 else { return }
        let name = URL(fileURLWithPath: path).lastPathComponent
        report.issues.append("\(name): \(String(cString: strerror(code)))")
    }
}
