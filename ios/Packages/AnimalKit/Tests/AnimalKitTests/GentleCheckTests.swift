import XCTest
@testable import AnimalKit

/// "Yardıma ihtiyacı var mı?" kontrolü ve uzaklık sorusu ne zaman sorulur.
final class GentleCheckTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let here = Coordinate(latitude: 40.9903, longitude: 29.029)
    /// ~2,4 km kuzey.
    private var far: Coordinate { Coordinate(latitude: here.latitude + 0.0216, longitude: here.longitude) }
    /// ~890 m kuzey.
    private var near: Coordinate { Coordinate(latitude: here.latitude + 0.008, longitude: here.longitude) }

    private func distance(
        need: Need = .food,
        pin: Coordinate? = nil,
        fixAge: TimeInterval = 60,
        accuracy: Double = 30
    ) -> Double? {
        GentleCheck.distanceToAsk(
            need: need,
            pin: pin ?? far,
            fix: here,
            fixAt: now.addingTimeInterval(-fixAge),
            horizontalAccuracy: accuracy,
            at: now
        )
    }

    // MARK: Kontrol

    func testOnlyLightNeedsAreChecked() {
        XCTAssertEqual(Need.allCases.filter(\.needsGentleCheck), [.food, .shelter])
        for need in Need.allCases {
            let reason = GentleCheck.reason(for: need, lightReportsSoFar: 0, recentReports: 0)
            XCTAssertEqual(reason != nil, need.needsGentleCheck, need.rawValue)
        }
    }

    func testFirstThreeLightReportsThenOnlyOnAPattern() {
        XCTAssertEqual(GentleCheck.reason(for: .food, lightReportsSoFar: 0, recentReports: 0), .intro)
        XCTAssertEqual(GentleCheck.reason(for: .shelter, lightReportsSoFar: 2, recentReports: 1), .intro)
        XCTAssertNil(GentleCheck.reason(for: .food, lightReportsSoFar: 3, recentReports: 1))
        XCTAssertEqual(GentleCheck.reason(for: .food, lightReportsSoFar: 3, recentReports: 2), .recent(count: 2))
        XCTAssertEqual(GentleCheck.reason(for: .shelter, lightReportsSoFar: 12, recentReports: 5), .recent(count: 5))
        // Örüntü ilk işaretlerde de söylenir ("Son 24 saatte 2 işaret koydun.").
        XCTAssertEqual(GentleCheck.reason(for: .food, lightReportsSoFar: 1, recentReports: 2), .recent(count: 2))
        // Ağır ihtiyaçta hiç sorulmaz.
        XCTAssertNil(GentleCheck.reason(for: .injured, lightReportsSoFar: 0, recentReports: 9))
        XCTAssertNil(GentleCheck.reason(for: .emergency, lightReportsSoFar: 0, recentReports: 9))
    }

    func testRecentWindowIs24Hours() {
        XCTAssertTrue(GentleCheck.isRecent(now.addingTimeInterval(-23.9 * 3600), at: now))
        XCTAssertFalse(GentleCheck.isRecent(now.addingTimeInterval(-24 * 3600), at: now))
    }

    // MARK: Uzaklık sorusu

    func testAsksWhenPinIsFarFromAFreshAccurateFix() {
        XCTAssertEqual(distance().map { Formatting.distance(meters: $0) }, "2,4 km")
        XCTAssertNil(distance(pin: near))
        // Ağır ihtiyaçlarda da sorulur; yalnızca acil yardımda sorulmaz.
        XCTAssertNotNil(distance(need: .injured))
        XCTAssertNil(distance(need: .emergency))
    }

    func testNeverAsksWithStaleOrCoarseFix() {
        XCTAssertNotNil(distance(fixAge: 120))
        XCTAssertNil(distance(fixAge: 121))
        XCTAssertNotNil(distance(accuracy: 100))
        XCTAssertNil(distance(accuracy: 101))
        // CoreLocation geçersiz konumda negatif doğruluk verir.
        XCTAssertNil(distance(accuracy: -1))
    }
}
