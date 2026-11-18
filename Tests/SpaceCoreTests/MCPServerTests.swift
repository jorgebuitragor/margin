import XCTest
@testable import SpaceCore

final class MCPServerTests: XCTestCase {
    var home: URL!
    var server: MCPServer!
    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("mcphome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("bin"), withIntermediateDirectories: true)
        server = MCPServer(env: DevEnvironment(home: home, projectRoots: [home.appendingPathComponent("Developer")], runner: FakeRunner(), toolDirectories: [home.appendingPathComponent("bin").path]))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    func file(_ path: String, _ count: Int = 10, _ text: String? = nil) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (text.map { Data($0.utf8) } ?? Data(repeating: 1, count: count)).write(to: url)
    }
    func request(_ id: Int, _ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        let response = try XCTUnwrap(server.handle(String(decoding: data, as: UTF8.self)))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
    }
    func callText(_ name: String, _ args: [String: Any] = [:]) throws -> (String, Bool) {
        let result = try XCTUnwrap(try request(9, "tools/call", ["name": name, "arguments": args])["result"] as? [String: Any])
        let text = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        return (text, result["isError"] as? Bool ?? false)
    }

    func testHandshakeAndToolList() throws {
        let initialize = try XCTUnwrap(try request(1, "initialize", ["protocolVersion": "2025-06-18", "capabilities": [:]])["result"] as? [String: Any])
        XCTAssertEqual(initialize["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNotNil((initialize["capabilities"] as? [String: Any])?["tools"])
        XCTAssertNil(server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#), "Las notificaciones no llevan respuesta")
        let tools = try XCTUnwrap((try request(2, "tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, MCPServer.toolNames)
        XCTAssertFalse(names.contains { $0.contains("apply") || $0.contains("delete") || $0.contains("trash") }, "Ninguna herramienta ejecuta acciones")
        for tool in tools { XCTAssertNotNil(tool["inputSchema"]) }
    }

    func testErrorsFollowJSONRPC() throws {
        let unknown = try request(3, "resources/list")
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
        let invalid = try XCTUnwrap(server.handle("{no es json"))
        XCTAssertTrue(invalid.contains("-32700"))
        let (text, isError) = try callText("no_existe")
        XCTAssertTrue(isError)
        XCTAssertTrue(text.contains("desconocida"))
    }

    func testProposeCleanupCreatesPlanButTouchesNothing() throws {
        try file("Developer/viejo/package.json", 0, "{}")
        try file("Developer/viejo/node_modules/pkg/index.js", 1_200_000)
        let old = Date().addingTimeInterval(-90 * 86_400)
        for name in ["package.json", "node_modules"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home.appendingPathComponent("Developer/viejo/\(name)").path)
        }
        let (dev, devError) = try callText("dev_report")
        XCTAssertFalse(devError)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(dev.utf8)) as? [String: Any])
        let item = try XCTUnwrap((report["actionable"] as? [[String: Any]])?.first { ($0["title"] as? String)?.contains("viejo") == true })
        let id = try XCTUnwrap(item["id"] as? String)

        let (planText, planError) = try callText("propose_cleanup", ["ids": [id]])
        XCTAssertFalse(planError, planText)
        let plan = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(planText.utf8)) as? [String: Any])
        let planID = try XCTUnwrap(plan["plan"] as? String)
        XCTAssertEqual(plan["apply"] as? String, "margin apply \(planID)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Developer/viejo/node_modules/pkg/index.js").path), "Proponer no mueve nada")

        let (result, _) = try callText("plan_result", ["plan": planID])
        XCTAssertTrue(result.contains("pendiente"))
    }

    func testProtectedFilesAreRejected() throws {
        try file("Descargas/clave.pem", 100)
        let (text, isError) = try callText("propose_cleanup", ["files": [home.appendingPathComponent("Descargas/clave.pem").path]])
        XCTAssertTrue(isError)
        XCTAssertTrue(text.contains("no se puede incluir"))
        let (unknown, unknownError) = try callText("propose_cleanup", ["ids": ["deadbeef"]])
        XCTAssertTrue(unknownError)
        XCTAssertTrue(unknown.contains("deadbeef"))
    }

    func testScanFolderSummary() throws {
        try file("Descargas/grande.dmg", 300_000)
        try file("Descargas/otro.zip", 100_000)
        let (text, isError) = try callText("scan_folder", ["path": home.path, "min_mb": 0, "max_files": 1])
        XCTAssertFalse(isError, text)
        let summary = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual((summary["largestFiles"] as? [[String: Any]])?.count, 1)
        XCTAssertGreaterThan(summary["totalAllocated"] as? Int ?? 0, 400_000)
    }
}
