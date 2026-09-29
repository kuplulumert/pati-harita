import XCTest
@testable import AnimalKit

/// Uzaktan eylem kapısı: hangi eylemler kapılı, 12 sa / 1 sa pencereleri, işareti koyanın itirazı,
/// yakınlığın ölçüsü ve uğranan işaretlerin kaydı. İşareti alice koyar; kişi dan'dır.
final class ProximityPolicyTests: ReportTestCase {
    private var now: Date { hours(2) }

    private func allowed(
        _ action: ReportAction,
        on report: Report? = nil,
        by user: String? = nil,
        near: Bool = false,
        lastNearAgo: TimeInterval? = nil
    ) -> Bool {
        ProximityPolicy.allowed(
            action: action,
            report: report ?? makeReport(),
            userID: user ?? dan,
            isNear: near,
            lastNearAt: lastNearAgo.map { now.addingTimeInterval(-$0) },
            now: now
        )
    }

    /// Kişinin `north` metre güneyinde duran okuma: işaret (kadikoy) ondan `north` metre kuzeyde kalır.
    private func reading(north: Double = 0, accuracy: Double = 5, age: TimeInterval = 1, simulated: Bool = false) -> LocationFix {
        LocationFix(
            coordinate: kadikoy.offset(north: -north),
            timestamp: now.addingTimeInterval(-age),
            horizontalAccuracy: accuracy,
            isSimulatedBySoftware: simulated
        )
    }

    private func report(_ id: String, north: Double) -> Report {
        ReportLifecycle.makeReport(
            id: id,
            species: .cat,
            need: .injured,
            at: kadikoy.offset(north: north),
            reporterID: alice,
            now: t0
        )
    }

    func testConstants() {
        XCTAssertEqual(ProximityPolicy.resolveWindow, 12 * 3600)
        XCTAssertEqual(ProximityPolicy.observationWindow, 3600)
        XCTAssertEqual(ProximityPolicy.lastNearRetention, 24 * 3600)
        XCTAssertEqual(
            ProximityPolicy.gatedActions,
            [.resolve, .confirmStillThere, .reportGone, .reportUnneeded, .dispute]
        )
        XCTAssertEqual(ProximityPolicy.Presence.near, ProximityPolicy.Presence(isNear: true, lastNearAt: nil))
        XCTAssertEqual(ProximityPolicy.Presence.away, ProximityPolicy.Presence(isNear: false, lastNearAt: nil))
    }

    func testWindowPerAction() {
        for action in ReportAction.allCases {
            switch action {
            case .resolve:
                XCTAssertEqual(ProximityPolicy.window(for: action), ProximityPolicy.resolveWindow)
            case .confirmStillThere, .reportGone, .reportUnneeded, .dispute:
                XCTAssertEqual(ProximityPolicy.window(for: action), ProximityPolicy.observationWindow, action.rawValue)
            case .claim, .release, .confirmClosing, .undoClosing, .expire:
                XCTAssertNil(ProximityPolicy.window(for: action), action.rawValue)
            }
            XCTAssertEqual(ProximityPolicy.window(for: action) != nil, ProximityPolicy.gatedActions.contains(action))
        }
    }

    // MARK: Kim ne zaman

    func testUngatedActionsAreAllowedFromAnywhere() {
        for action in [ReportAction.claim, .release, .confirmClosing, .undoClosing, .expire] {
            XCTAssertTrue(allowed(action), action.rawValue)
            XCTAssertTrue(allowed(action, by: alice), action.rawValue)
            XCTAssertFalse(ProximityPolicy.isGated(action, on: makeReport(), userID: dan), action.rawValue)
        }
    }

    func testNearAllowsEveryGatedAction() {
        for action in ProximityPolicy.gatedActions {
            XCTAssertTrue(allowed(action, near: true), action.rawValue)
            XCTAssertTrue(allowed(action, near: true, lastNearAgo: 30 * 3600), action.rawValue)
            // Hiç uğramayan uzaktaki kişi hiçbirini diyemez.
            XCTAssertFalse(allowed(action), action.rawValue)
        }
    }

    /// "Çözüldü": son 12 saatte uğrayan (ör. hayvanı veterinere götüren) uzaktan da diyebilir.
    func testResolveWindowIsTwelveHours() {
        XCTAssertTrue(allowed(.resolve, lastNearAgo: 0))
        XCTAssertTrue(allowed(.resolve, lastNearAgo: 5 * 3600))
        XCTAssertTrue(allowed(.resolve, lastNearAgo: 12 * 3600))
        XCTAssertFalse(allowed(.resolve, lastNearAgo: 12 * 3600 + 1))
        XCTAssertFalse(allowed(.resolve, lastNearAgo: 20 * 3600))
    }

    /// Hayvanı gördüğünü söyleyen eylemler: son 1 saatte uğradıysa.
    func testObservationWindowIsOneHour() {
        let food = makeReport(need: .food)
        for action in [ReportAction.confirmStillThere, .reportGone, .reportUnneeded, .dispute] {
            XCTAssertTrue(allowed(action, on: food, lastNearAgo: 0), action.rawValue)
            XCTAssertTrue(allowed(action, on: food, lastNearAgo: 3600), action.rawValue)
            XCTAssertFalse(allowed(action, on: food, lastNearAgo: 3601), action.rawValue)
            XCTAssertFalse(allowed(action, on: food, lastNearAgo: 5 * 3600), action.rawValue)
        }
        // 5 saat önce uğrayan "Çözüldü" diyebilir ama "Hâlâ orada" diyemez.
        XCTAssertTrue(allowed(.resolve, lastNearAgo: 5 * 3600))
        XCTAssertFalse(allowed(.confirmStillThere, lastNearAgo: 5 * 3600))
    }

    /// Saat geri alınınca gelecekte kalan kayıt uğrama sayılmaz.
    func testFutureVisitDoesNotCount() {
        XCTAssertFalse(allowed(.resolve, lastNearAgo: -60))
        XCTAssertFalse(ProximityPolicy.visited(lastNearAt: now.addingTimeInterval(1), within: 3600, at: now))
        XCTAssertTrue(ProximityPolicy.visited(lastNearAt: now, within: 3600, at: now))
        XCTAssertFalse(ProximityPolicy.visited(lastNearAt: nil, within: 3600, at: now))
    }

    /// İşareti koyan "Hâlâ yardım gerekiyor"u her yerden der; diğer kapılı eylemleri ona da kapılı.
    func testReporterMayDisputeFromAnywhere() {
        let report = makeReport()
        XCTAssertFalse(ProximityPolicy.isGated(.dispute, on: report, userID: alice))
        XCTAssertTrue(allowed(.dispute, on: report, by: alice))
        XCTAssertTrue(ProximityPolicy.isGated(.dispute, on: report, userID: dan))
        XCTAssertFalse(allowed(.dispute, on: report, by: dan))
        // Kimlik yoksa işareti koyan sayılmaz.
        XCTAssertTrue(ProximityPolicy.isGated(.dispute, on: report, userID: nil))
        XCTAssertFalse(
            ProximityPolicy.allowed(action: .dispute, report: report, userID: nil, isNear: false, lastNearAt: nil, now: now)
        )
        for action in [ReportAction.resolve, .confirmStillThere, .reportGone, .reportUnneeded] {
            XCTAssertTrue(ProximityPolicy.isGated(action, on: report, userID: alice), action.rawValue)
            XCTAssertFalse(allowed(action, on: report, by: alice), action.rawValue)
        }
    }

    // MARK: Yakınlık

    /// İşaretleme kapısıyla aynı çevre: 150 m + doğruluk kadar (en fazla 75 m), kullanılabilir okumayla.
    func testNearUsesThePlacementRing() {
        func isNear(_ fix: LocationFix?, rejectsSimulated: Bool = true) -> Bool {
            ProximityPolicy.isNear(kadikoy, fix: fix, rejectsSimulated: rejectsSimulated, at: now)
        }
        XCTAssertTrue(isNear(reading(north: 0)))
        XCTAssertTrue(isNear(reading(north: 149.99, accuracy: 0)))
        XCTAssertFalse(isNear(reading(north: 151, accuracy: 0)))
        // Doğruluk çevreyi en fazla 75 m büyütür.
        XCTAssertTrue(isNear(reading(north: 200, accuracy: 60)))
        XCTAssertFalse(isNear(reading(north: 200, accuracy: 20)))
        XCTAssertTrue(isNear(reading(north: 224, accuracy: 100)))
        XCTAssertFalse(isNear(reading(north: 230, accuracy: 100)))
        // Kullanılamayan okuma: kaba, bayat, geçersiz ya da yok.
        XCTAssertFalse(isNear(reading(accuracy: 101)))
        XCTAssertFalse(isNear(reading(accuracy: -1)))
        XCTAssertFalse(isNear(reading(age: PlacementGate.maxFixAge + 1)))
        XCTAssertTrue(isNear(reading(age: PlacementGate.maxFixAge)))
        XCTAssertFalse(isNear(nil))
        XCTAssertFalse(ProximityPolicy.isNear(Coordinate(latitude: .nan, longitude: 29), fix: reading(), rejectsSimulated: false, at: now))
        // Taklit konum yalnızca istenirse reddedilir (işaretleme kapısındaki gibi).
        XCTAssertFalse(isNear(reading(simulated: true)))
        XCTAssertTrue(isNear(reading(simulated: true), rejectsSimulated: false))
    }

    /// Kartın döşeme yakınlığı ve "Hâlâ orada mı?" sorusu kapının içinde kalır: orada sorulan her soru
    /// yanıtlanabilir, "Hâlâ orada" döşemesi açık gelir.
    func testCardNearAndNearbyPromptImplyGateNear() {
        XCTAssertLessThanOrEqual(CardLayout.nearRadius, PlacementGate.radius)
        XCTAssertLessThanOrEqual(CardLayout.nearMaxAccuracy, PlacementGate.maxAccuracy)
        XCTAssertLessThanOrEqual(NearbyPrompt.dismissRadius, PlacementGate.radius)
        XCTAssertLessThanOrEqual(NearbyPrompt.maxAccuracy, PlacementGate.maxAccuracy)
        XCTAssertLessThanOrEqual(NearbyPrompt.maxFixAge, PlacementGate.maxFixAge)

        let cardFix = reading(north: CardLayout.nearRadius, accuracy: CardLayout.nearMaxAccuracy, age: PlacementGate.maxFixAge)
        XCTAssertTrue(
            CardLayout.isNear(
                distance: cardFix.coordinate.distance(to: kadikoy) - 1e-6,
                accuracy: cardFix.horizontalAccuracy,
                fixAge: cardFix.age(at: now)
            )
        )
        XCTAssertTrue(ProximityPolicy.isNear(kadikoy, fix: cardFix, rejectsSimulated: true, at: now))

        let promptFix = reading(north: NearbyPrompt.dismissRadius, accuracy: NearbyPrompt.maxAccuracy, age: NearbyPrompt.maxFixAge)
        XCTAssertTrue(NearbyPrompt.isUsable(promptFix, at: now))
        XCTAssertTrue(ProximityPolicy.isNear(kadikoy, fix: promptFix, rejectsSimulated: true, at: now))
    }

    func testNotNearbyMessage() {
        XCTAssertEqual(
            ReportError.notNearby.errorDescription,
            "Bunu söylemek için hayvanın 150 m yakınında olmalısın."
        )
        XCTAssertEqual(PlacementGate.radius, 150)
    }

    // MARK: Uğranan işaretler

    /// Okumanın çevresindeki işaretler okumanın anıyla yazılır; uzaktakiler yazılmaz.
    func testUpdatedLastNearRecordsReportsInsideTheRing() {
        let near = report("near", north: 120)
        let far = report("far", north: 400)
        let fix = reading(accuracy: 5, age: 3)
        let updated = ProximityPolicy.updatedLastNear([:], reports: [near, far], fix: fix, rejectsSimulated: true, at: now)
        XCTAssertEqual(updated, ["near": fix.timestamp])

        // Kayıt yalnızca ileri gider: aynı okuma ya da daha eskisi değiştirmez, yenisi değiştirir.
        XCTAssertEqual(
            ProximityPolicy.updatedLastNear(updated, reports: [near], fix: reading(age: 10), rejectsSimulated: true, at: now),
            updated
        )
        let later = now.addingTimeInterval(30)
        let fresh = LocationFix(coordinate: fix.coordinate, timestamp: later, horizontalAccuracy: 5)
        XCTAssertEqual(
            ProximityPolicy.updatedLastNear(updated, reports: [near], fix: fresh, rejectsSimulated: true, at: later),
            ["near": later]
        )
    }

    /// Kullanılamayan, taklit ya da hiç olmayan okuma yazmaz; yalnızca budar.
    func testUnusableFixOnlyPrunes() {
        let near = report("near", north: 20)
        let old = ["old": now.addingTimeInterval(-25 * 3600), "kept": now.addingTimeInterval(-3600)]
        for fix in [reading(accuracy: 150), reading(age: 300), reading(simulated: true), nil] {
            XCTAssertEqual(
                ProximityPolicy.updatedLastNear(old, reports: [near], fix: fix, rejectsSimulated: true, at: now),
                ["kept": now.addingTimeInterval(-3600)]
            )
        }
        // Taklit konum kabul ediliyorsa yazılır.
        XCTAssertEqual(
            ProximityPolicy.updatedLastNear([:], reports: [near], fix: reading(simulated: true), rejectsSimulated: false, at: now).keys.sorted(),
            ["near"]
        )
    }

    /// Okumanın anı `now`dan ileride olsa da kayıt `now`u geçmez; saat geri alındıysa gelecekteki kayıt yenilenir.
    func testStampNeverInTheFuture() {
        let near = report("near", north: 20)
        let ahead = reading(age: -5)
        XCTAssertEqual(
            ProximityPolicy.updatedLastNear([:], reports: [near], fix: ahead, rejectsSimulated: true, at: now),
            ["near": now]
        )
        let stale = ["near": now.addingTimeInterval(3 * 3600)]
        XCTAssertEqual(
            ProximityPolicy.updatedLastNear(stale, reports: [near], fix: reading(age: 2), rejectsSimulated: true, at: now),
            ["near": now.addingTimeInterval(-2)]
        )
    }

    /// 24 saatten eski (ve 24 saatten ileride) kayıtlar atılır.
    func testPrunedLastNear() {
        let log: [String: Date] = [
            "fresh": now,
            "day": now.addingTimeInterval(-24 * 3600 + 1),
            "expired": now.addingTimeInterval(-24 * 3600),
            "soon": now.addingTimeInterval(60),
            "farFuture": now.addingTimeInterval(24 * 3600),
        ]
        XCTAssertEqual(
            Set(ProximityPolicy.prunedLastNear(log, at: now).keys),
            ["fresh", "day", "soon"]
        )
    }
}
