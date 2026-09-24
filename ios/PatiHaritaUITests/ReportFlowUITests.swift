import CoreLocation
import XCTest

/// Ana akışı demo modunda gerçek dokunuşlarla dener:
/// harita → "Hayvan gördüm" → tür → ihtiyaç → işarete dokun → "İlgileniyorum" → uzun basma.
/// Her adımın ekran görüntüsü test sonucuna, `SCREENSHOT_DIR` tanımlıysa (CI) o klasöre de yazılır.
final class ReportFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReportFlow() throws {
        let app = launchDemoApp()
        let screenshots = Screenshots(test: self)

        let reportButton = app.buttons.element(labelContaining: "Hayvan gördüm")
        XCTAssertTrue(reportButton.waitForExistence(timeout: 30), "Ana ekran açılmadı")
        // Harita karoları ve demo işaretleri yüklensin.
        sleep(4)
        screenshots.take("01-harita")

        reportButton.tap()
        let cat = app.buttons["species-cat"]
        XCTAssertTrue(cat.waitForExistence(timeout: 5), "Tür seçimi açılmadı")
        sleep(1)
        screenshots.take("02-tur-secimi")

        cat.tap()
        let food = app.buttons["need-food"]
        XCTAssertTrue(food.waitForExistence(timeout: 5), "İhtiyaç seçimi açılmadı")
        screenshots.take("03-ihtiyac-secimi")

        food.tap()
        let saved = app.staticTexts.element(labelContaining: "işaretlendi")
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "İşaret kaydedildi bildirimi görünmedi")
        sleep(1)
        screenshots.take("04-isaretlendi")

        // Demo verisindeki tek "Mama / su" işareti köpek; "Kedi" de aranınca bulunan, az önce koyulan işarettir.
        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", "report-marker", "Mama / su, Kedi"))
            .firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "Yeni işaret haritada bulunamadı")
        marker.tap()
        let claim = app.buttons.element(labelContaining: "İlgileniyorum")
        XCTAssertTrue(claim.waitForExistence(timeout: 5), "İşarete dokununca kart açılmadı")
        sleep(1)
        screenshots.take("05-isaret-karti")

        claim.tap()
        let thanks = app.staticTexts.element(labelContaining: "3 saat boyunca sende")
        XCTAssertTrue(thanks.waitForExistence(timeout: 5), "İlgileniyorum onayı görünmedi")
        screenshots.take("06-ilgileniyorum")

        let close = app.buttons["Kapat"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Kartın kapat düğmesi yok")
        close.tap()
        XCTAssertTrue(reportButton.waitForExistence(timeout: 5), "Kart kapanınca ana ekrana dönülmedi")

        // Haritada boş bir noktaya uzun basınca işaretleme o noktadan başlar.
        let map = app.maps.firstMatch
        XCTAssertTrue(map.exists, "Harita bulunamadı")
        let point = emptyMapPoint(in: app, map: map)
        point.press(forDuration: 1.2)
        let speciesTitle = app.staticTexts.element(labelContaining: "Hangi hayvan?")
        XCTAssertTrue(speciesTitle.waitForExistence(timeout: 5), "Uzun basınca işaretleme başlamadı")
        sleep(1)
        screenshots.take("07-uzun-basma")
        app.buttons["Vazgeç"].tap()
    }

    // MARK: Yardımcılar

    @MainActor
    private func launchDemoApp() -> XCUIApplication {
        // Kadıköy (ios/Kadikoy.gpx ile aynı).
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 40.9903, longitude: 29.0290))
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()

        // Konum izni sorulursa "Uygulamayı Kullanırken İzin Ver".
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "While Using", "Kullanırken"))
            .firstMatch
        if allow.waitForExistence(timeout: 5) {
            allow.tap()
        }
        return app
    }

    /// Üst çubuk, alt panel ve işaretlerin üstüne denk gelmeyen bir harita noktası.
    @MainActor
    private func emptyMapPoint(in app: XCUIApplication, map: XCUIElement) -> XCUICoordinate {
        let markerFrames = app.descendants(matching: .any)
            .matching(identifier: "report-marker")
            .allElementsBoundByIndex
            .map { $0.frame.insetBy(dx: -24, dy: -24) }
        let frame = map.frame
        let candidates: [CGVector] = [
            CGVector(dx: 0.8, dy: 0.3), CGVector(dx: 0.2, dy: 0.3), CGVector(dx: 0.8, dy: 0.6),
            CGVector(dx: 0.2, dy: 0.6), CGVector(dx: 0.5, dy: 0.25), CGVector(dx: 0.35, dy: 0.45),
            CGVector(dx: 0.65, dy: 0.45), CGVector(dx: 0.15, dy: 0.45), CGVector(dx: 0.85, dy: 0.45),
        ]
        for offset in candidates {
            let point = CGPoint(x: frame.minX + frame.width * offset.dx, y: frame.minY + frame.height * offset.dy)
            if !markerFrames.contains(where: { $0.contains(point) }) {
                return map.coordinate(withNormalizedOffset: offset)
            }
        }
        return map.coordinate(withNormalizedOffset: candidates[0])
    }
}

/// Adım adım ekran görüntüleri.
@MainActor
private struct Screenshots {
    let test: XCTestCase
    private let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"].map { URL(fileURLWithPath: $0) }

    init(test: XCTestCase) {
        self.test = test
    }

    func take(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

private extension XCUIElementQuery {
    /// Etiketi verilen metni içeren ilk öğe (düğme etiketleri simge adı ya da emoji de içerebilir).
    /// Haritadaki işaretler de düğmedir ("Mama / su, Kedi"); onlar hariç tutulur.
    func element(labelContaining text: String) -> XCUIElement {
        matching(NSPredicate(format: "label CONTAINS %@ AND identifier != %@", text, "report-marker")).firstMatch
    }
}
