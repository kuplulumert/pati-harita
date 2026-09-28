import XCTest
@testable import AnimalKit

final class ReportLifecycleTests: ReportTestCase {
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
        XCTAssertNil(report.closing)
        XCTAssertEqual(report.objectors, [])
        XCTAssertEqual(report.disputed, [])
        XCTAssertEqual(report.editCount, 0)
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

    func testClaimerReleasesAnytimeReporterOnlyStaleClaims() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        XCTAssertThrowsError(try ReportLifecycle.apply(.release, to: claimed, by: alice, at: minutes(44))) {
            XCTAssertEqual($0 as? ReportError, .notClaimedByYou)
        }
        XCTAssertThrowsError(try ReportLifecycle.apply(.release, to: claimed, by: cara, at: minutes(50))) {
            XCTAssertEqual($0 as? ReportError, .notClaimedByYou)
        }

        // "İlgilenen gelmedi": 45 dk'dır haber yok.
        let byReporter = try ReportLifecycle.apply(.release, to: claimed, by: alice, at: minutes(45))
        XCTAssertEqual(byReporter.status, .open)
        XCTAssertNil(byReporter.claim)

        let byClaimer = try ReportLifecycle.apply(.release, to: claimed, by: bob, at: minutes(10))
        XCTAssertEqual(byClaimer.status, .open)
        XCTAssertNil(byClaimer.claim)
    }

    func testClaimBecomesStaleAfter45Minutes() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        XCTAssertFalse(claimed.isClaimStale(at: minutes(44)))
        XCTAssertTrue(claimed.isClaimStale(at: minutes(45)))
        // Süresi dolan sahiplik artık canlı değil, bayat da sayılmaz.
        XCTAssertFalse(claimed.isClaimStale(at: hours(3)))
        XCTAssertEqual(claimed.phase(for: cara, at: minutes(50)), .helpedByOther(since: t0))
    }

    // MARK: Çözüldü

    func testReporterAloneClosesInstantly() throws {
        let resolved = try ReportLifecycle.apply(.resolve, to: makeReport(), by: alice, at: minutes(1))
        XCTAssertEqual(resolved.status, .closed)
        XCTAssertEqual(resolved.closedReason, .resolved)
        XCTAssertEqual(resolved.closedAt, minutes(1))
        XCTAssertEqual(resolved.purgeAt, minutes(1).addingTimeInterval(30 * 24 * 3600))
        XCTAssertNil(resolved.closing)
        XCTAssertFalse(resolved.isActive(at: minutes(2)))

        // Başkasının sahipliği de engellemez; kimse hayvanı ondan başka görmedi.
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        XCTAssertEqual(try ReportLifecycle.apply(.resolve, to: claimed, by: alice, at: minutes(5)).status, .closed)
    }

    func testReporterAfterOthersSawOnlyProposes() throws {
        let seen = try seenReport()
        let proposed = try ReportLifecycle.apply(.resolve, to: seen, by: alice, at: minutes(10))
        XCTAssertEqual(proposed.status, .closing)
        XCTAssertEqual(proposed.closing, Closing(reason: .resolved, userID: alice, at: minutes(10), credible: false))
        XCTAssertNil(proposed.closedReason)
        XCTAssertEqual(proposed.expiresAt, seen.expiresAt)
        XCTAssertTrue(proposed.isActive(at: minutes(11)))
    }

    func testClaimerResolveOnlyProposes() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        let proposed = try ReportLifecycle.apply(.resolve, to: claimed, by: bob, at: minutes(40))
        XCTAssertEqual(proposed.status, .closing)
        XCTAssertEqual(proposed.closing, Closing(reason: .resolved, userID: bob, at: minutes(40), credible: false))
        // Ömür kısalmaz; sahiplik kartta zaman çizelgesi için kalır ama canlı sayılmaz.
        XCTAssertEqual(proposed.expiresAt, claimed.expiresAt)
        XCTAssertEqual(proposed.claim, claimed.claim)
        XCTAssertNil(proposed.activeClaim(at: minutes(41)))
        XCTAssertTrue(proposed.isActive(at: minutes(41)))
        XCTAssertFalse(proposed.isWaiting(at: minutes(41)))
        XCTAssertEqual(
            proposed.phase(for: bob, at: minutes(41)),
            .closing(reason: .resolved, since: minutes(40), byMe: true, credible: false)
        )
        XCTAssertEqual(
            proposed.phase(for: cara, at: minutes(41)),
            .closing(reason: .resolved, since: minutes(40), byMe: false, credible: false)
        )
        XCTAssertEqual(
            proposed.changedFields(from: claimed),
            [.status, .closingReason, .closingBy, .closingAt, .closingCredible]
        )
    }

    func testPasserByCanProposeOnOpenReport() throws {
        let proposed = try ReportLifecycle.apply(.resolve, to: makeReport(), by: cara, at: minutes(1))
        XCTAssertEqual(proposed.status, .closing)
        XCTAssertEqual(proposed.closing?.userID, cara)
    }

    func testFreshClaimBlocksOthersResolveFor45Minutes() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: seenReport(), by: bob, at: minutes(2))
        XCTAssertThrowsError(try ReportLifecycle.apply(.resolve, to: claimed, by: dan, at: minutes(46))) {
            XCTAssertEqual($0 as? ReportError, .claimTooFresh)
        }
        XCTAssertFalse(ReportLifecycle.mayPropose(claimed, by: dan, at: minutes(46)))
        XCTAssertTrue(ReportLifecycle.mayPropose(claimed, by: dan, at: minutes(47)))
        let byDan = try ReportLifecycle.apply(.resolve, to: claimed, by: dan, at: minutes(47))
        XCTAssertEqual(byDan.closing?.userID, dan)

        // İşareti koyan taze sahipliği beklemez.
        XCTAssertEqual(try ReportLifecycle.apply(.resolve, to: claimed, by: alice, at: minutes(3)).closing?.userID, alice)
    }

    func testCredibleProposalIsRecorded() throws {
        let proposed = try ReportLifecycle.apply(.resolve, to: makeReport(), by: cara, at: minutes(1), credible: true)
        XCTAssertEqual(proposed.closing?.credible, true)
        XCTAssertEqual(
            proposed.phase(for: dan, at: minutes(2)),
            .closing(reason: .resolved, since: minutes(1), byMe: false, credible: true)
        )

        // Tek tanık işareti koyan hemen kapatır; öneri olmadığı için `credible` yok sayılır.
        let closed = try ReportLifecycle.apply(.resolve, to: makeReport(), by: alice, at: minutes(1), credible: true)
        XCTAssertEqual(closed.status, .closed)
        XCTAssertNil(closed.closing)
    }

    func testCredibleProposalNeedsAtMostOneDispute() throws {
        let once = try disputedReport(by: [bob])
        XCTAssertEqual(
            try ReportLifecycle.apply(.resolve, to: once, by: cara, at: hours(1), credible: true).closing?.credible,
            true
        )

        let twice = try disputedReport(by: [bob, dan])
        XCTAssertThrowsError(try ReportLifecycle.apply(.resolve, to: twice, by: cara, at: hours(1), credible: true)) {
            XCTAssertEqual($0 as? ReportError, .notAllowed)
        }
        XCTAssertEqual(try ReportLifecycle.apply(.resolve, to: twice, by: cara, at: hours(1)).closing?.credible, false)
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
        let proposed = try ReportLifecycle.apply(.resolve, to: claimed, by: bob, at: minutes(4))
        let goneOnce = try ReportLifecycle.apply(.reportGone, to: seen, by: dan, at: minutes(5))
        let goneTwice = try ReportLifecycle.apply(.reportGone, to: goneOnce, by: bob, at: minutes(6))
        for report in [claimed, released, proposed, goneOnce, goneTwice] {
            XCTAssertEqual(report.seenBy, [alice, cara])
        }
        // "Artık yok" diyen kişi "bildirdi" sayılmaz.
        XCTAssertFalse(goneTwice.seenBy.contains(bob))
    }

    func testConfirmResetsGoneVotes() throws {
        let once = try ReportLifecycle.apply(.reportGone, to: makeReport(), by: cara, at: minutes(5))
        let voted = try ReportLifecycle.apply(.reportGone, to: once, by: dan, at: minutes(6))
        let confirmed = try ReportLifecycle.apply(.confirmStillThere, to: voted, by: eve, at: minutes(10))
        XCTAssertEqual(confirmed.goneReports, [])
        XCTAssertEqual(confirmed.changedFields(from: voted), [.lastSeenAt, .expiresAt, .seenBy, .goneReports])
        // Günler arayla verilen oylar toplanmaz: aynı kişi yeniden oy verebilir.
        XCTAssertEqual(try ReportLifecycle.apply(.reportGone, to: confirmed, by: cara, at: minutes(11)).goneReports, [cara])
    }

    func testConfirmCannotExtendPastMaxAge() throws {
        var report = makeReport() // yaralı, 24 sa
        for hour in stride(from: 20.0, through: 160.0, by: 20.0) {
            report = try ReportLifecycle.apply(.confirmStillThere, to: report, by: cara, at: hours(hour))
        }
        XCTAssertEqual(ReportLifecycle.lifeCap(report), hours(168))
        XCTAssertEqual(report.expiresAt, hours(168)) // 160 + 24 değil, 7 gün

        let late = try ReportLifecycle.apply(.confirmStillThere, to: report, by: dan, at: hours(167))
        XCTAssertEqual(late.expiresAt, hours(168))
        XCTAssertFalse(late.changedFields(from: report).contains(.expiresAt))
        XCTAssertEqual(late.phase(for: dan, at: hours(168)), .closed(.expired))
    }

    func testClaimCannotExtendPastMaxAge() throws {
        // Eski sürümün kurucusu (yeni alanlar varsayılan) da derlenmeli.
        let old = Report(
            id: "r2",
            species: .cat,
            need: .food,
            coordinate: kadikoy,
            geohash: "sxk9hw43b9",
            reporterID: alice,
            createdAt: t0,
            status: .open,
            closedReason: nil,
            lastSeenAt: hours(155),
            expiresAt: hours(167),
            claim: nil,
            goneReports: [],
            seenBy: [alice, cara],
            closedAt: nil,
            purgeAt: nil
        )
        XCTAssertEqual(old.editCount, 0)
        let claimed = try ReportLifecycle.apply(.claim, to: old, by: bob, at: hours(166))
        XCTAssertEqual(claimed.claim?.expiresAt, hours(169))
        XCTAssertEqual(claimed.expiresAt, hours(168))
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

    func testTwoGoneVotesKeepReportOpenThirdOnlyProposes() throws {
        let once = try ReportLifecycle.apply(.reportGone, to: makeReport(), by: cara, at: minutes(5))
        let twice = try ReportLifecycle.apply(.reportGone, to: once, by: dan, at: minutes(6))
        XCTAssertEqual(twice.status, .open)
        XCTAssertEqual(twice.goneReports, [cara, dan])

        let thrice = try ReportLifecycle.apply(.reportGone, to: twice, by: eve, at: minutes(7))
        XCTAssertEqual(thrice.status, .closing)
        XCTAssertEqual(thrice.closing, Closing(reason: .gone, userID: eve, at: minutes(7), credible: false))
        XCTAssertNil(thrice.closedReason)
        XCTAssertEqual(thrice.expiresAt, twice.expiresAt)
        XCTAssertEqual(thrice.phase(for: cara, at: minutes(8)), .closing(reason: .gone, since: minutes(7), byMe: false, credible: false))
    }

    func testGoneVotesCannotStartClosingOverLiveClaim() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        var report = claimed
        // Sahiplik 45 dk'yı geçse de canlı olduğu sürece oylar yalnızca sayılır.
        for (index, user) in [cara, dan, eve].enumerated() {
            report = try ReportLifecycle.apply(.reportGone, to: report, by: user, at: minutes(50 + Double(index)))
        }
        XCTAssertEqual(report.status, .claimed)
        XCTAssertEqual(report.goneReports, [cara, dan, eve])
        XCTAssertEqual(report.claim, claimed.claim)
    }

    func testReporterAloneClosesAsGoneOthersOnlyPropose() throws {
        let byReporter = try ReportLifecycle.apply(.reportGone, to: makeReport(), by: alice, at: minutes(5))
        XCTAssertEqual(byReporter.status, .closed)
        XCTAssertEqual(byReporter.closedReason, .gone)
        XCTAssertEqual(byReporter.goneReports, [alice])

        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        let byClaimer = try ReportLifecycle.apply(.reportGone, to: claimed, by: bob, at: minutes(20))
        XCTAssertEqual(byClaimer.status, .closing)
        XCTAssertEqual(byClaimer.closing, Closing(reason: .gone, userID: bob, at: minutes(20), credible: false))

        let byReporterAfterOthers = try ReportLifecycle.apply(.reportGone, to: seenReport(), by: alice, at: minutes(5))
        XCTAssertEqual(byReporterAfterOthers.status, .closing)
        XCTAssertEqual(byReporterAfterOthers.closing?.reason, .gone)
        XCTAssertEqual(byReporterAfterOthers.closing?.userID, alice)
    }

    func testGoneListIsBounded() throws {
        // Canlı sahiplik varken oylar birikir; liste kurallardaki sınırda durur.
        var report = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        for index in 1...ReportLifecycle.maxGoneReports {
            report = try ReportLifecycle.apply(.reportGone, to: report, by: "voter-\(index)", at: minutes(Double(index)))
        }
        XCTAssertEqual(report.goneReports.count, ReportLifecycle.maxGoneReports)
        XCTAssertThrowsError(try ReportLifecycle.apply(.reportGone, to: report, by: "late", at: minutes(30))) {
            XCTAssertEqual($0 as? ReportError, .notAllowed)
        }
        XCTAssertFalse(ReportLifecycle.availableActions(for: report, userID: "late", at: minutes(30)).contains(.reportGone))
    }

    // MARK: Görünen eylemler

    func testActionsForPasserByOnWaitingReport() {
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: makeReport(), userID: cara, at: minutes(1)),
            [.claim, .confirmStillThere, .resolve, .reportGone]
        )
    }

    func testActionsForReporter() throws {
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: makeReport(), userID: alice, at: minutes(1)),
            [.claim, .resolve, .confirmStillThere, .reportGone]
        )
        // Başkası da gördükten sonra "Çözüldü" yalnızca öneridir ama düğme aynı yerde kalır.
        let seen = try seenReport()
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: seen, userID: alice, at: minutes(2)),
            [.claim, .resolve, .confirmStillThere, .reportGone]
        )
    }

    func testActionsForClaimerAndOthers() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        XCTAssertEqual(ReportLifecycle.availableActions(for: claimed, userID: bob, at: minutes(1)), [.resolve, .release, .reportGone])
        XCTAssertEqual(ReportLifecycle.availableActions(for: claimed, userID: cara, at: minutes(1)), [.confirmStillThere, .reportGone])
        XCTAssertEqual(ReportLifecycle.availableActions(for: claimed, userID: alice, at: minutes(1)), [.resolve, .confirmStillThere, .reportGone])
    }

    func testActionsOnStaleClaim() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: makeReport(), by: bob, at: t0)
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: claimed, userID: cara, at: minutes(50)),
            [.confirmStillThere, .resolve, .reportGone]
        )
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: claimed, userID: alice, at: minutes(50)),
            [.resolve, .confirmStillThere, .release, .reportGone]
        )
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: claimed, userID: bob, at: minutes(50)),
            [.resolve, .release, .reportGone]
        )
    }

    func testNoActionsOnExpiredReport() {
        XCTAssertEqual(ReportLifecycle.availableActions(for: makeReport(), userID: cara, at: hours(25)), [])
    }

    /// Mama işaretinde "Çözüldü"nün açık olduğu her yerde "Yardım gerekmiyor" da açık, "Artık yok"tan hemen önce.
    func testFoodOffersUnneededWhereResolveIsOffered() throws {
        let food = makeReport(need: .food)
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: food, userID: cara, at: minutes(1)),
            [.claim, .confirmStillThere, .resolve, .reportUnneeded, .reportGone]
        )
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: food, userID: alice, at: minutes(1)),
            [.claim, .resolve, .confirmStillThere, .reportUnneeded, .reportGone]
        )

        let claimed = try ReportLifecycle.apply(.claim, to: food, by: bob, at: t0)
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: claimed, userID: bob, at: minutes(1)),
            [.resolve, .release, .reportUnneeded, .reportGone]
        )
        // Başkasının taze sahipliğinde yoldan geçen "Çözüldü" diyemediği gibi "Yardım gerekmiyor" da diyemez.
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: claimed, userID: cara, at: minutes(1)),
            [.confirmStillThere, .reportGone]
        )
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: claimed, userID: cara, at: minutes(50)),
            [.confirmStillThere, .resolve, .reportUnneeded, .reportGone]
        )
        XCTAssertEqual(
            ReportLifecycle.availableActions(for: claimed, userID: alice, at: minutes(1)),
            [.resolve, .confirmStillThere, .reportUnneeded, .reportGone]
        )
    }

    func testSeriousNeedsNeverOfferUnneeded() throws {
        for need in Need.allCases where !need.allowsUnneeded {
            let seen = try seenReport(need: need)
            for (report, now) in [(makeReport(need: need), minutes(1)), (seen, minutes(2))] {
                for user in [alice, bob, cara] {
                    XCTAssertFalse(
                        ReportLifecycle.availableActions(for: report, userID: user, at: now).contains(.reportUnneeded),
                        "\(need) \(user)"
                    )
                }
            }
        }
    }

    func testEveryOfferedActionSucceeds() throws {
        var offered = Set<ReportAction>()
        for (name, report, now) in try phaseCatalogue() {
            for user in [alice, bob, cara, dan, eve] {
                for action in ReportLifecycle.availableActions(for: report, userID: user, at: now) {
                    offered.insert(action)
                    XCTAssertNoThrow(
                        try ReportLifecycle.apply(action, to: report, by: user, at: now),
                        "\(name): \(user) \(action)"
                    )
                    // Öneri başlatan eylem, bütçe harcanmışsa kanıtlı olarak da geçmeli.
                    if ReportLifecycle.wouldStartClosing(action, on: report, by: user, at: now) {
                        XCTAssertTrue(
                            [.resolve, .reportGone, .reportUnneeded].contains(action),
                            "\(name): \(user) \(action)"
                        )
                        if report.disputed.count <= Budget.credibleMaxDisputed {
                            XCTAssertEqual(
                                try ReportLifecycle.apply(action, to: report, by: user, at: now, credible: true).closing?.credible,
                                true,
                                "\(name): \(user) \(action)"
                            )
                        }
                    }
                }
            }
        }
        // Gösterilmeyen tek eylem süre dolumudur.
        XCTAssertEqual(offered, Set(ReportAction.allCases).subtracting([.expire]))
    }

    /// Her eylem yalnızca firestore.rules'un o eylem için izin verdiği alanları değiştirmeli
    /// (kurallardaki `changedKeys().hasOnly([...])` listeleri), kim/ne/nerede bilgisine dokunmamalı
    /// (`identityUnchanged()`) ve `validShape`i korumalı.
    func testEveryActionChangesOnlyFieldsAllowedByRules() throws {
        let closed: Set<ReportField> = [.status, .closedReason, .closedAt, .purgeAt]
        let proposes: Set<ReportField> = [.status, .closingReason, .closingBy, .closingAt, .closingCredible]
        let identity: Set<ReportField> = [.species, .need, .lat, .lng, .geohash, .editCount]
        let allowed: [ReportAction: [Set<ReportField>]] = [
            .claim: [[.status, .claimedBy, .claimedAt, .claimExpiresAt, .expiresAt]],
            .release: [[.status, .claimedBy, .claimedAt, .claimExpiresAt]],
            .resolve: [closed, proposes],
            // isUnneeded: "Çözüldü" ile aynı iki yol.
            .reportUnneeded: [closed, proposes],
            .confirmStillThere: [[.lastSeenAt, .expiresAt, .seenBy, .goneReports]],
            .reportGone: [
                [.goneReports],
                [.goneReports, .status, .closedReason, .closedAt, .purgeAt],
                [.goneReports, .status, .closingReason, .closingBy, .closingAt, .closingCredible],
            ],
            .dispute: [[
                .status, .closingReason, .closingBy, .closingAt, .closingCredible,
                .claimedBy, .claimedAt, .claimExpiresAt, .goneReports, .objectors, .disputed,
                .lastSeenAt, .expiresAt, .seenBy,
            ]],
            .confirmClosing: [closed],
            // isUndo: geçerli sahiplik aynen kalır (claimed) ya da sahiplik temizlenir (open).
            .undoClosing: [
                [.status, .closingReason, .closingBy, .closingAt, .closingCredible],
                [
                    .status, .closingReason, .closingBy, .closingAt, .closingCredible,
                    .claimedBy, .claimedAt, .claimExpiresAt,
                ],
            ],
            .expire: [closed],
        ]

        var checked = 0
        var undoneKeepingClaim = 0
        var undoneClearingClaim = 0
        for (name, report, now) in try phaseCatalogue() {
            var attempts: [(user: String, action: ReportAction, at: Date)] = []
            for user in [alice, bob, cara, dan, eve] {
                for action in ReportLifecycle.availableActions(for: report, userID: user, at: now) {
                    attempts.append((user: user, action: action, at: now))
                }
            }
            // Süre dolumu hiç gösterilmez; her evrede ayrıca denenir.
            attempts.append((user: eve, action: .expire, at: report.expiresAt))

            for attempt in attempts {
                let label = "\(name): \(attempt.user) \(attempt.action)"
                let updated = try ReportLifecycle.apply(attempt.action, to: report, by: attempt.user, at: attempt.at)
                let changed = updated.changedFields(from: report)
                XCTAssertFalse(changed.isEmpty, label)
                XCTAssertTrue(changed.isDisjoint(with: identity), label)
                XCTAssertTrue(
                    allowed[attempt.action, default: []].contains { changed.isSubset(of: $0) },
                    "\(label) değiştirdi: \(changed.map(\.rawValue).sorted())"
                )
                // Hiçbir eylem ömrü kısaltmaz.
                XCTAssertGreaterThanOrEqual(updated.expiresAt, report.expiresAt, label)
                assertValidShape(updated, label)
                if attempt.action == .undoClosing {
                    // isUndo: sahiplik hâlâ geçerliyse (başkasınınki de) alanları aynen kalır; yoksa işaret açılır.
                    if let claim = report.claim, claim.expiresAt > attempt.at {
                        XCTAssertEqual(updated.status, .claimed, label)
                        XCTAssertEqual(updated.claim, claim, label)
                        undoneKeepingClaim += 1
                    } else {
                        XCTAssertEqual(updated.status, .open, label)
                        XCTAssertNil(updated.claim, label)
                        undoneClearingClaim += 1
                    }
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 80)
        // Katalog iki "Geri al" yolunu da (sahiplik kalır / temizlenir) içermeli.
        XCTAssertGreaterThan(undoneKeepingClaim, 0)
        XCTAssertGreaterThan(undoneClearingClaim, 0)
    }

    func testChangedFieldsIgnoresUntouchedValues() throws {
        let report = makeReport(need: .food)
        // Ömür (12 sa) sahiplik bitişinden (1 + 3 sa) uzun: expiresAt değişmez, yazılmamalı.
        let claimed = try ReportLifecycle.apply(.claim, to: report, by: bob, at: hours(1))
        XCTAssertEqual(claimed.changedFields(from: report), [.status, .claimedBy, .claimedAt, .claimExpiresAt])
        XCTAssertEqual(report.changedFields(from: report), [])
    }

    // MARK: Geri al (silme)

    func testRetractOnlyWhileUntouched() throws {
        let report = makeReport()
        XCTAssertTrue(ReportLifecycle.canRetract(report, by: alice))
        XCTAssertFalse(ReportLifecycle.canRetract(report, by: bob))

        let claimed = try ReportLifecycle.apply(.claim, to: report, by: bob, at: t0)
        XCTAssertFalse(ReportLifecycle.canRetract(claimed, by: alice))
        let voted = try ReportLifecycle.apply(.reportGone, to: report, by: cara, at: minutes(1))
        XCTAssertFalse(ReportLifecycle.canRetract(voted, by: alice))
        // Başkası da gördükten sonra işareti koyan silemez.
        let seen = try seenReport()
        XCTAssertFalse(ReportLifecycle.canRetract(seen, by: alice))
        // İtiraz geçmişi olan işaret de silinemez (seenBy [alice] kalsa bile).
        let disputed = try disputedReport(by: [bob])
        XCTAssertEqual(disputed.seenBy, [alice])
        XCTAssertEqual(disputed.status, .open)
        XCTAssertFalse(ReportLifecycle.canRetract(disputed, by: alice))
    }
}
