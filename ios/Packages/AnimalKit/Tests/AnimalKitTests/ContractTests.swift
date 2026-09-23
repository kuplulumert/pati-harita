import XCTest
@testable import AnimalKit

/// iOS sabitlerinin shared/report-contract.json (ve dolayısıyla Firestore kuralları) ile aynı olduğunu doğrular.
final class ContractTests: XCTestCase {
    private var contract: ReportContract!

    override func setUpWithError() throws {
        contract = try SharedFixtures.load("report-contract.json", as: ReportContract.self)
    }

    func testSpeciesMatchContract() {
        XCTAssertEqual(Set(Species.allCases.map(\.rawValue)), Set(contract.species))
    }

    func testNeedLifetimesMatchContract() {
        XCTAssertEqual(Set(Need.allCases.map(\.rawValue)), Set(contract.needs.keys))
        for need in Need.allCases {
            XCTAssertEqual(need.lifetimeHours, contract.needs[need.rawValue]?.lifetimeHours, need.rawValue)
        }
    }

    func testLifecycleConstantsMatchContract() {
        XCTAssertEqual(ReportLifecycle.claimDuration, TimeInterval(contract.claimHours) * 3600)
        XCTAssertEqual(ReportLifecycle.goneThreshold, contract.goneThreshold)
        XCTAssertEqual(ReportLifecycle.retention, TimeInterval(contract.retentionDays) * 24 * 3600)
        XCTAssertEqual(ReportLifecycle.geohashPrecision, contract.geohashPrecision)
    }
}
