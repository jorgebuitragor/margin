import XCTest
@testable import SpaceCore

final class SpaceAlertTests: XCTestCase {
    let gb: Int64 = 1_000_000_000
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNoAlertAboveTheThreshold() {
        XCTAssertFalse(SpaceAlert.shouldNotify(available: 20 * gb, threshold: 15 * gb, lastAlert: nil, lastAvailable: nil, now: now))
    }

    func testFirstTimeBelowTheThresholdAlerts() {
        XCTAssertTrue(SpaceAlert.shouldNotify(available: 12 * gb, threshold: 15 * gb, lastAlert: nil, lastAvailable: nil, now: now))
    }

    func testAtMostOncePerDayUnlessItKeepsDropping() {
        let anHourAgo = now.addingTimeInterval(-3600)
        XCTAssertFalse(SpaceAlert.shouldNotify(available: 12 * gb, threshold: 15 * gb, lastAlert: anHourAgo, lastAvailable: 12 * gb, now: now), "Mismo espacio una hora después: no repite")
        XCTAssertTrue(SpaceAlert.shouldNotify(available: 9 * gb, threshold: 15 * gb, lastAlert: anHourAgo, lastAvailable: 12 * gb, now: now), "Bajó 3 GB más: avisa otra vez")
        XCTAssertTrue(SpaceAlert.shouldNotify(available: 12 * gb, threshold: 15 * gb, lastAlert: now.addingTimeInterval(-25 * 3600), lastAvailable: 12 * gb, now: now), "Pasó un día: recuerda")
    }
}
