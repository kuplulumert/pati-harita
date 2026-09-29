import XCTest
@testable import AnimalKit

/// "Hâlâ orada mı?": hangi işaret sorulur, ne sıklıkla, hızlı giderken sorulmaz ve yanıt ne yapar.
/// Yoldan geçen dan'dır; işaretleri alice koyar.
final class NearbyPromptTests: ReportTestCase {
    private var now: Date { minutes(30) }

    /// dan'dan `north` / `east` metre uzakta, alice'in t0'da koyduğu işaret.
    private func report(_ id: String, need: Need = .injured, north: Double = 0, east: Double = 0) -> Report {
        ReportLifecycle.makeReport(
            id: id,
            species: .cat,
            need: need,
            at: kadikoy.offset(north: north, east: east),
            reporterID: alice,
            now: t0
        )
    }

    private func reading(accuracy: Double = 10, age: TimeInterval = 1, at time: Date? = nil) -> LocationFix {
        LocationFix(
            coordinate: kadikoy,
            timestamp: (time ?? now).addingTimeInterval(-age),
            horizontalAccuracy: accuracy
        )
    }

    private func candidate(
        _ reports: [Report],
        user: String? = nil,
        fix: LocationFix? = nil,
        asked: Set<String> = [],
        at time: Date? = nil
    ) -> String? {
        NearbyPrompt.candidate(
            in: reports,
            userID: user ?? dan,
            fix: fix ?? reading(at: time),
            asked: asked,
            at: time ?? now
        )?.report.id
    }

    func testConstants() {
        XCTAssertEqual(NearbyPrompt.triggerRadius, 50)
        XCTAssertEqual(NearbyPrompt.dismissRadius, 80)
        XCTAssertEqual(NearbyPrompt.maxAccuracy, 35)
        XCTAssertEqual(NearbyPrompt.maxFixAge, 60)
        XCTAssertEqual(NearbyPrompt.fastSpeed, 2.5)
        XCTAssertEqual(NearbyPrompt.visibleDuration, 20)
        XCTAssertEqual(NearbyPrompt.armDelay, 0.8)
        XCTAssertEqual(NearbyPrompt.cooldown, 10 * 60)
        XCTAssertEqual(NearbyPrompt.dailyLimit, 5)
        XCTAssertEqual(NearbyPrompt.quietAfterUnanswered, 3)
        XCTAssertEqual(NearbyPrompt.quietDuration, 7 * 24 * 3600)
        XCTAssertEqual(NearbyPrompt.startupGrace, 15)
        XCTAssertEqual(NearbyPrompt.afterOwnReportGrace, 60)
        XCTAssertEqual(NearbyPrompt.askedRetention, ReportLifecycle.maxAge + 24 * 3600)
        XCTAssertEqual(NearbyPrompt.carefulGoneNeeds, [.emergency, .injured, .babies])
    }

    // MARK: Hangi işaret

    func testNearbyWaitingReportIsAsked() throws {
        let result = NearbyPrompt.candidate(in: [report("a", north: 30)], userID: dan, fix: reading(), asked: [], at: now)
        XCTAssertEqual(result?.report.id, "a")
        XCTAssertEqual(result?.distance ?? -1, 30, accuracy: 0.01)
        // Biri ilgileniyorsa da sorulur.
        let claimed = try ReportLifecycle.apply(.claim, to: report("a", north: 30), by: bob, at: minutes(2))
        XCTAssertEqual(claimed.status, .claimed)
        XCTAssertEqual(candidate([claimed]), "a")
    }

    func testExcludedReports() throws {
        let open = report("a", north: 30)
        XCTAssertEqual(candidate([open]), "a")
        // Kendi işareti.
        XCTAssertNil(candidate([open], user: alice))
        // İlgilendiği işaret.
        let mine = try ReportLifecycle.apply(.claim, to: open, by: dan, at: minutes(2))
        XCTAssertNil(candidate([mine]))
        // "… dendi".
        let seen = try ReportLifecycle.apply(.confirmStillThere, to: open, by: cara, at: minutes(1))
        let closing = try ReportLifecycle.apply(.resolve, to: seen, by: bob, at: minutes(2))
        XCTAssertEqual(closing.status, .closing)
        XCTAssertNil(candidate([closing]))
        // Süresi dolmuş (yaralı: 24 sa).
        XCTAssertNil(candidate([open], at: hours(25)))
        XCTAssertEqual(candidate([open], at: hours(23)), "a")
        // Daha önce gördü, "Artık yok" dedi ya da soruldu.
        let seenByMe = try ReportLifecycle.apply(.confirmStillThere, to: open, by: dan, at: minutes(2))
        XCTAssertNil(candidate([seenByMe]))
        let voted = try ReportLifecycle.apply(.reportGone, to: open, by: dan, at: minutes(2))
        XCTAssertEqual(voted.status, .open)
        XCTAssertNil(candidate([voted]))
        XCTAssertNil(candidate([open], asked: ["a"]))
        XCTAssertEqual(candidate([open], asked: ["b"]), "a")
    }

    func testDistanceAndFixLimits() {
        XCTAssertEqual(candidate([report("a", north: 49.9)]), "a")
        XCTAssertNil(candidate([report("a", north: 51)]))
        XCTAssertNil(candidate([report("a", east: 51)]))
        XCTAssertEqual(candidate([report("a")], fix: reading(accuracy: 35)), "a")
        XCTAssertNil(candidate([report("a")], fix: reading(accuracy: 36)))
        XCTAssertNil(candidate([report("a")], fix: reading(accuracy: -1)))
        XCTAssertEqual(candidate([report("a")], fix: reading(age: 60)), "a")
        XCTAssertNil(candidate([report("a")], fix: reading(age: 61)))
        XCTAssertNil(candidate([]))
    }

    func testNearestWinsAndTiesGoToHigherPriority() {
        XCTAssertEqual(candidate([report("food", need: .food, north: 10), report("hurt", east: 30)]), "food")
        // 1 m'den az fark eşitlik sayılır: yaralı mamadan önce gelir.
        XCTAssertEqual(candidate([report("food", need: .food, north: 10), report("hurt", east: 10.6)]), "hurt")
        XCTAssertEqual(candidate([report("food", need: .food, north: 10), report("hurt", east: 11.5)]), "food")
        XCTAssertEqual(
            candidate([report("vet", need: .vet, north: 20), report("sos", need: .emergency, east: 20.5)]),
            "sos"
        )
    }

    // MARK: Hız

    private func sample(_ second: Double, _ speed: Double, accuracy: Double = 1) -> NearbyPrompt.SpeedSample {
        NearbyPrompt.SpeedSample(at: now.addingTimeInterval(second), speed: speed, accuracy: accuracy)
    }

    func testMovingFast() {
        XCTAssertFalse(NearbyPrompt.isMovingFast([]))
        XCTAssertFalse(NearbyPrompt.isMovingFast([sample(0, 10)]))
        XCTAssertFalse(NearbyPrompt.isMovingFast([sample(0, 10), sample(1, 10)]))
        XCTAssertTrue(NearbyPrompt.isMovingFast([sample(0, 10), sample(2, 10)]))
        XCTAssertTrue(NearbyPrompt.isMovingFast([sample(2, 10), sample(0, 10)]))
        XCTAssertTrue(NearbyPrompt.isMovingFast([sample(0, 3), sample(1, 1), sample(2, 3)]))
        // Tam 2,5 m/s hızlı sayılmaz.
        XCTAssertFalse(NearbyPrompt.isMovingFast([sample(0, 2.5), sample(2, 2.5)]))
        // Durdu (ör. araçtan indi).
        XCTAssertFalse(NearbyPrompt.isMovingFast([sample(0, 10), sample(2, 10), sample(3, 1)]))
    }

    func testInvalidSpeedSamplesAreIgnored() {
        // 144 m/s ışınlanmadır.
        XCTAssertFalse(NearbyPrompt.isMovingFast([sample(0, 10), sample(2, 144)]))
        XCTAssertTrue(NearbyPrompt.isMovingFast([sample(0, 10), sample(2, 10), sample(3, 144)]))
        XCTAssertFalse(NearbyPrompt.isMovingFast([sample(0, 10), sample(2, 10, accuracy: -1)]))
        XCTAssertFalse(NearbyPrompt.isMovingFast([sample(0, -1), sample(2, 10)]))
        XCTAssertTrue(NearbyPrompt.isMovingFast([sample(0, 60), sample(2, 60)]))
    }

    // MARK: Sıklık

    private func gate(
        _ log: NearbyPrompt.Log = NearbyPrompt.Log(),
        activeSince: Date? = nil,
        ownReportAt: Date? = nil
    ) -> NearbyPrompt.Gate {
        NearbyPrompt.gate(
            log: log,
            activeSince: activeSince ?? now.addingTimeInterval(-3600),
            lastOwnReportAt: ownReportAt,
            at: now
        )
    }

    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }
    private func later(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    func testGateOpenByDefault() {
        XCTAssertEqual(gate(), .open)
    }

    func testStartupGrace() {
        XCTAssertEqual(gate(activeSince: ago(5)), .wait(until: later(10)))
        XCTAssertEqual(gate(activeSince: ago(15)), .open)
    }

    func testOwnReportGrace() {
        XCTAssertEqual(gate(ownReportAt: ago(10)), .wait(until: later(50)))
        XCTAssertEqual(gate(ownReportAt: ago(60)), .open)
    }

    func testCooldownAfterAnyShownPrompt() {
        XCTAssertEqual(gate(NearbyPrompt.Log(shownAt: [ago(5 * 60)])), .wait(until: later(5 * 60)))
        XCTAssertEqual(gate(NearbyPrompt.Log(shownAt: [ago(10 * 60)])), .open)
    }

    func testDailyLimit() {
        let hour: TimeInterval = 3600
        let four = [ago(23 * hour), ago(20 * hour), ago(15 * hour), ago(10 * hour)]
        XCTAssertEqual(gate(NearbyPrompt.Log(shownAt: four)), .open)
        XCTAssertEqual(gate(NearbyPrompt.Log(shownAt: four + [ago(5 * hour)])), .wait(until: later(1 * hour)))
        // 24 saatten eskisi sayılmaz.
        XCTAssertEqual(gate(NearbyPrompt.Log(shownAt: [ago(25 * hour)] + four)), .open)
        // Altıncı gösterim: iki eski gösterimin düşmesi gerekir.
        let six = [ago(22 * hour)] + four + [ago(5 * hour)]
        XCTAssertEqual(gate(NearbyPrompt.Log(shownAt: six)), .wait(until: later(2 * hour)))
    }

    func testQuietAfterThreeUnanswered() {
        var log = NearbyPrompt.Log()
        log.record(.unanswered, at: ago(3 * 3600))
        log.record(.unanswered, at: ago(2 * 3600))
        XCTAssertEqual(log.unansweredStreak, 2)
        XCTAssertNil(log.quietUntil)
        log.record(.unanswered, at: ago(3600))
        XCTAssertEqual(log.unansweredStreak, 0)
        let quietUntil = ago(3600).addingTimeInterval(NearbyPrompt.quietDuration)
        XCTAssertEqual(log.quietUntil, quietUntil)
        XCTAssertEqual(gate(log), .wait(until: quietUntil))
        XCTAssertEqual(
            NearbyPrompt.gate(log: log, activeSince: t0, lastOwnReportAt: nil, at: quietUntil),
            .open
        )
    }

    func testAnswerResetsStreakAndInterruptionIsNotCounted() {
        var log = NearbyPrompt.Log()
        log.record(.unanswered, at: ago(400))
        log.record(.unanswered, at: ago(300))
        log.record(.answered, at: ago(200))
        log.record(.unanswered, at: ago(100))
        XCTAssertEqual(log.unansweredStreak, 1)
        log.record(.interrupted, at: ago(50))
        log.record(.unanswered, at: ago(40))
        XCTAssertEqual(log.unansweredStreak, 2)
        XCTAssertNil(log.quietUntil)
    }

    func testSeveralLimitsWaitForTheLatest() {
        XCTAssertEqual(
            gate(NearbyPrompt.Log(shownAt: [ago(60)]), activeSince: ago(5), ownReportAt: ago(30)),
            .wait(until: later(9 * 60))
        )
    }

    func testLogRecordsAndPrunes() throws {
        var log = NearbyPrompt.Log()
        log.record(.shown, at: ago(25 * 3600))
        log.record(.shown, at: ago(60))
        XCTAssertEqual(log.shownAt, [ago(60)])
        log.quietUntil = ago(1)
        XCTAssertNil(log.pruned(at: now).quietUntil)
        log.quietUntil = later(1)
        XCTAssertEqual(log.pruned(at: now).quietUntil, later(1))

        let decoded = try JSONDecoder().decode(NearbyPrompt.Log.self, from: JSONEncoder().encode(log))
        XCTAssertEqual(decoded, log)
    }

    func testAskedReportsArePrunedAfterRetention() {
        let asked = ["old": ago(NearbyPrompt.askedRetention), "new": ago(3600)]
        XCTAssertEqual(NearbyPrompt.prunedAsked(asked, at: now), ["new": ago(3600)])
    }

    func testDismissDistance() {
        XCTAssertFalse(NearbyPrompt.isOutOfRange(distance: 80))
        XCTAssertTrue(NearbyPrompt.isOutOfRange(distance: 80.5))
        XCTAssertTrue(NearbyPrompt.isOutOfRange(distance: .nan))
    }

    // MARK: Yanıtlar

    func testOutcomeTable() {
        for need in Need.allCases {
            let available = ReportLifecycle.availableActions(for: makeReport(need: need), userID: dan, at: now)
            func outcome(_ step: NearbyPrompt.Step, _ answer: NearbyPrompt.Answer) -> NearbyPrompt.Outcome {
                NearbyPrompt.outcome(need: need, step: step, answer: answer, available: available)
            }
            let careful = NearbyPrompt.isCareful(need)
            XCTAssertEqual(careful, [Need.emergency, .injured, .babies].contains(need), need.rawValue)

            let yes: NearbyPrompt.Outcome = need == .food ? .next(.needsHelp) : .perform(.confirmStillThere)
            let no: NearbyPrompt.Outcome = careful ? .next(.confirmGone) : .perform(.reportGone)
            XCTAssertEqual(outcome(.presence, .first), yes, need.rawValue)
            XCTAssertEqual(outcome(.presence, .second), no, need.rawValue)
            XCTAssertEqual(outcome(.presence, .third), .dismiss, need.rawValue)

            let unneeded: NearbyPrompt.Outcome = need == .food ? .perform(.reportUnneeded) : .dismiss
            XCTAssertEqual(outcome(.needsHelp, .first), .perform(.confirmStillThere), need.rawValue)
            XCTAssertEqual(outcome(.needsHelp, .second), unneeded, need.rawValue)
            XCTAssertEqual(outcome(.needsHelp, .third), .dismiss, need.rawValue)

            XCTAssertEqual(outcome(.confirmGone, .first), .perform(.reportGone), need.rawValue)
            XCTAssertEqual(outcome(.confirmGone, .second), .dismiss, need.rawValue)
            XCTAssertEqual(outcome(.confirmGone, .third), .dismiss, need.rawValue)
        }
    }

    func testOutcomeRespectsAvailableActions() throws {
        // Mama, "Yardım gerekmiyor" kapalıyken: Evet doğrudan "Hâlâ orada".
        XCTAssertEqual(
            NearbyPrompt.outcome(need: .food, step: .presence, answer: .first, available: [.claim, .confirmStillThere, .reportGone]),
            .perform(.confirmStillThere)
        )
        // Evet, ama "Hâlâ orada" artık açık değil: yazmadan kapanır.
        XCTAssertEqual(
            NearbyPrompt.outcome(need: .injured, step: .presence, answer: .first, available: [.reportGone]),
            .dismiss
        )
        // dan zaten "Artık yok" dedi: Hayır bir şey yazmaz.
        for need in [Need.injured, .vet] {
            let voted = try ReportLifecycle.apply(.reportGone, to: makeReport(need: need), by: dan, at: minutes(2))
            let available = ReportLifecycle.availableActions(for: voted, userID: dan, at: now)
            XCTAssertFalse(available.contains(.reportGone))
            XCTAssertEqual(
                NearbyPrompt.outcome(need: need, step: .presence, answer: .second, available: available),
                .dismiss,
                need.rawValue
            )
            XCTAssertEqual(
                NearbyPrompt.outcome(need: need, step: .confirmGone, answer: .first, available: available),
                .dismiss,
                need.rawValue
            )
        }
    }

    func testResultAccounting() {
        XCTAssertEqual(NearbyPrompt.result(of: .first, at: .presence), .answered)
        XCTAssertEqual(NearbyPrompt.result(of: .second, at: .presence), .answered)
        XCTAssertEqual(NearbyPrompt.result(of: .third, at: .presence), .unanswered)
        XCTAssertEqual(NearbyPrompt.result(of: nil, at: .presence), .unanswered)
        // İlk adımda Evet ya da Hayır diyen yanıtlamış sayılır.
        XCTAssertEqual(NearbyPrompt.result(of: .third, at: .needsHelp), .answered)
        XCTAssertEqual(NearbyPrompt.result(of: nil, at: .needsHelp), .answered)
        XCTAssertEqual(NearbyPrompt.result(of: .second, at: .confirmGone), .answered)
        XCTAssertEqual(NearbyPrompt.result(of: nil, at: .confirmGone), .answered)
    }
}
