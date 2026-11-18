import XCTest
@testable import SpaceCore

final class StorageTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("storage-\(UUID().uuidString)")
        for (path, size) in [
            ("Documents/informe.pdf", 3_000_000), ("Developer/app/src.bin", 2_000_000), (".gradle/caches/x.bin", 4_000_000),
            ("Library/Caches/app/c.bin", 1_000_000), ("Library/Developer/Xcode/d.bin", 5_000_000), (".Trash/viejo.bin", 1_500_000),
            ("Applications/Util.app/bin", 500_000)
        ] {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: size).write(to: url)
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    func testHomeFoldersGoToTheirCategoryAndTestHomeSkipsSystem() {
        let env = DevEnvironment(home: home)
        let jobs = StorageAnalyzer.jobs(env)
        func kind(_ relative: String) -> StorageSegment.Kind? { jobs.first { $0.path == home.appendingPathComponent(relative).path }?.kind }
        XCTAssertEqual(kind("Documents"), .personal)
        XCTAssertEqual(kind("Developer"), .development, "Raíz de proyectos")
        XCTAssertEqual(kind(".gradle"), .development, "Carpeta oculta de herramienta")
        XCTAssertEqual(kind("Library/Caches"), .appData)
        XCTAssertEqual(kind("Library/Developer"), .development)
        XCTAssertEqual(kind(".Trash"), .trash)
        XCTAssertEqual(kind("Applications"), .apps)
        XCTAssertNil(kind("Library"), "La Biblioteca se mide por partes, nunca entera")
        XCTAssertFalse(jobs.contains { !$0.path.hasPrefix(home.path) }, "Con una carpeta sintética no se mide el sistema real")
    }

    func testMeasuredSegmentsAddUpToTheVolume() throws {
        let capacity = VolumeCapacity(total: 100_000_000, available: 40_000_000, purgeable: 2_000_000)
        let breakdown = try XCTUnwrap(StorageAnalyzer.measure(DevEnvironment(home: home), capacity: capacity))
        XCTAssertEqual(breakdown.segments.reduce(0) { $0 + $1.bytes } + breakdown.available, breakdown.total)
        XCTAssertGreaterThanOrEqual(breakdown.bytes(.development), 11_000_000)
        XCTAssertGreaterThanOrEqual(breakdown.bytes(.trash), 1_500_000)
        XCTAssertEqual(breakdown.bytes(.purgeable), 2_000_000)
        XCTAssertEqual(breakdown.segments.last?.kind, .system)
    }

    func testOvercountedMeasurementsAreScaledToUsedSpace() {
        // Clones de APFS o enlaces duros pueden hacer que lo medido supere lo usado: nunca se pasa del total.
        let capacity = VolumeCapacity(total: 1_000, available: 600, purgeable: 0)
        let breakdown = StorageAnalyzer.build(capacity: capacity, measured: [.apps: 300, .personal: 300])
        XCTAssertEqual(breakdown.used, 400)
        XCTAssertLessThanOrEqual(breakdown.segments.reduce(0) { $0 + $1.bytes }, 400)
        XCTAssertEqual(breakdown.bytes(.apps), 200)
        XCTAssertEqual(breakdown.bytes(.system), 0)
    }

    func testSystemVolumesComeFromTheDataContainer() throws {
        // Formato real de `diskutil apfs list -plist`: se suman los volúmenes del contenedor de «Data» menos Data,
        // y se ignoran otros contenedores (discos externos, imágenes de simuladores).
        func volume(_ name: String, _ roles: [String], _ used: Int64) -> [String: Any] { ["Name": name, "Roles": roles, "CapacityInUse": used] }
        let plist: [String: Any] = ["Containers": [
            ["CapacityCeiling": Int64(500), "Volumes": [volume("ExternalDisk", [], 300)]],
            ["CapacityCeiling": Int64(1_000), "Volumes": [volume("Macintosh HD", ["System"], 100), volume("Preboot", ["Preboot"], 50),
                                                         volume("Data", ["Data"], 600), volume("VM", ["VM"], 20)]]
        ]]
        let xml = String(decoding: try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0), as: UTF8.self)
        let runner = FakeRunner(["diskutil apfs list -plist": xml])
        XCTAssertEqual(StorageAnalyzer.systemVolumesBytes(total: 1_000, runner: runner), 170)
        XCTAssertNil(StorageAnalyzer.systemVolumesBytes(total: 2_000, runner: runner), "Otro tamaño de disco: no se adivina")
        XCTAssertNil(StorageAnalyzer.systemVolumesBytes(total: 1_000, runner: FakeRunner()), "Sin diskutil no se inventa nada")
    }

    func testCacheRoundTripAndLegacyDataFolderIsKept() throws {
        let legacy = home.appendingPathComponent("Library/Application Support/GestorEspacio")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("acciones.jsonl"))
        let env = DevEnvironment(home: home)
        XCTAssertTrue(env.supportDirectory.hasSuffix("Application Support/Margen"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: env.supportDirectory + "/acciones.jsonl"), "El registro de la 0.6 se conserva")
        let breakdown = StorageAnalyzer.build(capacity: VolumeCapacity(total: 10, available: 4, purgeable: 1), measured: [.apps: 2], date: Date(timeIntervalSince1970: 1_800_000_000))
        StorageAnalyzer.save(breakdown, env)
        XCTAssertEqual(StorageAnalyzer.cached(env), breakdown)
    }
}
