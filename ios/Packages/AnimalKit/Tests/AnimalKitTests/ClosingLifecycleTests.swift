import XCTest
@testable import AnimalKit

/// "Çözüldü dendi" / "Artık yok dendi": onay, geri alma, itiraz, süre dolumu ve değişmez kural.
final class ClosingLifecycleTests: ReportTestCase {
    /// bob (yoldan geçen) 30. dakikada "Çözüldü" dedi; cara hayvanı daha önce görmüştü.
    private func proposedByBob(credible: Bool = false) throws -> Report {
        try ReportLifecycle.apply(.resolve, to: seenReport(), by: bob, at: minutes(30), credible: credible)
    }

    // MARK: Evet, çözüldü

    func testAgreeNeedsSecondPerson() throws {
        let byBob = try proposedByBob()
        // Kapatan kendi önerisini, hayvanı gören ya da görmeyen başkası da onaylayamaz; yalnızca işareti koyan.
        for user in [bob, cara, dan] {
            XCTAssertThrowsError(try ReportLifecycle.apply(.confirmClosing, to: byBob, by: user, at: minutes(40)), user) {
                XCTAssertEqual($0 as? ReportError, .notAllowed)
            }
        }
        let agreed = try ReportLifecycle.apply(.confirmClosing, to: byBob, by: alice, at: minutes(40))
        XCTAssertEqual(agreed.status, .closed)
        XCTAssertEqual(agreed.closedReason, .resolved)
        XCTAssertEqual(agreed.closedAt, minutes(40))
        XCTAssertEqual(agreed.closing, byBob.closing) // geçmiş olarak kalır
        XCTAssertEqual(agreed.phase(for: bob, at: minutes(41)), .closed(.resolved))

        // İşareti koyan önerdiyse hayvanı gören başka biri onaylar.
        let byAlice = try ReportLifecycle.apply(.resolve, to: seenReport(), by: alice, at: minutes(30))
        for user in [alice, bob, dan] {
            XCTAssertThrowsError(try ReportLifecycle.apply(.confirmClosing, to: byAlice, by: user, at: minutes(40)), user) {
                XCTAssertEqual($0 as? ReportError, .notAllowed)
            }
        }
        XCTAssertTrue(ReportLifecycle.canConfirmClosing(byAlice, by: cara))
        XCTAssertEqual(try ReportLifecycle.apply(.confirmClosing, to: byAlice, by: cara, at: minutes(40)).closedReason, .resolved)
    }

    func testGoneProposalIsConfirmedAsGone() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: seenReport(), by: bob, at: minutes(2))
        let gone = try ReportLifecycle.apply(.reportGone, to: claimed, by: bob, at: minutes(20))
        XCTAssertEqual(gone.closing?.reason, .gone)
        let agreed = try ReportLifecycle.apply(.confirmClosing, to: gone, by: alice, at: minutes(25))
        XCTAssertEqual(agreed.status, .closed)
        XCTAssertEqual(agreed.closedReason, .gone)
    }

    // MARK: Geri al

    func testUndoWindow() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: seenReport(), by: bob, at: minutes(2))
        let proposed = try ReportLifecycle.apply(.resolve, to: claimed, by: bob, at: minutes(30))
        for (user, time) in [(cara, 31.0), (alice, 31.0), (bob, 40.0)] {
            XCTAssertThrowsError(try ReportLifecycle.apply(.undoClosing, to: proposed, by: user, at: minutes(time)), user) {
                XCTAssertEqual($0 as? ReportError, .notYourClosing)
            }
        }

        let undone = try ReportLifecycle.apply(.undoClosing, to: proposed, by: bob, at: minutes(39.9))
        XCTAssertEqual(undone.status, .open)
        XCTAssertNil(undone.closing)
        XCTAssertNil(undone.claim)
        XCTAssertEqual(undone.expiresAt, proposed.expiresAt)
        XCTAssertEqual(undone.phase(for: cara, at: minutes(40)), .waiting)

        XCTAssertEqual(ReportLifecycle.availableActions(for: proposed, userID: bob, at: minutes(39)), [.undoClosing])
        XCTAssertEqual(ReportLifecycle.availableActions(for: proposed, userID: bob, at: minutes(40)), [])
    }

    // MARK: Hâlâ yardım gerekiyor

    func testDisputeReopensAndRecordsCloser() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        let voted = try ReportLifecycle.apply(.reportGone, to: claimed, by: cara, at: minutes(10))
        let proposed = try ReportLifecycle.apply(.resolve, to: voted, by: bob, at: minutes(40))
        let disputed = try ReportLifecycle.apply(.dispute, to: proposed, by: dan, at: minutes(60))

        XCTAssertEqual(disputed.status, .open)
        XCTAssertNil(disputed.closing)
        XCTAssertNil(disputed.claim)
        XCTAssertEqual(disputed.goneReports, [])
        XCTAssertEqual(disputed.disputed, [bob])
        XCTAssertEqual(disputed.objectors, [dan])
        // İtiraz eden hayvanı şimdi görmüş sayılır ("Hâlâ orada" kuralları).
        XCTAssertEqual(disputed.seenBy, [alice, dan])
        XCTAssertEqual(disputed.lastSeenAt, minutes(60))
        XCTAssertEqual(disputed.expiresAt, minutes(60).addingTimeInterval(24 * 3600))
        XCTAssertEqual(disputed.phase(for: cara, at: minutes(61)), .waiting)
    }

    func testDisputeClearsCredibility() throws {
        let credible = try proposedByBob(credible: true)
        let disputed = try ReportLifecycle.apply(.dispute, to: credible, by: cara, at: minutes(35))
        XCTAssertNil(disputed.closing)
        XCTAssertTrue(disputed.changedFields(from: credible).contains(.closingCredible))
    }

    func testCloserCannotDispute() throws {
        let proposed = try proposedByBob()
        XCTAssertThrowsError(try ReportLifecycle.apply(.dispute, to: proposed, by: bob, at: minutes(31))) {
            XCTAssertEqual($0 as? ReportError, .notAllowed)
        }
        XCTAssertFalse(ReportLifecycle.canDispute(proposed, by: bob))
    }

    func testNonReporterDisputesOnceReporterAlways() throws {
        let first = try ReportLifecycle.apply(.dispute, to: proposedByBob(), by: cara, at: minutes(40))
        let second = try ReportLifecycle.apply(.resolve, to: first, by: dan, at: minutes(50))
        XCTAssertThrowsError(try ReportLifecycle.apply(.dispute, to: second, by: cara, at: minutes(55))) {
            XCTAssertEqual($0 as? ReportError, .alreadyObjected)
        }
        XCTAssertFalse(ReportLifecycle.canDispute(second, by: cara))
        XCTAssertEqual(ReportLifecycle.availableActions(for: second, userID: cara, at: minutes(55)), [])

        let byReporter = try ReportLifecycle.apply(.dispute, to: second, by: alice, at: minutes(55))
        XCTAssertEqual(byReporter.objectors, [cara])
        XCTAssertEqual(byReporter.disputed, [bob, dan])

        let third = try ReportLifecycle.apply(.resolve, to: byReporter, by: eve, at: minutes(60))
        XCTAssertEqual(try ReportLifecycle.apply(.dispute, to: third, by: alice, at: minutes(65)).disputed, [bob, dan, eve])
    }

    func testDisputedUserCannotClaimOrProposeAgain() throws {
        let report = try ReportLifecycle.apply(.dispute, to: proposedByBob(), by: cara, at: minutes(40))
        XCTAssertThrowsError(try ReportLifecycle.apply(.claim, to: report, by: bob, at: minutes(41))) {
            XCTAssertEqual($0 as? ReportError, .disputed)
        }
        XCTAssertThrowsError(try ReportLifecycle.apply(.resolve, to: report, by: bob, at: minutes(41))) {
            XCTAssertEqual($0 as? ReportError, .disputed)
        }
        XCTAssertFalse(ReportLifecycle.mayPropose(report, by: bob, at: minutes(41)))
        XCTAssertEqual(ReportLifecycle.availableActions(for: report, userID: bob, at: minutes(41)), [.confirmStillThere, .reportGone])

        // Üçüncü "Artık yok" oyunu verse de öneri başlamaz, oy yalnızca sayılır.
        let once = try ReportLifecycle.apply(.reportGone, to: report, by: dan, at: minutes(42))
        let twice = try ReportLifecycle.apply(.reportGone, to: once, by: eve, at: minutes(43))
        let third = try ReportLifecycle.apply(.reportGone, to: twice, by: bob, at: minutes(44))
        XCTAssertEqual(third.status, .open)
        XCTAssertEqual(third.goneReports, [dan, eve, bob])
    }

    func testTenDisputesStopProposals() throws {
        let closers = (1...ReportLifecycle.maxDisputed).map { "closer-\($0)" }
        let report = try disputedReport(by: closers)
        XCTAssertEqual(report.disputed.count, ReportLifecycle.maxDisputed)

        XCTAssertFalse(ReportLifecycle.mayPropose(report, by: cara, at: hours(3)))
        XCTAssertThrowsError(try ReportLifecycle.apply(.resolve, to: report, by: cara, at: hours(3))) {
            XCTAssertEqual($0 as? ReportError, .tooManyDisputes)
        }
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: report, userID: cara, at: hours(3)),
            [.claim, .confirmStillThere, .reportGone]
        )

        // Oylar da öneri başlatamaz; işaret yalnızca süresi dolunca kalkar.
        let once = try ReportLifecycle.apply(.reportGone, to: report, by: cara, at: hours(3))
        let twice = try ReportLifecycle.apply(.reportGone, to: once, by: dan, at: hours(3))
        let third = try ReportLifecycle.apply(.reportGone, to: twice, by: eve, at: hours(3))
        XCTAssertEqual(third.status, .open)

        // Hayvanı ondan başka gören olmadıysa işareti koyan yine kapatabilir (kurallardaki reporterAlone).
        XCTAssertEqual(try ReportLifecycle.apply(.resolve, to: report, by: alice, at: hours(3)).status, .closed)
    }

    // MARK: Durum uyuşmazlığı

    func testActionsRequireTheirStatus() throws {
        let proposed = try proposedByBob()
        let waitingActions: [ReportAction] = [.claim, .release, .resolve, .confirmStillThere, .reportGone]
        for action in waitingActions {
            XCTAssertThrowsError(try ReportLifecycle.apply(action, to: proposed, by: cara, at: minutes(31)), "\(action)") {
                XCTAssertEqual($0 as? ReportError, .statusChanged)
            }
        }
        let seen = try seenReport()
        let closingActions: [ReportAction] = [.dispute, .confirmClosing, .undoClosing]
        for action in closingActions {
            XCTAssertThrowsError(try ReportLifecycle.apply(action, to: seen, by: alice, at: minutes(31)), "\(action)") {
                XCTAssertEqual($0 as? ReportError, .statusChanged)
            }
        }
    }

    // MARK: Süre dolunca

    func testExpireOnlyAfterExpiresAt() throws {
        let open = makeReport()
        XCTAssertFalse(ReportLifecycle.isDue(open, at: hours(23.9)))
        XCTAssertThrowsError(try ReportLifecycle.apply(.expire, to: open, by: dan, at: hours(23.9))) {
            XCTAssertEqual($0 as? ReportError, .notExpired)
        }
        XCTAssertTrue(ReportLifecycle.isDue(open, at: hours(24)))
        let expired = try ReportLifecycle.apply(.expire, to: open, by: dan, at: hours(24))
        XCTAssertEqual(expired.status, .closed)
        XCTAssertEqual(expired.closedReason, .expired)
        XCTAssertEqual(expired.closedAt, hours(24))
        XCTAssertFalse(ReportLifecycle.isDue(expired, at: hours(25)))
        XCTAssertThrowsError(try ReportLifecycle.apply(.expire, to: expired, by: dan, at: hours(25))) {
            XCTAssertEqual($0 as? ReportError, .notActive)
        }

        let claimed = try ReportLifecycle.apply(.claim, to: open, by: bob, at: t0)
        XCTAssertThrowsError(try ReportLifecycle.apply(.expire, to: claimed, by: dan, at: hours(23))) {
            XCTAssertEqual($0 as? ReportError, .notExpired)
        }
        XCTAssertEqual(try ReportLifecycle.apply(.expire, to: claimed, by: dan, at: hours(24)).closedReason, .expired)
    }

    func testExpiredProposalClosesWithItsReason() throws {
        let resolved = try proposedByBob()
        XCTAssertThrowsError(try ReportLifecycle.apply(.expire, to: resolved, by: eve, at: minutes(31))) {
            XCTAssertEqual($0 as? ReportError, .notExpired)
        }
        XCTAssertEqual(resolved.phase(for: cara, at: resolved.expiresAt), .closed(.resolved))
        XCTAssertEqual(ReportLifecycle.availableActions(for: resolved, userID: alice, at: resolved.expiresAt), [])
        let expired = try ReportLifecycle.apply(.expire, to: resolved, by: eve, at: resolved.expiresAt)
        XCTAssertEqual(expired.closedReason, .resolved)
        XCTAssertEqual(expired.closing, resolved.closing)

        let claimed = try ReportLifecycle.apply(.claim, to: seenReport(), by: bob, at: minutes(2))
        let gone = try ReportLifecycle.apply(.reportGone, to: claimed, by: bob, at: minutes(20))
        XCTAssertEqual(try ReportLifecycle.apply(.expire, to: gone, by: eve, at: gone.expiresAt).closedReason, .gone)
    }

    func testActionsOtherThanExpireNeedLiveReport() throws {
        let open = makeReport()
        let proposed = try proposedByBob()
        for report in [open, proposed] {
            for action in ReportAction.allCases where action != .expire {
                for user in [alice, bob, cara] {
                    XCTAssertThrowsError(
                        try ReportLifecycle.apply(action, to: report, by: user, at: report.expiresAt),
                        "\(report.status) \(user) \(action)"
                    ) {
                        XCTAssertEqual($0 as? ReportError, .notActive)
                    }
                }
            }
        }
    }

    // MARK: Depo için

    func testWouldStartClosing() throws {
        let open = makeReport()
        XCTAssertTrue(ReportLifecycle.wouldStartClosing(.resolve, on: open, by: bob, at: minutes(1)))
        // Tek tanık işareti koyan hemen kapatır; öneri yok, bütçe harcanmaz.
        XCTAssertFalse(ReportLifecycle.wouldStartClosing(.resolve, on: open, by: alice, at: minutes(1)))
        XCTAssertFalse(ReportLifecycle.wouldStartClosing(.reportGone, on: open, by: bob, at: minutes(1)))
        XCTAssertFalse(ReportLifecycle.wouldStartClosing(.confirmStillThere, on: open, by: bob, at: minutes(1)))

        let votedTwice = try ReportLifecycle.apply(
            .reportGone,
            to: ReportLifecycle.apply(.reportGone, to: open, by: cara, at: minutes(2)),
            by: dan,
            at: minutes(3)
        )
        XCTAssertTrue(ReportLifecycle.wouldStartClosing(.reportGone, on: votedTwice, by: eve, at: minutes(4)))

        let proposed = try proposedByBob()
        XCTAssertFalse(ReportLifecycle.wouldStartClosing(.dispute, on: proposed, by: cara, at: minutes(31)))
        XCTAssertFalse(ReportLifecycle.wouldStartClosing(.confirmClosing, on: proposed, by: alice, at: minutes(31)))
    }

    // MARK: Değişmez kural

    /// Başkasının da gördüğü işareti tek bir kişi (bob) hangi sırayla ne yaparsa yapsın
    /// süresinden önce kapatamaz, ömrünü kısaltamaz, silemez.
    func testNoSinglePersonRemovesAConfirmedReport() throws {
        let seen = try seenReport()
        let times = [minutes(2), minutes(20), minutes(70), hours(4), hours(10)]
        var frontier: Set<Report> = [seen]
        var reached = 0
        for now in times {
            var next = Set<Report>()
            for report in frontier {
                for action in ReportAction.allCases {
                    for credible in [false, true] {
                        guard let updated = try? ReportLifecycle.apply(action, to: report, by: bob, at: now, credible: credible) else {
                            continue
                        }
                        reached += 1
                        XCTAssertNotEqual(updated.status, .closed, "\(action)")
                        XCTAssertGreaterThanOrEqual(updated.expiresAt, seen.expiresAt, "\(action)")
                        XCTAssertFalse(ReportLifecycle.canRetract(updated, by: bob))
                        next.insert(updated)
                    }
                }
            }
            frontier = frontier.union(next)
        }
        XCTAssertGreaterThan(reached, 20)
    }
}
