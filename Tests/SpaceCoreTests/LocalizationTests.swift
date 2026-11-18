import XCTest
@testable import SpaceCore

final class LocalizationTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("idioma-\(UUID().uuidString)")
        let log = home.appendingPathComponent("Library/Logs/EjemploApp/registro.log")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 25_000_000).write(to: log)
    }

    override func tearDownWithError() throws {
        CoreText.isEnglish = false
        try? FileManager.default.removeItem(at: home)
    }

    func testExplanationsFollowTheLanguageButIdsAndActionsDoNot() throws {
        let env = DevEnvironment(home: home, runner: FakeRunner())
        CoreText.isEnglish = true
        let english = try XCTUnwrap(DevProfiles.profile("logs", env)?.items.first)
        CoreText.isEnglish = false
        let spanish = try XCTUnwrap(DevProfiles.profile("logs", env)?.items.first)

        XCTAssertTrue(english.reason.contains("Only useful"), english.reason)
        XCTAssertTrue(spanish.reason.contains("Solo sirve"), spanish.reason)
        XCTAssertEqual(english.id, spanish.id, "El identificador no depende del idioma")
        XCTAssertEqual(english.shortID, spanish.shortID, "Los id de la CLI tampoco")
        XCTAssertEqual(english.action, spanish.action, "La acción se compara por lo que ejecuta, no por sus textos")
    }

    func testPlanCreatedInEnglishStaysValidInSpanish() throws {
        // Un plan hecho en la app en inglés se puede aplicar desde la terminal, que va en español.
        let env = DevEnvironment(home: home, runner: FakeRunner())
        CoreText.isEnglish = true
        let item = try XCTUnwrap(DevProfiles.profile("logs", env)?.items.first)
        let plan = try Planner.plan(devItems: [item], env: env)
        CoreText.isEnglish = false
        var fresh: [String: ProfileResult] = [:]
        XCTAssertNil(Planner.blocker(plan.steps[0], plan: plan, env: env, freshProfiles: &fresh))
    }
}
