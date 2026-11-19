import XCTest
@testable import SpaceCore

final class SpaceCoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        // Fixtures locales fuera de Documentos, que puede estar sincronizado con iCloud.
        root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func file(_ path: String, _ count: Int) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: count).write(to: url)
        return url
    }
    func testSizesSortingAndReadOnly() throws {
        let small = try file("pequeño.txt", 12)
        let large = try file("vídeo.mp4", 4096)
        let before = try Data(contentsOf: large)
        let date = try large.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let report = try Scanner.scan(root: root)
        XCTAssertEqual(report.entries.map(\.bytes), [4096, 12])
        XCTAssertEqual(report.entries.first?.classification.category, .review)
        XCTAssertEqual(try Data(contentsOf: large), before)
        XCTAssertEqual(try large.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date)
        XCTAssertTrue(FileManager.default.fileExists(atPath: small.path))
        XCTAssertTrue(report.issues.isEmpty)
    }
    func testProtectionAndNoTraversal() throws {
        _ = try file("Library/Application Support/private.pdf", 20)
        _ = try file("Photos.photoslibrary/original.jpg", 20)
        _ = try file(".ssh/id_rsa", 20)
        let report = try Scanner.scan(root: root)
        XCTAssertEqual(report.entries.count, 3)
        XCTAssertTrue(report.entries.allSatisfy { $0.classification.category == .protected && $0.bytes == nil })
        // Las carpetas protegidas se miden aunque no se listen sus archivos.
        XCTAssertTrue(report.entries.allSatisfy { ($0.allocatedBytes ?? 0) > 0 })
        XCTAssertFalse(report.entries.contains { $0.name == "private.pdf" || $0.name == "original.jpg" || $0.name == "id_rsa" })
        // La Biblioteca no se rechaza: se mide por dentro, sin listar archivos ni proponer nada.
        let library = try Scanner.scan(root: root.appendingPathComponent("Library"))
        XCTAssertNotNil(library.measureOnly)
        XCTAssertTrue(library.entries.isEmpty, "Dentro de una carpeta protegida no se lista ningún archivo")
        XCTAssertTrue(library.folders.contains { $0.depth == 0 && $0.protection == "protected" }, "La raíz se mide como protegida")
        XCTAssertGreaterThan(library.totalAllocated, 0)
    }
    func testClonesAreMeasuredOnceAndNotCountedAsFreeable() throws {
        // Tres clones APFS de los mismos 2 MB: cada uno informa 2 MB, pero los datos están una vez en el disco y borrar
        // uno no libera nada propio.
        let original = try file("Videos/original.mov", 2_000_000)
        let folder = original.deletingLastPathComponent()
        for name in ["reenviado.mov", "migrado.mov"] {
            XCTAssertEqual(copyfile(original.path, folder.appendingPathComponent(name).path, nil, copyfile_flags_t(COPYFILE_CLONE_FORCE)), 0, "El disco de pruebas debe ser APFS")
        }
        let info = try XCTUnwrap(original.path.withCString { DiskUsage.cloneInfo($0) })
        XCTAssertNotNil(info.familyKey, "Las copias idénticas forman una familia")
        XCTAssertEqual(info.familySize, 3)
        let usage = DiskUsage.measure(folder.path)
        XCTAssertGreaterThanOrEqual(usage.allocated, 1_900_000)
        XCTAssertLessThan(usage.allocated, 3_000_000, "Los datos de la familia cuentan una sola vez")
        XCTAssertLessThan(usage.exclusive, 1_000_000, "Lo compartido entre clones no cuenta como liberable")
        let report = try Scanner.scan(root: root)
        XCTAssertGreaterThanOrEqual(report.totalAllocated, 1_900_000)
        XCTAssertLessThan(report.totalAllocated, 3_000_000, "El total de la carpeta tampoco cuenta cada copia")
        XCTAssertLessThan(try XCTUnwrap(report.totalFreeable), 1_000_000)
        // Una copia que se modifica deja la familia: sus datos nuevos ya son suyos.
        let edited = folder.appendingPathComponent("migrado.mov")
        let handle = try FileHandle(forWritingTo: edited)
        try handle.write(contentsOf: Data(repeating: 7, count: 1_000_000))
        try handle.close()
        let afterEdit = DiskUsage.measure(folder.path)
        XCTAssertGreaterThanOrEqual(afterEdit.exclusive, 900_000, "Lo reescrito es privado de esa copia")
        // Sin clones, lo liberable coincide con lo asignado.
        for name in ["reenviado.mov", "migrado.mov"] { try FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
        let alone = DiskUsage.measure(folder.path)
        XCTAssertGreaterThanOrEqual(alone.exclusive, 1_900_000)
        XCTAssertEqual(alone.exclusive, alone.allocated)
    }

    func testLinksAreNotFollowed() throws {
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data([1, 2, 3]).write(to: outside.appendingPathComponent("secret.txt"))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let report = try Scanner.scan(root: root)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(report.entries.first?.classification.category, .unknown)
        XCTAssertThrowsError(try Scanner.scan(root: link))
    }
    func testMisleadingCacheAndCredentials() throws {
        let cache = Classifier.classify(root.appendingPathComponent("cache.tmp"))
        XCTAssertEqual(cache.category, .unknown)
        XCTAssertFalse(cache.canDelete)
        let credential = Classifier.classify(root.appendingPathComponent(".env.production"))
        XCTAssertEqual(credential.category, .protected)
        let cloud = Classifier.classify(root.appendingPathComponent("foto.jpg"), isCloud: true)
        XCTAssertEqual(cloud.category, .protected)
        XCTAssertFalse(cloud.canDelete)
        for entry in [cache, credential, cloud] {
            XCTAssertFalse(entry.reason.isEmpty)
            XCTAssertFalse(entry.consequence.isEmpty)
        }
    }
    func testCancellationAndLimit() throws {
        for i in 0..<10 { _ = try file("\(i).txt", 10) }
        let token = ScanCancellation()
        token.cancel()
        let cancelled = try Scanner.scan(root: root, cancellation: token)
        XCTAssertTrue(cancelled.cancelled)
        XCTAssertTrue(cancelled.entries.isEmpty)
        let limited = try Scanner.scan(root: root, limit: 3)
        XCTAssertTrue(limited.limited)
        XCTAssertEqual(limited.entries.count, 3)
    }
    func testCancellationDuringScanAndFreshRun() throws {
        for i in 0..<140 { _ = try file("item-\(i).txt", 1) }
        let token = ScanCancellation()
        let partial = try Scanner.scan(root: root, cancellation: token) { count in
            if count >= 100 { token.cancel() }
        }
        XCTAssertTrue(partial.cancelled)
        XCTAssertLessThan(partial.entries.count, 140)
        let complete = try Scanner.scan(root: root)
        XCTAssertFalse(complete.cancelled)
        XCTAssertEqual(complete.entries.count, 140)
    }
    func testUnreadableDirectoryReportsIssue() throws {
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let report = try Scanner.scan(root: root)
        XCTAssertFalse(report.issues.isEmpty)
        XCTAssertGreaterThan(report.omitted, 0)
    }
    func testEmptyAndInvalidRoots() throws {
        XCTAssertTrue(try Scanner.scan(root: root).entries.isEmpty)
        let regular = try file("not-folder.txt", 1)
        XCTAssertThrowsError(try Scanner.scan(root: regular))
        XCTAssertThrowsError(try Scanner.scan(root: root.appendingPathComponent("missing")))
    }
    func testJSONContract() throws {
        _ = try file("installer.dmg", 50)
        let report = try Scanner.scan(root: root)
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(ScanReport.self, from: data)
        XCTAssertEqual(decoded.entries.first?.classification.rule, "archive")
        XCTAssertEqual(decoded.entries.first?.bytes, 50)
    }

    func testFolderTotalsMatchContents() throws {
        _ = try file("a/uno.bin", 10_000)
        _ = try file("a/b/dos.bin", 20_000)
        _ = try file("c/tres.bin", 5_000)
        let report = try Scanner.scan(root: root, options: ScanOptions(minFolderBytes: 0))
        // Foundation normaliza /private/tmp como /tmp: se compara por sufijo.
        func folder(_ suffix: String) throws -> FolderTotal { try XCTUnwrap(report.folders.first { $0.path.hasSuffix(suffix) }) }
        let a = try folder("/a"), b = try folder("/a/b"), c = try folder("/c")
        XCTAssertEqual(a.files, 2)
        XCTAssertGreaterThanOrEqual(a.allocatedBytes, b.allocatedBytes + 10_000)
        XCTAssertGreaterThanOrEqual(b.allocatedBytes, 20_000)
        XCTAssertEqual(report.folders.first?.depth, 0, "La raíz es la carpeta más grande")
        XCTAssertEqual(report.totalAllocated, report.folders.first?.allocatedBytes)
        XCTAssertGreaterThanOrEqual(report.totalAllocated, a.allocatedBytes + c.allocatedBytes)
    }
    func testHardLinksCountedOnce() throws {
        let original = try file("original.bin", 64_000)
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("enlace.bin"))
        let report = try Scanner.scan(root: root)
        let fileBytes = report.entries.compactMap(\.allocatedBytes).reduce(0, +)
        XCTAssertLessThan(report.totalAllocated, fileBytes, "El total no debe contar dos veces el mismo inodo")
    }
    func testProtectedFoldersAreMeasuredButNotListed() throws {
        _ = try file("proyecto/node_modules/pkg/index.js", 30_000)
        _ = try file("proyecto/main.swift", 100)
        let report = try Scanner.scan(root: root, options: ScanOptions(minFolderBytes: 0))
        let modules = try XCTUnwrap(report.entries.first { $0.name == "node_modules" })
        XCTAssertEqual(modules.classification.category, .protected)
        XCTAssertGreaterThanOrEqual(modules.allocatedBytes ?? 0, 30_000)
        XCTAssertFalse(modules.classification.canDelete)
        XCTAssertFalse(report.entries.contains { $0.name == "index.js" })
        let folder = try XCTUnwrap(report.folders.first { $0.path.hasSuffix("proyecto/node_modules") })
        XCTAssertEqual(folder.protection, "protected")
    }
    func testGoogleDriveMirrorIsProtected() throws {
        // Google Drive en modo espejo deja .tmp.driveupload en la raíz de la carpeta sincronizada.
        _ = try file("Documentos/.tmp.driveupload/123", 10)
        _ = try file("Documentos/informe.pdf", 40_000)
        _ = try file("Descargas/instalador.dmg", 50_000)
        let report = try Scanner.scan(root: root, options: ScanOptions(minFolderBytes: 0))
        XCTAssertFalse(report.entries.contains { $0.name == "informe.pdf" }, "Nada sincronizado debe aparecer como archivo revisable")
        let docs = try XCTUnwrap(report.entries.first { $0.name == "Documentos" })
        XCTAssertEqual(docs.classification.rule, "sync")
        XCTAssertTrue(docs.classification.reason.contains("Google Drive"))
        XCTAssertGreaterThanOrEqual(docs.allocatedBytes ?? 0, 40_000)
        XCTAssertTrue(report.entries.contains { $0.name == "instalador.dmg" && $0.classification.category == .review })
        // Analizar una subcarpeta de la carpeta sincronizada hereda la protección.
        let inner = try Scanner.scan(root: root.appendingPathComponent("Documentos"))
        XCTAssertEqual(inner.syncedBy, "Google Drive")
        XCTAssertTrue(inner.entries.allSatisfy { $0.bytes == nil })
    }
    func testCloudStoragePathIsSync() {
        let url = URL(fileURLWithPath: "/Users/x/Library/CloudStorage/OneDrive-Personal/Docs")
        XCTAssertEqual(SyncDetector.provider(forDirectory: url), "OneDrive")
        XCTAssertEqual(SyncDetector.provider(forDirectory: URL(fileURLWithPath: "/Users/x/Library/Mobile Documents/com~apple~CloudDocs")), "iCloud Drive")
    }
    func testFolderDepthAndMinimumSize() throws {
        _ = try file("uno/dos/tres/cuatro/grande.bin", 50_000)
        _ = try file("pequeña/x.txt", 10)
        let report = try Scanner.scan(root: root, options: ScanOptions(folderDepth: 2, minFolderBytes: 20_000))
        XCTAssertTrue(report.folders.allSatisfy { $0.depth <= 2 })
        XCTAssertFalse(report.folders.contains { $0.name == "pequeña" })
        XCTAssertTrue(report.folders.contains { $0.name == "dos" })
    }
}
