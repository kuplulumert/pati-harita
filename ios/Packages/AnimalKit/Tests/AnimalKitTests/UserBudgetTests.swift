import XCTest
@testable import AnimalKit

/// `users/{uid}` hakları: yeni işaret kotası, kanıtlı kapatma bütçesi ve kanıtlılık.
final class UserBudgetTests: XCTestCase {
    private let alice = "alice" // işareti koyan
    private let bob = "bob" // kapatan
    private let dan = "dan"
    private let eve = "eve"
    /// 2026-09-21 00.00, Türkiye saati.
    private let midnight = Date(timeIntervalSince1970: 1_789_938_000)

    private func hours(_ value: Double) -> Date { midnight.addingTimeInterval(value * 3600) }

    private func record(
        createdAt: Date,
        createWindow: Date? = nil,
        createUsed: Int = 0,
        closeWindow: Date? = nil,
        closeUsed: Int = 0
    ) -> UserRecord {
        UserRecord(
            createdAt: createdAt,
            createWindow: createWindow ?? createdAt,
            createUsed: createUsed,
            closeWindow: closeWindow ?? createdAt,
            closeUsed: closeUsed
        )
    }

    /// 09.00'da alice'in koyduğu işaret; `closers` sırayla "Çözüldü" deyip alice'in itirazını aldı.
    private func report(need: Need = .injured, disputedBy closers: [String] = []) throws -> Report {
        var report = ReportLifecycle.makeReport(
            id: "r1",
            species: .dog,
            need: need,
            at: Coordinate(latitude: 41.0082, longitude: 28.9784),
            reporterID: alice,
            now: hours(9)
        )
        for (index, closer) in closers.enumerated() {
            let round = hours(9).addingTimeInterval(Double(index + 1) * 600)
            report = try ReportLifecycle.apply(.resolve, to: report, by: closer, at: round)
            report = try ReportLifecycle.apply(.dispute, to: report, by: alice, at: round.addingTimeInterval(300))
        }
        return report
    }

    // MARK: Yeni işaret

    func testNewRecordStartsEmpty() {
        XCTAssertEqual(
            UserRecord.new(at: midnight),
            UserRecord(createdAt: midnight, createWindow: midnight, createUsed: 0, closeWindow: midnight, closeUsed: 0)
        )
    }

    func testFirstDayAllowsFiveCreates() {
        var user = UserRecord.new(at: hours(8))
        XCTAssertTrue(Budget.isNewAccount(user, at: hours(9)))
        XCTAssertEqual(Budget.createLimit(user, at: hours(9)), 5)
        for index in 1...5 {
            XCTAssertNil(Budget.nextCreateAt(user, at: hours(9)))
            guard let spent = Budget.spendCreate(user, at: hours(9)) else {
                return XCTFail("\(index). işaret")
            }
            XCTAssertEqual(spent.spend, .sameWindow)
            user = spent.record
            XCTAssertEqual(Budget.remainingCreates(user, at: hours(9)), 5 - index)
        }
        XCTAssertNil(Budget.spendCreate(user, at: hours(9)))

        // Pencere ve ilk gün birlikte biter; istemci sunucu saatine 15 dk pay bırakır.
        XCTAssertEqual(Budget.nextCreateAt(user, at: hours(9)), hours(8 + 24.25))
        XCTAssertNil(Budget.spendCreate(user, at: hours(8 + 24.2)))
        let nextDay = Budget.spendCreate(user, at: hours(8 + 24.25))
        XCTAssertEqual(nextDay?.spend, .newWindow)
        XCTAssertEqual(nextDay?.record.createUsed, 1)
        XCTAssertEqual(nextDay?.record.createWindow, hours(8 + 24.25))
        XCTAssertEqual(Budget.createLimit(user, at: hours(8 + 24.25)), 10)
    }

    func testAgedAccountAllowsTenPerWindow() {
        let nine = record(createdAt: hours(-72), createWindow: hours(10), createUsed: 9)
        XCTAssertFalse(Budget.isNewAccount(nine, at: hours(12)))
        XCTAssertEqual(Budget.createLimit(nine, at: hours(12)), 10)
        XCTAssertEqual(Budget.remainingCreates(nine, at: hours(12)), 1)

        let tenth = Budget.spendCreate(nine, at: hours(12))
        XCTAssertEqual(tenth?.spend, .sameWindow)
        XCTAssertEqual(tenth?.record.createUsed, 10)
        XCTAssertEqual(tenth?.record.createWindow, hours(10))

        let full = record(createdAt: hours(-72), createWindow: hours(10), createUsed: 10)
        XCTAssertNil(Budget.spendCreate(full, at: hours(12)))
        XCTAssertEqual(Budget.remainingCreates(full, at: hours(12)), 0)
        XCTAssertEqual(Budget.nextCreateAt(full, at: hours(12)), hours(34.25))
        XCTAssertEqual(Budget.remainingCreates(full, at: hours(34.25)), 10)
    }

    func testCreateWindowBoundaryKeepsSameWindowInsideMargin() {
        let user = record(createdAt: hours(-72), createWindow: hours(0), createUsed: 4)
        // Sunucu saati 24 saati geçmiş olabilir ama emin değiliz: aynı pencerede artır (her zaman kabul edilir).
        let early = Budget.spendCreate(user, at: hours(24.1))
        XCTAssertEqual(early?.spend, .sameWindow)
        XCTAssertEqual(early?.record.createUsed, 5)

        let late = Budget.spendCreate(user, at: hours(24.25))
        XCTAssertEqual(late?.spend, .newWindow)
        XCTAssertEqual(late?.record.createUsed, 1)
        XCTAssertEqual(late?.record.createWindow, hours(24.25))

        // Sunucu yeni pencereyi reddederse diğer dalla yeniden denenir.
        XCTAssertEqual(Budget.spendCreate(user, at: hours(24.25), branch: .sameWindow)?.createUsed, 5)
        XCTAssertEqual(Budget.spendCreate(user, at: hours(24.1), branch: .newWindow)?.createUsed, 1)
    }

    func testNextCreateAtRoundsUpToWholeMinute() {
        let window = midnight.addingTimeInterval(14 * 3600 + 5 * 60 + 30) // 14.05.30
        let full = record(createdAt: hours(-72), createWindow: window, createUsed: 10)
        let next = Budget.nextCreateAt(full, at: hours(15))
        XCTAssertEqual(next, hours(24 + 14).addingTimeInterval(21 * 60)) // 14.20.30 → 14.21
        XCTAssertEqual(next.map { Formatting.clock($0, now: hours(15)) }, "yarın 14.21")
    }

    // MARK: Kanıtlı kapatma bütçesi

    func testCloseBudgetSpendsNeedCost() {
        var user = record(createdAt: hours(-72), closeWindow: hours(1))
        // 3 ağır (6 puan) + 2 hafif = 8 puan.
        let steps: [(need: Need, used: Int)] = [(.injured, 2), (.babies, 4), (.vet, 6), (.food, 7), (.other, 8)]
        for step in steps {
            guard let spent = Budget.spendClose(user, cost: step.need.closeCost, at: hours(2)) else {
                return XCTFail(step.need.rawValue)
            }
            XCTAssertEqual(spent.spend, .sameWindow)
            XCTAssertEqual(spent.record.closeUsed, step.used)
            XCTAssertEqual(spent.record.closeWindow, hours(1))
            user = spent.record
        }
        XCTAssertNil(Budget.spendClose(user, cost: 1, at: hours(2)))
    }

    func testCloseWindowResetsOnlyAfterMargin() {
        let spent = record(createdAt: hours(-72), closeWindow: hours(0), closeUsed: 8)
        XCTAssertNil(Budget.spendClose(spent, cost: 1, at: hours(24)))
        XCTAssertNil(Budget.spendClose(spent, cost: 1, at: hours(24.2)))
        let reset = Budget.spendClose(spent, cost: 2, at: hours(24.25))
        XCTAssertEqual(reset?.spend, .newWindow)
        XCTAssertEqual(reset?.record.closeUsed, 2)
        XCTAssertEqual(reset?.record.closeWindow, hours(24.25))
        // Diğer dalla yeniden deneme: aynı pencerede puan kalmadı.
        XCTAssertNil(Budget.spendClose(spent, cost: 2, at: hours(24.25), branch: .sameWindow))

        let partly = record(createdAt: hours(-72), closeWindow: hours(0), closeUsed: 3)
        let inMargin = Budget.spendClose(partly, cost: 2, at: hours(24.1))
        XCTAssertEqual(inMargin?.spend, .sameWindow)
        XCTAssertEqual(inMargin?.record.closeUsed, 5)
        XCTAssertEqual(inMargin?.record.closeWindow, hours(0))
    }

    func testCloseCostMustMatchRules() {
        let user = UserRecord.new(at: midnight)
        XCTAssertNil(Budget.spendClose(user, cost: 0, at: hours(1)))
        XCTAssertNil(Budget.spendClose(user, cost: 3, at: hours(1)))
        XCTAssertEqual(Budget.spendClose(user, cost: 1, at: hours(1))?.record.closeUsed, 1)
    }

    // MARK: Kanıtlılık

    func testCredibilityMatrix() throws {
        let now = hours(10)
        let fresh = try report()
        let aged = record(createdAt: hours(-48))

        XCTAssertEqual(ReportLifecycle.credibility(of: fresh, by: bob, record: nil, at: now), .noRecord)
        XCTAssertEqual(ReportLifecycle.credibility(of: fresh, by: bob, record: aged, at: now), .credible)

        // İtiraz: bir tane kanıtlı kapatmayı engellemez, iki tane engeller.
        XCTAssertEqual(ReportLifecycle.credibility(of: try report(disputedBy: [dan]), by: bob, record: aged, at: now), .credible)
        XCTAssertEqual(
            ReportLifecycle.credibility(of: try report(disputedBy: [dan, eve]), by: bob, record: aged, at: now),
            .disputed
        )

        // Hesap yaşı: 23 saatlik hesap yeni sayılır; işareti koyan için aranmaz.
        let young = record(createdAt: hours(-13))
        XCTAssertEqual(ReportLifecycle.credibility(of: fresh, by: bob, record: young, at: now), .newAccount)
        XCTAssertEqual(ReportLifecycle.credibility(of: fresh, by: alice, record: young, at: now), .credible)
        // İstemci payı: 24 sa 10 dk henüz yeni, 24 sa 15 dk değil.
        let almost = record(createdAt: now.addingTimeInterval(-(24 * 3600 + 10 * 60)))
        XCTAssertEqual(ReportLifecycle.credibility(of: fresh, by: bob, record: almost, at: now), .newAccount)
        let justAged = record(createdAt: now.addingTimeInterval(-(24 * 3600 + 15 * 60)))
        XCTAssertEqual(ReportLifecycle.credibility(of: fresh, by: bob, record: justAged, at: now), .credible)

        // Bütçe: ağır ihtiyaç 2 puan, hafif 1.
        let sevenUsed = record(createdAt: hours(-48), closeWindow: hours(1), closeUsed: 7)
        XCTAssertEqual(ReportLifecycle.credibility(of: fresh, by: bob, record: sevenUsed, at: now), .budgetUsed)
        XCTAssertEqual(
            ReportLifecycle.credibility(of: try report(need: .food), by: bob, record: sevenUsed, at: now),
            .credible
        )
    }

    func testCredibilityOrder() throws {
        let now = hours(10)
        let fresh = try report()
        let youngAndSpent = record(createdAt: hours(-13), closeWindow: hours(1), closeUsed: 8)
        // İtiraz yaştan ve bütçeden önce, yaş bütçeden önce denetlenir.
        XCTAssertEqual(
            ReportLifecycle.credibility(of: try report(disputedBy: [dan, eve]), by: bob, record: youngAndSpent, at: now),
            .disputed
        )
        XCTAssertEqual(ReportLifecycle.credibility(of: fresh, by: bob, record: youngAndSpent, at: now), .newAccount)
        XCTAssertEqual(ReportLifecycle.credibility(of: fresh, by: alice, record: youngAndSpent, at: now), .budgetUsed)
    }

    /// Deponun kanıtlı "Çözüldü" akışı: öneri mi, kanıtlı mı, harcama ve işaretin yeni hâli.
    func testCredibleCloseFlow() throws {
        let now = hours(10)
        let open = try report()
        let user = record(createdAt: hours(-48), closeWindow: hours(1))
        XCTAssertTrue(ReportLifecycle.wouldStartClosing(.resolve, on: open, by: bob, at: now))
        XCTAssertEqual(ReportLifecycle.credibility(of: open, by: bob, record: user, at: now), .credible)
        let spent = Budget.spendClose(user, cost: open.need.closeCost, at: now)
        XCTAssertEqual(spent?.spend, .sameWindow)
        XCTAssertEqual(spent?.record.closeUsed, 2)
        let proposed = try ReportLifecycle.apply(.resolve, to: open, by: bob, at: now, credible: true)
        XCTAssertEqual(proposed.closing, Closing(reason: .resolved, userID: bob, at: now, credible: true))
    }
}
