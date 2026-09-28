import CoreLocation
import XCTest

/// Ana akışı demo modunda gerçek dokunuşlarla dener:
/// kurallar → harita → "Yardım gereken hayvan" → tür → ihtiyaç → "Yardıma ihtiyacı var mı?" → işarete dokun →
/// "Düzenle" ile tür ve ihtiyaç düzeltilir → "İlgileniyorum" → "Hâlâ orada" ile gören sayısı artar →
/// "Aynı hayvan mı?" önerisi → uzun basma → yoldan geçen "Çözüldü" der → "Çözüldü dendi" kartı →
/// "Hâlâ yardım gerekiyor" itirazı → "Aç ve zayıf" işaretinde "Yardım gerekmiyor" → "⋯" ile işareti bildirme.
/// Her adımın ekran görüntüsü test sonucuna, `SCREENSHOT_DIR` tanımlıysa (CI) o klasöre de yazılır.
///
/// Düğmeler görünen metinleri yerine kimlikleriyle bulunur (`report-button`, `need-food`, `action-…`); metinler
/// değişse de test aynı akışı dener.
final class ReportFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReportFlow() throws {
        let app = launchDemoApp()
        let screenshots = Screenshots(test: self)

        // İlk açılışta kurallar (demo cihaz durumunu hatırlamaz: her açılış ilk açılış gibidir). Harita arkada yüklenir.
        let accept = app.buttons["onboarding-accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 30), "Kurallar sayfası açılmadı")
        sleep(1)
        screenshots.take("00-kurallar")
        accept.tap()
        XCTAssertTrue(waitUntilGone(accept, timeout: 5), "Kabul edince kurallar sayfası kapanmadı")

        let reportButton = app.buttons["report-button"]
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
        XCTAssertTrue(
            app.staticTexts["need-guidance"].exists,
            "İhtiyaçların üstünde 'Yalnızca yardıma ihtiyacı varsa işaretle' satırı yok"
        )
        screenshots.take("03-ihtiyac-secimi")

        // Cihazın ilk hafif işaretleri: önce "Yardıma ihtiyacı var mı?" sorulur. Demo konumu iğnenin kendisi
        // olduğu için uzaklık sorusu gelmez.
        food.tap()
        let checkConfirm = app.buttons["check-confirm"]
        XCTAssertTrue(checkConfirm.waitForExistence(timeout: 5), "'Yardıma ihtiyacı var mı?' sorulmadı")
        XCTAssertTrue(app.buttons["check-cancel"].exists, "Kontrolde 'Sağlıklı görünüyor, vazgeç' yok")
        sleep(1)
        screenshots.take("04-yardim-kontrolu")

        checkConfirm.tap()
        let saved = app.staticTexts.element(labelContaining: "işaretlendi")
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "İşaret kaydedildi bildirimi görünmedi")
        sleep(1)
        screenshots.take("05-isaretlendi")

        // Demo verisindeki tek "Aç ve zayıf" işareti köpek; "Kedi" de aranınca bulunan, az önce koyulan işarettir.
        let newMarker = mapMarker(in: app, label: "Aç ve zayıf, Kedi")
        XCTAssertTrue(newMarker.waitForExistence(timeout: 10), "Yeni işaret haritada bulunamadı")

        // İşaret iğnenin gösterdiği yere koyuldu mu: kamera hedefi görünen alanın (üst çubuk ile alt
        // düğmeler arası) ortasındadır, yeni işaretin ucu da tam orada olmalı. Kenar boşlukları iki kez
        // sayıldığında bu kayma ~20 nokta oluyordu.
        sleep(1)
        let chip = app.staticTexts.element(labelContaining: "Demo modu")
        XCTAssertTrue(chip.exists, "Üst durum etiketi bulunamadı")
        let visibleCenterY = (chip.frame.minY + reportButton.frame.minY) / 2
        XCTAssertEqual(newMarker.frame.maxY, visibleCenterY, accuracy: 12, "Yeni işaret görünen alanın ortasında değil")
        XCTAssertEqual(newMarker.frame.midX, app.frame.midX, accuracy: 12, "Yeni işaret yatayda ortada değil")

        // Küçük (hafif ihtiyaç) iğnenin ucu mavi konum noktasının üstünde: başına dokunulur.
        newMarker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        let edit = app.buttons["action-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Kendi yeni işaretinin kartında 'Düzenle' yok")
        let claim = app.buttons["action-claim"]
        XCTAssertTrue(claim.exists, "Kartta 'İlgileniyorum' yok")
        sleep(1)
        screenshots.take("06-isaret-karti")

        // Yanlış işaretleme düzeltilir: kedi değil köpek, mama değil veteriner. Demo verisinde köpek veteriner
        // işareti yok; yeni etiket tektir.
        edit.tap()
        let editTitle = app.staticTexts.element(labelContaining: "İşareti düzelt")
        XCTAssertTrue(editTitle.waitForExistence(timeout: 5), "Düzeltme paneli açılmadı")
        let dog = app.buttons["species-dog"]
        XCTAssertTrue(dog.waitForExistence(timeout: 5), "Düzeltmede tür seçimi yok")
        sleep(1)
        screenshots.take("07-duzenle")

        dog.tap()
        let vet = app.buttons["need-vet"]
        XCTAssertTrue(vet.waitForExistence(timeout: 5), "Düzeltmede ihtiyaç seçimi açılmadı")
        vet.tap()
        let edited = app.staticTexts.element(labelContaining: "İşaret güncellendi")
        XCTAssertTrue(edited.waitForExistence(timeout: 5), "Düzeltme bildirimi görünmedi")
        let editedMarker = mapMarker(in: app, label: "Veteriner desteği, Köpek")
        XCTAssertTrue(editedMarker.waitForExistence(timeout: 10), "Düzeltilen işaret haritada yeni etiketiyle bulunamadı")
        XCTAssertFalse(newMarker.exists, "Düzeltmeden sonra eski etiket haritada kaldı")
        sleep(1)
        screenshots.take("08-isaret-guncellendi")

        // Düzeltmeden sonra kart yeniden açılır. Gece hatırlatması `-noNightReminder` ile kapalı.
        XCTAssertTrue(claim.waitForExistence(timeout: 5), "Düzeltmeden sonra kart açılmadı")
        claim.tap()
        let thanks = app.staticTexts.element(labelContaining: "3 saat boyunca sende")
        XCTAssertTrue(thanks.waitForExistence(timeout: 5), "İlgileniyorum onayı görünmedi")
        // Biri ilgilenen işaret artık düzeltilemez.
        XCTAssertTrue(waitUntilGone(edit, timeout: 5), "İlgilenilen işarette 'Düzenle' kaldı")
        screenshots.take("09-ilgileniyorum")

        let close = app.buttons["Kapat"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Kartın kapat düğmesi yok")
        close.tap()
        XCTAssertTrue(reportButton.waitForExistence(timeout: 5), "Kart kapanınca ana ekrana dönülmedi")

        // Kaç kişi bildirdi: demo verisindeki yaralı kediyi 3 kişi bildirmiş (demo kullanıcısı değil).
        // Kamera kullanıcının üstünde; bu işaret ~120 m kuzeyde, 80 m batıda, yani ekranın sol üstünde.
        let injuredCat = mapMarker(in: app, label: "Yaralı / hasta, Kedi")
        XCTAssertTrue(injuredCat.waitForExistence(timeout: 10), "Örnek yaralı kedi işareti haritada bulunamadı")
        // Kart kapanınca harita yeniden ortalanıyor; işaret yerine otursun, yoksa dokunuş ıskalar.
        sleep(1)
        injuredCat.tap()
        let seenByThree = app.staticTexts.element(labelContaining: "3 kişi bildirdi")
        XCTAssertTrue(seenByThree.waitForExistence(timeout: 5), "Kartta gören sayısı (3) görünmedi")

        let stillThere = app.buttons["action-confirmStillThere"]
        XCTAssertTrue(stillThere.waitForExistence(timeout: 5), "Hâlâ orada düğmesi yok")
        stillThere.tap()
        // "Hâlâ orada" diyen demo kullanıcısı da sayılır: kart (ve bildirim) 4 der.
        let seenByFour = app.staticTexts.element(labelContaining: "4 kişi bildirdi")
        XCTAssertTrue(seenByFour.waitForExistence(timeout: 5), "Hâlâ orada deyince gören sayısı artmadı")
        sleep(1)
        screenshots.take("10-goren-sayisi")

        XCTAssertTrue(close.waitForExistence(timeout: 5), "Kartın kapat düğmesi yok")
        close.tap()
        XCTAssertTrue(reportButton.waitForExistence(timeout: 5), "Kart kapanınca ana ekrana dönülmedi")

        // Aynı hayvan mı: az önce koyulup köpeğe düzeltilen işaret iğnenin dibinde. Aynı tür seçilince yeni işaret
        // yerine "Ben de gördüm" önerilir; dokununca o işaretin kartı açılır.
        reportButton.tap()
        XCTAssertTrue(dog.waitForExistence(timeout: 5), "Tür seçimi açılmadı")
        dog.tap()
        let duplicate = app.descendants(matching: .any).matching(identifier: "duplicate-suggestion").firstMatch
        XCTAssertTrue(duplicate.waitForExistence(timeout: 10), "Aynı hayvan mı önerisi görünmedi")
        sleep(1)
        screenshots.take("11-ayni-hayvan-mi")

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
        screenshots.take("12-uzun-basma")
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
        XCTAssertTrue(waitUntilGone(injuredCat, timeout: 5), "Çözüldü deyince işaret diyenin haritasından kalkmadı")
        sleep(1)
        screenshots.take("13-cozuldu-dendi")

        // Demo verisindeki "Çözüldü dendi" örneği: yoldan geçen biri bütçesiz dedi, bu yüzden demo
        // kullanıcısına "?" rozetiyle "doğrulanmadı" görünür. Kullanıcının ~260 m güneyinde; harita kediye dokununca
        // ona ortalandığı için köpek görünen alanın ortasının ~210 nokta altında (bildirimin üstünde) kalır.
        let closingDog = mapMarker(in: app, label: "Yaralı / hasta, Köpek")
        XCTAssertTrue(closingDog.waitForExistence(timeout: 10), "Örnek 'Çözüldü dendi' işareti haritada bulunamadı")
        let spoken = (closingDog.value as? String) ?? ""
        XCTAssertTrue(spoken.contains("doğrulanmadı"), "İşaretin sesli değeri 'doğrulanmadı' demiyor: \(spoken)")
        closingDog.tap()
        let closingStatus = app.staticTexts
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "report-status", "Çözüldü dendi"))
            .firstMatch
        XCTAssertTrue(closingStatus.waitForExistence(timeout: 5), "Kartta 'Çözüldü dendi' görünmedi")
        sleep(1)
        screenshots.take("14-cozuldu-dendi-karti")

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
        screenshots.take("15-itiraz")

        XCTAssertTrue(close.waitForExistence(timeout: 5), "Kartın kapat düğmesi yok")
        close.tap()
        XCTAssertTrue(reportButton.waitForExistence(timeout: 5), "Kart kapanınca ana ekrana dönülmedi")

        // "Aç ve zayıf" işaretindeki hayvan iyi görünüyor: "Yardım gerekmiyor" → "Hayvan orada ama iyi görünüyor".
        // Demo verisindeki tek "Aç ve zayıf" işareti köpek, kullanıcının ~200 m güneydoğusunda.
        recenter.tap()
        sleep(2)
        let foodDog = mapMarker(in: app, label: "Aç ve zayıf, Köpek")
        XCTAssertTrue(foodDog.waitForExistence(timeout: 10), "Örnek 'Aç ve zayıf' işareti haritada bulunamadı")
        foodDog.tap()
        let unneeded = app.buttons["action-reportGone"]
        XCTAssertTrue(unneeded.waitForExistence(timeout: 5), "'Aç ve zayıf' kartında 'Yardım gerekmiyor' yok")
        XCTAssertTrue(unneeded.label.contains("Yardım gerekmiyor"), "Düğme 'Yardım gerekmiyor' demiyor: \(unneeded.label)")
        let stillNeeds = app.buttons["action-confirmStillThere"]
        XCTAssertTrue(stillNeeds.label.contains("Hâlâ yardım lazım"), "Düğme 'Hâlâ yardım lazım' demiyor: \(stillNeeds.label)")
        unneeded.tap()
        let fine = app.buttons.element(identifier: "unneeded-fine", orLabel: "Hayvan orada ama iyi görünüyor")
        XCTAssertTrue(fine.waitForExistence(timeout: 5), "'Ne gördün?' sorulmadı")
        sleep(1)
        screenshots.take("16-ne-gordun")

        fine.tap()
        let cleaner = app.staticTexts.element(labelContaining: "daha temiz")
        XCTAssertTrue(cleaner.waitForExistence(timeout: 5), "'Yardım gerekmiyor' bildirimi görünmedi")
        XCTAssertTrue(waitUntilGone(foodDog, timeout: 5), "'Yardım gerekmiyor' deyince işaret diyenin haritasından kalkmadı")
        sleep(1)
        screenshots.take("17-yardim-gerekmiyor")

        // Şüpheli bir işaret kartın "⋯" menüsünden bildirilir; neden sabit listeden seçilir. İşaret yalnızca
        // bildirenin haritasından kalkar. Acil köpek kullanıcının ~260 m batısında, ekranın sol yarısında.
        recenter.tap()
        sleep(2)
        let emergencyDog = mapMarker(in: app, label: "Acil yardım, Köpek")
        XCTAssertTrue(emergencyDog.waitForExistence(timeout: 10), "Örnek acil köpek işareti haritada bulunamadı")
        emergencyDog.tap()
        let cardMenu = app.descendants(matching: .any).matching(identifier: "card-menu").firstMatch
        XCTAssertTrue(cardMenu.waitForExistence(timeout: 5), "Kartta ⋯ menüsü yok")
        // Acil işaretinde gidilen yer bir yakına gönderilebilir.
        let shareLocation = app.descendants(matching: .any).matching(identifier: "share-location").firstMatch
        XCTAssertTrue(shareLocation.exists, "Acil işaret kartında 'Konumu paylaş' yok")
        cardMenu.tap()
        let flagItem = app.buttons.element(identifier: "menu-flag", orLabel: "Bu işareti bildir")
        XCTAssertTrue(flagItem.waitForExistence(timeout: 5), "Menüde 'Bu işareti bildir' yok")
        flagItem.tap()
        let fake = app.buttons.element(identifier: "flag-fake", orLabel: "Burada yardım bekleyen hayvan yok (sahte işaret)")
        XCTAssertTrue(fake.waitForExistence(timeout: 5), "'Bu işarette ne sorun var?' sorulmadı")
        sleep(1)
        screenshots.take("18-bildir")

        fake.tap()
        let flagged = app.staticTexts.element(labelContaining: "bildirimin bize ulaştı")
        XCTAssertTrue(flagged.waitForExistence(timeout: 5), "Bildirim teşekkürü görünmedi")
        XCTAssertTrue(waitUntilGone(emergencyDog, timeout: 5), "Bildirilen işaret bildirenin haritasından kalkmadı")
        sleep(1)
        screenshots.take("19-bildirildi")
    }

    // MARK: Yardımcılar

    @MainActor
    private func launchDemoApp() -> XCUIApplication {
        // Kadıköy (ios/Kadikoy.gpx ile aynı).
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 40.9903, longitude: 29.0290))
        let app = XCUIApplication()
        // Gece hatırlatması kapalı: test günün her saatinde aynı akışı dener (AppEnvironment.noNightReminderArgument).
        app.launchArguments = ["-demo", "-noNightReminder"]
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

    /// Haritadaki işaret, erişilebilirlik etiketiyle ("Aç ve zayıf, Kedi"). Gri nokta da aynı etiketi taşır.
    @MainActor
    private func mapMarker(in app: XCUIApplication, label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", "report-marker", label))
            .firstMatch
    }

    /// Öğe `timeout` içinde kaybolursa `true`.
    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
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
    /// Haritadaki işaretler de düğmedir ("Aç ve zayıf, Kedi"); onlar hariç tutulur.
    func element(labelContaining text: String) -> XCUIElement {
        matching(NSPredicate(format: "label CONTAINS %@ AND identifier != %@", text, "report-marker")).firstMatch
    }

    /// Kimliği ya da etiketi verilen ilk öğe: onay sorusu ve menü düğmelerinde kimlik her zaman iletilmiyor.
    func element(identifier: String, orLabel label: String) -> XCUIElement {
        matching(NSPredicate(format: "identifier == %@ OR label == %@", identifier, label)).firstMatch
    }
}
