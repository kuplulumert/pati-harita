import CoreLocation
import XCTest

/// Ana akışı demo modunda gerçek dokunuşlarla dener:
/// harita → "Hayvan gördüm" → tür → ihtiyaç → işarete dokun → "İlgileniyorum" →
/// "Hâlâ orada" ile gören sayısı artar → "Aynı hayvan mı?" önerisi → uzun basma →
/// yoldan geçen "Çözüldü" der → "Çözüldü dendi" kartı → "Hâlâ yardım gerekiyor" itirazı.
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

        // İşaret iğnenin gösterdiği yere koyuldu mu: kamera hedefi görünen alanın (üst çubuk ile alt
        // düğmeler arası) ortasındadır, yeni işaretin ucu da tam orada olmalı. Kenar boşlukları iki kez
        // sayıldığında bu kayma ~20 nokta oluyordu.
        sleep(1)
        let chip = app.staticTexts.element(labelContaining: "Demo modu")
        XCTAssertTrue(chip.exists, "Üst durum etiketi bulunamadı")
        let visibleCenterY = (chip.frame.minY + reportButton.frame.minY) / 2
        XCTAssertEqual(marker.frame.maxY, visibleCenterY, accuracy: 12, "Yeni işaret görünen alanın ortasında değil")
        XCTAssertEqual(marker.frame.midX, app.frame.midX, accuracy: 12, "Yeni işaret yatayda ortada değil")

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

        // Kaç kişi bildirdi: demo verisindeki yaralı kediyi 3 kişi bildirmiş (demo kullanıcısı değil).
        // Kamera kullanıcının üstünde; bu işaret ~120 m kuzeyde, 80 m batıda, yani ekranın sol üstünde.
        let injuredCat = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", "report-marker", "Yaralı / hasta, Kedi"))
            .firstMatch
        XCTAssertTrue(injuredCat.waitForExistence(timeout: 10), "Örnek yaralı kedi işareti haritada bulunamadı")
        // Kart kapanınca harita yeniden ortalanıyor; işaret yerine otursun, yoksa dokunuş ıskalar.
        sleep(1)
        injuredCat.tap()
        let seenByThree = app.staticTexts.element(labelContaining: "3 kişi bildirdi")
        XCTAssertTrue(seenByThree.waitForExistence(timeout: 5), "Kartta gören sayısı (3) görünmedi")

        let stillThere = app.buttons.element(labelContaining: "Hâlâ orada")
        XCTAssertTrue(stillThere.waitForExistence(timeout: 5), "Hâlâ orada düğmesi yok")
        stillThere.tap()
        // "Hâlâ orada" diyen demo kullanıcısı da sayılır: kart (ve bildirim) 4 der.
        let seenByFour = app.staticTexts.element(labelContaining: "4 kişi bildirdi")
        XCTAssertTrue(seenByFour.waitForExistence(timeout: 5), "Hâlâ orada deyince gören sayısı artmadı")
        sleep(1)
        screenshots.take("07-goren-sayisi")

        XCTAssertTrue(close.waitForExistence(timeout: 5), "Kartın kapat düğmesi yok")
        close.tap()
        XCTAssertTrue(reportButton.waitForExistence(timeout: 5), "Kart kapanınca ana ekrana dönülmedi")

        // Aynı hayvan mı: az önce koyulan kedi işareti iğnenin dibinde. Aynı tür seçilince yeni işaret
        // yerine "Ben de gördüm" önerilir; dokununca o işaretin kartı açılır.
        reportButton.tap()
        XCTAssertTrue(cat.waitForExistence(timeout: 5), "Tür seçimi açılmadı")
        cat.tap()
        let duplicate = app.descendants(matching: .any).matching(identifier: "duplicate-suggestion").firstMatch
        XCTAssertTrue(duplicate.waitForExistence(timeout: 10), "Aynı hayvan mı önerisi görünmedi")
        sleep(1)
        screenshots.take("08-ayni-hayvan-mi")

        duplicate.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Ben de gördüm deyince işaretin kartı açılmadı")
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
        screenshots.take("09-uzun-basma")
        app.buttons["Vazgeç"].tap()

        // Yoldan geçen "Çözüldü" der (İlgileniyorum demeden). Demo hesabı 3 günlük ve bütçesi var: öneri
        // kanıtlıdır, kart kapanır ve işaret onun haritasından hemen kalkar. Bildirim saate göre değişir
        // ("yaklaşık 2 saat sonra" / gece "saat 08.00 civarında"); yalnızca ortak kısmı aranır.
        // Uzun basılan noktadan kullanıcının üstüne dönülür (yakınlık 16: gri noktalar çizilmez).
        let recenter = app.buttons["Konumuma git"]
        XCTAssertTrue(recenter.waitForExistence(timeout: 5), "Konumuma git düğmesi yok")
        recenter.tap()
        sleep(2)
        XCTAssertTrue(injuredCat.waitForExistence(timeout: 10), "Örnek yaralı kedi işareti haritada bulunamadı")
        injuredCat.tap()
        let resolve = app.buttons["action-resolve"]
        XCTAssertTrue(resolve.waitForExistence(timeout: 5), "Yoldan geçen için Çözüldü düğmesi yok")
        resolve.tap()
        let recorded = app.staticTexts.element(labelContaining: "Yardımın kaydedildi")
        XCTAssertTrue(recorded.waitForExistence(timeout: 5), "Çözüldü bildirimi görünmedi")
        XCTAssertTrue(reportButton.waitForExistence(timeout: 5), "Çözüldü deyince kart kapanmadı")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: injuredCat)
        wait(for: [gone], timeout: 5)
        sleep(1)
        screenshots.take("10-cozuldu-dendi")

        // Demo verisindeki "Çözüldü dendi" örneği: yoldan geçen biri bütçesiz dedi, bu yüzden demo
        // kullanıcısına "?" rozetiyle "doğrulanmadı" görünür. Kullanıcının ~260 m güneyinde; harita kediye dokununca
        // ona ortalandığı için köpek görünen alanın ortasının ~210 nokta altında (bildirimin üstünde) kalır.
        let closingDog = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", "report-marker", "Yaralı / hasta, Köpek"))
            .firstMatch
        XCTAssertTrue(closingDog.waitForExistence(timeout: 10), "Örnek 'Çözüldü dendi' işareti haritada bulunamadı")
        let spoken = (closingDog.value as? String) ?? ""
        XCTAssertTrue(spoken.contains("doğrulanmadı"), "İşaretin sesli değeri 'doğrulanmadı' demiyor: \(spoken)")
        closingDog.tap()
        let closingStatus = app.staticTexts
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "report-status", "Çözüldü dendi"))
            .firstMatch
        XCTAssertTrue(closingStatus.waitForExistence(timeout: 5), "Kartta 'Çözüldü dendi' görünmedi")
        sleep(1)
        screenshots.take("11-cozuldu-dendi-karti")

        // "Hâlâ yardım gerekiyor": önce onay sorulur (yalnızca hayvanı şimdi gördüysen), sonra işaret
        // yeniden yardım bekler.
        let dispute = app.buttons["action-dispute"]
        XCTAssertTrue(dispute.waitForExistence(timeout: 5), "Hâlâ yardım gerekiyor düğmesi yok")
        dispute.tap()
        let confirmDispute = app.buttons["Evet, hâlâ yardım gerekiyor"]
        XCTAssertTrue(confirmDispute.waitForExistence(timeout: 5), "İtiraz onayı sorulmadı")
        confirmDispute.tap()
        let reopened = app.staticTexts.element(labelContaining: "yeniden yardım bekliyor")
        XCTAssertTrue(reopened.waitForExistence(timeout: 5), "İtiraz bildirimi görünmedi")
        let waiting = app.staticTexts
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "report-status", "Yardım bekliyor"))
            .firstMatch
        XCTAssertTrue(waiting.waitForExistence(timeout: 5), "İtirazdan sonra kart 'Yardım bekliyor' demiyor")
        sleep(1)
        screenshots.take("12-itiraz")
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
