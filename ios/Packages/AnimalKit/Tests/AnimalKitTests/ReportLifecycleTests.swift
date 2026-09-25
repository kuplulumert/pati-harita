import XCTest
@testable import AnimalKit

final class ReportLifecycleTests: XCTestCase {
    private let alice = "alice" // işareti koyan
    private let bob = "bob" // yardım eden
    private let cara = "cara" // yoldan geçen
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let kadikoy = Coordinate(latitude: 40.9903, longitude: 29.029)

    private func makeReport(need: Need = .injured) -> Report {
        ReportLifecycle.makeReport(id: "r1", species: .cat, need: need, at: kadikoy, reporterID: alice, now: t0)
    }

    private func minutes(_ value: Double) -> Date { t0.addingTimeInterval(value * 60) }
    private func hours(_ value: Double) -> Date { t0.addingTimeInterval(value * 3600) }

    // MARK: Oluşturma

    func testNewReportIsOpenAndExpiresAfterNeedLifetime() {
        let report = makeReport(need: .food)
        XCTAssertEqual(report.status, .open)
        XCTAssertEqual(report.geohash, "sxk9hw43b9")
        XCTAssertEqual(report.lastSeenAt, t0)
        XCTAssertEqual(report.expiresAt, hours(12))
        XCTAssertTrue(report.isActive(at: hours(11.9)))
        XCTAssertFalse(report.isActive(at: hours(12)))
        XCTAssertEqual(report.phase(for: alice, at: hours(12)), .closed(.expired))
    }

    func testNewReportIsSeenByReporterOnly() {
        let report = makeReport()
        XCTAssertEqual(report.seenBy, [alice])
        XCTAssertEqual(report.seenCount, 1)
    }

    func testFreshnessFadesTowardsExpiry() {
        let report = makeReport(need: .injured) // 24 sa
        XCTAssertEqual(report.freshness(at: t0), 1)
        XCTAssertEqual(report.freshness(at: hours(12)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(report.freshness(at: hours(30)), 0)
    }

    // MARK: İlgileniyorum / Vazgeç

    func testClaimMarksReportAsBeingHelped() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: minutes(5))
        XCTAssertEqual(claimed.status, .claimed)
        XCTAssertEqual(claimed.claim, Claim(userID: bob, claimedAt: minutes(5), expiresAt: minutes(5 + 180)))
        XCTAssertEqual(claimed.phase(for: bob, at: minutes(6)), .helpedByMe(until: minutes(185)))
        XCTAssertEqual(claimed.phase(for: cara, at: minutes(6)), .helpedByOther(since: minutes(5)))
    }

    func testClaimKeepsReportOnMapUntilClaimEnds() throws {
        let food = makeReport(need: .food) // 12 sa sonra düşer
        let claimed = try ReportLifecycle.apply(.claim, to: food, by: bob, at: hours(11))
        XCTAssertEqual(claimed.expiresAt, hours(14))
    }

    func testCannotClaimWhileSomeoneElseIsHelping() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        XCTAssertThrowsError(try ReportLifecycle.apply(.claim, to: claimed, by: cara, at: hours(1))) {
            XCTAssertEqual($0 as? ReportError, .alreadyClaimed)
        }
    }

    func testAbandonedClaimExpiresAndReportWaitsAgain() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        XCTAssertEqual(claimed.phase(for: cara, at: hours(3)), .waiting)
        let reclaimed = try ReportLifecycle.apply(.claim, to: claimed, by: cara, at: hours(3))
        XCTAssertEqual(reclaimed.claim?.userID, cara)
    }

    func testOnlyClaimerCanRelease() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        XCTAssertThrowsError(try ReportLifecycle.apply(.release, to: claimed, by: alice, at: minutes(10)))
        let released = try ReportLifecycle.apply(.release, to: claimed, by: bob, at: minutes(10))
        XCTAssertEqual(released.status, .open)
        XCTAssertNil(released.claim)
    }

    // MARK: Çözüldü

    func testClaimerResolvesAndReportLeavesMap() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        let resolved = try ReportLifecycle.apply(.resolve, to: claimed, by: bob, at: minutes(40))
        XCTAssertEqual(resolved.status, .closed)
        XCTAssertEqual(resolved.closedReason, .resolved)
        XCTAssertEqual(resolved.closedAt, minutes(40))
        XCTAssertEqual(resolved.purgeAt, minutes(40).addingTimeInterval(30 * 24 * 3600))
        XCTAssertFalse(resolved.isActive(at: minutes(41)))
    }

    func testReporterCanResolveButPasserByCannot() throws {
        XCTAssertThrowsError(try ReportLifecycle.apply(.resolve, to: makeReport(), by: cara, at: minutes(1))) {
            XCTAssertEqual($0 as? ReportError, .notAllowed)
        }
        let resolved = try ReportLifecycle.apply(.resolve, to: makeReport(), by: alice, at: minutes(1))
        XCTAssertEqual(resolved.closedReason, .resolved)
    }

    func testClosedReportRejectsEveryAction() throws {
        let resolved = try ReportLifecycle.apply(.resolve, to: makeReport(), by: alice, at: minutes(1))
        for action in ReportAction.allCases {
            XCTAssertThrowsError(try ReportLifecycle.apply(action, to: resolved, by: bob, at: minutes(2))) {
                XCTAssertEqual($0 as? ReportError, .notActive)
            }
        }
    }

    // MARK: Hâlâ orada

    func testConfirmExtendsLifetime() throws {
        let confirmed = try ReportLifecycle.apply(.confirmStillThere, to: makeReport(), by: cara, at: hours(20))
        XCTAssertEqual(confirmed.lastSeenAt, hours(20))
        XCTAssertEqual(confirmed.expiresAt, hours(44))
    }

    func testConfirmByOthersAddsThemToSeenBy() throws {
        let report = makeReport()
        XCTAssertTrue(ReportLifecycle.confirmAddsSeen(to: report, by: cara))
        let byCara = try ReportLifecycle.apply(.confirmStillThere, to: report, by: cara, at: hours(1))
        XCTAssertEqual(byCara.seenBy, [alice, cara])
        XCTAssertEqual(byCara.seenCount, 2)
        XCTAssertEqual(byCara.changedFields(from: report), [.lastSeenAt, .expiresAt, .seenBy])

        let byBob = try ReportLifecycle.apply(.confirmStillThere, to: byCara, by: bob, at: hours(2))
        XCTAssertEqual(byBob.seenBy, [alice, cara, bob])
    }

    func testConfirmBySameUserCountsOnce() throws {
        let report = makeReport()
        // İşareti koyan zaten sayılı: ömür uzar, sayı değişmez.
        XCTAssertFalse(ReportLifecycle.confirmAddsSeen(to: report, by: alice))
        let byReporter = try ReportLifecycle.apply(.confirmStillThere, to: report, by: alice, at: hours(1))
        XCTAssertEqual(byReporter.seenBy, [alice])
        XCTAssertEqual(byReporter.changedFields(from: report), [.lastSeenAt, .expiresAt])

        let once = try ReportLifecycle.apply(.confirmStillThere, to: report, by: cara, at: hours(1))
        XCTAssertFalse(ReportLifecycle.confirmAddsSeen(to: once, by: cara))
        let twice = try ReportLifecycle.apply(.confirmStillThere, to: once, by: cara, at: hours(2))
        XCTAssertEqual(twice.seenBy, [alice, cara])
        XCTAssertEqual(twice.lastSeenAt, hours(2))
        XCTAssertEqual(twice.changedFields(from: once), [.lastSeenAt, .expiresAt])
    }

    func testSeenByStopsGrowingAtCap() throws {
        var report = makeReport()
        for index in 1..<ReportLifecycle.maxSeenBy {
            report = try ReportLifecycle.apply(.confirmStillThere, to: report, by: "user-\(index)", at: minutes(Double(index)))
        }
        XCTAssertEqual(report.seenCount, ReportLifecycle.maxSeenBy)
        XCTAssertEqual(Set(report.seenBy).count, ReportLifecycle.maxSeenBy)

        // Liste dolu: yeni gelen yine "Hâlâ orada" diyebilir ama eklenmez.
        XCTAssertFalse(ReportLifecycle.confirmAddsSeen(to: report, by: "late"))
        let late = try ReportLifecycle.apply(.confirmStillThere, to: report, by: "late", at: hours(3))
        XCTAssertEqual(late.seenBy, report.seenBy)
        XCTAssertEqual(late.lastSeenAt, hours(3))
        XCTAssertFalse(late.changedFields(from: report).contains(.seenBy))
    }

    func testOtherActionsLeaveSeenByUnchanged() throws {
        let seen = try ReportLifecycle.apply(.confirmStillThere, to: makeReport(), by: cara, at: minutes(1))
        let claimed = try ReportLifecycle.apply(.claim, to: seen, by: bob, at: minutes(2))
        let released = try ReportLifecycle.apply(.release, to: claimed, by: bob, at: minutes(3))
        let resolved = try ReportLifecycle.apply(.resolve, to: claimed, by: bob, at: minutes(4))
        let goneOnce = try ReportLifecycle.apply(.reportGone, to: seen, by: "dan", at: minutes(5))
        let goneTwice = try ReportLifecycle.apply(.reportGone, to: goneOnce, by: bob, at: minutes(6))
        for report in [claimed, released, resolved, goneOnce, goneTwice] {
            XCTAssertEqual(report.seenBy, [alice, cara])
        }
        // "Artık yok" diyen kişi "bildirdi" sayılmaz.
        XCTAssertFalse(goneTwice.seenBy.contains(bob))
    }

    // MARK: Artık yok

    func testSingleGoneReportFromPasserByOnlyCounts() throws {
        let reported = try ReportLifecycle.apply(.reportGone, to: makeReport(), by: cara, at: minutes(5))
        XCTAssertEqual(reported.status, .open)
        XCTAssertEqual(reported.goneReports, [cara])
        XCTAssertThrowsError(try ReportLifecycle.apply(.reportGone, to: reported, by: cara, at: minutes(6))) {
            XCTAssertEqual($0 as? ReportError, .alreadyReportedGone)
        }
    }

    func testSecondGoneReportClosesReport() throws {
        let once = try ReportLifecycle.apply(.reportGone, to: makeReport(), by: cara, at: minutes(5))
        let twice = try ReportLifecycle.apply(.reportGone, to: once, by: bob, at: minutes(7))
        XCTAssertEqual(twice.status, .closed)
        XCTAssertEqual(twice.closedReason, .gone)
    }

    func testReporterOrClaimerAloneCanCloseAsGone() throws {
        let byReporter = try ReportLifecycle.apply(.reportGone, to: makeReport(), by: alice, at: minutes(5))
        XCTAssertEqual(byReporter.closedReason, .gone)

        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        let byClaimer = try ReportLifecycle.apply(.reportGone, to: claimed, by: bob, at: minutes(20))
        XCTAssertEqual(byClaimer.closedReason, .gone)
    }

    // MARK: Görünen eylemler

    func testActionsForPasserByOnWaitingReport() {
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: makeReport(), userID: cara, at: minutes(1)),
            [.claim, .confirmStillThere, .reportGone]
        )
    }

    func testActionsForReporter() {
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: makeReport(), userID: alice, at: minutes(1)),
            [.claim, .resolve, .confirmStillThere, .reportGone]
        )
    }

    func testActionsForClaimerAndOthers() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        XCTAssertEqual(ReportLifecycle.availableActions(for: claimed, userID: bob, at: minutes(1)), [.resolve, .release, .reportGone])
        XCTAssertEqual(ReportLifecycle.availableActions(for: claimed, userID: cara, at: minutes(1)), [.confirmStillThere, .reportGone])
        XCTAssertEqual(ReportLifecycle.availableActions(for: claimed, userID: alice, at: minutes(1)), [.resolve, .confirmStillThere, .reportGone])
    }

    func testEveryOfferedActionSucceeds() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        for report in [makeReport(), claimed] {
            for user in [alice, bob, cara] {
                for action in ReportLifecycle.availableActions(for: report, userID: user, at: minutes(1)) {
                    XCTAssertNoThrow(try ReportLifecycle.apply(action, to: report, by: user, at: minutes(1)), "\(user) \(action)")
                }
            }
        }
    }

    /// Her eylem yalnızca firestore.rules'un o eylem için izin verdiği alanları değiştirmeli
    /// (kurallardaki `changedKeys().hasOnly([...])` listeleri).
    func testEveryActionChangesOnlyFieldsAllowedByRules() throws {
        let closing: Set<ReportField> = [.status, .closedReason, .closedAt, .purgeAt]
        let allowed: [ReportAction: [Set<ReportField>]] = [
            .claim: [[.status, .claimedBy, .claimedAt, .claimExpiresAt, .expiresAt]],
            .release: [[.status, .claimedBy, .claimedAt, .claimExpiresAt]],
            .resolve: [closing],
            .confirmStillThere: [[.lastSeenAt, .expiresAt, .seenBy]],
            .reportGone: [[.goneReports], closing.union([.goneReports])],
        ]
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(need: .food), by: bob, at: hours(10))
        let reportedOnce = try ReportLifecycle.apply(.reportGone, to: makeReport(), by: cara, at: minutes(1))

        var checked = 0
        for report in [makeReport(), makeReport(need: .food), claimed, reportedOnce] {
            for user in [alice, bob, cara, "dan"] {
                let now = report.claim == nil ? minutes(30) : hours(10.5)
                for action in ReportLifecycle.availableActions(for: report, userID: user, at: now) {
                    let updated = try ReportLifecycle.apply(action, to: report, by: user, at: now)
                    let changed = updated.changedFields(from: report)
                    XCTAssertFalse(changed.isEmpty, "\(user) \(action)")
                    XCTAssertTrue(
                        allowed[action, default: []].contains { changed.isSubset(of: $0) },
                        "\(user) \(action) değiştirdi: \(changed.map(\.rawValue).sorted())"
                    )
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 20)
    }

    func testChangedFieldsIgnoresUntouchedValues() throws {
        let report = makeReport(need: .food)
        // Ömür (12 sa) sahiplik bitişinden (1 + 3 sa) uzun: expiresAt değişmez, yazılmamalı.
        let claimed = try ReportLifecycle.apply(.claim, to: report, by: bob, at: hours(1))
        XCTAssertEqual(claimed.changedFields(from: report), [.status, .claimedBy, .claimedAt, .claimExpiresAt])
        XCTAssertEqual(report.changedFields(from: report), [])
    }

    func testNoActionsOnExpiredReport() {
        XCTAssertEqual(ReportLifecycle.availableActions(for: makeReport(), userID: cara, at: hours(25)), [])
    }

    // MARK: Geri al

    func testRetractOnlyWhileUntouched() throws {
        let report = makeReport()
        XCTAssertTrue(ReportLifecycle.canRetract(report, by: alice))
        XCTAssertFalse(ReportLifecycle.canRetract(report, by: bob))
        let claimed = try ReportLifecycle.apply(.claim, to: report, by: bob, at: t0)
        XCTAssertFalse(ReportLifecycle.canRetract(claimed, by: alice))
    }
}
