import XCTest
@testable import AnimalKit

/// "Çözüldü dendi" işaretinin kimin haritasında nasıl göründüğü ve sayılıp sayılmadığı.
final class ClosingDisplayTests: XCTestCase {
    private let alice = "alice" // işareti koyan
    private let bob = "bob" // "Çözüldü" diyen
    private let cara = "cara" // hayvanı gördüğünü söyledi
    private let dan = "dan" // haritaya bakan başka biri
    /// 2026-09-21 00.00, Türkiye saati (UTC+3).
    private let midnight = Date(timeIntervalSince1970: 1_789_938_000)

    /// Gece yarısından bu yana geçen dakika.
    private func at(_ minutes: Int) -> Date { midnight.addingTimeInterval(TimeInterval(minutes * 60)) }

    private func openReport(need: Need = .food) -> Report {
        ReportLifecycle.makeReport(
            id: "r1",
            species: .dog,
            need: need,
            at: Coordinate(latitude: 41.0082, longitude: 28.9784),
            reporterID: alice,
            now: at(10 * 60)
        )
    }

    /// 10.00'da konan, 11.00'de cara'nın da gördüğü, 12.00'de bob'un "Çözüldü" dediği işaret.
    private func proposed(need: Need = .food, credible: Bool) throws -> Report {
        let seen = try ReportLifecycle.apply(.confirmStillThere, to: openReport(need: need), by: cara, at: at(11 * 60))
        return try ReportLifecycle.apply(.resolve, to: seen, by: bob, at: at(12 * 60), credible: credible)
    }

    // MARK: Haritadan kalkış

    func testDemoteAtCountsOnlyDaytime() {
        let table: [(close: Int, need: Need, leaves: Int)] = [
            (12 * 60, .food, 13 * 60),
            (23 * 60 + 30, .food, 24 * 60 + 7 * 60 + 30),
            (23 * 60 + 30, .injured, 24 * 60 + 8 * 60 + 30),
            (22 * 60 + 30, .injured, 24 * 60 + 7 * 60 + 30),
            (2 * 60, .food, 8 * 60),
            (2 * 60, .babies, 9 * 60),
            (6 * 60 + 59, .food, 8 * 60),
            // Sınırlar: gündüz tam 07.00'de başlar, gece yarısında biter.
            (7 * 60, .emergency, 9 * 60),
            (23 * 60, .other, 24 * 60),
            (23 * 60, .shelter, 24 * 60 + 8 * 60),
        ]
        for row in table {
            XCTAssertEqual(
                ClosingDisplay.demoteAt(closingAt: at(row.close), need: row.need),
                at(row.leaves),
                "\(row.close / 60).\(row.close % 60) \(row.need)"
            )
        }
    }

    // MARK: Görünüş

    func testLookInDemoteMode() throws {
        let credible = try proposed(credible: true)
        // Başkası: kalkana kadar soluk, sonra gizli.
        XCTAssertEqual(
            ClosingDisplay.look(of: credible, mode: .demote, viewer: dan, answered: false, at: at(12 * 60 + 30)),
            .fading(leavesAt: at(13 * 60))
        )
        XCTAssertEqual(ClosingDisplay.look(of: credible, mode: .demote, viewer: dan, answered: false, at: at(13 * 60)), .hidden)
        XCTAssertEqual(ClosingDisplay.look(of: credible, mode: .demote, viewer: nil, answered: false, at: at(13 * 60)), .hidden)
        // Kapatanın haritasından hemen kalkar.
        XCTAssertEqual(ClosingDisplay.look(of: credible, mode: .demote, viewer: bob, answered: false, at: at(12 * 60 + 1)), .hidden)
        // İşareti koyan ve hayvanı gören, yanıtlayana kadar görmeye devam eder.
        for viewer in [alice, cara] {
            XCTAssertEqual(
                ClosingDisplay.look(of: credible, mode: .demote, viewer: viewer, answered: false, at: at(14 * 60)),
                .fading(leavesAt: at(13 * 60)),
                viewer
            )
            XCTAssertEqual(
                ClosingDisplay.look(of: credible, mode: .demote, viewer: viewer, answered: true, at: at(14 * 60)),
                .hidden,
                viewer
            )
        }
        XCTAssertTrue(ClosingDisplay.isStakeholder(credible, viewer: cara))
        XCTAssertFalse(ClosingDisplay.isStakeholder(credible, viewer: bob))
        XCTAssertFalse(ClosingDisplay.isStakeholder(credible, viewer: dan))
    }

    func testSeriousNeedsStayTwoDaytimeHours() throws {
        let injured = try proposed(need: .injured, credible: true)
        XCTAssertEqual(
            ClosingDisplay.look(of: injured, mode: .demote, viewer: dan, answered: false, at: at(13 * 60 + 30)),
            .fading(leavesAt: at(14 * 60))
        )
    }

    func testLookInLabelAndStrictModes() throws {
        let credible = try proposed(credible: true)
        XCTAssertEqual(
            ClosingDisplay.look(of: credible, mode: .label, viewer: dan, answered: false, at: at(20 * 60)),
            .fading(leavesAt: nil)
        )
        XCTAssertEqual(ClosingDisplay.look(of: credible, mode: .strict, viewer: dan, answered: false, at: at(20 * 60)), .unverified)
        XCTAssertEqual(ClosingDisplay.look(of: credible, mode: .strict, viewer: bob, answered: false, at: at(20 * 60)), .hidden)
    }

    func testUnverifiedProposalNeverHidesForOthers() throws {
        let unverified = try proposed(credible: false)
        for mode in ClosingMode.allCases {
            XCTAssertEqual(
                ClosingDisplay.look(of: unverified, mode: mode, viewer: dan, answered: false, at: at(20 * 60)),
                .unverified,
                mode.rawValue
            )
            XCTAssertEqual(
                ClosingDisplay.look(of: unverified, mode: mode, viewer: alice, answered: true, at: at(20 * 60)),
                .unverified,
                mode.rawValue
            )
            XCTAssertEqual(
                ClosingDisplay.look(of: unverified, mode: mode, viewer: bob, answered: false, at: at(12 * 60 + 1)),
                .hidden,
                mode.rawValue
            )
        }
    }

    func testLookIsNilUnlessClosing() throws {
        XCTAssertNil(ClosingDisplay.look(of: openReport(), mode: .demote, viewer: dan, answered: false, at: at(11 * 60)))
        let agreed = try ReportLifecycle.apply(.confirmClosing, to: proposed(credible: true), by: alice, at: at(12 * 60 + 10))
        XCTAssertNil(ClosingDisplay.look(of: agreed, mode: .demote, viewer: dan, answered: false, at: at(12 * 60 + 11)))
    }

    func testFallbackModeIsLabel() {
        XCTAssertEqual(ClosingMode.fallback, .label)
        XCTAssertEqual(ClosingMode(rawValue: "unknown") ?? .fallback, .label)
    }

    // MARK: "N hayvan yardım bekliyor"

    func testCountsAsWaiting() throws {
        let open = openReport()
        XCTAssertTrue(ClosingDisplay.countsAsWaiting(open, viewer: dan, mode: .demote, at: at(11 * 60)))
        XCTAssertTrue(ClosingDisplay.countsAsWaiting(open, viewer: nil, mode: .demote, at: at(11 * 60)))
        // Süresi dolan (mama: 12 sa) sayılmaz.
        XCTAssertFalse(ClosingDisplay.countsAsWaiting(open, viewer: dan, mode: .demote, at: at(22 * 60)))

        // Başkasının sahipliği 45 dk sonra yeniden sayılır; ilgilenen için sayılmaz.
        let claimed = try ReportLifecycle.apply(.claim, to: open, by: bob, at: at(11 * 60))
        XCTAssertFalse(ClosingDisplay.countsAsWaiting(claimed, viewer: dan, mode: .demote, at: at(11 * 60 + 44)))
        XCTAssertTrue(ClosingDisplay.countsAsWaiting(claimed, viewer: dan, mode: .demote, at: at(11 * 60 + 45)))
        XCTAssertFalse(ClosingDisplay.countsAsWaiting(claimed, viewer: bob, mode: .demote, at: at(11 * 60 + 45)))

        // "?" işaret sayılır (kapatanın kendi haritasında olmadığı için onun sayısına girmez).
        let unverified = try proposed(credible: false)
        for mode in ClosingMode.allCases {
            XCTAssertTrue(ClosingDisplay.countsAsWaiting(unverified, viewer: dan, mode: mode, at: at(12 * 60 + 5)), mode.rawValue)
            XCTAssertTrue(ClosingDisplay.countsAsWaiting(unverified, viewer: alice, mode: mode, at: at(12 * 60 + 5)), mode.rawValue)
            XCTAssertFalse(ClosingDisplay.countsAsWaiting(unverified, viewer: bob, mode: mode, at: at(12 * 60 + 5)), mode.rawValue)
        }

        // Kanıtlı öneri sayılmaz; strict modda yalnızca "?" olduğu için sayılır.
        let credible = try proposed(credible: true)
        XCTAssertFalse(ClosingDisplay.countsAsWaiting(credible, viewer: dan, mode: .demote, at: at(12 * 60 + 5)))
        XCTAssertFalse(ClosingDisplay.countsAsWaiting(credible, viewer: dan, mode: .label, at: at(12 * 60 + 5)))
        XCTAssertTrue(ClosingDisplay.countsAsWaiting(credible, viewer: dan, mode: .strict, at: at(12 * 60 + 5)))
    }
}
