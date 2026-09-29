import CoreLocation
import XCTest

/// Ana akışı demo modunda gerçek dokunuşlarla dener:
/// kurallar → harita → "Yardım gereken hayvan" → tür → ihtiyaç → "Yardıma ihtiyacı var mı?" → işarete dokun →
/// "Düzenle" ile tür ve ihtiyaç düzeltilir → "İlgileniyorum" → "Hâlâ orada" ile gören sayısı artar →
/// "Aynı hayvan mı?" önerisi → uzak bir yere uzun basma reddedilir → çevrede uzun basma → iğneyi çevrenin dışına
/// sürükleme → "İğneyi konumuma getir" → yoldan geçen "Çözüldü" der → "… 'Çözüldü' dedi" kartı (uzakta itiraz
/// kapalı) → yanına gidip "Hâlâ yardım gerekiyor" itirazı → "Aç ve zayıf" işaretinin yanında "⋯ Diğer" →
/// "Yardım gerekmiyor" → "⋯ Diğer" ile işareti bildirme. Ayrı testler: orman ve deniz engeli, yanından geçilen
/// işaret için "Hâlâ orada mı?", uzaktaki işarette kapalı "Çözüldü". Her adımın ekran görüntüsü test sonucuna,
/// `SCREENSHOT_DIR` tanımlıysa (CI) o klasöre de yazılır.
///
/// Düğmeler görünen metinleri yerine kimlikleriyle bulunur (`report-button`, `need-food`, `action-…`); metinler
/// değişse de test aynı akışı dener. Kart, açılırken hayvana yakın olup olmadığına göre bazı eylemleri döşeme,
/// bazılarını "⋯ Diğer" menüsünde gösterir; `cardAction` ikisinde de bulur. "Çözüldü" ve hayvanı gördüğünü söyleyen
/// eylemler yalnızca hayvanın 150 m (+ doğruluk) yakınındayken açıktır (`ProximityPolicy`): yaralı kedi başlangıç
/// konumuna ~145 m, diğer örnekler daha uzak; test o adımlardan önce simülatör konumunu hayvanın yanına taşır.
///
/// İşaret yalnızca konumun çevresine konabildiği için testler simülatör konumunu verir (`launchDemoApp`); demo
/// modu simülatörde okumanın yaşını saymaz. Alan verisinden bağımsız olsun diye her nokta `-areaClass` ile aynı
/// alandır (ana akışta `allowed`); "Hâlâ orada mı?" ana akışta kapalıdır (`-noNearbyPrompt`).
final class ReportFlowUITests: XCTestCase {
    /// Kadıköy (ios/Kadikoy.gpx ile aynı). Demo örnek işaretleri kameranın çevresine konur.
    static let kadikoy = CLLocationCoordinate2D(latitude: 40.9903, longitude: 29.0290)
    /// Açık Marmara: shared/area-golden.json'daki deniz noktası.
    static let marmara = CLLocationCoordinate2D(latitude: 40.80, longitude: 28.50)

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
        // Simülatör konumu kapıya ulaşıyor: iğne konumun üstünde, ihtiyaçlar açık, engel satırı yok.
        XCTAssertTrue(waitForEnabled(food, true), "Konum varken ihtiyaç düğmeleri açılmadı")
        XCTAssertFalse(
            app.descendants(matching: .any)["placement-message"].exists,
            "Konumun üstündeki iğnede engel satırı var"
        )
        screenshots.take("03-ihtiyac-secimi")

        // Cihazın ilk hafif işaretleri: önce "Yardıma ihtiyacı var mı?" sorulur.
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

        // Düzeltmeden sonra kart yeniden açılır. Güvenlik hatırlatmaları (gece ve ilk gidiş) `-noNightReminder` ile
        // kapalı.
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
        // Güvenlik notu kartta değil; ilk gidişte bir kez sorulur (`-noNightReminder` ile kapalı).
        XCTAssertFalse(app.staticTexts.element(labelContaining: "Yalnız gitme").exists, "Kartta güvenlik notu kaldı")

        // Uzaktaysan "Hâlâ orada" menüde, yakındaysan döşemededir.
        let stillThere = cardAction(app, id: "action-confirmStillThere", labelPrefix: "Hâlâ orada")
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

        // Uzun basma yalnızca çevrede işaretlemeyi başlatır. Önce kullanıcının üstüne dönülür (yakınlık 16,
        // ~1,8 m/nokta).
        let recenter = app.buttons["Konumuma git"]
        XCTAssertTrue(recenter.waitForExistence(timeout: 5), "Konumuma git düğmesi yok")
        recenter.tap()
        sleep(2)
        let speciesTitle = app.staticTexts.element(labelContaining: "Hangi hayvan?")

        // ~375 m uzağa uzun basma: işaretleme başlamaz, neden söylenir.
        let farPoint = pointFromVisibleCenter(app, candidates: [
            CGVector(dx: -120, dy: -170), CGVector(dx: 120, dy: -170), CGVector(dx: -140, dy: 150),
        ])
        farPoint.press(forDuration: 1.2)
        let farToast = app.staticTexts.element(labelContaining: "150 m çevresine")
        XCTAssertTrue(farToast.waitForExistence(timeout: 5), "Uzak bir yere uzun basınca neden söylenmedi")
        XCTAssertFalse(speciesTitle.waitForExistence(timeout: 2), "Uzak bir yere uzun basınca işaretleme başladı")
        screenshots.take("12a-uzak-uzun-basma")

        // ~100 m öteye uzun basma: işaretleme o noktadan başlar.
        let nearPoint = pointFromVisibleCenter(app, candidates: [
            CGVector(dx: 55, dy: 0), CGVector(dx: -55, dy: 0), CGVector(dx: 0, dy: 55),
        ])
        nearPoint.press(forDuration: 1.2)
        XCTAssertTrue(speciesTitle.waitForExistence(timeout: 5), "Çevrede uzun basınca işaretleme başlamadı")
        sleep(1)
        screenshots.take("12-uzun-basma")
        cat.tap()
        XCTAssertTrue(waitForEnabled(food, true), "Çevredeki iğnede ihtiyaç düğmeleri açılmadı")

        // İğne çevrenin dışına sürüklenir: parmak sağdan sola, kamera doğuya gider. Yakınlık 17'de (~0,9 m/nokta)
        // bir sürükleme ~280 m; tek başına 225 m sınırını aşar.
        let map = app.maps.firstMatch
        XCTAssertTrue(map.exists, "Harita bulunamadı")
        for _ in 0..<2 {
            map.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.25))
                .press(forDuration: 0.1, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.25)))
            sleep(1)
        }
        let outside = placementMessage(app, containing: "çevrenin dışında")
        XCTAssertTrue(outside.waitForExistence(timeout: 10), "Çevrenin dışındaki iğne için engel satırı çıkmadı")
        XCTAssertTrue(waitForEnabled(food, false), "Çevrenin dışında ihtiyaç düğmeleri açık kaldı")
        screenshots.take("12b-cevre-disi")

        // "İğneyi konumuma getir": iğne kullanıcının üstüne döner, düğmeler yeniden açılır.
        let recenterPin = app.buttons["placement-recenter"]
        XCTAssertTrue(recenterPin.waitForExistence(timeout: 5), "'İğneyi konumuma getir' yok")
        recenterPin.tap()
        XCTAssertTrue(waitForEnabled(food, true), "İğne konuma dönünce ihtiyaç düğmeleri açılmadı")
        XCTAssertTrue(
            waitUntilGone(app.descendants(matching: .any)["placement-message"], timeout: 5),
            "İğne konuma dönünce engel satırı kalkmadı"
        )
        app.buttons["Vazgeç"].tap()

        // Yoldan geçen "Çözüldü" der (İlgileniyorum demeden). Demo hesabı 3 günlük ve bütçesi var: öneri
        // kanıtlıdır, kart kapanır ve işaret onun haritasından hemen kalkar. Bildirim saate göre değişir
        // ("yaklaşık 2 saat sonra" / gece "saat 08.00 civarında"); yalnızca ortak kısmı aranır.
        // Uzun basılan noktadan kullanıcının üstüne dönülür (yakınlık 16: gri noktalar çizilmez).
        XCTAssertTrue(recenter.waitForExistence(timeout: 5), "Konumuma git düğmesi yok")
        recenter.tap()
        sleep(2)
        XCTAssertTrue(injuredCat.waitForExistence(timeout: 10), "Örnek yaralı kedi işareti haritada bulunamadı")
        injuredCat.tap()
        // Yoldan geçenin "Çözüldü"sü "⋯ Diğer" menüsündedir (yanlışlıkla tek dokunuşla kapatılmasın).
        let resolve = cardAction(app, id: "action-resolve", labelPrefix: "Çözüldü")
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
        // Durum bloğu kimin ne dediğini ve nasıl göründüğünü söyler: "'İlgileniyorum' demeyen biri 'Çözüldü' dedi" /
        // "20 dk önce · doğrulanmadı".
        let closingStatus = app.staticTexts
            .matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@ AND label CONTAINS %@",
                "report-status", "'Çözüldü' dedi", "doğrulanmadı"
            ))
            .firstMatch
        XCTAssertTrue(closingStatus.waitForExistence(timeout: 5), "Kartta \"'Çözüldü' dedi · doğrulanmadı\" görünmedi")
        // Köpek 150 m çevrenin dışında: "Hâlâ yardım gerekiyor" yerinde durur ama kapalıdır; altında "Hayvanın
        // yanındayken (150 m)" yazar, sesli okumada da değeri budur.
        let dispute = app.buttons["action-dispute"]
        XCTAssertTrue(dispute.waitForExistence(timeout: 5), "Hâlâ yardım gerekiyor düğmesi yok")
        XCTAssertTrue(waitForEnabled(dispute, false), "Uzaktaki işarette 'Hâlâ yardım gerekiyor' açık")
        XCTAssertEqual(dispute.value as? String, "Hayvanın yanındayken (150 m)", "Kapalı itirazın nedeni okunmuyor")
        sleep(1)
        screenshots.take("14-cozuldu-dendi-karti")

        // Kişi köpeğin yanına yürür: kart açıkken düğme açılır. "Hâlâ yardım gerekiyor": önce onay sorulur
        // (yalnızca hayvanı şimdi gördüysen), sonra işaret yeniden yardım bekler.
        moveSimulatedLocation(north: -260, east: 20)
        XCTAssertTrue(waitForEnabled(dispute, true), "Köpeğin yanına gidince 'Hâlâ yardım gerekiyor' açılmadı")
        dispute.tap()
        let confirmDispute = app.buttons["Evet, hâlâ yardım gerekiyor"]
        XCTAssertTrue(confirmDispute.waitForExistence(timeout: 5), "İtiraz onayı sorulmadı")
        confirmDispute.tap()
        let reopened = app.staticTexts.element(labelContaining: "yeniden yardım bekliyor")
        XCTAssertTrue(reopened.waitForExistence(timeout: 5), "İtiraz bildirimi görünmedi")
        // Bekleyen işarette durum bloğu yok; itiraz eden (itiraz edilen değil) yeniden "İlgileniyorum" diyebilir.
        let claimAgain = app.buttons["action-claim"]
        XCTAssertTrue(claimAgain.waitForExistence(timeout: 5), "İtirazdan sonra kartta 'İlgileniyorum' yok")
        sleep(1)
        screenshots.take("15-itiraz")

        XCTAssertTrue(close.waitForExistence(timeout: 5), "Kartın kapat düğmesi yok")
        close.tap()
        XCTAssertTrue(reportButton.waitForExistence(timeout: 5), "Kart kapanınca ana ekrana dönülmedi")

        // "Aç ve zayıf" işaretindeki hayvan iyi görünüyor: "⋯ Diğer" → "Yardım gerekmiyor" (alt satırı "Hayvan orada
        // ama iyi görünüyor"). Demo verisindeki tek "Aç ve zayıf" işareti köpek, başlangıç konumunun ~250 m
        // güneydoğusunda. Bunu söylemek için yanında olmak gerekir: kişi köpeğin ~60 m batısına yürür (mavi nokta
        // işaretin üstüne binmesin, dokunuş ıskalamasın).
        moveSimulatedLocation(north: -200, east: 90)
        // Yeni konum uygulamaya ulaşsın; "Konumuma git" onun üstüne döner.
        sleep(1)
        recenter.tap()
        sleep(2)
        let foodDog = mapMarker(in: app, label: "Aç ve zayıf, Köpek")
        XCTAssertTrue(foodDog.waitForExistence(timeout: 10), "Örnek 'Aç ve zayıf' işareti haritada bulunamadı")
        foodDog.tap()
        // Yakında "Hâlâ yardım lazım" döşemededir (uzakta menüde); `cardAction` ikisinde de bulur.
        let stillNeeds = cardAction(app, id: "action-confirmStillThere", labelPrefix: "Hâlâ yardım lazım")
        XCTAssertTrue(stillNeeds.waitForExistence(timeout: 5), "'Aç ve zayıf' kartında 'Hâlâ yardım lazım' yok")
        XCTAssertTrue(stillNeeds.label.hasPrefix("Hâlâ yardım lazım"), "Öğe 'Hâlâ yardım lazım' demiyor: \(stillNeeds.label)")
        // "Yardım gerekmiyor" ve "Artık yok" menüde ayrı öğelerdir, soru sorulmadan yapılır.
        let fine = cardAction(app, id: "unneeded-fine", labelPrefix: "Yardım gerekmiyor")
        XCTAssertTrue(fine.waitForExistence(timeout: 5), "'Aç ve zayıf' kartında 'Yardım gerekmiyor' yok")
        // Alt satır ("Hayvan orada ama iyi görünüyor") ekranda görünür, ama iOS menü öğesinin alt yazısını
        // XCUITest'e vermiyor (etiket yalnızca "Yardım gerekmiyor"); bu yüzden burada denetlenmez.
        sleep(1)
        screenshots.take("16-diger-menu")

        fine.tap()
        let cleaner = app.staticTexts.element(labelContaining: "daha temiz")
        XCTAssertTrue(cleaner.waitForExistence(timeout: 5), "'Yardım gerekmiyor' bildirimi görünmedi")
        XCTAssertTrue(waitUntilGone(foodDog, timeout: 5), "'Yardım gerekmiyor' deyince işaret diyenin haritasından kalkmadı")
        sleep(1)
        screenshots.take("17-yardim-gerekmiyor")

        // Şüpheli bir işaret kartın "⋯ Diğer" menüsünden bildirilir (bunun için yanında olmak gerekmez); neden sabit
        // listeden seçilir. İşaret yalnızca bildirenin haritasından kalkar. Kişi başladığı yere döner: acil köpek
        // ~260 m batıda, ekranın sol yarısında.
        setSimulatedLocation(Self.kadikoy)
        sleep(1)
        recenter.tap()
        sleep(2)
        let emergencyDog = mapMarker(in: app, label: "Acil yardım, Köpek")
        XCTAssertTrue(emergencyDog.waitForExistence(timeout: 10), "Örnek acil köpek işareti haritada bulunamadı")
        emergencyDog.tap()
        let cardMenu = app.descendants(matching: .any).matching(identifier: "card-menu").firstMatch
        XCTAssertTrue(cardMenu.waitForExistence(timeout: 5), "Kartta '⋯ Diğer' yok")
        cardMenu.tap()
        // Acil işaretinde gidilen yer bir yakına gönderilebilir: yoldan geçene menüde (ilgilenene döşeme).
        let shareLocation = app.descendants(matching: .any).element(identifier: "share-location", orLabel: "Konumu paylaş")
        XCTAssertTrue(shareLocation.waitForExistence(timeout: 5), "Acil işaret kartının menüsünde 'Konumu paylaş' yok")
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

    // MARK: Nereye işaret konamaz

    /// Orman engeli, alan verisinden bağımsız: her nokta `-areaClass forest` ile orman sayılır. Engel tür
    /// seçiminden itibaren söylenir; ihtiyaç düğmeleri kapalıdır ve basmak hiçbir şey kaydetmez.
    @MainActor
    func testRiskyAreaBlocked() throws {
        let app = launchDemoApp(areaClass: "forest")
        let screenshots = Screenshots(test: self)
        acceptOnboarding(app)

        let reportButton = app.buttons["report-button"]
        XCTAssertTrue(reportButton.waitForExistence(timeout: 30), "Ana ekran açılmadı")
        sleep(2)
        reportButton.tap()
        let forest = placementMessage(app, containing: "ormanlık")
        XCTAssertTrue(forest.waitForExistence(timeout: 10), "Ormanda engel satırı çıkmadı")

        let dog = app.buttons["species-dog"]
        XCTAssertTrue(dog.waitForExistence(timeout: 5), "Tür seçimi açılmadı")
        dog.tap()
        let vet = app.buttons["need-vet"]
        XCTAssertTrue(waitForEnabled(vet, false), "Ormanda ihtiyaç düğmeleri açık")
        // Kapalı düğmeye dokunmak işaret koymaz.
        vet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let saved = app.staticTexts.element(labelContaining: "işaretlendi")
        XCTAssertFalse(saved.waitForExistence(timeout: 3), "Ormanda işaret kaydedildi")
        screenshots.take("21-orman")
        app.buttons["Vazgeç"].tap()
    }

    /// Uygulamayla gelen alan ızgarası: açık Marmara'da işaret konamaz. Bu, ızgaranın Release paketine
    /// girdiğini gösterir; `shared/area-tr.bin` henüz üretilmediyse (tools/area-grid) atlanır.
    @MainActor
    func testSeaBlockedByBundledGrid() throws {
        try XCTSkipUnless(Self.repositoryHasAreaGrid, "shared/area-tr.bin yok (tools/area-grid ile üretilir)")
        let app = launchDemoApp(at: Self.marmara, areaClass: nil)
        let screenshots = Screenshots(test: self)
        acceptOnboarding(app)

        let reportButton = app.buttons["report-button"]
        XCTAssertTrue(reportButton.waitForExistence(timeout: 30), "Ana ekran açılmadı")
        sleep(2)
        reportButton.tap()
        let sea = placementMessage(app, containing: "Denizin")
        XCTAssertTrue(sea.waitForExistence(timeout: 10), "Denizde engel satırı çıkmadı")
        let cat = app.buttons["species-cat"]
        XCTAssertTrue(cat.waitForExistence(timeout: 5), "Tür seçimi açılmadı")
        cat.tap()
        XCTAssertTrue(waitForEnabled(app.buttons["need-injured"], false), "Denizde ihtiyaç düğmeleri açık")
        screenshots.take("20-deniz")
        app.buttons["Vazgeç"].tap()
        app.terminate()
    }

    // MARK: "Hâlâ orada mı?"

    /// Yaralı kedinin yanından geçen kişiye sorulur; "Evet" gören sayısını artırır ve (dikkat isteyen ihtiyaç)
    /// kartı açar. Aynı işaret bir daha sorulmaz.
    @MainActor
    func testNearbyPromptStillThere() throws {
        let app = launchDemoApp(nearbyPrompt: true)
        let screenshots = Screenshots(test: self)
        acceptOnboarding(app)

        let reportButton = app.buttons["report-button"]
        XCTAssertTrue(reportButton.waitForExistence(timeout: 30), "Ana ekran açılmadı")
        // Harita karoları ve demo işaretleri yüklensin.
        sleep(4)
        let injuredCat = mapMarker(in: app, label: "Yaralı / hasta, Kedi")
        XCTAssertTrue(injuredCat.waitForExistence(timeout: 10), "Örnek yaralı kedi işareti haritada bulunamadı")

        // Demo örneği kullanıcının ~120 m kuzeyinde, 80 m batısında: kişi yanına yürür.
        moveSimulatedLocation(north: 120, east: -80)
        // Açılıştan sonraki 15 sn'lik bekleme de bu sürenin içinde.
        let question = nearbyQuestion(app, containing: "Yakınındaki kedi hâlâ orada mı?")
        XCTAssertTrue(question.waitForExistence(timeout: 25), "'Hâlâ orada mı?' sorulmadı")
        screenshots.take("22-hala-orada-mi")

        let yes = app.buttons["nearby-yes"]
        XCTAssertTrue(waitForEnabled(yes, true, timeout: 3), "'Evet' açılmadı")
        yes.tap()
        let seenByFour = app.staticTexts.element(labelContaining: "4 kişi bildirdi")
        XCTAssertTrue(seenByFour.waitForExistence(timeout: 5), "'Evet' gören sayısını artırmadı")
        XCTAssertTrue(app.buttons["action-claim"].waitForExistence(timeout: 5), "Yaralı işarette 'Evet' kartı açmadı")
        XCTAssertTrue(waitUntilGone(anyNearbyQuestion(app), timeout: 5), "Yanıttan sonra soru kalkmadı")

        let close = app.buttons["Kapat"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Kartın kapat düğmesi yok")
        close.tap()
        XCTAssertFalse(anyNearbyQuestion(app).waitForExistence(timeout: 5), "Aynı işaret yeniden soruldu")
    }

    /// "Aç ve zayıf" köpeğin yanından geçen kişi: "Evet" → "Yardıma ihtiyacı var mı?" → "Yardım gerekmiyor".
    /// Yeni açılış: cihazdaki soru kaydı boş.
    @MainActor
    func testNearbyPromptFoodUnneeded() throws {
        let app = launchDemoApp(nearbyPrompt: true)
        let screenshots = Screenshots(test: self)
        acceptOnboarding(app)

        let reportButton = app.buttons["report-button"]
        XCTAssertTrue(reportButton.waitForExistence(timeout: 30), "Ana ekran açılmadı")
        sleep(4)
        let foodDog = mapMarker(in: app, label: "Aç ve zayıf, Köpek")
        XCTAssertTrue(foodDog.waitForExistence(timeout: 10), "Örnek 'Aç ve zayıf' işareti haritada bulunamadı")

        // Demo örneği kullanıcının ~200 m güneyinde, 150 m doğusunda.
        moveSimulatedLocation(north: -200, east: 150)
        let question = nearbyQuestion(app, containing: "Yakınındaki köpek hâlâ orada mı?")
        XCTAssertTrue(question.waitForExistence(timeout: 25), "'Hâlâ orada mı?' sorulmadı")
        let yes = app.buttons["nearby-yes"]
        XCTAssertTrue(waitForEnabled(yes, true, timeout: 3), "'Evet' açılmadı")
        yes.tap()

        // Mamada ikinci adım; düğmeler yeniden kısa bir bekleyişten sonra açılır.
        let needsHelp = nearbyQuestion(app, containing: "Yardıma ihtiyacı var mı?")
        XCTAssertTrue(needsHelp.waitForExistence(timeout: 5), "Mamada 'Yardıma ihtiyacı var mı?' sorulmadı")
        let unneeded = app.buttons["nearby-unneeded"]
        XCTAssertTrue(waitForEnabled(unneeded, true, timeout: 5), "'Yardım gerekmiyor' açılmadı")
        screenshots.take("23-mama-yardim-gerekmiyor")
        unneeded.tap()

        let cleaner = app.staticTexts.element(labelContaining: "daha temiz")
        XCTAssertTrue(cleaner.waitForExistence(timeout: 5), "'Yardım gerekmiyor' bildirimi görünmedi")
        XCTAssertTrue(waitUntilGone(foodDog, timeout: 5), "'Yardım gerekmiyor' deyince işaret haritadan kalkmadı")
    }

    // MARK: Uzaktan "Çözüldü" denemez

    /// "İlgileniyorum" uzaktan da denir, "Çözüldü" ise yalnızca hayvanın yanındayken (ya da son 12 saatte yanına
    /// uğradıysa). Uzaktaki köpeğe "İlgileniyorum" diyen kişinin birincil "Çözüldü"sü kapalıdır ve altında "Hayvanın
    /// yanına gidince açılır" yazar; yanına yürüyünce kart açıkken açılır.
    @MainActor
    func testResolveNeedsVisit() throws {
        let app = launchDemoApp()
        let screenshots = Screenshots(test: self)
        acceptOnboarding(app)

        let reportButton = app.buttons["report-button"]
        XCTAssertTrue(reportButton.waitForExistence(timeout: 30), "Ana ekran açılmadı")
        sleep(4)
        // Demo örneği kullanıcının ~250 m güneydoğusunda (200 m güney, 150 m doğu): 150 m çevrenin dışında.
        let foodDog = mapMarker(in: app, label: "Aç ve zayıf, Köpek")
        XCTAssertTrue(foodDog.waitForExistence(timeout: 10), "Örnek 'Aç ve zayıf' işareti haritada bulunamadı")
        foodDog.tap()

        let claim = app.buttons["action-claim"]
        XCTAssertTrue(claim.waitForExistence(timeout: 5), "Kartta 'İlgileniyorum' yok")
        claim.tap()
        let thanks = app.staticTexts.element(labelContaining: "3 saat boyunca sende")
        XCTAssertTrue(thanks.waitForExistence(timeout: 5), "İlgileniyorum onayı görünmedi")

        // İlgilenenin sıradaki adımı "Çözüldü": yerinde, kapalı, nedeni altında ve sesli okumada değer olarak.
        let resolve = app.buttons["action-resolve"]
        XCTAssertTrue(resolve.waitForExistence(timeout: 5), "İlgilenenin kartında 'Çözüldü' yok")
        XCTAssertTrue(waitForEnabled(resolve, false), "Uzaktaki işarette 'Çözüldü' açık")
        XCTAssertEqual(resolve.value as? String, "Hayvanın yanına gidince açılır", "Kapalı 'Çözüldü'nün nedeni okunmuyor")
        sleep(1)
        screenshots.take("24-uzakta-cozuldu-kapali")

        // Köpeğin ~60 m batısına yürür.
        moveSimulatedLocation(north: -200, east: 90)
        XCTAssertTrue(waitForEnabled(resolve, true), "Hayvanın yanına gidince 'Çözüldü' açılmadı")
        sleep(1)
        screenshots.take("25-yaninda-cozuldu-acik")

        resolve.tap()
        let recorded = app.staticTexts.element(labelContaining: "Yardımın kaydedildi")
        XCTAssertTrue(recorded.waitForExistence(timeout: 5), "Çözüldü bildirimi görünmedi")
    }

    // MARK: Yardımcılar

    /// Demo modunda açar. Simülatör konumu (doğruluk 5 m) açılıştan önce verilir; işaret yalnızca bu konumun
    /// çevresine konabilir. `areaClass`: her nokta bu alan (`nil`: uygulamayla gelen ızgara). "Hâlâ orada mı?"
    /// yalnızca `nearbyPrompt` ile açıktır.
    @MainActor
    private func launchDemoApp(
        at coordinate: CLLocationCoordinate2D = ReportFlowUITests.kadikoy,
        areaClass: String? = "allowed",
        nearbyPrompt: Bool = false,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        setSimulatedLocation(coordinate)
        let app = XCUIApplication()
        // Güvenlik hatırlatmaları kapalı: test günün her saatinde aynı akışı dener (AppEnvironment.noNightReminderArgument).
        var arguments = ["-demo", "-noNightReminder"]
        if !nearbyPrompt {
            arguments.append("-noNearbyPrompt")
        }
        if let areaClass {
            arguments += ["-areaClass", areaClass]
        }
        app.launchArguments = arguments + extraArguments
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

    /// İlk açılıştaki kurallar (demo cihaz durumunu hatırlamaz: her açılış ilk açılış gibidir).
    @MainActor
    private func acceptOnboarding(_ app: XCUIApplication) {
        let accept = app.buttons["onboarding-accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 30), "Kurallar sayfası açılmadı")
        accept.tap()
        XCTAssertTrue(waitUntilGone(accept, timeout: 5), "Kabul edince kurallar sayfası kapanmadı")
    }

    @MainActor
    private func setSimulatedLocation(_ coordinate: CLLocationCoordinate2D) {
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: 0,
            timestamp: Date()
        ))
    }

    /// Simülatör konumunu Kadıköy'den metre cinsinden kaydırır (demo örnekleriyle aynı hesap).
    @MainActor
    private func moveSimulatedLocation(north: Double, east: Double) {
        let origin = Self.kadikoy
        setSimulatedLocation(CLLocationCoordinate2D(
            latitude: origin.latitude + north / 111_320,
            longitude: origin.longitude + east / (111_320 * cos(origin.latitude * .pi / 180))
        ))
    }

    /// Öğe `timeout` içinde açılır ya da kapanırsa `true`. Bir kez bakıp karar verilmez: karar konum
    /// geldikçe değişir.
    @MainActor
    @discardableResult
    private func waitForEnabled(_ element: XCUIElement, _ enabled: Bool, timeout: TimeInterval = 10) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == %@", NSNumber(value: enabled)),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Seçim panelindeki engel satırı, metninde `text` geçen.
    @MainActor
    private func placementMessage(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "placement-message", text))
            .firstMatch
    }

    /// "Hâlâ orada mı?" şeridindeki soru, metninde `text` geçen.
    @MainActor
    private func nearbyQuestion(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "nearby-question", text))
            .firstMatch
    }

    /// Şeritteki soru, hangisi olursa.
    @MainActor
    private func anyNearbyQuestion(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "nearby-question").firstMatch
    }

    /// Haritanın görünen alanının (üst etiket ile alt düğme arası) ortasından `candidates` kadar kaymış ilk
    /// nokta; işaretlerin üstüne (her yana 24 nokta pay) denk gelenler atlanır.
    @MainActor
    private func pointFromVisibleCenter(_ app: XCUIApplication, candidates: [CGVector]) -> XCUICoordinate {
        let chip = app.staticTexts.element(labelContaining: "Demo modu")
        let reportButton = app.buttons["report-button"]
        let center = CGPoint(x: app.frame.midX, y: (chip.frame.minY + reportButton.frame.minY) / 2)
        let markerFrames = app.descendants(matching: .any)
            .matching(identifier: "report-marker")
            .allElementsBoundByIndex
            .map { $0.frame.insetBy(dx: -24, dy: -24) }
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let points = candidates.map { CGPoint(x: center.x + $0.dx, y: center.y + $0.dy) }
        let point = points.first { point in !markerFrames.contains { $0.contains(point) } } ?? points[0]
        return origin.withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
    }

    /// Haritadaki işaret, erişilebilirlik etiketiyle ("Aç ve zayıf, Kedi"). Gri nokta da aynı etiketi taşır.
    @MainActor
    private func mapMarker(in app: XCUIApplication, label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", "report-marker", label))
            .firstMatch
    }

    /// Kartta görünüyorsa düğme; değilse "⋯ Diğer" menüsü açılıp oradaki öğe. Menü öğelerinde kimlik her zaman
    /// iletilmediği için etiketin başıyla da aranır. Menü zaten açıksa öğe hemen bulunur; menüye yeniden
    /// dokunulmaz (dokunuş onu kapatırdı).
    @MainActor
    private func cardAction(_ app: XCUIApplication, id: String, labelPrefix: String) -> XCUIElement {
        let item = app.buttons
            .matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", id, labelPrefix))
            .firstMatch
        if item.waitForExistence(timeout: 2) { return item }
        let menu = app.descendants(matching: .any).matching(identifier: "card-menu").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Kartta '⋯ Diğer' yok")
        menu.tap()
        return item
    }

    /// Öğe `timeout` içinde kaybolursa `true`.
    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    /// Depodaki alan ızgarası (bu dosyaya göre ../../shared/area-tr.bin). Simülatördeki test süreci Mac'teki
    /// kaynak klasörünü okuyabilir; ızgara varsa uygulamaya da girer (project.yml).
    private static var repositoryHasAreaGrid: Bool {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("shared/area-tr.bin").path)
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
