import XCTest
import CoreGraphics
@testable import SpaceCore

final class TreemapAndMemoryTests: XCTestCase {
    func testTreemapAreasAreProportionalInsideAndDisjoint() {
        let values: [Double] = [600, 300, 120, 60, 40, 20, 0]
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        let rects = Treemap.layout(values, in: bounds)
        XCTAssertEqual(rects.count, values.count)
        XCTAssertEqual(rects.last, .zero, "Un valor cero no ocupa área")
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) where value > 0 {
            let expected = Double(bounds.width * bounds.height) * value / total
            XCTAssertEqual(Double(rect.width * rect.height), expected, accuracy: expected * 0.001)
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect), "\(rect) fuera de \(bounds)")
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.01, "\(i) y \(j) se solapan")
            }
        }
    }

    func testTreemapPrefersSquareishPieces() {
        let rects = Treemap.layout([1, 1, 1, 1], in: CGRect(x: 0, y: 0, width: 200, height: 200))
        for rect in rects { XCTAssertEqual(rect.width / rect.height, 1, accuracy: 0.01) }
    }

    func testTreemapLevelAddsRestSoAreasMatchTotal() throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("map-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, size) in [("grande/a.bin", 3_000_000), ("mediana/b.bin", 1_500_000), ("suelto.bin", 2_000_000)] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 2, count: size).write(to: url)
        }
        let report = try Scanner.scan(root: root, options: ScanOptions(folderDepth: 2, minFolderBytes: 1_000_000))
        let level = Treemap.children(of: report.root, in: report)
        XCTAssertEqual(Set(level.map(\.name)), ["grande", "mediana", "…"])
        XCTAssertEqual(level.reduce(0) { $0 + $1.allocatedBytes }, report.totalAllocated)
        XCTAssertTrue(Treemap.children(of: report.root + "/grande", in: report).allSatisfy { $0.name == "…" } )
    }

    func testMemoryDiagnosticsReadPressureAndApps() {
        let d = Diagnostics.read()
        XCTAssertNotNil(d.pressureLevel)
        XCTAssertNotNil(d.pressure)
        XCTAssertFalse(d.apps.isEmpty, "Al menos el propio proceso de pruebas es visible")
        XCTAssertEqual(d.apps.map(\.bytes), d.apps.map(\.bytes).sorted(by: >))
        XCTAssertLessThanOrEqual(d.apps.count, 12)
    }
}
