import XCTest
@testable import AnimalKit

/// "Yardım gerekmiyor" → "Hayvan orada ama iyi görünüyor" (`reportUnneeded`): yalnızca mama işaretinde,
/// "Çözüldü" ile aynı yoldan ama `unneeded` nedeniyle (kurallardaki `isUnneeded`).
final class UnneededTests: ReportTestCase {
    func testOnlyFoodReportsAllowIt() {
        for need in Need.allCases where !need.allowsUnneeded {
            // İşareti koyan tek tanık olsa da ağır ihtiyacı böyle kapatamaz.
            for user in [alice, cara] {
                XCTAssertThrowsError(
                    try ReportLifecycle.apply(.reportUnneeded, to: makeReport(need: need), by: user, at: minutes(1)),
                    "\(need) \(user)"
                ) {
                    XCTAssertEqual($0 as? ReportError, .notAllowed)
                }
            }
        }
    }

    func testReporterAloneClosesAsFalseAlarm() throws {
        let food = makeReport(need: .food)
        XCTAssertFalse(ReportLifecycle.wouldStartClosing(.reportUnneeded, on: food, by: alice, at: minutes(5)))
        let closed = try ReportLifecycle.apply(.reportUnneeded, to: food, by: alice, at: minutes(5))
        XCTAssertEqual(closed.status, .closed)
        XCTAssertEqual(closed.closedReason, .unneeded)
        XCTAssertEqual(closed.closedAt, minutes(5))
        XCTAssertEqual(closed.purgeAt, minutes(5).addingTimeInterval(ReportLifecycle.retention))
        XCTAssertNil(closed.closing)
        XCTAssertEqual(closed.phase(for: cara, at: minutes(6)), .closed(.unneeded))
        XCTAssertEqual(closed.changedFields(from: food), [.status, .closedReason, .closedAt, .purgeAt])
    }

    func testOthersOnlyPropose() throws {
        let seen = try seenReport(need: .food)
        XCTAssertTrue(ReportLifecycle.wouldStartClosing(.reportUnneeded, on: seen, by: cara, at: minutes(10)))
        let byCara = try ReportLifecycle.apply(.reportUnneeded, to: seen, by: cara, at: minutes(10))
        XCTAssertEqual(byCara.status, .closing)
        XCTAssertEqual(byCara.closing, Closing(reason: .unneeded, userID: cara, at: minutes(10), credible: false))
        XCTAssertNil(byCara.closedReason)
        // Ömür kısalmaz.
        XCTAssertEqual(byCara.expiresAt, seen.expiresAt)
        XCTAssertEqual(byCara.changedFields(from: seen), [.status, .closingReason, .closingBy, .closingAt, .closingCredible])
        XCTAssertEqual(
            byCara.phase(for: dan, at: minutes(11)),
            .closing(reason: .unneeded, since: minutes(10), byMe: false, credible: false)
        )

        // Başkası da gördükten sonra işareti koyan da yalnızca önerir.
        let byAlice = try ReportLifecycle.apply(.reportUnneeded, to: seen, by: alice, at: minutes(10))
        XCTAssertEqual(byAlice.status, .closing)
        XCTAssertEqual(byAlice.closing?.userID, alice)

        // Kimse görmemiş olsa da yoldan geçen yalnızca önerir; bütçesi varsa kanıtlı.
        let byDan = try ReportLifecycle.apply(.reportUnneeded, to: makeReport(need: .food), by: dan, at: minutes(1), credible: true)
        XCTAssertEqual(byDan.closing, Closing(reason: .unneeded, userID: dan, at: minutes(1), credible: true))
    }

    func testRespectsFreshClaimAndDisputes() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: seenReport(need: .food), by: bob, at: minutes(2))
        XCTAssertThrowsError(try ReportLifecycle.apply(.reportUnneeded, to: claimed, by: dan, at: minutes(46))) {
            XCTAssertEqual($0 as? ReportError, .claimTooFresh)
        }
        XCTAssertEqual(try ReportLifecycle.apply(.reportUnneeded, to: claimed, by: dan, at: minutes(47)).closing?.userID, dan)
        // İlgilenen ve işareti koyan beklemez.
        XCTAssertEqual(try ReportLifecycle.apply(.reportUnneeded, to: claimed, by: bob, at: minutes(3)).closing?.userID, bob)
        XCTAssertEqual(try ReportLifecycle.apply(.reportUnneeded, to: claimed, by: alice, at: minutes(3)).closing?.userID, alice)

        // Önerisine itiraz edilen kişi bu işarette bir daha "Yardım gerekmiyor" diyemez.
        let proposed = try ReportLifecycle.apply(.reportUnneeded, to: seenReport(need: .food), by: bob, at: minutes(30))
        let objected = try ReportLifecycle.apply(.dispute, to: proposed, by: cara, at: minutes(35))
        XCTAssertEqual(objected.status, .open)
        XCTAssertEqual(objected.disputed, [bob])
        XCTAssertEqual(objected.objectors, [cara])
        XCTAssertThrowsError(try ReportLifecycle.apply(.reportUnneeded, to: objected, by: bob, at: minutes(36))) {
            XCTAssertEqual($0 as? ReportError, .disputed)
        }
        XCTAssertFalse(ReportLifecycle.availableActions(for: objected, userID: bob, at: minutes(36)).contains(.reportUnneeded))
    }

    func testSecondPersonConfirms() throws {
        let byBob = try ReportLifecycle.apply(.reportUnneeded, to: seenReport(need: .food), by: bob, at: minutes(30))
        XCTAssertEqual(ReportLifecycle.availableActions(for: byBob, userID: alice, at: minutes(31)), [.confirmClosing, .dispute])
        XCTAssertEqual(ReportLifecycle.availableActions(for: byBob, userID: cara, at: minutes(31)), [.dispute])
        let agreed = try ReportLifecycle.apply(.confirmClosing, to: byBob, by: alice, at: minutes(31))
        XCTAssertEqual(agreed.status, .closed)
        XCTAssertEqual(agreed.closedReason, .unneeded)
        XCTAssertEqual(agreed.closing, byBob.closing) // geçmiş olarak kalır

        // İşareti koyan önerdiyse hayvanı gören başka biri onaylar.
        let byAlice = try ReportLifecycle.apply(.reportUnneeded, to: seenReport(need: .food), by: alice, at: minutes(30))
        XCTAssertTrue(ReportLifecycle.canConfirmClosing(byAlice, by: cara))
        XCTAssertFalse(ReportLifecycle.canConfirmClosing(byAlice, by: dan))
        XCTAssertEqual(try ReportLifecycle.apply(.confirmClosing, to: byAlice, by: cara, at: minutes(31)).closedReason, .unneeded)
    }

    func testUndoKeepsLiveClaimAndExpiryKeepsReason() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: seenReport(need: .food), by: bob, at: minutes(2))
        let proposed = try ReportLifecycle.apply(.reportUnneeded, to: claimed, by: bob, at: minutes(30))
        XCTAssertEqual(ReportLifecycle.availableActions(for: proposed, userID: bob, at: minutes(31)), [.undoClosing])
        let undone = try ReportLifecycle.apply(.undoClosing, to: proposed, by: bob, at: minutes(39))
        XCTAssertEqual(undone.status, .claimed)
        XCTAssertEqual(undone.claim, claimed.claim)
        XCTAssertNil(undone.closing)
        XCTAssertThrowsError(try ReportLifecycle.apply(.undoClosing, to: proposed, by: bob, at: minutes(40))) {
            XCTAssertEqual($0 as? ReportError, .notYourClosing)
        }

        // Süresi dolan "Yardım gerekmiyor dendi" bu nedenle kapanır (kurallardaki isExpire).
        XCTAssertEqual(proposed.phase(for: cara, at: proposed.expiresAt), .closed(.unneeded))
        let expired = try ReportLifecycle.apply(.expire, to: proposed, by: eve, at: proposed.expiresAt)
        XCTAssertEqual(expired.closedReason, .unneeded)
    }

    /// Kanıtlı öneri mamanın bütçe puanını (1) harcar ve haritada "Çözüldü dendi" gibi görünür.
    func testCredibleProposalUsesFoodCostAndClosingDisplay() throws {
        let now = minutes(30)
        let record = UserRecord(createdAt: hours(-48), createWindow: hours(-48), createUsed: 0, closeWindow: minutes(1), closeUsed: 7)
        let seen = try seenReport(need: .food)
        XCTAssertEqual(ReportLifecycle.credibility(of: seen, by: bob, record: record, at: now), .credible)
        XCTAssertEqual(Budget.spendClose(record, cost: seen.need.closeCost, at: now)?.record.closeUsed, 8)

        let proposed = try ReportLifecycle.apply(.reportUnneeded, to: seen, by: bob, at: now, credible: true)
        let later = minutes(31)
        XCTAssertEqual(ClosingDisplay.look(of: proposed, mode: .label, viewer: dan, answered: false, at: later), .fading(leavesAt: nil))
        XCTAssertEqual(ClosingDisplay.look(of: proposed, mode: .strict, viewer: dan, answered: false, at: later), .unverified)
        XCTAssertEqual(ClosingDisplay.look(of: proposed, mode: .label, viewer: bob, answered: false, at: later), .hidden)
        XCTAssertFalse(ClosingDisplay.countsAsWaiting(proposed, viewer: dan, mode: .label, at: later))
        XCTAssertTrue(ClosingDisplay.isStakeholder(proposed, viewer: alice))
        XCTAssertTrue(ClosingDisplay.isStakeholder(proposed, viewer: cara))
    }
}
