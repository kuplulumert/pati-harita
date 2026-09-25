import XCTest
@testable import AnimalKit

final class FormattingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testTimeAgo() {
        XCTAssertEqual(Formatting.timeAgo(now.addingTimeInterval(-20), now: now), "az önce")
        XCTAssertEqual(Formatting.timeAgo(now.addingTimeInterval(-12 * 60), now: now), "12 dk önce")
        XCTAssertEqual(Formatting.timeAgo(now.addingTimeInterval(-3 * 3600 - 59), now: now), "3 sa önce")
        XCTAssertEqual(Formatting.timeAgo(now.addingTimeInterval(-2 * 86400), now: now), "2 gün önce")
        // İstemci saati biraz gerideyse "gelecekte" görünmesin.
        XCTAssertEqual(Formatting.timeAgo(now.addingTimeInterval(30), now: now), "az önce")
    }

    func testRemaining() {
        XCTAssertEqual(Formatting.remaining(until: now.addingTimeInterval(40 * 60), now: now), "40 dk")
        XCTAssertEqual(Formatting.remaining(until: now.addingTimeInterval(2 * 3600), now: now), "2 sa")
        XCTAssertEqual(Formatting.remaining(until: now.addingTimeInterval(2 * 3600 + 15 * 60), now: now), "2 sa 15 dk")
        XCTAssertEqual(Formatting.remaining(until: now.addingTimeInterval(5), now: now), "1 dk")
    }

    func testDistance() {
        XCTAssertEqual(Formatting.distance(meters: 3), "10 m")
        XCTAssertEqual(Formatting.distance(meters: 347), "350 m")
        XCTAssertEqual(Formatting.distance(meters: 996), "1,0 km")
        XCTAssertEqual(Formatting.distance(meters: 1_240), "1,2 km")
        XCTAssertEqual(Formatting.distance(meters: 15_600), "16 km")
    }

    func testSeenCountBadge() {
        // Yalnızca işareti koyan bildirdiyse rozet yok.
        XCTAssertNil(Formatting.seenCountBadge(0))
        XCTAssertNil(Formatting.seenCountBadge(1))
        XCTAssertEqual(Formatting.seenCountBadge(2), "2")
        XCTAssertEqual(Formatting.seenCountBadge(10), "10")
        XCTAssertEqual(Formatting.seenCountBadge(99), "99")
        XCTAssertEqual(Formatting.seenCountBadge(100), "99+")
        XCTAssertEqual(Formatting.seenCountBadge(250), "99+")
    }

    func testSeenCount() {
        XCTAssertNil(Formatting.seenCount(1))
        XCTAssertEqual(Formatting.seenCount(2), "2 kişi bildirdi")
        XCTAssertEqual(Formatting.seenCount(100), "100 kişi bildirdi")
    }
}
