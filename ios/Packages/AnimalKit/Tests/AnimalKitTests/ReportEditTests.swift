import XCTest
@testable import AnimalKit

/// "Düzenle": işareti koyan, kimse dokunmadan, 30 dk içinde ve en fazla 3 kez tür, ihtiyaç ve konumu düzeltir
/// (kurallardaki `isEdit`).
final class ReportEditTests: ReportTestCase {
    /// `kadikoy`tan derece cinsinden kaydırılmış konum.
    private func moved(lat: Double = 0, lng: Double = 0) -> Coordinate {
        Coordinate(latitude: kadikoy.latitude + lat, longitude: kadikoy.longitude + lng)
    }

    // MARK: Kim, ne zaman

    func testOnlyReporterEditsWithinWindow() {
        let report = makeReport()
        XCTAssertTrue(ReportLifecycle.canEdit(report, by: alice, at: t0))
        XCTAssertTrue(ReportLifecycle.canEdit(report, by: alice, at: minutes(29.9)))
        XCTAssertFalse(ReportLifecycle.canEdit(report, by: alice, at: minutes(30)))
        XCTAssertThrowsError(
            try ReportLifecycle.edit(report, species: .dog, need: .injured, coordinate: kadikoy, by: alice, at: minutes(30))
        ) {
            XCTAssertEqual($0 as? ReportError, .notEditable)
        }

        for user in [bob, cara] {
            XCTAssertFalse(ReportLifecycle.canEdit(report, by: user, at: minutes(1)), user)
            XCTAssertThrowsError(
                try ReportLifecycle.edit(report, species: .dog, need: .injured, coordinate: kadikoy, by: user, at: minutes(1)),
                user
            ) {
                XCTAssertEqual($0 as? ReportError, .notEditable)
            }
        }
    }

    /// Başka biri işarete dokunduysa (gördü, "Artık yok" dedi, ilgileniyor, kapatma önerdi, itiraz edildi)
    /// işareti koyan artık düzeltemez.
    func testAnyoneElsesTouchEndsEditing() throws {
        let report = makeReport()
        let seen = try seenReport()
        let voted = try ReportLifecycle.apply(.reportGone, to: report, by: cara, at: minutes(1))
        let claimed = try ReportLifecycle.apply(.claim, to: report, by: bob, at: minutes(1))
        let proposed = try ReportLifecycle.apply(.resolve, to: report, by: bob, at: minutes(1))
        let disputed = try disputedReport(by: [bob])
        // Yalnızca bu koşulu sınamak için: itiraz eden var, başka iz yok.
        var objected = report
        objected.objectors = [cara]
        let touched: [(name: String, report: Report)] = [
            ("görüldü", seen),
            ("artık yok oyu", voted),
            ("ilgileniliyor", claimed),
            ("çözüldü dendi", proposed),
            ("itiraz edildi", disputed),
            ("itiraz eden var", objected),
        ]
        for item in touched {
            XCTAssertFalse(ReportLifecycle.canEdit(item.report, by: alice, at: minutes(20)), item.name)
            XCTAssertThrowsError(
                try ReportLifecycle.edit(item.report, species: .dog, need: .injured, coordinate: kadikoy, by: alice, at: minutes(20)),
                item.name
            ) {
                XCTAssertEqual($0 as? ReportError, .notEditable, item.name)
            }
        }
    }

    func testClosedOrExpiredReportIsNotActive() throws {
        let closed = try ReportLifecycle.apply(.resolve, to: makeReport(), by: alice, at: minutes(1))
        var expired = makeReport()
        expired.expiresAt = minutes(10)
        for (report, now) in [(closed, minutes(2)), (expired, minutes(10))] {
            XCTAssertFalse(ReportLifecycle.canEdit(report, by: alice, at: now))
            XCTAssertThrowsError(
                try ReportLifecycle.edit(report, species: .dog, need: .injured, coordinate: kadikoy, by: alice, at: now)
            ) {
                XCTAssertEqual($0 as? ReportError, .notActive)
            }
        }
    }

    func testAtMostThreeEdits() throws {
        var report = makeReport()
        for index in 1...ReportLifecycle.maxEdits {
            let species: Species = index.isMultiple(of: 2) ? .cat : .dog
            report = try ReportLifecycle.edit(
                report, species: species, need: .injured, coordinate: kadikoy, by: alice, at: minutes(Double(index))
            )
            XCTAssertEqual(report.editCount, index)
        }
        XCTAssertFalse(ReportLifecycle.canEdit(report, by: alice, at: minutes(10)))
        XCTAssertThrowsError(
            try ReportLifecycle.edit(report, species: .cat, need: .injured, coordinate: kadikoy, by: alice, at: minutes(10))
        ) {
            XCTAssertEqual($0 as? ReportError, .notEditable)
        }
        // Düzeltmek silmeyi etkilemez ("İşareti sil" hâlâ açık).
        XCTAssertTrue(ReportLifecycle.canRetract(report, by: alice))
    }

    // MARK: Ne değişir

    func testChangingNeedRestartsLifetime() throws {
        let report = makeReport(need: .shelter) // 72 sa
        let asFood = try ReportLifecycle.edit(report, species: .cat, need: .food, coordinate: kadikoy, by: alice, at: minutes(10))
        XCTAssertEqual(asFood.need, .food)
        // Ömür şimdiden yeni ihtiyaca göre başlar; kısalabilir de.
        XCTAssertEqual(asFood.expiresAt, minutes(10).addingTimeInterval(12 * 3600))
        XCTAssertEqual(asFood.lastSeenAt, t0)
        XCTAssertEqual(asFood.createdAt, t0)
        XCTAssertEqual(asFood.seenBy, [alice])
        XCTAssertEqual(asFood.status, .open)
        XCTAssertEqual(asFood.changedFields(from: report), [.need, .expiresAt, .editCount])

        // Aynı ömürlü ihtiyaca geçmek de ömrü şimdiden başlatır.
        let asEmergency = try ReportLifecycle.edit(asFood, species: .cat, need: .emergency, coordinate: kadikoy, by: alice, at: minutes(15))
        XCTAssertEqual(asEmergency.expiresAt, minutes(15).addingTimeInterval(12 * 3600))

        // İhtiyaç değişmezse ömür aynı kalır.
        let asDog = try ReportLifecycle.edit(asEmergency, species: .dog, need: .emergency, coordinate: kadikoy, by: alice, at: minutes(20))
        XCTAssertEqual(asDog.species, .dog)
        XCTAssertEqual(asDog.expiresAt, asEmergency.expiresAt)
        XCTAssertEqual(asDog.changedFields(from: asEmergency), [.species, .editCount])
    }

    /// Hiçbir şey değişmese de düzeltme sayılır: kurallar `editCount`un tam bir artmasını ister.
    func testEditWithoutChangesStillCounts() throws {
        let report = makeReport()
        let same = try ReportLifecycle.edit(report, species: .cat, need: .injured, coordinate: kadikoy, by: alice, at: minutes(5))
        XCTAssertEqual(same.changedFields(from: report), [.editCount])
        XCTAssertEqual(same.editCount, 1)
    }

    func testLocationMovesAtMostAbout200MetresPerEdit() throws {
        let report = makeReport()
        let corner = moved(lat: 0.00179, lng: -0.00239)
        XCTAssertTrue(ReportLifecycle.isWithinEditRange(report, to: corner))
        let edited = try ReportLifecycle.edit(report, species: .cat, need: .injured, coordinate: corner, by: alice, at: minutes(1))
        XCTAssertEqual(edited.coordinate, corner)
        XCTAssertEqual(edited.geohash, Geohash.encode(corner, precision: ReportLifecycle.geohashPrecision))
        XCTAssertNotEqual(edited.geohash, report.geohash)
        XCTAssertEqual(edited.expiresAt, report.expiresAt)
        XCTAssertEqual(edited.changedFields(from: report), [.lat, .lng, .geohash, .editCount])
        // Her eksende ~200 m.
        XCTAssertEqual(report.coordinate.distance(to: moved(lat: 0.00179)), 199, accuracy: 2)
        XCTAssertEqual(report.coordinate.distance(to: moved(lng: 0.00239)), 200, accuracy: 3)

        // Yalnızca enlem değişirse boylam yazılmaz.
        let north = try ReportLifecycle.edit(report, species: .cat, need: .injured, coordinate: moved(lat: 0.001), by: alice, at: minutes(1))
        XCTAssertEqual(north.changedFields(from: report), [.lat, .geohash, .editCount])

        for tooFar in [moved(lat: 0.00181), moved(lat: -0.00181), moved(lng: 0.00241), moved(lng: -0.00241)] {
            XCTAssertFalse(ReportLifecycle.isWithinEditRange(report, to: tooFar), "\(tooFar)")
            XCTAssertThrowsError(
                try ReportLifecycle.edit(report, species: .cat, need: .injured, coordinate: tooFar, by: alice, at: minutes(1)),
                "\(tooFar)"
            ) {
                XCTAssertEqual($0 as? ReportError, .editTooFar)
            }
        }
    }

    /// Sınır her düzeltmede işaretin o anki konumundan ölçülür (kurallar önceki ve yeni konumu karşılaştırır).
    func testEachEditMeasuresFromCurrentLocation() throws {
        let first = try ReportLifecycle.edit(
            makeReport(), species: .cat, need: .injured, coordinate: moved(lat: 0.0017), by: alice, at: minutes(1)
        )
        XCTAssertFalse(ReportLifecycle.isWithinEditRange(makeReport(), to: moved(lat: 0.0034)))
        XCTAssertTrue(ReportLifecycle.isWithinEditRange(first, to: moved(lat: 0.0034)))
        let second = try ReportLifecycle.edit(
            first, species: .cat, need: .injured, coordinate: moved(lat: 0.0034), by: alice, at: minutes(2)
        )
        XCTAssertEqual(second.coordinate, moved(lat: 0.0034))
        XCTAssertEqual(second.editCount, 2)
    }

    /// Her düzeltme yalnızca kurallardaki `isEdit`in izin verdiği alanları değiştirir, `editCount`u tam bir
    /// artırır, ömrü kuralların sınırlarında tutar ve `validShape`i korur.
    func testEveryEditChangesOnlyFieldsAllowedByRules() throws {
        let allowed: Set<ReportField> = [.species, .need, .lat, .lng, .geohash, .expiresAt, .editCount]
        let coordinates = [kadikoy, moved(lat: 0.001), moved(lng: -0.002), moved(lat: -0.0015, lng: 0.0022)]
        let now = minutes(12)
        var checked = 0
        for oldNeed in Need.allCases {
            let report = makeReport(need: oldNeed)
            for species in Species.allCases {
                for need in Need.allCases {
                    for coordinate in coordinates {
                        let label = "\(oldNeed) → \(species) \(need) \(coordinate)"
                        let edited = try ReportLifecycle.edit(
                            report, species: species, need: need, coordinate: coordinate, by: alice, at: now
                        )
                        let changed = edited.changedFields(from: report)
                        XCTAssertTrue(changed.isSubset(of: allowed), "\(label): \(changed.map(\.rawValue).sorted())")
                        XCTAssertTrue(changed.contains(.editCount), label)
                        XCTAssertEqual(edited.editCount, report.editCount + 1, label)
                        XCTAssertEqual(edited.reporterID, report.reporterID, label)
                        XCTAssertEqual(edited.createdAt, report.createdAt, label)
                        XCTAssertEqual(edited.species, species, label)
                        XCTAssertEqual(edited.need, need, label)
                        XCTAssertEqual(edited.coordinate, coordinate, label)
                        XCTAssertEqual(
                            edited.geohash,
                            Geohash.encode(coordinate, precision: ReportLifecycle.geohashPrecision),
                            label
                        )
                        if need == oldNeed {
                            XCTAssertEqual(edited.expiresAt, report.expiresAt, label)
                        } else {
                            XCTAssertGreaterThan(edited.expiresAt, now, label)
                            XCTAssertLessThanOrEqual(edited.expiresAt, now.addingTimeInterval(need.lifetime), label)
                            XCTAssertLessThanOrEqual(edited.expiresAt, ReportLifecycle.lifeCap(report), label)
                        }
                        assertValidShape(edited, label)
                        // Düzeltilen işaret yine düzeltilebilir ve silinebilir.
                        XCTAssertTrue(ReportLifecycle.canEdit(edited, by: alice, at: now), label)
                        XCTAssertTrue(ReportLifecycle.canRetract(edited, by: alice), label)
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, Need.allCases.count * Species.allCases.count * Need.allCases.count * coordinates.count)
    }

    /// Düzeltilen işaret sıradan bir işarettir: herkes eylemlerini yapabilir, ömür kuralları yeni ihtiyaca göre işler.
    func testEditedReportFollowsItsNewNeed() throws {
        let edited = try editedReport() // köpek / mama, 5. dakikada
        XCTAssertEqual(edited.expiresAt, minutes(5).addingTimeInterval(12 * 3600))
        let confirmed = try ReportLifecycle.apply(.confirmStillThere, to: edited, by: cara, at: hours(2))
        XCTAssertEqual(confirmed.expiresAt, hours(14))
        XCTAssertFalse(ReportLifecycle.canEdit(confirmed, by: alice, at: hours(2)))
        XCTAssertTrue(ReportLifecycle.availableActions(for: edited, userID: cara, at: minutes(10)).contains(.reportUnneeded))
    }
}
