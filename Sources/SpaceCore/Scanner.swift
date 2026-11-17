import Foundation

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
    public let bytes: Int64?
    public let allocatedBytes: Int64?
    public let modified: Date?
    public let classification: Classification
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct ScanReport: Codable, Sendable {
    public let root: String
    public let date: Date
    public var entries: [FileEntry] = []
    public var issues: [String] = []
    public var visited = 0
    public var omitted = 0
    public var cancelled = false
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
        let fm = FileManager.default
        let root = input.standardizedFileURL
        guard root.path != "/" else { throw ScanError.protectedRoot("Elige una carpeta de usuario, no la raíz del sistema.") }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey, .isPackageKey, .isUbiquitousItemKey, .fileSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
        let rootValues = try root.resourceValues(forKeys: keys)
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true, rootValues.isAliasFile != true else { throw ScanError.invalidRoot }
        if let reason = Classifier.protectedReason(root.resolvingSymlinksInPath(), isPackage: rootValues.isPackage == true) {
            throw ScanError.protectedRoot(reason)
        }
        if rootValues.isUbiquitousItem == true { throw ScanError.protectedRoot("Carpeta de iCloud: utiliza Finder para gestionar su almacenamiento.") }
        let canonicalRoot = root.resolvingSymlinksInPath().path
        var report = ScanReport(root: root.path, date: Date())
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants], errorHandler: { url, error in
            if report.issues.count < 100 { report.issues.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            report.omitted += 1
            return !cancellation.isCancelled
        }) else { throw ScanError.invalidRoot }
        while true {
            if cancellation.isCancelled { report.cancelled = true; break }
            if report.visited >= max(1, limit) { report.limited = true; break }
            guard let url = enumerator.nextObject() as? URL else { break }
            report.visited += 1
            if report.visited % 100 == 0 { progress(report.visited) }
            do {
                let v = try url.resourceValues(forKeys: keys)
                let link = v.isSymbolicLink == true || v.isAliasFile == true
                let resolved = url.resolvingSymlinksInPath().path
                guard !link && (resolved.hasPrefix(canonicalRoot + "/")) else {
                    enumerator.skipDescendants()
                    report.omitted += 1
                    report.entries.append(FileEntry(path: url.path, bytes: nil, allocatedBytes: nil, modified: nil, classification: Classifier.classify(url, isLink: true)))
                    continue
                }
                let classification = Classifier.classify(url, isPackage: v.isPackage == true, isCloud: v.isUbiquitousItem == true)
                if classification.category == .protected {
                    enumerator.skipDescendants()
                    report.omitted += 1
                    report.entries.append(FileEntry(path: url.path, bytes: nil, allocatedBytes: nil, modified: nil, classification: classification))
                    continue
                }
                if v.isDirectory == true { continue }
                guard v.isRegularFile == true else { report.omitted += 1; continue }
                report.entries.append(FileEntry(path: url.path, bytes: v.fileSize.map(Int64.init), allocatedBytes: v.fileAllocatedSize.map(Int64.init), modified: v.contentModificationDate, classification: classification))
            } catch {
                report.omitted += 1
                if report.issues.count < 100 { report.issues.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        report.entries.sort { ($0.bytes ?? -1) == ($1.bytes ?? -1) ? $0.path < $1.path : ($0.bytes ?? -1) > ($1.bytes ?? -1) }
        progress(report.visited)
        return report
    }
}
