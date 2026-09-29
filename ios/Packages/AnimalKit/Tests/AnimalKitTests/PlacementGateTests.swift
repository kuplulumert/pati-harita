import XCTest
@testable import AnimalKit

/// Yakınlık kapısı: çevre ve doğruluk payı, okumanın kullanılabilirliği, kararın öncelik sırası ve düzeltme.
final class PlacementGateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// Kullanıcının bulunduğu yer.
    private let here = Coordinate(latitude: 40.9903, longitude: 29.029)

    private func reading(accuracy: Double = 5, age: TimeInterval = 1, simulated: Bool = false) -> LocationFix {
        LocationFix(
            coordinate: here,
            timestamp: now.addingTimeInterval(-age),
            horizontalAccuracy: accuracy,
            isSimulatedBySoftware: simulated
        )
    }

    /// Kullanıcıdan `pinNorth` metre kuzeydeki iğnenin kararı.
    private func verdict(
        pinNorth: Double = 0,
        fix: LocationFix?,
        access: LocationAccess = .full,
        rejectsSimulated: Bool = true,
        area: AreaClass? = .allowed,
        locatingFor: TimeInterval = 0
    ) -> PlacementVerdict {
        PlacementGate.verdict(
            pin: here.offset(north: pinNorth),
            fix: fix,
            access: access,
            rejectsSimulated: rejectsSimulated,
            area: area,
            locatingSince: now.addingTimeInterval(-locatingFor),
            at: now
        )
    }

    /// Kayıtlı yeri kullanıcıdan `originalNorth`, yeni yeri `pinNorth` metre kuzeyde olan düzeltmenin kararı.
    private func editVerdict(
        originalNorth: Double,
        pinNorth: Double,
        fix: LocationFix?,
        access: LocationAccess = .full,
        area: AreaClass? = .allowed
    ) -> PlacementVerdict {
        PlacementGate.editVerdict(
            original: here.offset(north: originalNorth),
            pin: here.offset(north: pinNorth),
            fix: fix,
            access: access,
            rejectsSimulated: true,
            area: area,
            locatingSince: now,
            at: now
        )
    }

    func testConstants() {
        XCTAssertEqual(PlacementGate.radius, 150)
        XCTAssertEqual(PlacementGate.maxAccuracyAllowance, 75)
        XCTAssertEqual(PlacementGate.maxAllowedRadius, 225)
        XCTAssertEqual(PlacementGate.maxAccuracy, 100)
        XCTAssertEqual(PlacementGate.maxFixAge, 120)
        XCTAssertEqual(PlacementGate.slowLocatingAfter, 20)
        XCTAssertEqual(PlacementGate.refreshIfOlderThan, 30)
        XCTAssertEqual(PlacementGate.unmovedTolerance, 1)
    }

    // MARK: Çevre

    func testAllowedRadiusGrowsWithAccuracyUpTo225() {
        XCTAssertEqual(PlacementGate.allowedRadius(accuracy: 0), 150)
        XCTAssertEqual(PlacementGate.allowedRadius(accuracy: 20), 170)
        XCTAssertEqual(PlacementGate.allowedRadius(accuracy: 60), 210)
        XCTAssertEqual(PlacementGate.allowedRadius(accuracy: 75), 225)
        XCTAssertEqual(PlacementGate.allowedRadius(accuracy: 100), 225)
        XCTAssertEqual(PlacementGate.allowedRadius(accuracy: .infinity), 225)
        // Geçersiz doğruluk pay vermez.
        XCTAssertEqual(PlacementGate.allowedRadius(accuracy: -1), 150)
        XCTAssertEqual(PlacementGate.allowedRadius(accuracy: .nan), 150)
    }

    func testRingWithExactFix() {
        XCTAssertEqual(verdict(pinNorth: 0, fix: reading(accuracy: 0)), .ready)
        // 150 m sınırı (kayan nokta payıyla).
        XCTAssertEqual(verdict(pinNorth: 149.99, fix: reading(accuracy: 0)), .ready)
        XCTAssertEqual(verdict(pinNorth: 151, fix: reading(accuracy: 0)), .tooFar)
    }

    func testAccuracyWidensTheRing() {
        XCTAssertEqual(verdict(pinNorth: 200, fix: reading(accuracy: 60)), .ready)
        XCTAssertEqual(verdict(pinNorth: 200, fix: reading(accuracy: 20)), .tooFar)
        // Pay en fazla 75 m: 225 m.
        XCTAssertEqual(verdict(pinNorth: 224, fix: reading(accuracy: 100)), .ready)
        XCTAssertEqual(verdict(pinNorth: 230, fix: reading(accuracy: 100)), .tooFar)
    }

    // MARK: Okuma

    func testUnusableFixKeepsLocating() {
        XCTAssertEqual(verdict(fix: reading(accuracy: 101)), .locating(slow: false))
        XCTAssertEqual(verdict(fix: reading(accuracy: -1)), .locating(slow: false))
        XCTAssertEqual(verdict(fix: reading(accuracy: .nan)), .locating(slow: false))
        XCTAssertEqual(verdict(fix: reading(age: 121)), .locating(slow: false))
        XCTAssertEqual(verdict(fix: nil), .locating(slow: false))
        // Sınırlar dahil.
        XCTAssertEqual(verdict(fix: reading(accuracy: 100)), .ready)
        XCTAssertEqual(verdict(fix: reading(age: 120)), .ready)
    }

    func testIsUsable() {
        XCTAssertFalse(PlacementGate.isUsable(nil, at: now))
        XCTAssertTrue(PlacementGate.isUsable(reading(accuracy: 0, age: 0), at: now))
        // Cihaz saati okumadan biraz gerideyse de kullanılır.
        XCTAssertTrue(PlacementGate.isUsable(reading(age: -2), at: now))
        var broken = reading()
        broken.coordinate = Coordinate(latitude: .nan, longitude: 29)
        XCTAssertFalse(PlacementGate.isUsable(broken, at: now))
    }

    func testSlowLocatingAfter20Seconds() {
        XCTAssertEqual(verdict(fix: nil, locatingFor: 19), .locating(slow: false))
        XCTAssertEqual(verdict(fix: nil, locatingFor: 20), .locating(slow: true))
        XCTAssertEqual(verdict(fix: nil, locatingFor: 21), .locating(slow: true))
        XCTAssertEqual(verdict(fix: reading(age: 300), locatingFor: 21), .locating(slow: true))
    }

    // MARK: İzin ve taklit

    func testDeniedBeatsEverything() {
        XCTAssertEqual(
            verdict(pinNorth: 500, fix: reading(simulated: true), access: .denied, area: .water),
            .needsPermission
        )
        XCTAssertEqual(verdict(fix: nil, access: .denied), .needsPermission)
    }

    func testApproximateAndNotDetermined() {
        XCTAssertEqual(verdict(fix: reading(), access: .approximate), .approximateOnly)
        XCTAssertEqual(verdict(fix: nil, access: .approximate), .approximateOnly)
        XCTAssertEqual(verdict(fix: reading(simulated: true), access: .approximate), .approximateOnly)
        // İzin henüz sorulmadıysa elde okuma olsa da beklenir.
        XCTAssertEqual(verdict(fix: reading(), access: .notDetermined), .locating(slow: false))
        XCTAssertEqual(verdict(fix: reading(), access: .notDetermined, locatingFor: 25), .locating(slow: true))
    }

    func testSimulatedFixOnlyWhenRejected() {
        XCTAssertEqual(verdict(fix: reading(simulated: true)), .simulatedLocation)
        XCTAssertEqual(verdict(fix: reading(simulated: true), rejectsSimulated: false), .ready)
        // Taklit, konum beklemekten ve uzaklıktan önce gelir.
        XCTAssertEqual(verdict(fix: reading(age: 600, simulated: true)), .simulatedLocation)
        XCTAssertEqual(verdict(pinNorth: 500, fix: reading(simulated: true)), .simulatedLocation)
        XCTAssertEqual(verdict(fix: reading(simulated: true), access: .notDetermined), .simulatedLocation)
    }

    // MARK: Alan

    func testTooFarBeatsArea() {
        XCTAssertEqual(verdict(pinNorth: 300, fix: reading(), area: .water), .tooFar)
        XCTAssertEqual(verdict(pinNorth: 300, fix: reading(), area: .forest), .tooFar)
    }

    func testLocatingBeatsArea() {
        XCTAssertEqual(verdict(fix: nil, area: .forest), .locating(slow: false))
    }

    func testAreaVerdicts() {
        XCTAssertEqual(verdict(pinNorth: 50, fix: reading(), area: .water), .water)
        XCTAssertEqual(verdict(pinNorth: 50, fix: reading(), area: .forest), .forest)
        XCTAssertEqual(verdict(pinNorth: 50, fix: reading(), area: .remote), .remote)
        XCTAssertEqual(verdict(pinNorth: 50, fix: reading(), area: .allowed), .ready)
        // Bilinmeyen alan (kutunun dışı, ızgara yok) serbest.
        XCTAssertEqual(verdict(pinNorth: 50, fix: reading(), area: nil), .ready)
        for area in AreaClass.allCases {
            XCTAssertEqual(PlacementGate.areaVerdict(area).isAreaBlock, area != .allowed, area.name)
        }
        XCTAssertEqual(PlacementGate.areaVerdict(nil), .ready)
    }

    func testBlockingFlags() {
        let all: [PlacementVerdict] = [
            .ready, .needsPermission, .approximateOnly, .simulatedLocation,
            .locating(slow: false), .locating(slow: true), .tooFar, .water, .forest, .remote,
        ]
        XCTAssertEqual(all.filter(\.isBlocking).count, all.count - 1)
        XCTAssertFalse(PlacementVerdict.ready.isBlocking)
        XCTAssertEqual(all.filter(\.isAreaBlock), [.water, .forest, .remote])
    }

    // MARK: Düzeltme

    func testUnmovedEditSkipsEveryCheck() {
        // Tür ve ihtiyaç her yerden düzeltilebilir.
        XCTAssertEqual(editVerdict(originalNorth: 2000, pinNorth: 2000.5, fix: nil), .ready)
        XCTAssertEqual(editVerdict(originalNorth: 2000, pinNorth: 2000, fix: reading(), area: .forest), .ready)
        XCTAssertEqual(editVerdict(originalNorth: 0, pinNorth: 0.5, fix: nil, access: .denied), .ready)
    }

    func testMovedEditIsGatedLikeANewPin() {
        XCTAssertEqual(editVerdict(originalNorth: 0, pinNorth: 20, fix: nil), .locating(slow: false))
        XCTAssertEqual(editVerdict(originalNorth: 100, pinNorth: 120, fix: reading()), .ready)
        XCTAssertEqual(editVerdict(originalNorth: 100, pinNorth: 170, fix: reading(accuracy: 5)), .tooFar)
        XCTAssertEqual(editVerdict(originalNorth: 100, pinNorth: 120, fix: reading(), area: .forest), .forest)
        XCTAssertEqual(editVerdict(originalNorth: 0, pinNorth: 20, fix: reading(), access: .denied), .needsPermission)
        XCTAssertEqual(editVerdict(originalNorth: 0, pinNorth: 1.5, fix: nil), .locating(slow: false))
    }

    // MARK: Uzun basma

    func testLongPress() {
        let far = here.offset(north: 400)
        let near = here.offset(north: 100)
        // Konum yoksa panel açılır ve "konum bulunuyor"da bekler.
        XCTAssertTrue(PlacementGate.acceptsLongPress(at: far, fix: nil, at: now))
        XCTAssertTrue(PlacementGate.acceptsLongPress(at: far, fix: reading(age: 200), at: now))
        XCTAssertTrue(PlacementGate.acceptsLongPress(at: near, fix: reading(), at: now))
        XCTAssertFalse(PlacementGate.acceptsLongPress(at: far, fix: reading(), at: now))
        XCTAssertTrue(PlacementGate.acceptsLongPress(at: here.offset(north: 200), fix: reading(accuracy: 60), at: now))
        XCTAssertFalse(PlacementGate.acceptsLongPress(at: here.offset(north: 200), fix: reading(accuracy: 20), at: now))
        XCTAssertFalse(
            PlacementGate.acceptsLongPress(at: Coordinate(latitude: .nan, longitude: 29), fix: reading(), at: now)
        )
    }
}
