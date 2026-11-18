import XCTest
@testable import SpaceCore

/// Desinstalación de apps con apps de mentira en una carpeta personal sintética: nunca se mira /Applications.
final class AppsTests: XCTestCase {
    var home: URL!
    var executor: FakeExecutor!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("apps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("bin"), withIntermediateDirectories: true)
        executor = FakeExecutor(trashDir: home.appendingPathComponent(".papelera-falsa"))
        try app("Fake.app", id: "com.example.fake", name: "Fake")
        try app("Safari.app", id: "com.apple.Safari", name: "Safari")
        try app("Margin.app", id: "local.margin.mac", name: "Margin")
        try file("Library/Caches/com.example.fake/cache.db", 2_000_000)
        try file("Library/Application Support/com.example.fake/datos.sqlite", 3_000_000)
        try file("Library/Preferences/com.example.fake.plist", 1_000)
        try file("Library/Containers/com.example.fake/Data/doc.txt", 1_000)
        try file("Library/Saved Application State/com.example.fake.savedState/windows.plist", 1_000)
        // Restos de una app que ya no está instalada.
        try file("Library/Caches/com.gone.oldapp/blob", 1_500_000)
        try file("Library/Application Support/com.gone.oldapp/state.json", 600_000)
        try file("Library/Preferences/com.gone.oldapp.plist", 1_000)
        // Datos de un ayudante de una app instalada: no son restos.
        try file("Library/Caches/com.example.fake.helper/x", 2_000_000)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    @discardableResult
    func file(_ path: String, _ count: Int) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: count).write(to: url)
        return url
    }

    func app(_ file: String, id: String, name: String) throws {
        let contents = home.appendingPathComponent("Applications/\(file)/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 1, count: 500_000).write(to: contents.appendingPathComponent("MacOS/\(name)"))
    }

    func env(_ runner: FakeRunner = FakeRunner()) -> DevEnvironment {
        DevEnvironment(home: home, runner: runner, toolDirectories: [home.appendingPathComponent("bin").path])
    }

    func fake(_ report: AppsReport) throws -> AppEntry { try XCTUnwrap(report.apps.first { $0.bundleID == "com.example.fake" }) }

    func testAppAndItsLeftoversWithRiskByKind() throws {
        let report = AppInventory.report(env())
        let app = try fake(report)
        XCTAssertNil(app.protectedReason)
        XCTAssertEqual(app.items.first?.path, home.appendingPathComponent("Applications/Fake.app").path, "La app va primero")
        XCTAssertEqual(app.items.first?.category, .review, "Quitar una app nunca es «bajo riesgo»")
        func kind(_ suffix: String) -> DevItem? { app.items.first { $0.path?.hasSuffix(suffix) == true } }
        XCTAssertEqual(kind("Caches/com.example.fake")?.category, .lowRisk)
        XCTAssertEqual(kind("com.example.fake.savedState")?.category, .lowRisk)
        XCTAssertEqual(kind("Application Support/com.example.fake")?.category, .review, "Puede haber datos que solo están ahí")
        XCTAssertEqual(kind("com.example.fake.plist")?.category, .review)
        XCTAssertEqual(kind("Containers/com.example.fake")?.category, .review)
        XCTAssertNil(kind("Containers/com.example.fake")?.bytes, "Los contenedores no se recorren (macOS pediría permiso)")
        XCTAssertNil(kind("com.example.fake.helper"), "Un ayudante no es la app")
        XCTAssertTrue(app.items.allSatisfy { $0.action?.requiresClosed.first?.bundleID == "com.example.fake" }, "Todo exige la app cerrada")
    }

    func testAppleAppsAndMarginAreProtected() throws {
        let report = AppInventory.report(env())
        for id in ["com.apple.Safari", "local.margin.mac"] {
            let app = try XCTUnwrap(report.apps.first { $0.bundleID == id })
            XCTAssertNotNil(app.protectedReason, id)
            XCTAssertTrue(app.items.isEmpty, id)
        }
    }

    func testLeftoversOfDeletedAppsAreGroupedForReview() throws {
        let orphans = AppInventory.report(env()).orphans
        let gone = try XCTUnwrap(orphans.first { $0.title == "com.gone.oldapp" })
        XCTAssertEqual(gone.category, .review)
        XCTAssertEqual(gone.action?.paths.count, 3, "Caché, datos y preferencias juntos")
        XCTAssertFalse(orphans.contains { $0.title.hasPrefix("com.example.fake") }, "Lo de apps instaladas (y sus ayudantes) no son restos")
    }

    func testUninstallPlanMovesAppAndChosenLeftoversToTheTrash() throws {
        let env = env()
        let app = try fake(AppInventory.report(env))
        let chosen = app.items.filter { $0.path?.hasSuffix("Fake.app") == true || $0.path?.hasSuffix("Caches/com.example.fake") == true }
        let plan = try Planner.plan(devItems: chosen, env: env)
        let report = try Planner.apply(plan, env: env, executor: executor)
        XCTAssertEqual(report.results.map(\.status), [.done, .done], report.results.map(\.message).joined(separator: " | "))
        XCTAssertEqual(Set(executor.trashed), Set(chosen.compactMap(\.path)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Support/com.example.fake").path), "Lo no elegido no se toca")
    }

    func testRunningAppBlocksItsUninstall() throws {
        let quiet = env()
        let plan = try Planner.plan(devItems: [try XCTUnwrap(try fake(AppInventory.report(quiet)).items.first)], env: quiet)
        let busy = env(FakeRunner(["lsappinfo find bundleid=com.example.fake": "ASN:0x0-0x1234"]))
        let report = try Planner.apply(plan, env: busy, executor: executor)
        XCTAssertEqual(report.results.first?.status, .blocked)
        XCTAssertTrue(executor.trashed.isEmpty)
    }

    func testHomebrewAppsUseTheirOfficialCommand() throws {
        let brew = home.appendingPathComponent("bin/brew")
        try Data("#!/bin/sh\n".utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let json = #"{"casks":[{"token":"fake","artifacts":[{"app":["Fake.app"]}]}]}"#
        let env = env(FakeRunner(["brew info --installed --cask --json=v2": json]))
        let app = try fake(AppInventory.report(env))
        XCTAssertEqual(app.source, .homebrew)
        XCTAssertEqual(app.items.first?.action?.argv, ["brew", "uninstall", "--cask", "fake"])
    }

    func testApplicationsFolderIsOffLimitsInTestModeAndNestedPathsAlways() {
        let env = env()
        XCTAssertNotNil(Planner.pathProblem("/Applications/Algo.app", env: env), "Con carpeta sintética nunca se toca /Applications")
        XCTAssertEqual(AppInventory.applicationDirectories(env), [home.appendingPathComponent("Applications").path])
        let real = DevEnvironment()
        XCTAssertNotNil(Planner.applicationProblem("/Applications/Utilities/Terminal.app", env: real), "Solo apps de primer nivel")
        XCTAssertNotNil(Planner.applicationProblem("/Applications/Carpeta", env: real))
    }

    func testRevalidationProfilesMatchTheReport() throws {
        let env = env()
        let ids = Set(AppInventory.report(env).apps.flatMap(\.items).map(\.id))
        XCTAssertEqual(Set(try XCTUnwrap(DevProfiles.profile(AppInventory.profileID, env)).items.map(\.id)), ids)
        XCTAssertTrue(try XCTUnwrap(DevProfiles.profile(AppInventory.orphanProfileID, env)).items.contains { $0.title == "com.gone.oldapp" })
    }
}
