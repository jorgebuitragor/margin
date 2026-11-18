import XCTest
@testable import SpaceCore

final class SmartScanTests: XCTestCase {
    var home: URL!
    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("smarthome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("bin"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    @discardableResult
    func file(_ path: String, _ count: Int = 10, age days: Double? = nil) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 5, count: count).write(to: url)
        if let days { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-days * 86_400)], ofItemAtPath: url.path) }
        return url
    }
    func env(_ runner: FakeRunner = FakeRunner()) -> DevEnvironment {
        DevEnvironment(home: home, projectRoots: [home.appendingPathComponent("Developer")], runner: runner, toolDirectories: [home.appendingPathComponent("bin").path])
    }
    func items(_ report: DevReport, _ profile: String) -> [DevItem] { report.profiles.first { $0.id == profile }?.items ?? [] }

    func testAppCachesClassification() throws {
        try file("Library/Caches/Firefox/cache2/a", 60_000_000)
        try file("Library/Caches/com.acme.Editor/data", 60_000_000)
        try file("Library/Caches/misterio/blob", 60_000_000)
        try file("Library/Caches/com.apple.Safari/x", 60_000_000)
        try file("Library/Caches/Homebrew/x", 60_000_000)
        try file("Library/Caches/pequena/x", 1_000)
        let caches = items(DevProfiles.report(env()), "app-caches")
        XCTAssertEqual(Set(caches.map(\.title)), ["Caché de Firefox", "Caché de com.acme.Editor", "Caché «misterio»"], "Ni macOS, ni Homebrew (otro perfil), ni lo pequeño")
        let firefox = try XCTUnwrap(caches.first { $0.title == "Caché de Firefox" })
        XCTAssertEqual(firefox.category, .lowRisk)
        XCTAssertEqual(firefox.action?.requiresClosed.first?.label, "Firefox")
        let app = try XCTUnwrap(caches.first { $0.title.contains("com.acme.Editor") })
        XCTAssertEqual(app.action?.requiresClosed.first?.bundleID, "com.acme.Editor")
        XCTAssertEqual(try XCTUnwrap(caches.first { $0.title.contains("misterio") }).category, .review)
    }

    func testRunningAppByBundleIDBlocksTrash() throws {
        try file("Library/Caches/com.acme.Editor/data", 60_000_000)
        let quiet = env()
        let item = try XCTUnwrap(items(DevProfiles.report(quiet), "app-caches").first)
        let plan = try Planner.plan(devItems: [item], env: quiet)
        let busy = env(FakeRunner(["lsappinfo find bundleid=com.acme.Editor": "ASN:0x0-0x1234"]))
        let report = try Planner.apply(plan, env: busy, executor: FakeExecutor(trashDir: home.appendingPathComponent(".falsa")))
        XCTAssertEqual(report.results.first?.status, .blocked)
        XCTAssertTrue(report.results.first?.message.contains("com.acme.Editor") == true)
    }

    func testLogsAndOldInstallers() throws {
        try file("Library/Logs/AppA/a.log", 15_000_000)
        try file("Library/Logs/AppB/b.log", 15_000_000)
        try file("Downloads/viejo.dmg", 2_000_000, age: 90)
        try file("Downloads/reciente.pkg", 2_000_000, age: 2)
        try file("Downloads/foto.jpg", 2_000_000, age: 200)
        let report = DevProfiles.report(env())
        let logs = try XCTUnwrap(items(report, "logs").first)
        XCTAssertEqual(logs.category, .lowRisk)
        XCTAssertEqual(logs.action?.paths.count, 2)
        let downloads = try XCTUnwrap(items(report, "downloads").first)
        XCTAssertEqual(downloads.category, .review, "Un instalador puede ser la única copia")
        XCTAssertEqual(downloads.action?.paths, [home.appendingPathComponent("Downloads/viejo.dmg").path], "Ni recientes ni fotos")
    }

    func testSyncedDownloadsAreIgnored() throws {
        try file("Downloads/.tmp.driveupload/1")
        try file("Downloads/viejo.dmg", 2_000_000, age: 90)
        let profile = try XCTUnwrap(DevProfiles.report(env()).profiles.first { $0.id == "downloads" })
        XCTAssertTrue(profile.items.isEmpty)
        XCTAssertTrue(profile.notes.joined().contains("sincronizada"))
    }

    func testTrashStatusAndEmptying() throws {
        try file(".Trash/viejo.zip", 1_000_000)
        try file(".Trash/otro.txt", 10)
        let env = env()
        let status = TrashStatus.read(env)
        XCTAssertEqual(status.items, 2)
        XCTAssertGreaterThan(status.bytes ?? 0, 1_000_000)
        // Vaciar se delega en Finder con un comando fijo; aquí con un ejecutor falso que no toca nada.
        let executor = FakeExecutor(trashDir: home.appendingPathComponent(".falsa"))
        let done = TrashEmptier.empty(env: env, executor: executor)
        XCTAssertEqual(executor.commands, [["osascript", "-e", "tell application \"Finder\" to empty trash"]])
        XCTAssertEqual(done.status, .done)
        let log = try String(contentsOfFile: "\(env.supportDirectory)/acciones.jsonl", encoding: .utf8)
        XCTAssertTrue(log.contains("vaciar-papelera"))
        executor.commandStatus = 1
        let failed = TrashEmptier.empty(env: env, executor: executor)
        XCTAssertEqual(failed.status, .failed)
    }

    func testRealTrashIsNeverEmptiedFromATestHome() {
        // Con el ejecutor real y una carpeta personal sintética, no se llega a pedir nada a Finder.
        let result = TrashEmptier.empty(env: env(), executor: SystemExecutor())
        XCTAssertEqual(result.status, .blocked)
        XCTAssertNil(result.availableBefore)
    }

    func testEmptyingTrashIsNeverAPlanOrMCPAction() throws {
        try file("Library/Caches/com.acme.Editor/data", 60_000_000)
        try file("Library/Logs/AppA/a.log", 30_000_000)
        let report = DevProfiles.report(env())
        let trashHome = home.appendingPathComponent(".Trash").path
        for item in report.profiles.flatMap(\.items) {
            XCTAssertFalse(item.action?.command.contains("empty trash") == true)
            XCTAssertFalse(item.action?.paths.contains { $0.hasPrefix(trashHome) } == true)
        }
        XCTAssertFalse(MCPServer.toolNames.contains { $0.contains("trash") || $0.contains("papelera") })
    }

    func testProfilesRunInParallelButKeepOrder() {
        let report = DevProfiles.report(env())
        XCTAssertEqual(report.profiles.map(\.id), DevProfiles.ids)
    }
}
