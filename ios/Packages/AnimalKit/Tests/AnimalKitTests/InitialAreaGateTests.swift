import XCTest
@testable import AnimalKit

/// Açılış kapısı: ilk aboneliğin hangi koşulda açıldığı, izin sorusu sürerken süresiz bekleme ve zaman aşımının sınırı.
final class InitialAreaGateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let accesses: [LocationAccess] = [.notDetermined, .denied, .approximate, .full]

    /// `availableFor`: erişim kaç saniyedir kullanılabilir (`nil`: bilinmiyor).
    private func verdict(
        centered: Bool = false,
        moved: Bool = false,
        redirected: Bool = false,
        access: LocationAccess = .full,
        availableFor: TimeInterval? = 0
    ) -> InitialAreaGate.Verdict {
        InitialAreaGate.verdict(
            centeredOnUser: centered,
            movedByPerson: moved,
            redirected: redirected,
            access: access,
            accessAvailableSince: availableFor.map { now.addingTimeInterval(-$0) },
            at: now
        )
    }

    /// Kararın kalan süresi; kapı açıksa ya da izin bekleniyorsa `nil`.
    private func remaining(_ value: InitialAreaGate.Verdict) -> TimeInterval? {
        if case .waitingForFix(let remaining) = value { return remaining }
        return nil
    }

    func testConstants() {
        XCTAssertEqual(InitialAreaGate.fixTimeout, 8)
    }

    func testOnlyOpenIsOpen() {
        XCTAssertTrue(InitialAreaGate.Verdict.open.isOpen)
        XCTAssertFalse(InitialAreaGate.Verdict.waitingForPermission.isOpen)
        XCTAssertFalse(InitialAreaGate.Verdict.waitingForFix(remaining: 3).isOpen)
    }

    // MARK: Bekleme

    func testWaitsWhileNothingHappened() {
        XCTAssertEqual(verdict(access: .full, availableFor: 0), .waitingForFix(remaining: 8))
        XCTAssertEqual(verdict(access: .full, availableFor: 3), .waitingForFix(remaining: 5))
        XCTAssertEqual(verdict(access: .notDetermined, availableFor: nil), .waitingForPermission)
    }

    func testApproximateAccessWaitsLikeFullAccess() {
        XCTAssertEqual(verdict(access: .approximate, availableFor: 3), .waitingForFix(remaining: 5))
        XCTAssertEqual(verdict(access: .approximate, availableFor: 8), .open)
    }

    func testUnknownStartCountsAsNow() {
        XCTAssertEqual(verdict(access: .full, availableFor: nil), .waitingForFix(remaining: 8))
        XCTAssertEqual(verdict(access: .approximate, availableFor: nil), .waitingForFix(remaining: 8))
    }

    func testClockGoingBackwardsRestartsTheWait() {
        XCTAssertEqual(verdict(access: .full, availableFor: -30), .waitingForFix(remaining: 8))
    }

    // MARK: Açılma koşulları

    func testFirstFixOpens() {
        for access in accesses {
            XCTAssertEqual(verdict(centered: true, access: access, availableFor: nil), .open, "\(access)")
            XCTAssertEqual(verdict(centered: true, access: access, availableFor: 0), .open, "\(access)")
        }
    }

    func testDeniedAccessOpensWithoutWaiting() {
        XCTAssertEqual(verdict(access: .denied, availableFor: nil), .open)
        XCTAssertEqual(verdict(access: .denied, availableFor: 0), .open)
        XCTAssertEqual(verdict(access: .denied, availableFor: 100), .open)
    }

    func testPersonMovingTheMapOpensEvenWhilePromptIsShown() {
        XCTAssertEqual(verdict(moved: true, access: .notDetermined, availableFor: nil), .open)
        for access in accesses {
            XCTAssertEqual(verdict(moved: true, access: access, availableFor: 0), .open, "\(access)")
        }
    }

    func testAnotherCameraRequestOpensEvenWhilePromptIsShown() {
        XCTAssertEqual(verdict(redirected: true, access: .notDetermined, availableFor: nil), .open)
        for access in accesses {
            XCTAssertEqual(verdict(redirected: true, access: access, availableFor: 0), .open, "\(access)")
        }
    }

    // MARK: Zaman aşımı

    func testPermissionPromptHasNoTimeout() {
        XCTAssertEqual(verdict(access: .notDetermined, availableFor: nil), .waitingForPermission)
        for seconds in [0, 7.9, 8, 60, 3_600, 86_400] {
            XCTAssertEqual(verdict(access: .notDetermined, availableFor: seconds), .waitingForPermission, "\(seconds) sn")
        }
    }

    func testTimeoutBoundary() throws {
        XCTAssertEqual(verdict(access: .full, availableFor: 7), .waitingForFix(remaining: 1))
        XCTAssertEqual(verdict(access: .full, availableFor: 7.5), .waitingForFix(remaining: 0.5))
        let almost = try XCTUnwrap(remaining(verdict(access: .full, availableFor: 7.999)))
        XCTAssertEqual(almost, 0.001, accuracy: 1e-6)
        // Sınırda ve sonrasında açılır.
        XCTAssertEqual(verdict(access: .full, availableFor: 8), .open)
        XCTAssertEqual(verdict(access: .full, availableFor: 8.001), .open)
        XCTAssertEqual(verdict(access: .full, availableFor: 600), .open)
    }

    // MARK: Birleşimler

    func testEveryCombination() {
        for centered in [false, true] {
            for moved in [false, true] {
                for redirected in [false, true] {
                    for access in accesses {
                        for waited in [0.0, 7.9, 8.0, 100.0] {
                            let isAvailable = access == .approximate || access == .full
                            let expectsOpen = centered || moved || redirected || access == .denied
                                || (isAvailable && waited >= InitialAreaGate.fixTimeout)
                            let result = verdict(
                                centered: centered,
                                moved: moved,
                                redirected: redirected,
                                access: access,
                                availableFor: waited
                            )
                            let context = "okuma \(centered), kaydırma \(moved), istek \(redirected), \(access), \(waited) sn"
                            XCTAssertEqual(result.isOpen, expectsOpen, context)
                            guard !expectsOpen else { continue }
                            if access == .notDetermined {
                                XCTAssertEqual(result, .waitingForPermission, context)
                            } else {
                                XCTAssertEqual(
                                    remaining(result) ?? -1,
                                    InitialAreaGate.fixTimeout - waited,
                                    accuracy: 1e-6,
                                    context
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
