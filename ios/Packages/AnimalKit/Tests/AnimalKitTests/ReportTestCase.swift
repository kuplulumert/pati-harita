import XCTest
@testable import AnimalKit

/// İşaret testlerinin ortak kişileri, saati ve kurucuları. Kendi testi yoktur.
class ReportTestCase: XCTestCase {
    let alice = "alice" // işareti koyan
    let bob = "bob" // yardım eden
    let cara = "cara" // yoldan geçen, hayvanı gördü
    let dan = "dan" // yoldan geçen
    let eve = "eve" // yoldan geçen
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    let kadikoy = Coordinate(latitude: 40.9903, longitude: 29.029)

    func makeReport(need: Need = .injured) -> Report {
        ReportLifecycle.makeReport(id: "r1", species: .cat, need: need, at: kadikoy, reporterID: alice, now: t0)
    }

    func minutes(_ value: Double) -> Date { t0.addingTimeInterval(value * 60) }
    func hours(_ value: Double) -> Date { t0.addingTimeInterval(value * 3600) }

    /// cara da hayvanı gördü (seenBy [alice, cara]): işareti koyan artık tek başına kapatamaz.
    func seenReport(need: Need = .injured) throws -> Report {
        try ReportLifecycle.apply(.confirmStillThere, to: makeReport(need: need), by: cara, at: minutes(1))
    }

    /// Sırayla her kapatanın "Çözüldü" önerisine işareti koyan itiraz etmiş işaret
    /// (i. tur: i×10. dakikada öneri, 5 dk sonra itiraz). seenBy [alice] kalır.
    func disputedReport(by closers: [String], need: Need = .injured) throws -> Report {
        var report = makeReport(need: need)
        for (index, closer) in closers.enumerated() {
            let round = Double(index + 1) * 10
            report = try ReportLifecycle.apply(.resolve, to: report, by: closer, at: minutes(round))
            report = try ReportLifecycle.apply(.dispute, to: report, by: alice, at: minutes(round + 5))
        }
        return report
    }

    /// Farklı evrelerdeki işaretler ve bakıldıkları an.
    func phaseCatalogue() throws -> [(name: String, report: Report, now: Date)] {
        let open = makeReport()
        let food = makeReport(need: .food)
        let seen = try seenReport()
        let claimed = try ReportLifecycle.apply(.claim, to: seen, by: bob, at: minutes(2))
        let votedOnce = try ReportLifecycle.apply(.reportGone, to: open, by: cara, at: minutes(3))
        let votedTwice = try ReportLifecycle.apply(.reportGone, to: votedOnce, by: dan, at: minutes(4))
        let byPasserBy = try ReportLifecycle.apply(.resolve, to: seen, by: bob, at: minutes(30))
        let byClaimer = try ReportLifecycle.apply(.resolve, to: claimed, by: bob, at: minutes(30))
        let byReporter = try ReportLifecycle.apply(.resolve, to: seen, by: alice, at: minutes(30))
        // İşareti koyan, bob'un taze sahipliği üstüne "Çözüldü" dedi ("Geri al" sahipliği korur).
        let byReporterOverClaim = try ReportLifecycle.apply(.resolve, to: claimed, by: alice, at: minutes(10))
        // bob'un sahipliği 182. dakikada doldu; dan 4. saatte "Çözüldü" dedi ("Geri al" sahipliği temizler).
        let overExpiredClaim = try ReportLifecycle.apply(.resolve, to: claimed, by: dan, at: hours(4))
        let credible = try ReportLifecycle.apply(.resolve, to: seen, by: dan, at: minutes(30), credible: true)
        let goneClosing = try ReportLifecycle.apply(.reportGone, to: votedTwice, by: eve, at: minutes(30))
        let disputed = try ReportLifecycle.apply(.dispute, to: byPasserBy, by: cara, at: minutes(40))
        let secondRound = try ReportLifecycle.apply(.resolve, to: disputed, by: dan, at: minutes(50))
        return [
            ("açık", open, minutes(30)),
            ("mama", food, minutes(30)),
            ("görülmüş", seen, minutes(30)),
            ("taze sahiplik", claimed, minutes(10)),
            ("bayat sahiplik", claimed, minutes(50)),
            ("süresi dolmuş sahiplik", claimed, hours(4)),
            ("bir oy", votedOnce, minutes(30)),
            ("iki oy", votedTwice, minutes(30)),
            ("yoldan geçen çözüldü dedi", byPasserBy, minutes(35)),
            ("geri alma süresi bitti", byPasserBy, minutes(45)),
            ("ilgilenen çözüldü dedi", byClaimer, minutes(35)),
            ("koyan çözüldü dedi", byReporter, minutes(35)),
            ("koyan taze sahiplikte çözüldü dedi", byReporterOverClaim, minutes(12)),
            ("süresi dolmuş sahiplikte çözüldü dendi", overExpiredClaim, minutes(245)),
            ("kanıtlı öneri", credible, minutes(35)),
            ("artık yok dendi", goneClosing, minutes(35)),
            ("itiraz edildi", disputed, minutes(45)),
            ("ikinci öneri", secondRound, minutes(55)),
        ]
    }

    /// firestore.rules `validShape` karşılığı.
    func assertValidShape(_ report: Report, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        switch report.status {
        case .open:
            XCTAssertNil(report.closing, message, file: file, line: line)
        case .claimed:
            XCTAssertNotNil(report.claim, message, file: file, line: line)
            XCTAssertNil(report.closing, message, file: file, line: line)
        case .closing:
            XCTAssertNotNil(report.closing, message, file: file, line: line)
        case .closed:
            XCTAssertNotNil(report.closedReason, message, file: file, line: line)
            XCTAssertNotNil(report.closedAt, message, file: file, line: line)
            XCTAssertNotNil(report.purgeAt, message, file: file, line: line)
        }
        if report.status != .closed {
            XCTAssertNil(report.closedReason, message, file: file, line: line)
            XCTAssertNil(report.closedAt, message, file: file, line: line)
            XCTAssertNil(report.purgeAt, message, file: file, line: line)
        }
        if let closing = report.closing {
            XCTAssertTrue(closing.reason == .resolved || closing.reason == .gone, message, file: file, line: line)
        }
        XCTAssertTrue((1...ReportLifecycle.maxSeenBy).contains(report.seenBy.count), message, file: file, line: line)
        XCTAssertLessThanOrEqual(report.goneReports.count, ReportLifecycle.maxGoneReports, message, file: file, line: line)
        XCTAssertLessThanOrEqual(report.objectors.count, ReportLifecycle.maxDisputed, message, file: file, line: line)
        XCTAssertLessThanOrEqual(report.disputed.count, ReportLifecycle.maxDisputed, message, file: file, line: line)
        XCTAssertLessThanOrEqual(report.expiresAt, ReportLifecycle.lifeCap(report), message, file: file, line: line)
    }
}
