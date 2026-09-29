import XCTest
@testable import AnimalKit

/// "Yardıma ihtiyacı var mı?" kontrolü ne zaman sorulur.
final class GentleCheckTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

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
}
