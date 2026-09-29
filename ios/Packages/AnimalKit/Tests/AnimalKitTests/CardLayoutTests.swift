import XCTest
@testable import AnimalKit

/// Kartın düzeni (`CardLayout.plan`): her durumda birincil düğme, döşemeler ve "⋯ Diğer" menüsü.
/// Hiçbir eylem kaybolmaz; her öğe kartta tam bir kez yer alır.
final class CardLayoutTests: ReportTestCase {
    /// Uygulamada "Konumu paylaş" sunulan ihtiyaçlar (MapViewModel.shareLocationNeeds).
    private let shareNeeds: Set<Need> = [.emergency, .injured, .babies]
    private let flagHideMail: [CardItem] = [.flag, .hide, .mail]

    /// Uygulamanın vereceği girdilerle: Düzenle `canEdit`ten, bildir / gizle işareti koyan dışındakilere.
    private func plan(_ report: Report, for userID: String, at now: Date, near: Bool = false, hasMail: Bool = true) -> CardPlan {
        CardLayout.plan(
            for: report,
            userID: userID,
            at: now,
            isNear: near,
            canEdit: ReportLifecycle.canEdit(report, by: userID, at: now),
            canShare: shareNeeds.contains(report.need),
            canFlag: report.reporterID != userID,
            hasMail: hasMail
        )
    }

    // MARK: Yakınlık

    func testNearNeedsCloseFreshAccurateFix() {
        XCTAssertEqual(CardLayout.nearRadius, 100)
        XCTAssertEqual(CardLayout.nearMaxAccuracy, 50)
        XCTAssertTrue(CardLayout.isNear(distance: 0, accuracy: 5, fixAge: 0))
        XCTAssertTrue(CardLayout.isNear(distance: 100, accuracy: 50, fixAge: PlacementGate.maxFixAge))
        XCTAssertFalse(CardLayout.isNear(distance: 101, accuracy: 10, fixAge: 10))
        XCTAssertFalse(CardLayout.isNear(distance: 50, accuracy: 51, fixAge: 10))
        XCTAssertFalse(CardLayout.isNear(distance: 50, accuracy: 10, fixAge: PlacementGate.maxFixAge + 1))
        // CoreLocation geçersiz konumda negatif doğruluk verir.
        XCTAssertFalse(CardLayout.isNear(distance: 50, accuracy: -1, fixAge: 10))
        XCTAssertFalse(CardLayout.isNear(distance: .nan, accuracy: 10, fixAge: 10))
    }

    // MARK: Durumlar

    /// 2.1 Bekleyen işaret, yoldan geçen: İlgileniyorum; uzakta Yol tarifi, yakında Hâlâ orada.
    func testWaitingPasserBy() throws {
        let seen = try seenReport()
        XCTAssertEqual(
            plan(seen, for: dan, at: minutes(30)),
            CardPlan(
                primary: .claim,
                tiles: [.directions],
                observe: [.action(.confirmStillThere), .action(.reportGone)],
                more: [.action(.resolve), .shareLocation],
                moderation: flagHideMail
            )
        )
        XCTAssertEqual(
            plan(seen, for: dan, at: minutes(30), near: true),
            CardPlan(
                primary: .claim,
                tiles: [.action(.confirmStillThere)],
                observe: [.action(.reportGone)],
                more: [.action(.resolve), .directions, .shareLocation],
                moderation: flagHideMail
            )
        )
        // İletişim adresi yoksa e-posta menüde yok.
        XCTAssertEqual(plan(seen, for: dan, at: minutes(30), hasMail: false).moderation, [.flag, .hide])

        // "Artık yok" diyen onu bir daha görmez; başkası görür.
        let voted = try ReportLifecycle.apply(.reportGone, to: makeReport(), by: cara, at: minutes(3))
        XCTAssertEqual(
            plan(voted, for: cara, at: minutes(30)),
            CardPlan(
                primary: .claim,
                tiles: [.directions],
                observe: [.action(.confirmStillThere)],
                more: [.action(.resolve), .shareLocation],
                moderation: flagHideMail
            )
        )
        XCTAssertEqual(plan(voted, for: dan, at: minutes(30)).observe, [.action(.confirmStillThere), .action(.reportGone)])
    }

    /// 2.1 Dediğine itiraz edilen kişi: birincil düğme yok, döşeme yakınlığa göre.
    func testDisputedViewerHasNoPrimary() throws {
        let report = try disputedReport(by: [dan])
        XCTAssertEqual(
            plan(report, for: dan, at: minutes(20)),
            CardPlan(
                primary: nil,
                tiles: [.directions],
                observe: [.action(.confirmStillThere), .action(.reportGone)],
                more: [.shareLocation],
                moderation: flagHideMail
            )
        )
        XCTAssertEqual(
            plan(report, for: dan, at: minutes(20), near: true),
            CardPlan(
                primary: nil,
                tiles: [.action(.confirmStillThere)],
                observe: [.action(.reportGone)],
                more: [.directions, .shareLocation],
                moderation: flagHideMail
            )
        )
    }

    /// 2.2 Sen ilgileniyorsun: Çözüldü; uzakta Yol tarifi, yakında Artık yok; ağır ihtiyaçta Konumu paylaş.
    func testHelper() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: seenReport(), by: bob, at: minutes(2))
        XCTAssertEqual(
            plan(claimed, for: bob, at: minutes(10)),
            CardPlan(
                primary: .resolve,
                tiles: [.directions, .shareLocation],
                observe: [.action(.reportGone)],
                more: [.action(.release)],
                moderation: flagHideMail
            )
        )
        XCTAssertEqual(
            plan(claimed, for: bob, at: minutes(10), near: true),
            CardPlan(
                primary: .resolve,
                tiles: [.action(.reportGone), .shareLocation],
                observe: [],
                more: [.action(.release), .directions],
                moderation: flagHideMail
            )
        )

        // Veteriner işaretinde Konumu paylaş yok.
        let vet = try ReportLifecycle.apply(.claim, to: seenReport(need: .vet), by: bob, at: minutes(2))
        XCTAssertEqual(
            plan(vet, for: bob, at: minutes(10)),
            CardPlan(
                primary: .resolve,
                tiles: [.directions],
                observe: [.action(.reportGone)],
                more: [.action(.release)],
                moderation: flagHideMail
            )
        )

        // Mamada "Yardım gerekmiyor" ayrı bir öğedir.
        let food = try ReportLifecycle.apply(.claim, to: seenReport(need: .food), by: bob, at: minutes(2))
        XCTAssertEqual(
            plan(food, for: bob, at: minutes(10)),
            CardPlan(
                primary: .resolve,
                tiles: [.directions],
                observe: [.action(.reportUnneeded), .action(.reportGone)],
                more: [.action(.release)],
                moderation: flagHideMail
            )
        )

        // Önce "Artık yok" deyip sonra üstüne alan kişi yakında da Yol tarifi görür.
        let voted = try ReportLifecycle.apply(.reportGone, to: makeReport(), by: cara, at: minutes(3))
        let votedThenClaimed = try ReportLifecycle.apply(.claim, to: voted, by: cara, at: minutes(4))
        XCTAssertEqual(
            plan(votedThenClaimed, for: cara, at: minutes(10), near: true),
            CardPlan(
                primary: .resolve,
                tiles: [.directions, .shareLocation],
                observe: [],
                more: [.action(.release)],
                moderation: flagHideMail
            )
        )
    }

    /// 2.3 Biri tazece ilgileniyor: uzaktaki yoldan geçene düğme yok; işareti koyana Çözüldü.
    func testFreshClaimByOther() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: seenReport(), by: bob, at: minutes(2))
        XCTAssertEqual(
            plan(claimed, for: dan, at: minutes(10)),
            CardPlan(
                primary: nil,
                tiles: [],
                observe: [.action(.confirmStillThere), .action(.reportGone)],
                more: [.directions, .shareLocation],
                moderation: flagHideMail
            )
        )
        XCTAssertEqual(
            plan(claimed, for: dan, at: minutes(10), near: true),
            CardPlan(
                primary: nil,
                tiles: [.action(.confirmStillThere)],
                observe: [.action(.reportGone)],
                more: [.directions, .shareLocation],
                moderation: flagHideMail
            )
        )
        XCTAssertEqual(
            plan(claimed, for: alice, at: minutes(10)),
            CardPlan(
                primary: .resolve,
                tiles: [.directions],
                observe: [.action(.confirmStillThere), .action(.reportGone)],
                more: [.shareLocation],
                moderation: []
            )
        )
        XCTAssertEqual(
            plan(claimed, for: alice, at: minutes(10), near: true),
            CardPlan(
                primary: .resolve,
                tiles: [.action(.confirmStillThere)],
                observe: [.action(.reportGone)],
                more: [.directions, .shareLocation],
                moderation: []
            )
        )
    }

    /// 2.4 Sahiplik 45 dk'yı geçti: yoldan geçene yeniden Yol tarifi; işareti koyana İlgilenen gelmedi.
    func testStaleClaimByOther() throws {
        let claimed = try ReportLifecycle.apply(.claim, to: seenReport(), by: bob, at: minutes(2))
        XCTAssertEqual(
            plan(claimed, for: dan, at: minutes(50)),
            CardPlan(
                primary: nil,
                tiles: [.directions],
                observe: [.action(.confirmStillThere), .action(.reportGone)],
                more: [.action(.resolve), .shareLocation],
                moderation: flagHideMail
            )
        )
        XCTAssertEqual(
            plan(claimed, for: dan, at: minutes(50), near: true),
            CardPlan(
                primary: nil,
                tiles: [.action(.confirmStillThere)],
                observe: [.action(.reportGone)],
                more: [.action(.resolve), .directions, .shareLocation],
                moderation: flagHideMail
            )
        )
        let reporter = CardPlan(
            primary: .resolve,
            tiles: [.action(.release)],
            observe: [.action(.confirmStillThere), .action(.reportGone)],
            more: [.directions, .shareLocation],
            moderation: []
        )
        XCTAssertEqual(plan(claimed, for: alice, at: minutes(50)), reporter)
        XCTAssertEqual(plan(claimed, for: alice, at: minutes(50), near: true), reporter)
    }

    /// 2.5 Başkası "Çözüldü" dedi: Hâlâ yardım gerekiyor döşemesi; itiraz ettiysen yalnızca Diğer.
    func testClosingByOther() throws {
        let byPasserBy = try ReportLifecycle.apply(.resolve, to: seenReport(), by: bob, at: minutes(30))
        let expected = CardPlan(
            primary: nil,
            tiles: [.action(.dispute)],
            observe: [],
            more: [.directions, .shareLocation],
            moderation: flagHideMail
        )
        XCTAssertEqual(plan(byPasserBy, for: dan, at: minutes(35)), expected)
        XCTAssertEqual(plan(byPasserBy, for: dan, at: minutes(35), near: true), expected)
        // Hayvanı gören kişi de yalnızca işareti koyanın önerisini onaylayabilir.
        XCTAssertEqual(plan(byPasserBy, for: cara, at: minutes(35)), expected)

        let objected = try ReportLifecycle.apply(.dispute, to: byPasserBy, by: cara, at: minutes(40))
        let secondRound = try ReportLifecycle.apply(.resolve, to: objected, by: dan, at: minutes(50))
        XCTAssertEqual(
            plan(secondRound, for: cara, at: minutes(55)),
            CardPlan(primary: nil, tiles: [], observe: [], more: [.directions, .shareLocation], moderation: flagHideMail)
        )
    }

    /// 2.6 Onaylayan (işareti koyan ya da koyanın önerisinde hayvanı gören): "Evet" birincil, itiraz alt satırda.
    func testConfirmerSeesYesAndObjectionOnSeparateRows() throws {
        let byPasserBy = try ReportLifecycle.apply(.resolve, to: seenReport(), by: bob, at: minutes(30))
        let reporter = CardPlan(
            primary: .confirmClosing,
            tiles: [.action(.dispute)],
            observe: [],
            more: [.directions, .shareLocation],
            moderation: []
        )
        XCTAssertEqual(plan(byPasserBy, for: alice, at: minutes(35)), reporter)
        XCTAssertEqual(plan(byPasserBy, for: alice, at: minutes(35), near: true), reporter)

        let byReporter = try ReportLifecycle.apply(.resolve, to: seenReport(), by: alice, at: minutes(30))
        XCTAssertEqual(
            plan(byReporter, for: cara, at: minutes(35)),
            CardPlan(
                primary: .confirmClosing,
                tiles: [.action(.dispute)],
                observe: [],
                more: [.directions, .shareLocation],
                moderation: flagHideMail
            )
        )

        // "Yardım gerekmiyor dendi" (mama): Konumu paylaş yok.
        let unneeded = try ReportLifecycle.apply(.reportUnneeded, to: seenReport(need: .food), by: bob, at: minutes(30))
        XCTAssertEqual(
            plan(unneeded, for: alice, at: minutes(35)),
            CardPlan(primary: .confirmClosing, tiles: [.action(.dispute)], observe: [], more: [.directions], moderation: [])
        )
    }

    /// 2.7 Kendi önerin: 10 dk Geri al; sonra yalnızca Diğer (Yol tarifi orada kalır).
    func testOwnProposal() throws {
        let byPasserBy = try ReportLifecycle.apply(.resolve, to: seenReport(), by: bob, at: minutes(30))
        XCTAssertEqual(
            plan(byPasserBy, for: bob, at: minutes(35)),
            CardPlan(primary: .undoClosing, tiles: [], observe: [], more: [.directions, .shareLocation], moderation: flagHideMail)
        )
        XCTAssertEqual(
            plan(byPasserBy, for: bob, at: minutes(45)),
            CardPlan(primary: nil, tiles: [], observe: [], more: [.directions, .shareLocation], moderation: flagHideMail)
        )

        let byReporter = try ReportLifecycle.apply(.resolve, to: seenReport(), by: alice, at: minutes(30))
        XCTAssertEqual(
            plan(byReporter, for: alice, at: minutes(35)),
            CardPlan(primary: .undoClosing, tiles: [], observe: [], more: [.directions, .shareLocation], moderation: [])
        )
    }

    /// 2.8 Kendi yeni işaretin: Düzenle döşemesi; 30 dk sonra ya da biri dokununca yakınlık kuralı.
    func testOwnNewPin() throws {
        let food = makeReport(need: .food)
        let editable = CardPlan(
            primary: .claim,
            tiles: [.edit],
            observe: [.action(.confirmStillThere), .action(.reportUnneeded), .action(.reportGone)],
            more: [.action(.resolve), .directions],
            moderation: []
        )
        XCTAssertEqual(plan(food, for: alice, at: minutes(10)), editable)
        XCTAssertEqual(plan(food, for: alice, at: minutes(10), near: true), editable)
        XCTAssertEqual(
            plan(makeReport(), for: alice, at: minutes(10)),
            CardPlan(
                primary: .claim,
                tiles: [.edit],
                observe: [.action(.confirmStillThere), .action(.reportGone)],
                more: [.action(.resolve), .directions, .shareLocation],
                moderation: []
            )
        )

        let settled = CardPlan(
            primary: .claim,
            tiles: [.directions],
            observe: [.action(.confirmStillThere), .action(.reportUnneeded), .action(.reportGone)],
            more: [.action(.resolve)],
            moderation: []
        )
        XCTAssertEqual(plan(food, for: alice, at: minutes(31)), settled)
        XCTAssertEqual(
            plan(food, for: alice, at: minutes(31), near: true),
            CardPlan(
                primary: .claim,
                tiles: [.action(.confirmStillThere)],
                observe: [.action(.reportUnneeded), .action(.reportGone)],
                more: [.action(.resolve), .directions],
                moderation: []
            )
        )
        let touched = try seenReport(need: .food)
        XCTAssertEqual(plan(touched, for: alice, at: minutes(10)), settled)
    }

    /// 2.9 Mama işareti, yoldan geçen: "Hâlâ yardım lazım", "Yardım gerekmiyor" ve "Artık yok" ayrı öğeler.
    func testFoodPasserBy() throws {
        let food = try seenReport(need: .food)
        XCTAssertEqual(
            plan(food, for: dan, at: minutes(30)),
            CardPlan(
                primary: .claim,
                tiles: [.directions],
                observe: [.action(.confirmStillThere), .action(.reportUnneeded), .action(.reportGone)],
                more: [.action(.resolve)],
                moderation: flagHideMail
            )
        )
        XCTAssertEqual(
            plan(food, for: dan, at: minutes(30), near: true),
            CardPlan(
                primary: .claim,
                tiles: [.action(.confirmStillThere)],
                observe: [.action(.reportUnneeded), .action(.reportGone)],
                more: [.action(.resolve), .directions],
                moderation: flagHideMail
            )
        )
    }

    /// Kimlik henüz yokken eylem sunulmaz; Yol tarifi ve Konumu paylaş yine vardır.
    func testWithoutUserOnlyNavigation() {
        XCTAssertEqual(
            CardLayout.plan(
                for: makeReport(),
                userID: nil,
                at: minutes(10),
                isNear: false,
                canEdit: false,
                canShare: true,
                canFlag: false,
                hasMail: true
            ),
            CardPlan(primary: nil, tiles: [.directions], observe: [], more: [.shareLocation], moderation: [])
        )
    }

    // MARK: Değişmez kural

    /// Birincil + döşemeler + menü, çoklu küme olarak: `expire` dışındaki açık eylemler, Yol tarifi ve izin
    /// verilen Düzenle / Konumu paylaş / bildir / gizle / e-posta. Hiçbiri iki kez yok, en fazla iki döşeme,
    /// "Evet, çözüldü" ile "Hâlâ yardım gerekiyor" aynı satırda değil.
    func testEveryItemIsReachableExactlyOnce() throws {
        let observation: Set<CardItem> = [.action(.confirmStillThere), .action(.reportUnneeded), .action(.reportGone)]
        let moderationItems: Set<CardItem> = [.flag, .hide, .mail]
        let flagOptions: [(canFlag: Bool, hasMail: Bool)] = [(false, true), (true, false), (true, true)]
        var tileShapes = Set<[CardItem]>()
        var primaries = Set<ReportAction?>()
        var checked = 0

        for (report, now) in try generatedStates() {
            for user in [alice, bob, cara, dan, eve] {
                let actions = ReportLifecycle.availableActions(for: report, userID: user, at: now)
                for isNear in [false, true] {
                    for canEdit in [false, true] {
                        for canShare in [false, true] {
                            let (canFlag, hasMail) = flagOptions[checked % flagOptions.count]
                            checked += 1
                            let plan = CardLayout.plan(
                                for: report,
                                userID: user,
                                at: now,
                                isNear: isNear,
                                canEdit: canEdit,
                                canShare: canShare,
                                canFlag: canFlag,
                                hasMail: hasMail
                            )
                            let minute = now.timeIntervalSince(t0) / 60
                            let context: () -> String = {
                                let inputs = "yakın:\(isNear) düzenle:\(canEdit) paylaş:\(canShare) bildir:\(canFlag) e-posta:\(hasMail)"
                                return "\(report.status) \(report.need) \(user) \(minute) dk \(inputs) \(actions) → \(plan)"
                            }

                            var expected: [CardItem] = actions.filter { $0 != .expire }.map(CardItem.action)
                            expected.append(.directions)
                            if canEdit { expected.append(.edit) }
                            if canShare { expected.append(.shareLocation) }
                            if canFlag {
                                expected.append(.flag)
                                expected.append(.hide)
                                if hasMail { expected.append(.mail) }
                            }

                            let primaryRow: [CardItem] = plan.primary.map { [CardItem.action($0)] } ?? []
                            let placed = primaryRow + plan.tiles + plan.menuItems
                            XCTAssertEqual(Set(placed).count, placed.count, context())
                            XCTAssertEqual(placed.count, expected.count, context())
                            XCTAssertEqual(Set(placed), Set(expected), context())

                            XCTAssertLessThanOrEqual(plan.tiles.count, 2, context())
                            for row in [primaryRow, plan.tiles] {
                                XCTAssertFalse(
                                    row.contains(.action(.confirmClosing)) && row.contains(.action(.dispute)),
                                    context()
                                )
                            }

                            // Birincil düğme bugünkü kuralla: ilk eylem, yalnızca bu dördünden biriyse.
                            if let first = actions.first, CardLayout.primaryActions.contains(first) {
                                XCTAssertEqual(plan.primary, first, context())
                            } else {
                                XCTAssertNil(plan.primary, context())
                            }
                            if canEdit { XCTAssertEqual(plan.tiles, [.edit], context()) }

                            XCTAssertTrue(plan.observe.allSatisfy { observation.contains($0) }, context())
                            XCTAssertTrue(
                                plan.more.allSatisfy { !observation.contains($0) && !moderationItems.contains($0) },
                                context()
                            )
                            XCTAssertTrue(plan.moderation.allSatisfy { moderationItems.contains($0) }, context())

                            tileShapes.insert(plan.tiles)
                            primaries.insert(plan.primary)
                        }
                    }
                }
            }
        }

        // Üretilen durumlar her döşeme kuralına ve her birincil düğmeye ulaştı.
        let expectedShapes: Set<[CardItem]> = [
            [.edit],
            [.action(.dispute)],
            [],
            [.directions],
            [.action(.confirmStillThere)],
            [.action(.release)],
            [.directions, .shareLocation],
            [.action(.reportGone), .shareLocation],
            [.action(.reportGone)],
        ]
        XCTAssertTrue(expectedShapes.isSubset(of: tileShapes), "\(expectedShapes.subtracting(tileShapes))")
        XCTAssertEqual(primaries, [nil, .claim, .resolve, .confirmClosing, .undoClosing])
    }

    // MARK: Yardımcılar

    /// `phaseCatalogue` ile rastgele eylem dizilerinden üretilen işaretler: her ihtiyaçta `walks` yürüyüş;
    /// her adımda saat ilerler ve biri kendisine açık bir eylemi uygular. Tohum sabit: her çalıştırmada aynı durumlar.
    private func generatedStates(walks: Int = 10, steps: Int = 12) throws -> [(report: Report, now: Date)] {
        var random = SplitMix64(seed: 2026)
        let people = [alice, bob, cara, dan, eve]
        // Geri alma (10 dk), bayat sahiplik (45 dk) ve sahiplik süresi (3 sa) sınırlarını aşan adımlar.
        let gaps: [TimeInterval] = [30, 4 * 60, 11 * 60, 46 * 60, 2 * 3600]
        var states: [(report: Report, now: Date)] = try phaseCatalogue().map { (report: $0.report, now: $0.now) }
        for need in Need.allCases {
            for _ in 0..<walks {
                var report = makeReport(need: need)
                var now = t0
                for _ in 0..<steps {
                    now = now.addingTimeInterval(gaps.randomElement(using: &random) ?? 60)
                    let user = people.randomElement(using: &random) ?? alice
                    let actions = ReportLifecycle.availableActions(for: report, userID: user, at: now)
                    let credible = Bool.random(using: &random)
                    if let action = actions.randomElement(using: &random),
                       let next = try? ReportLifecycle.apply(action, to: report, by: user, at: now, credible: credible) {
                        report = next
                    }
                    states.append((report: report, now: now))
                    if !report.isActive(at: now) { break }
                }
            }
        }
        return states
    }
}

/// Tohumlu, tekrarlanabilir rastgele sayı üreteci (SplitMix64).
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
