import XCTest
@testable import SpaceCore

/// Papelera falsa dentro de la carpeta sintética: las pruebas nunca tocan la Papelera real.
final class FakeExecutor: ActionExecutor, @unchecked Sendable {
    let trashDir: URL
    var failing: Set<String> = []
    private(set) var trashed: [String] = []
    private(set) var commands: [[String]] = []
    var commandStatus: Int32 = 0
    init(trashDir: URL) { self.trashDir = trashDir }
    func trash(_ path: String) throws -> String? {
        if failing.contains(path) { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let target = trashDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(atPath: path, toPath: target.path)
        trashed.append(path)
        return target.path
    }
    func run(_ executable: String, _ arguments: [String]) -> CommandResult? {
        commands.append([URL(fileURLWithPath: executable).lastPathComponent] + arguments)
        return CommandResult(status: commandStatus, output: "salida de prueba")
    }
}

final class ActionsTests: XCTestCase {
    var home: URL!
    var executor: FakeExecutor!
    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("acthome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("bin"), withIntermediateDirectories: true)
        executor = FakeExecutor(trashDir: home.appendingPathComponent(".papelera-falsa"))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    @discardableResult
    func file(_ path: String, _ count: Int = 10, _ text: String? = nil) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (text.map { Data($0.utf8) } ?? Data(repeating: 3, count: count)).write(to: url)
        return url
    }
    func age(_ path: String, days: Double) throws {
        let date = Date().addingTimeInterval(-days * 86_400)
        let dir = home.appendingPathComponent(path)
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: dir.appendingPathComponent(name).path)
        }
    }
    func env(_ runner: FakeRunner = FakeRunner(), now: Date = Date()) -> DevEnvironment {
        DevEnvironment(home: home, projectRoots: [home.appendingPathComponent("Developer")], now: now, runner: runner, toolDirectories: [home.appendingPathComponent("bin").path])
    }
    func oldProject(_ name: String = "viejo") throws {
        try file("Developer/\(name)/package.json", 0, "{}")
        try file("Developer/\(name)/node_modules/pkg/index.js", 1_200_000)
        try age("Developer/\(name)", days: 90)
    }
    func item(_ env: DevEnvironment, _ title: String) throws -> DevItem {
        try XCTUnwrap(DevProfiles.report(env).profiles.flatMap(\.items).first { $0.title.contains(title) }, title)
    }

    func testTrashInactiveArtifactLogsAndCannotRepeat() throws {
        try oldProject()
        let env = env()
        let plan = try Planner.plan(devItems: [try item(env, "viejo · node_modules")], env: env)
        try PlanStore.save(plan, env)
        let report = try Planner.apply(try PlanStore.load(plan.id, env), env: env, executor: executor)
        XCTAssertEqual(report.results.map(\.status), [.done], report.results.first?.message ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("Developer/viejo/node_modules").path))
        XCTAssertTrue(report.usedTrash)
        XCTAssertNotNil(report.availableBefore)
        let log = try String(contentsOfFile: "\(env.supportDirectory)/acciones.jsonl", encoding: .utf8)
        XCTAssertTrue(log.contains(plan.id) && log.contains("hecho"))
        XCTAssertThrowsError(try Planner.apply(plan, env: env, executor: executor)) { XCTAssertTrue($0 is PlanError) }
    }

    func testProtectedAndActiveItemsCannotBePlanned() throws {
        try file("Developer/activo/package.json", 0, "{}")
        try file("Developer/activo/node_modules/pkg/index.js", 1_200_000)
        let env = env()
        let active = try item(env, "activo · node_modules")
        XCTAssertFalse(active.canDelete)
        XCTAssertThrowsError(try Planner.plan(devItems: [active], env: env))
        let personal = FileEntry(path: try file("Descargas/clave.pem").path, bytes: 10, allocatedBytes: 4096, modified: nil, classification: Classifier.classify(home.appendingPathComponent("Descargas/clave.pem")))
        XCTAssertThrowsError(try Planner.plan(files: [personal], env: env), "Un archivo protegido no entra en un plan")
    }

    func testReplacedDirectoryIsBlocked() throws {
        try oldProject()
        let env = env()
        let plan = try Planner.plan(devItems: [try item(env, "viejo · node_modules")], env: env)
        // Otro proceso reemplaza la carpeta entre el plan y la ejecución: mismo nombre, distinto inodo.
        let modules = home.appendingPathComponent("Developer/viejo/node_modules")
        try FileManager.default.removeItem(at: modules)
        try file("Developer/viejo/node_modules/otro/index.js", 1_200_000)
        try age("Developer/viejo", days: 90)
        let report = try Planner.apply(plan, env: env, executor: executor)
        XCTAssertEqual(report.results.first?.status, .blocked)
        XCTAssertTrue(report.results.first?.message.contains("Cambió") == true)
        XCTAssertTrue(executor.trashed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: modules.path))
    }

    func testProjectThatBecameActiveIsBlocked() throws {
        try oldProject()
        let env = env()
        let plan = try Planner.plan(devItems: [try item(env, "viejo · node_modules")], env: env)
        try file("Developer/viejo/package.json", 0, "{\"name\":\"editado hoy\"}")
        let report = try Planner.apply(plan, env: env, executor: executor)
        XCTAssertEqual(report.results.first?.status, .blocked)
        XCTAssertTrue(report.results.first?.message.contains("categoría") == true)
        XCTAssertTrue(executor.trashed.isEmpty)
    }

    func testModifiedPersonalFileIsBlocked() throws {
        let url = try file("Descargas/instalador.dmg", 50_000)
        let entry = FileEntry(path: url.path, bytes: 50_000, allocatedBytes: 53_248, modified: nil, classification: Classifier.classify(url))
        let env = env()
        let plan = try Planner.plan(files: [entry], env: env)
        try Data(repeating: 9, count: 60_000).write(to: url)
        let report = try Planner.apply(plan, env: env, executor: executor)
        XCTAssertEqual(report.results.first?.status, .blocked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testUnchangedPersonalFileGoesToTrash() throws {
        let url = try file("Descargas/instalador.dmg", 50_000)
        let entry = FileEntry(path: url.path, bytes: 50_000, allocatedBytes: 53_248, modified: nil, classification: Classifier.classify(url))
        let env = env()
        let report = try Planner.apply(try Planner.plan(files: [entry], env: env), env: env, executor: executor)
        XCTAssertEqual(report.results.first?.status, .done)
        XCTAssertEqual(executor.trashed, [url.path])
    }

    func testTmpAliasIsCanonicalized() throws {
        let url = try file("Descargas/alias.zip", 5_000)
        let alias = url.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
        let entry = FileEntry(path: alias, bytes: 5_000, allocatedBytes: 8_192, modified: nil, classification: Classifier.classify(URL(fileURLWithPath: alias)))
        let env = env()
        let report = try Planner.apply(try Planner.plan(files: [entry], env: env), env: env, executor: executor)
        XCTAssertEqual(report.results.first?.status, .done, report.results.first?.message ?? "")
        XCTAssertEqual(executor.trashed, [url.path])
    }

    func testSyncedFileIsBlocked() throws {
        try file("Documentos/.tmp.driveupload/1")
        let url = try file("Documentos/informe.pdf", 30_000)
        let entry = FileEntry(path: url.path, bytes: 30_000, allocatedBytes: 32_768, modified: nil, classification: Classifier.classify(url))
        let env = env()
        let report = try Planner.apply(try Planner.plan(files: [entry], env: env), env: env, executor: executor)
        XCTAssertEqual(report.results.first?.status, .blocked)
        XCTAssertTrue(report.results.first?.message.contains("Google Drive") == true)
    }

    func testPartialFailureNeverDeletesPermanently() throws {
        try file(".vscode/extensions/acme.tool-1.0.0/package.json", 2_000)
        try file(".vscode/extensions/acme.tool-1.1.0/package.json", 2_000)
        try file(".vscode/extensions/acme.tool-1.2.0/package.json", 2_000)
        let env = env()
        let stale = try item(env, "versiones antiguas")
        XCTAssertEqual(stale.action?.paths.count, 2)
        let plan = try Planner.plan(devItems: [stale], env: env)
        let failing = home.appendingPathComponent(".vscode/extensions/acme.tool-1.0.0").path
        executor.failing = [failing]
        let report = try Planner.apply(plan, env: env, executor: executor)
        let result = try XCTUnwrap(report.results.first)
        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.trashed.count, 1)
        XCTAssertNotNil(result.failures[failing])
        XCTAssertTrue(FileManager.default.fileExists(atPath: failing), "Un fallo de Papelera deja el archivo en su sitio")
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".vscode/extensions/acme.tool-1.2.0").path))
    }

    func testRunningAppBlocksAction() throws {
        try file("Library/Developer/Xcode/DerivedData/App/Build/x", 2_000_000)
        let quiet = env()
        let plan = try Planner.plan(devItems: [try item(quiet, "DerivedData")], env: quiet)
        let busy = env(FakeRunner(["pgrep -f Xcode.app": "123"]))
        let report = try Planner.apply(plan, env: busy, executor: executor)
        XCTAssertEqual(report.results.first?.status, .blocked)
        XCTAssertTrue(report.results.first?.message.contains("Xcode") == true)
        XCTAssertTrue(executor.trashed.isEmpty)
    }

    func testCommandRunsOfficialArgumentsWithoutShell() throws {
        let pnpm = try file("bin/pnpm", 0, "#!/bin/sh\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pnpm.path)
        try file("Library/pnpm/store/v10/files/aa/blob", 2_000_000)
        let env = env()
        let store = try item(env, "Store de pnpm")
        let report = try Planner.apply(try Planner.plan(devItems: [store], env: env), env: env, executor: executor)
        XCTAssertEqual(report.results.first?.status, .done)
        XCTAssertEqual(executor.commands, [["pnpm", "store", "prune"]])
        executor.commandStatus = 1
        let failed = try Planner.apply(try Planner.plan(devItems: [store], env: env), env: env, executor: executor)
        XCTAssertEqual(failed.results.first?.status, .failed)
    }

    func testRealRunnerUsesToolsOwnNodeAndKeepsErrors() throws {
        // Simula una herramienta de nvm: un script que llama a «node» y un «node» hermano en la misma carpeta.
        let dir = home.appendingPathComponent(".nvm/versions/node/v24.0.0/bin")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let node = dir.appendingPathComponent("node")
        try Data("#!/bin/sh\necho node-propio\necho aviso >&2\nexit 3\n".utf8).write(to: node)
        let tool = dir.appendingPathComponent("herramienta")
        try Data("#!/usr/bin/env node\n".utf8).write(to: tool)
        for url in [node, tool] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        let result = try XCTUnwrap(ProcessRunner().run(tool.path, [], timeout: 10))
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "node-propio")
        XCTAssertEqual(result.error.trimmingCharacters(in: .whitespacesAndNewlines), "aviso")
        XCTAssertEqual(result.status, 3)
    }

    func testFailedCommandKeepsErrorOutput() throws {
        let pnpm = try file("bin/pnpm", 0, "#!/bin/sh\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pnpm.path)
        try file("Library/pnpm/store/v10/files/aa/blob", 2_000_000)
        final class ErrorExecutor: ActionExecutor, @unchecked Sendable {
            func trash(_ path: String) throws -> String? { nil }
            func run(_ executable: String, _ arguments: [String]) -> CommandResult? { CommandResult(status: 1, output: "", error: "ERR_PNPM_X algo falló") }
        }
        let env = env()
        let report = try Planner.apply(try Planner.plan(devItems: [try item(env, "Store de pnpm")], env: env), env: env, executor: ErrorExecutor())
        XCTAssertEqual(report.results.first?.status, .failed)
        XCTAssertTrue(report.results.first?.output?.contains("ERR_PNPM_X") == true)
    }

    func testExpiredPlanIsRejected() throws {
        try oldProject()
        let env = env()
        let plan = try Planner.plan(devItems: [try item(env, "viejo · node_modules")], env: env)
        var later = env
        later.now = env.now.addingTimeInterval(25 * 3600)
        XCTAssertThrowsError(try Planner.apply(plan, env: later, executor: executor))
        XCTAssertTrue(executor.trashed.isEmpty)
    }

    func testPathSafetyRules() throws {
        let env = env()
        try file("Developer/a/b.txt")
        XCTAssertNotNil(Planner.pathProblem(home.path, env: env))
        XCTAssertNotNil(Planner.pathProblem(home.appendingPathComponent("Developer").path, env: env), "Una carpeta de primer nivel es demasiado general")
        XCTAssertNotNil(Planner.pathProblem("/private/tmp/otro/x/y", env: env))
        XCTAssertNil(Planner.pathProblem(home.appendingPathComponent("Developer/a").path, env: env))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Developer/enlace"), withDestinationURL: home.appendingPathComponent("Developer/a"))
        XCTAssertNotNil(Planner.pathProblem(home.appendingPathComponent("Developer/enlace/b.txt").path, env: env))
        XCTAssertNil(FileIdentity.of(home.appendingPathComponent("Developer/enlace").path), "Un enlace no tiene identidad válida para actuar")
    }
}
