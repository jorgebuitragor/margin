import XCTest
@testable import SpaceCore

/// Ejecutor falso: responde a consultas conocidas y registra todo lo que se le pide.
final class FakeRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    let responses: [String: String]
    init(_ responses: [String: String] = [:]) { self.responses = responses }
    var calls: [String] { lock.withLock { log } }
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult? {
        let line = ([URL(fileURLWithPath: executable).lastPathComponent] + arguments).joined(separator: " ")
        lock.withLock { log.append(line) }
        for (prefix, output) in responses where line.hasPrefix(prefix) { return CommandResult(status: 0, output: output) }
        return CommandResult(status: 1, output: "")
    }
}

final class DevProfilesTests: XCTestCase {
    var home: URL!
    var bin: URL!
    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("devhome-\(UUID().uuidString)")
        bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    @discardableResult
    func file(_ path: String, _ count: Int = 10, _ text: String? = nil) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (text.map { Data($0.utf8) } ?? Data(repeating: 7, count: count)).write(to: url)
        return url
    }
    func tool(_ name: String) throws {
        let url = try file("bin/\(name)", 0, "#!/bin/sh\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    func age(_ path: String, days: Double) throws {
        let date = Date().addingTimeInterval(-days * 86_400)
        let dir = home.appendingPathComponent(path)
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: dir.appendingPathComponent(name).path)
        }
    }
    func env(_ runner: FakeRunner = FakeRunner(), roots: [String] = ["Developer"]) -> DevEnvironment {
        DevEnvironment(home: home, projectRoots: roots.map { home.appendingPathComponent($0) }, runner: runner, toolDirectories: [bin.path])
    }
    func item(_ report: DevReport, _ profile: String, _ title: String) throws -> DevItem {
        try XCTUnwrap(report.profiles.first { $0.id == profile }?.items.first { $0.title.contains(title) }, "\(profile): \(title)")
    }

    func testAndroidImagesAndNdkFollowUsage() throws {
        try file("Library/Android/sdk/system-images/android-36/google_apis/arm64-v8a/system.img", 5_000)
        try file("Library/Android/sdk/system-images/android-34/google_apis/arm64-v8a/system.img", 5_000)
        try file("Library/Android/sdk/ndk/25.1.8937393/source.properties", 100)
        try file("Library/Android/sdk/ndk/27.1.12297006/source.properties", 100)
        try file(".android/avd/Pixel.avd/config.ini", 0, "image.sysdir.1=system-images/android-36/google_apis/arm64-v8a/\n")
        try file("Developer/app/android/app/build.gradle", 0, "android { ndkVersion \"27.1.12297006\" }")
        let report = DevProfiles.report(env())
        XCTAssertEqual(try item(report, "android-sdk", "android-36").category, .protected)
        let unused = try item(report, "android-sdk", "android-34")
        XCTAssertEqual(unused.category, .lowRisk)
        XCTAssertEqual(unused.action?.command, "sdkmanager --uninstall \"system-images;android-34;google_apis;arm64-v8a\"")
        XCTAssertEqual(try item(report, "android-sdk", "NDK 27").category, .protected)
        XCTAssertEqual(try item(report, "android-sdk", "NDK 25").category, .review, "Sin referencia no basta para bajo riesgo")
        XCTAssertEqual(try item(report, "android-avd", "Emulador Pixel").category, .review)
    }

    func testProjectArtifactsDependOnActivity() throws {
        try file("Developer/viejo/package.json", 0, "{}")
        try file("Developer/viejo/node_modules/pkg/big.js", 1_200_000)
        try file("Developer/nuevo/package.json", 0, "{}")
        try file("Developer/nuevo/node_modules/pkg/big.js", 1_200_000)
        try file("Developer/swift/Package.swift", 0, "// swift")
        try file("Developer/swift/.build/debug/app", 1_500_000)
        try age("Developer/viejo", days: 90)
        try age("Developer/swift", days: 40)
        let report = DevProfiles.report(env())
        let old = try item(report, "project-artifacts", "viejo · node_modules")
        XCTAssertEqual(old.category, .lowRisk)
        XCTAssertEqual(old.action?.kind, .trash)
        XCTAssertTrue(old.reason.contains("90 días"))
        XCTAssertEqual(try item(report, "project-artifacts", "nuevo · node_modules").category, .protected)
        XCTAssertNil(try item(report, "project-artifacts", "nuevo · node_modules").action)
        XCTAssertEqual(try item(report, "project-artifacts", "swift · .build").category, .lowRisk)
    }

    func testPnpmHardLinksReduceRecoverable() throws {
        try file("Developer/web/package.json", 0, "{}")
        try file("Developer/web/pnpm-lock.yaml", 0, "lockfileVersion: 9")
        let stored = try file("Library/pnpm/store/v10/files/aa/blob", 2_000_000)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Developer/web/node_modules/pkg"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: stored, to: home.appendingPathComponent("Developer/web/node_modules/pkg/blob"))
        try age("Developer/web", days: 60)
        let report = DevProfiles.report(env())
        let modules = try item(report, "project-artifacts", "web · node_modules")
        XCTAssertGreaterThanOrEqual(modules.bytes ?? 0, 2_000_000)
        XCTAssertLessThan(modules.recoverable ?? .max, 1_000_000, "Los archivos enlazados con el store no se liberan al borrar node_modules")
        XCTAssertTrue(modules.reason.contains("pnpm store prune"))
        let store = try item(report, "js-packages", "Store de pnpm")
        XCTAssertLessThan(store.recoverable ?? .max, 1_000_000, "Un paquete referenciado no es recuperable con prune")
    }

    func testGradleDistributionsFollowWrappers() throws {
        try file(".gradle/wrapper/dists/gradle-8.13-bin/abc/gradle.zip", 5_000)
        try file(".gradle/wrapper/dists/gradle-9.2.0-bin/abc/gradle.zip", 5_000)
        try file("Developer/app/android/build.gradle", 0, "// gradle")
        try file("Developer/app/android/gradle/wrapper/gradle-wrapper.properties", 0, "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip\n")
        let report = DevProfiles.report(env())
        XCTAssertEqual(try item(report, "gradle-maven", "Gradle 8.13").category, .protected)
        XCTAssertEqual(try item(report, "gradle-maven", "Gradle 9.2.0").category, .lowRisk)
    }

    func testSimulatorsAndDockerUseToolQueries() throws {
        try tool("docker")
        try file("Library/Developer/CoreSimulator/Devices/OLD/data/x", 4_000)
        let devices = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[{"udid":"OLD","name":"iPhone 15","isAvailable":false,"dataPath":"\(home.path)/Library/Developer/CoreSimulator/Devices/OLD/data"}]}}
        """
        let runtimes = """
        {"R1":{"identifier":"R1","version":"17.0","sizeBytes":7000000000,"deletable":true,"lastUsedAt":"2025-01-01T00:00:00Z","path":"/System/Library/AssetsV2/x.dmg"}}
        """
        let docker = """
        {"Type":"Images","Size":"3.2GB","Reclaimable":"2.1GB (65%)"}
        {"Type":"Build Cache","Size":"800MB","Reclaimable":"800MB"}
        {"Type":"Local Volumes","Size":"1GB","Reclaimable":"0B"}
        """
        let runner = FakeRunner(["xcrun simctl list devices": devices, "xcrun simctl runtime list": runtimes, "docker system df": docker])
        let report = DevProfiles.report(env(runner))
        let unavailable = try item(report, "ios-simulators", "no disponibles")
        XCTAssertEqual(unavailable.category, .lowRisk)
        XCTAssertEqual(unavailable.action?.command, "xcrun simctl delete unavailable")
        let runtime = try item(report, "ios-simulators", "Runtime iOS 17.0")
        XCTAssertEqual(runtime.category, .review)
        XCTAssertEqual(runtime.recoverable, 7_000_000_000)
        XCTAssertEqual(try item(report, "docker", "Caché de compilación").recoverable, 800_000_000)
        XCTAssertEqual(try item(report, "docker", "Imágenes sin usar").category, .review)
        XCTAssertNil(report.profiles.first { $0.id == "docker" }?.items.first { $0.title.contains("Volúmenes") }, "Sin espacio reclamable no se propone")
    }

    func testOnlyReadOnlyQueriesAndNothingDeletable() throws {
        try tool("docker"); try tool("brew"); try tool("pnpm")
        try file("Developer/web/package.json", 0, "{}")
        try file("Developer/web/node_modules/a.js", 1_100_000)
        try file("Library/Developer/CoreSimulator/Devices/x", 10)
        try file("Library/Developer/Xcode/DerivedData/App/Build/x", 2_000_000)
        try file("Library/Application Support/Claude/vm_bundles/claudevm.bundle/disk.img", 200_000_000)
        try age("Developer/web", days: 100)
        let runner = FakeRunner()
        let before = try FileManager.default.subpathsOfDirectory(atPath: home.path).sorted()
        let report = DevProfiles.report(env(runner))
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: home.path).sorted(), before, "Analizar no modifica nada")
        let allowed = ["xcrun simctl list", "xcrun simctl runtime list", "docker system df", "git -C", "pnpm store path", "brew --cache"]
        for call in runner.calls {
            XCTAssertTrue(allowed.contains { call.hasPrefix($0) }, "Consulta no permitida: \(call)")
        }
        let items = report.profiles.flatMap(\.items)
        XCTAssertFalse(items.isEmpty)
        for item in items {
            if item.category == .protected { XCTAssertFalse(item.canDelete, item.title) }
            XCTAssertFalse(item.reason.isEmpty)
            XCTAssertFalse(item.regenerate.isEmpty)
            if item.category == .lowRisk { XCTAssertNotNil(item.action, item.title) }
        }
        XCTAssertEqual(try item(report, "claude-desktop", "Máquina virtual").category, .review)
        XCTAssertEqual(try item(report, "xcode", "DerivedData").category, .lowRisk)
    }

    func testProjectRootsAreDeduplicated() throws {
        try file("Developer/viejo/package.json", 0, "{}")
        try file("Developer/viejo/node_modules/a.js", 1_100_000)
        try age("Developer/viejo", days: 90)
        // En APFS sin distinción de mayúsculas, DEVELOPER es la misma carpeta.
        let report = DevProfiles.report(env(roots: ["Developer", "DEVELOPER", "Developer/../Developer"]))
        let matches = report.profiles.first { $0.id == "project-artifacts" }?.items.filter { $0.title.contains("node_modules") } ?? []
        XCTAssertEqual(matches.count, 1)
    }

    func testDockerSizesAndVersions() {
        XCTAssertEqual(DevEnvironmentHelpers.parseDockerSize("2.1GB (65%)"), 2_100_000_000)
        XCTAssertEqual(DevEnvironmentHelpers.parseDockerSize("512kB"), 512_000)
        XCTAssertEqual(DevEnvironmentHelpers.parseDockerSize("0B"), 0)
        XCTAssertTrue(DevEnvironment.versionLess("v20.11.0", "v20.19.6"))
        XCTAssertTrue(DevEnvironment.versionLess("8.7", "8.13"))
        XCTAssertFalse(DevEnvironment.versionLess("27.1.12297006", "25.1.8937393"))
    }
}
