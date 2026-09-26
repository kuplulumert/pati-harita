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

    func testStatusesMatchContract() {
        XCTAssertEqual(Set(ReportStatus.allCases.map(\.rawValue)), Set(contract.statuses))
    }

    func testNeedLifetimesMatchContract() {
        XCTAssertEqual(Set(Need.allCases.map(\.rawValue)), Set(contract.needs.keys))
        for need in Need.allCases {
            XCTAssertEqual(need.lifetimeHours, contract.needs[need.rawValue]?.lifetimeHours, need.rawValue)
        }
    }

    func testNeedClosingValuesMatchContract() {
        for need in Need.allCases {
            XCTAssertEqual(need.closeCost, contract.needs[need.rawValue]?.closeCost, need.rawValue)
            XCTAssertEqual(need.demoteMinutes, contract.needs[need.rawValue]?.demoteMinutes, need.rawValue)
        }
    }

    func testLifecycleConstantsMatchContract() {
        XCTAssertEqual(ReportLifecycle.claimDuration, TimeInterval(contract.claimHours) * 3600)
        XCTAssertEqual(ReportLifecycle.claimStale, TimeInterval(contract.claimStaleMinutes) * 60)
        XCTAssertEqual(ReportLifecycle.undoWindow, TimeInterval(contract.undoMinutes) * 60)
        XCTAssertEqual(ReportLifecycle.goneThreshold, contract.goneThreshold)
        XCTAssertEqual(ReportLifecycle.maxSeenBy, contract.maxSeenBy)
        XCTAssertEqual(ReportLifecycle.maxDisputed, contract.maxDisputed)
        XCTAssertEqual(ReportLifecycle.maxAge, TimeInterval(contract.maxReportAgeDays) * 24 * 3600)
        XCTAssertEqual(ReportLifecycle.retention, TimeInterval(contract.retentionDays) * 24 * 3600)
        XCTAssertEqual(ReportLifecycle.geohashPrecision, contract.geohashPrecision)
    }

    func testBudgetConstantsMatchContract() {
        XCTAssertEqual(Budget.window, TimeInterval(contract.budgetWindowHours) * 3600)
        XCTAssertEqual(Budget.newAccountAge, TimeInterval(contract.newAccountHours) * 3600)
        XCTAssertEqual(Budget.maxCreates, contract.createQuota.perWindow)
        XCTAssertEqual(Budget.maxCreatesFirstDay, contract.createQuota.firstDay)
        XCTAssertEqual(Budget.closePoints, contract.closeBudget.points)
        XCTAssertEqual(Budget.credibleMaxDisputed, contract.closeBudget.maxDisputed)
        // Pencere payı, kuralların istemci saati toleransıyla aynı.
        XCTAssertEqual(Budget.resetMargin, TimeInterval(contract.clockSkewMinutes) * 60)
    }

    func testClosingDisplayMatchesContract() {
        let display = contract.closingDisplay
        XCTAssertEqual(ClosingDisplay.dayStartHour, display.dayStartHour)
        XCTAssertEqual(ClosingDisplay.dayEndHour, display.dayEndHour)
        XCTAssertEqual(ClosingDisplay.utcOffsetHours, display.utcOffsetHours)
        XCTAssertEqual(ClosingDisplay.streetDotMaxRadius, display.streetDotMaxRadiusMeters)
        XCTAssertEqual(ClosingDisplay.closerUndoToastDuration, display.closerUndoToastSeconds)
        XCTAssertEqual(ClosingMode.allCases.map(\.rawValue), display.modes)
        XCTAssertEqual(ClosingMode.fallback.rawValue, display.defaultMode)
    }
}
