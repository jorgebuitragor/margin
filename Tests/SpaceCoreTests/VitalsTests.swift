import XCTest
@testable import SpaceCore

final class VitalsTests: XCTestCase {
    func testTwoSamplesGiveCPUUseAndSaneValues() throws {
        let sampler = VitalsSampler()
        let first = sampler.sample()
        XCTAssertNil(first.cpuLoad, "Sin muestra anterior no hay uso de CPU que calcular")
        // Algo de trabajo para que haya CPU que medir.
        var x = 0.0
        let end = Date().addingTimeInterval(0.4)
        while Date() < end { x += sin(x) + 1 }
        XCTAssertGreaterThan(x, 0)
        let second = sampler.sample()
        let load = try XCTUnwrap(second.cpuLoad)
        XCTAssertTrue((0...1).contains(load))
        XCTAssertGreaterThan(second.cpuCount, 0)
        XCTAssertEqual(second.loadAverage.count, 3)
        XCTAssertGreaterThan(try XCTUnwrap(second.uptime), 60)
        XCTAssertFalse(second.topCPU.isEmpty, "Este mismo proceso de pruebas ha usado CPU")
        XCTAssertTrue(second.topCPU.allSatisfy { $0.percent >= 0.5 && $0.percent < Double(second.cpuCount) * 100 + 1 })
        if let battery = second.battery {
            if let health = battery.health { XCTAssertTrue((1...100).contains(health)) }
            if let charge = battery.charge { XCTAssertTrue((0...100).contains(charge)) }
        }
        print("VITALS cpu=\(Int(load * 100))% núcleos=\(second.cpuCount) carga=\(second.loadAverage.map { String(format: "%.2f", $0) }) térmico=\(second.thermal) encendido=\(Int((second.uptime ?? 0) / 3600)) h batería=\(second.battery.map { "\($0.charge ?? -1)% salud \($0.health ?? -1)% ciclos \($0.cycleCount ?? -1) \($0.condition ?? "")" } ?? "no") top=\(second.topCPU.prefix(3).map { "\($0.name) \(Int($0.percent))%" })")
    }
}
