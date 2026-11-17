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
        XCTAssertFalse(report.entries.contains { $0.name == "private.pdf" || $0.name == "original.jpg" || $0.name == "id_rsa" })
        XCTAssertThrowsError(try Scanner.scan(root: root.appendingPathComponent("Library")))
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
}
