import XCTest
@testable import AnimalKit

/// "En iyi yakın okuma": hangi konum okuması eldekinin yerini alır.
final class LocationFixTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let here = Coordinate(latitude: 40.9903, longitude: 29.029)

    private func reading(accuracy: Double, at second: TimeInterval) -> LocationFix {
        LocationFix(coordinate: here, timestamp: t0.addingTimeInterval(second), horizontalAccuracy: accuracy)
    }

    func testConstants() {
        XCTAssertEqual(LocationFix.replaceAccuracySlack, 20)
        XCTAssertEqual(LocationFix.replaceAfter, 15)
    }

    func testFirstValidReadingIsTaken() {
        XCTAssertTrue(LocationFix.shouldReplace(current: nil, with: reading(accuracy: 500, at: 0)))
        XCTAssertFalse(LocationFix.shouldReplace(current: nil, with: reading(accuracy: -1, at: 0)))
    }

    func testOlderCachedDeliveryIsIgnored() {
        // Yeniden başlatınca önce önbellekteki eski konum gelir; doğruluğu iyi olsa da alınmaz.
        let current = reading(accuracy: 30, at: 60)
        XCTAssertFalse(LocationFix.shouldReplace(current: current, with: reading(accuracy: 5, at: 10)))
        XCTAssertFalse(LocationFix.shouldReplace(current: current, with: reading(accuracy: 5, at: 59.9)))
        // Aynı an, daha iyi doğruluk: alınır.
        XCTAssertTrue(LocationFix.shouldReplace(current: current, with: reading(accuracy: 5, at: 60)))
    }

    func testCoarseReadingReplacesOnlyWhenMuchNewer() {
        let current = reading(accuracy: 10, at: 0)
        XCTAssertFalse(LocationFix.shouldReplace(current: current, with: reading(accuracy: 500, at: 5)))
        XCTAssertFalse(LocationFix.shouldReplace(current: current, with: reading(accuracy: 500, at: 15)))
        XCTAssertTrue(LocationFix.shouldReplace(current: current, with: reading(accuracy: 500, at: 16)))
    }

    func testSlightlyWorseReadingIsTaken() {
        let current = reading(accuracy: 10, at: 0)
        XCTAssertTrue(LocationFix.shouldReplace(current: current, with: reading(accuracy: 25, at: 1)))
        XCTAssertTrue(LocationFix.shouldReplace(current: current, with: reading(accuracy: 30, at: 1)))
        XCTAssertFalse(LocationFix.shouldReplace(current: current, with: reading(accuracy: 31, at: 1)))
        XCTAssertTrue(LocationFix.shouldReplace(current: current, with: reading(accuracy: 5, at: 1)))
    }

    func testInvalidAccuracyIsIgnored() {
        let current = reading(accuracy: 10, at: 0)
        XCTAssertFalse(LocationFix.shouldReplace(current: current, with: reading(accuracy: -1, at: 1)))
        XCTAssertFalse(LocationFix.shouldReplace(current: current, with: reading(accuracy: -1, at: 600)))
        XCTAssertFalse(LocationFix.shouldReplace(current: current, with: reading(accuracy: .nan, at: 600)))
    }

    func testAge() {
        XCTAssertEqual(reading(accuracy: 5, at: 0).age(at: t0.addingTimeInterval(42)), 42)
        XCTAssertEqual(reading(accuracy: 5, at: 3).age(at: t0), -3)
    }
}
