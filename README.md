# Pati Harita

Sokakta yardıma ihtiyacı olan hayvanlar için **yaşayan, sürekli güncellenen bir yardım haritası**.
Sosyal medya ya da ilan uygulaması değil; tek ekranı olan, birkaç saniyede kullanılan bir harita.

> Yardıma ihtiyacı olan bir hayvan gördüm → haritada işaretledim → neye ihtiyacı olduğunu seçtim → yakındakiler gördü → biri yardım etti → işaret kapandı.

Sağlıklı, beslenen sokak hayvanları ve mama noktaları **işaretlenmez**: her işaret bir gönüllünün yola çıkması demektir.

## Kullanıcı deneyimi

**Ana ekran doğrudan haritadır** (Apple Haritalar). Üstte canlı bir durum etiketi, altta tek büyük düğme: **Yardım gereken hayvan**.

Durum etiketi önce ağır ihtiyaçları, sonra düşük öncelikli olanları sayar: "3 hayvan yardım bekliyor · 5 düşük öncelikli",
"Yakında acil ihtiyaç yok · 5 düşük öncelikli" ya da "Yakında yardım bekleyen yok".

### İlk açılış: kurallar

Uygulama ilk açıldığında harita arkada yüklenirken tek sayfalık kurallar gösterilir: harita ne içindir, neler işaretlenir
(yaralı ya da hasta, tehlikede ya da annesiz yavrular, çok zayıf ya da terk edilmiş hayvanlar), neler işaretlenmez
(sağlıklı ve beslenen sokak hayvanları, mama noktaları), güvenlik ("Yalnız gitme, kimseyle tartışmaya girme, özel mülke
girme. Hayati tehlike varsa 112'yi ara.") ve kötüye kullanıma sıfır tolerans. **Kabul ediyorum, başla** ile bir kez
kabul edilir; kurallar değişince (`AppInfo.termsVersion`) yeniden sorulur. Açıklama ekranındaki **Kurallar** ile yeniden
okunabilir. Ayrıntılar: [Kullanım koşulları](docs/kullanim-kosullari.md), [Gizlilik politikası](docs/gizlilik-politikasi.md).

### İşaretleme: 3 dokunuş, birkaç saniye

1. **Yardım gereken hayvan** → harita bulunduğun noktaya yaklaşır, ortada sabit bir iğne belirir.
   Konum yanlışsa haritayı kaydırmak yeterli; iğne hep ortada kalır. Haritaya **uzun basmak** da o noktadan işaretlemeyi başlatır.
2. **Tür**: Kedi · Köpek
3. **İhtiyaç**: Acil yardım (en üstte, kırmızı) · Aç ve zayıf · Yaralı / hasta · Terk edilmiş / bakıma muhtaç ·
   Yavrular tehlikede · Veteriner desteği. Listenin üstünde tek satır: "Yalnızca yardıma ihtiyacı varsa işaretle.
   Sağlıklı sokak hayvanları işaretlenmez."

İhtiyaca dokunduğun an işaret kaydedilir. Form, fotoğraf, açıklama yok. Yanlışlık olursa 5 saniye boyunca **Geri al** görünür.
Bağlantı zayıfsa işaret yine anında haritada görünür ve bağlantı gelince gönderilir.

Bazen kaydetmeden önce tek bir soru gelir; hiçbiri işaretlemeyi engellemez:

- **Yardıma ihtiyacı var mı?** Yalnızca "Aç ve zayıf" ve "Terk edilmiş / bakıma muhtaç" için (bunlar sağlıklı bir sokak
  hayvanıyla en kolay karışanlar), bu cihazın ilk 3 böyle işaretinde ve sonra yalnızca son 24 saatte 2 ya da daha fazla
  (acil olmayan) işaret konduysa ("Son 24 saatte 2 işaret koydun."). **Yardıma ihtiyacı var, işaretle** kaydeder;
  **Sağlıklı görünüyor, vazgeç** teşekkür edip kapatır. Acil, yaralı, yavru ve veteriner işaretlerinde hiç sorulmaz.
- **İğne uzakta mı?** Konum okuması taze (en fazla 2 dk) ve doğruysa (≤ 100 m) ve iğne 1 km'den uzaktaysa:
  "İğne bulunduğun yerden 2,4 km uzakta. Hayvanı orada, son bir saat içinde gördün mü?" **Evet, orada gördüm** ya da
  **İğneyi düzelt**. Acil yardımda sorulmaz.

İğnenin 40 m yakınında aynı türden aktif bir işaret varsa ihtiyaç listesinin üstünde **Ben de gördüm**
("Aynı hayvan mı? Yakında Yaralı / hasta · 3 kişi bildirdi") önerisi çıkar. Dokununca yeni işaret açılmaz; mevcut işaret
açılır ve ona **Hâlâ orada** denir, yani aynı hayvan ikinci kez işaretlenmek yerine bildirenlerin sayısı artar.
İhtiyaç düğmeleri yine her zamanki gibi yeni işaret koyar.

### Yanlış işaretlemeyi düzeltmek

İşareti koyan kişi, kartındaki **Düzenle** ile türü, ihtiyacı ve yeri düzeltebilir (panel: "İşareti düzelt · İğneyi en
fazla 200 m kaydırabilirsin"). Tür seçilir, iğne kaydırılır, ihtiyaca dokununca kaydedilir ("İşaret güncellendi.").

- Yalnızca işareti koyan; işaret hâlâ "yardım bekliyor"ken ve **kimse dokunmadan** (başka "Hâlâ orada", "Artık yok",
  "İlgileniyorum" ya da itiraz yokken).
- İşaretlendikten sonraki **30 dakika** içinde, en fazla **3 kez**; her düzeltmede konum en fazla ~200 m kayar.
- İhtiyaç değişirse işaretin ömrü yeni ihtiyaca göre yeniden başlar (7 günlük üst sınır yine geçerli).
- Aynı paneldeki **İşareti sil** ("Bu işareti silmek istiyor musun?") işareti tamamen kaldırır; yine yalnızca kimse
  dokunmamışken.

### Haritada işaretleri okumak

| Görsel | Anlamı |
| --- | --- |
| Renk + simge | İhtiyaç (kırmızı ünlem = acil, turuncu bandaj = yaralı, yeşil çatal-bıçak = aç ve zayıf, mavi steteskop = veteriner, mor ev = terk edilmiş / bakıma muhtaç, pembe ayıcık = yavrular) |
| Köşedeki emoji | Tür (🐈 🐕) |
| Küçük işaret | Düşük öncelik ("Aç ve zayıf"): ağır ihtiyaçların altında çizilir, çakışınca altta kalır; hiçbir yakınlıkta gizlenmez |
| Mavi "yürüyen kişi" rozeti | Biri ilgileniyor (45 dk'dır haber yoksa gri) |
| Koyu "?" rozeti | Biri "Çözüldü", "Artık yok" ya da "Yardım gerekmiyor" dedi, henüz doğrulanmadı |
| Gri nokta (yakınlaşınca) | Böyle denip haritadan kalkan işaret; hayvan hâlâ oradaysa dokunup bildirilebilir |
| Sağ alttaki beyaz sayı | Hayvanı kaç farklı kişinin bildirdiği (işareti koyan + "Hâlâ orada" ya da "Ben de gördüm" diyenler; 2 kişiden itibaren görünür, 100 ve üstü "99+") |
| Büyük ve haleli işaret | Acil |
| Soluklaşan işaret | Bir süredir kimse doğrulamadı |

Üst üste binen işaretlerde acil olan üstte çizilir. Sağ üstteki **i** düğmesi bu açıklamayı, her ihtiyacın kısa tanımını
("Aç ve zayıf: Çok zayıf, günlerdir beslenmiyor ya da su bulamıyor"), kuralları ve kullanım koşulları ile gizlilik
politikası bağlantılarını gösterir.

### İşarete dokununca

Yalnızca temel bilgiler: **ihtiyaç, tür, ne zaman işaretlendiği, uzaklık ve mevcut durum** ("Yardım bekliyor", "Biri ilgileniyor · 12 dk önce", "Sen ilgileniyorsun · 2 sa 40 dk kaldı").
Hayvanı birden fazla kişi bildirdiyse **"N kişi bildirdi"** de yazar.
Altında duruma göre değişen düğmeler:

| Kim | Görülen eylemler |
| --- | --- |
| Yoldan geçen | **İlgileniyorum** · Hâlâ orada · Çözüldü · Artık yok · Yol tarifi |
| İlgilenen kişi | **Çözüldü** · Vazgeç · Artık yok · Yol tarifi |
| İşareti koyan | **İlgileniyorum** · Çözüldü · Hâlâ orada · Artık yok · Yol tarifi (45 dk'dır haber vermeyen ilgilenen için "İlgilenen gelmedi"; ilk 30 dakikada başlıkta **Düzenle**) |
| "Çözüldü dendi" işaretinde | **Evet, çözüldü** (işareti koyan) · Hâlâ yardım gerekiyor · Yol tarifi |

"Aç ve zayıf" işaretlerinde **Hâlâ orada** yerine **Hâlâ yardım lazım**, **Artık yok** yerine **Yardım gerekmiyor**
yazar; ikincisi "Ne gördün?" diye sorar: **Hayvan orada ama iyi görünüyor** ya da **Hayvan artık orada değil**.

**Hâlâ orada** diyen kişi bildirenlerin sayısına da eklenir ("Teşekkürler! Bu hayvanı artık 4 kişi bildirdi.").
Kartın altında küçük bir güvenlik notu durur: "Yalnız gitme, kimseyle tartışmaya girme, özel mülke girme."
Acil, yaralı ve yavru kartlarında yanında **Konumu paylaş** vardır: gidilen yer tek dokunuşla bir yakına gönderilir.
Gece (21.00–06.00) bu işaretlere **İlgileniyorum** ya da **Yol tarifi** denince haftada en fazla bir kez kısa bir
güvenlik hatırlatması çıkar ("Gece yardıma gidiyorsun"); **Devam et** ile eylem sürer.

### Şüpheli bir işaret: bildir ya da gizle

Kartın başlığındaki **⋯** menüsü (işareti koyana gösterilmez):

- **Bu işareti bildir**: "Bu işarette ne sorun var?" — sahte işaret, tehlikeli ya da şüpheli bir yer, hayvan dışında bir
  amaç (buluşma, taciz, reklam…). Serbest metin yoktur. Bildirim yalnızca uygulamanın sahibine gider; haritada hiçbir
  etkisi yoktur. İşaret bildirenin haritasından kalkar.
- **Bu işareti gizle**: işaret yalnızca senin haritandan kalkar (cihazda tutulur).
- **E-postayla ayrıntı gönder**: iletişim adresi tanımlıysa, işaret kimliğiyle hazır bir e-posta açar.

Kurallara uymayan işaretler kaldırılır ve o kimlik engellenir. Engellenen kimlik işaret koyamaz, işaretlere dokunamaz;
üst etikette "Bu kimlikle işaret koyma kapatıldı." yazar.

### "Çözüldü" ve kötüye kullanıma karşı önlemler

Hayvan düşmanı biri işaretleri sessizce kapatamasın diye: **başkasının da gördüğü bir işareti tek bir kişi süresinden
önce haritadan kaldıramaz.**

- İşareti koyan kişi, hayvanı başka gören yoksa **Çözüldü** / **Artık yok** / **Yardım gerekmiyor** ile işareti hemen
  kapatır ("Yardım gerekmiyor" için "Yanlış alarmdı").
- Diğer her durumda işaret **"Çözüldü dendi"** (ya da "Artık yok dendi", "Yardım gerekmiyor dendi") olur; ömrü kısalmaz.
  İşareti koyan **Evet, çözüldü** (ya da "Evet, ihtiyacı yoktu") derse kapanır. Diyen kişi 10 dk içinde **Geri al** diyebilir.
- **Yardım gerekmiyor** ("Hayvan orada ama iyi görünüyor") yalnızca "Aç ve zayıf" işaretlerinde vardır ve "Çözüldü" ile
  aynı kurallara bağlıdır: aynı günlük hak, "?" rozeti, itiraz, geri alma, ikinci kişi onayı, süre dolumu.
- Hayvanı gören herkes **Hâlâ yardım gerekiyor** diyerek itiraz edebilir: işaret yeniden yardım bekler, itiraz edilen kişi
  bu işareti bir daha kapatamaz ve üstlenemez.
- **Kanıtlı kapatma**: uygulaması en az 1 günlük olan kişinin (ya da işareti koyanın) önerisi günlük haktan düşer
  (24 saatte 8 puan; acil, yaralı, yavru, veteriner, terk edilmiş / bakıma muhtaç 2 puan; aç ve zayıf 1 puan). Kanıtlı
  işaret başkalarının haritasından "Aç ve zayıf" için 1, diğerleri için 2 **gündüz** saati sonra kalkar (gece 00.00–07.00
  sayılmaz); işareti koyan ve hayvanı görenler soruyu yanıtlayana kadar görmeye devam eder. Kanıtsız öneri yalnızca "?"
  rozeti ekler; işaret yardım bekleyenler arasında sayılmaya devam eder.
- Bu gösterim sahibin konsoldaki `config/public.closingMode` ayarına bağlıdır: `demote` (yukarıdaki), `label`
  (kanıtlı işaret de soluk "?" olarak kalır; ayar yoksa bu) ya da `strict` (her öneri yalnızca "?"). Hiçbir işaret
  erken kapanmadığı için ayar değişince gizlenen her işaret geri gelir.
- **Artık yok**: 3 farklı kişi derse (biri ilgilenmiyorsa) "Artık yok dendi" olur; "Hâlâ orada" oyları sıfırlar.
- **İlgileniyorum** kimseyi engellemez: 45 dk haber gelmezse başkaları da "Çözüldü" diyebilir.
- **İşaret sınırı**: her telefon 24 saatte en fazla 10 yeni işaret koyabilir (uygulamanın ilk gününde 5).
- Uygulama açılınca, koyduğun ya da gördüğün bir işaret için "Çözüldü" / "Yardım gerekmiyor" dendiyse sorulur:
  "Koyduğun Aç ve zayıf kedi işareti için 20 dk önce 'Yardım gerekmiyor' dendi. Doğru mu?"
- `config/public.minBuild` bu derlemeden büyükse uygulama kapatılamayan bir "Güncelleme gerekli" sayfası gösterir.

Tasarım ve gerekçeler: [docs/tasarim/](docs/tasarim/).

### Uygulama sahibinin rutini (Firebase konsolu)

- **Her gün** `flags` koleksiyonuna bak: doküman kimliği `işaretKimliği_bildirenKimliği`, alanlar `reportId`, `reason`
  (`fake` · `unsafe` · `misuse`), `at`.
- **İşareti kaldırmak**: `reports/{id}` dokümanında `status: 'closed'`, `closedReason: 'removed'`, `closedAt` (şimdi) ve
  `purgeAt` (şimdiden 30 gün sonra) yaz. Uygulama bilinmeyen nedeni kapalı sayar ve işareti gizler.
- **Kimliği engellemek**: `banned/{uid}` dokümanı ekle (içeriği önemsiz, ör. `{ at: <zaman>, note: '…' }`). Silince engel kalkar.
- **Eski sürümleri durdurmak**: `config/public.minBuild` alanına en düşük desteklenen derleme numarasını (CFBundleVersion) yaz.

### Eski işaretler haritada kalmaz

- Her ihtiyacın bir ömrü var (acil ve aç ve zayıf 12 sa, yaralı 24 sa, veteriner 48 sa, terk edilmiş / bakıma muhtaç ve
  yavrular 72 sa). Süre dolunca işaret haritadan kalkar.
- Hayvanı yine gören herkes **Hâlâ orada** diyerek süreyi yeniden başlatır. İşaret yaşlandıkça soluklaşır.
  Bu, seni hayvanı bildirenlerin sayısına da ekler ("N kişi bildirdi"): her kişi bir kez sayılır, tekrar demek sayıyı artırmaz; en fazla 100 kişi tutulur.
- Hiçbir işaret, "Hâlâ orada" ile uzatılsa bile oluşturulmasından 7 gün sonra haritada kalamaz.
- **İlgileniyorum** 3 saat geçerlidir; çözülmezse işaret kendiliğinden yeniden "yardım bekliyor" olur.
- Süresi dolan işaretleri uygulamanın kendisi kapatır (ücretsiz planda sunucu temizliği yok). Blaze'e geçince
  sunucudaki temizlik de çalışır ve kapanan işaretler 30 gün sonra veritabanından silinir.

## Teknik çözüm (özet)

| Katman | Seçim | Neden |
| --- | --- | --- |
| iOS | SwiftUI (iOS 17+), MapKit (Apple Haritalar) | Tek ekran, akıcı harita; API anahtarı ve ücret yok |
| Alan mantığı | `AnimalKit` Swift paketi | Durum makinesi, geohash ve biçimlendirme ağdan bağımsız ve test edilebilir |
| Veri | Cloud Firestore | Canlı dinleme (harita kendiliğinden güncellenir), çevrimdışı yazma, sunucu yönetmeye gerek yok |
| Kimlik | Firebase anonim oturum | Kayıt/giriş yok; yalnızca "kim koydu, kim ilgileniyor" ayrımı için |
| Kurallar | Firestore Security Rules | İstemcideki durum makinesinin aynısı sunucuda zorunlu |
| Temizlik | Cloud Functions (zamanlanmış) + Firestore TTL | Süresi dolanları kapatır, kapananları siler |
| Konum sorgusu | Geohash (geofire-common'ın Swift karşılığı) | Yalnızca görünen bölgedeki işaretler dinlenir |

Ayrıntılar: [docs/architecture.md](docs/architecture.md)

## Depo yapısı

```
ios/
  project.yml                 XcodeGen tanımı (Xcode projesi buradan üretilir)
  Config/                     xcconfig; kişisel ayarlar Secrets.xcconfig'ta (git'e girmez)
  PatiHarita/                 SwiftUI uygulaması
    App/                      açılış, oturum, konum
    Data/                     Firestore ve demo veri kaynakları
    Map/                      harita ekranı, Apple Haritalar (MapKit) köprüsü, view model
    Report/                   işaretleme ve düzeltme paneli, işaret kartı, açıklama ekranı, kurallar sayfası
    Design/                   işaret görünümü ve renkler
  Packages/AnimalKit/         saf alan mantığı + testleri
firebase/
  firestore.rules             güvenlik kuralları (durum makinesi)
  firestore.indexes.json      indeksler + TTL
  functions/                  zamanlanmış temizlik fonksiyonu
  tests/                      kural ve sözleşme testleri (emülatörde)
shared/
  report-contract.json        iOS ve Firebase'in ortak sabitleri
  geohash-vectors.json        geohash referans değerleri
docs/
  architecture.md             mimari, veri modeli, kurallar
  kullanim-kosullari.md       kullanım koşulları (taslak)
  gizlilik-politikasi.md      gizlilik politikası (taslak)
```

## Çalıştırma

Gerekenler: Xcode 16.3+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), Node 22, Java 21 (emülatör için).

### 1. iOS uygulaması — demo modu (Firebase gerekmez)

```bash
cd ios
xcodegen
open PatiHarita.xcodeproj
```

`GoogleService-Info.plist` yoksa uygulama **demo modunda** açılır: çevrede örnek işaretler görünür, tüm akış denenebilir, veriler yalnızca cihazdadır.
Demo işaretleri her açılışta yeniden oluşur; gizlenen işaretler hatırlanmaz. Kabul edilen kurallar, "Yardıma ihtiyacı var mı?"
sayacı ve gece hatırlatması cihazda saklanır (TestFlight'ta kurallar bir kez sorulur). `-demo` argümanıyla hiçbir şey saklanmaz:
her açılış ilk açılış gibidir (arayüz testi bunu kullanır).
Simülatörün varsayılan konumu Kadıköy'dür (`ios/Kadikoy.gpx`). Harita Apple Haritalar'dır; API anahtarı gerekmez.

Başlatma argümanları (*Edit Scheme → Run → Arguments*): `-demo` (plist olsa da demo modu), `-useEmulator` (yerel
emülatörler, aşağıda), `-noNightReminder` (gece güvenlik hatırlatmasını kapatır; arayüz testi günün her saatinde aynı
akışı denesin diye kullanır).

Kendi iPhone'unuzda çalıştırmak için `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` ile Apple Developer ekip kimliğinizi (`DEVELOPMENT_TEAM`) yazın.

### Mac olmadan: tarayıcıda simülatör

CI, iOS dosyaları değişince (ya da elle: `gh workflow run ci.yml --ref <dal>`) uygulamanın simülatör paketini üretir ve uygulamayı simülatörde açıp ekran görüntüsü alır.

1. GitHub → **Actions** → son çalışma → *Artifacts* altından `PatiHarita-simulator`'ı indirin. İçinden `PatiHarita-simulator.zip` çıkar.
2. [appetize.io](https://appetize.io)'da hesap açıp bu zip'i yükleyin (iOS). Uygulama tarayıcıda bir iPhone simülatöründe açılır.
3. Konum: Appetize'ın ayarlarından konumu değiştirebilirsiniz; demo modu bakılan bölgeye örnek işaretler koyar.

Açılış ekran görüntüsü aynı çalışmada `simulator-screenshot` artifact'ındadır.

### TestFlight (gerçek iPhone)

Codemagic, `codemagic.yaml`'daki **iOS TestFlight** iş akışıyla derler, imzalar ve App Store Connect'e yükler
(uygulama: *Pati Harita*, Apple ID 6815833939). Yeni sürüm göndermek için `project.yml`'de `MARKETING_VERSION`'ı
gerekirse artırıp bir etiket gönderin; derleme numarası otomatik artar:

```bash
git tag v1.0.1
git push origin v1.0.1
```

Etiketi, mesajında `[skip ci]` olan bir commit'e koymayın: Codemagic de bu commit'leri atlar ("Webhook is skipped").
Etiket derleme başlatmazsa Codemagic'te uygulamanın **Webhooks** sekmesindeki *Recent deliveries* listesine bakın.

Derleme işlenince TestFlight'taki **Ekip** grubuna otomatik dağıtılır. Codemagic'te `ios_signing` grubuna
`GOOGLE_SERVICE_INFO_PLIST` (base64) eklenirse uygulama gerçek Firebase'e bağlanır; yoksa demo modunda açılır.

### 2. Yerel Firebase emülatörleriyle

```bash
cd firebase
npm install && npm install --prefix functions
npm run emulators            # Firestore, Auth, Functions + arayüz: http://127.0.0.1:4000
```

Xcode'da *Edit Scheme → Run → Arguments* altında `-useEmulator`'ı işaretleyin. Gerçek bir Firebase projesi gerekmez.

### 3. Gerçek Firebase projesi

1. [Firebase konsolunda](https://console.firebase.google.com) proje oluşturun ve iOS uygulaması ekleyin (bundle id `app.patiharita.ios`).
   İndirilen `GoogleService-Info.plist`'i `ios/PatiHarita/` içine koyup `xcodegen`'i yeniden çalıştırın.
2. **Authentication → Sign-in method → Anonymous**'ı açın.
3. **Firestore Database** oluşturun (ör. `eur3` ya da `europe-west1`).
4. `firebase/.firebaserc` içindeki `demo-patiharita`'yı kendi proje kimliğinizle değiştirip dağıtın:
   ```bash
   cd firebase
   npx firebase deploy --only firestore            # kurallar, indeksler, TTL
   npx firebase deploy --only functions            # Blaze (kullandıkça öde) planı gerekir
   ```
5. **App Check**: Debug derlemeler hata ayıklama sağlayıcısını, Release derlemeler DeviceCheck'i kullanır. Konsolda uygulamayı kaydedin; zorunlu kılmayı (enforcement) yayından önce açın.

## Testler

```bash
cd firebase && npm test                          # kurallar, sözleşme, temizlik fonksiyonu, geohash referansları
cd ios/Packages/AnimalKit && swift test          # durum makinesi, geohash, sözleşme, biçimlendirme
# Xcode'da PatiHarita şeması → Cmd+U                # arayüz testi (PatiHaritaUITests): demo akışı simülatörde
```

`shared/` altındaki dosyalar iki tarafı birbirine bağlar: iOS ile Firestore kuralları aynı süreleri ve kuralları kullanmazsa testler başarısız olur.
GitHub Actions (`.github/workflows/ci.yml`) her işi yalnızca kendi dosyaları değişince çalıştırır: Firebase testleri,
AnimalKit testleri (Linux) ve iOS uygulamasının derlemesi ile arayüz testi (macOS). Depo açık olduğu için ücretsizdir;
depo özele dönerse macOS dakikaları 10 kat sayılır (bir iOS çalışması ≈ 200 dakika, ayda 2000 dakikalık hakkın onda biri).
Ardından uygulamayı simülatörde açar ve arayüz testiyle ana akışı gerçek dokunuşlarla dener: kuralları kabul etme, işaret
koyma ("Yardıma ihtiyacı var mı?" kontrolüyle), işareti düzeltme, işarete dokunma, "İlgileniyorum", "Hâlâ orada",
"Ben de gördüm", uzun basma, yoldan geçenin "Çözüldü"sü, "Çözüldü dendi" kartı, itiraz, "Aç ve zayıf" işaretinde
"Yardım gerekmiyor" ve "⋯" menüsünden işaret bildirme. Her adımın ekran görüntüsü (`00-kurallar` … `19-bildirildi`)
çalışmanın `simulator-screenshot` artifact'ındadır (`ui/` klasörü).

## Sonraki adımlar

- **Yakındakilere bildirim**: acil/yaralı işaretlerde, kaba konumuna (geohash-5) abone olan kullanıcılara FCM ile bildirim.
- **Kümeleme**: yoğun bölgelerde işaretleri MapKit'in yerleşik kümelemesiyle (`MKClusterAnnotation`) gruplamak.
- **Kötüye kullanıma karşı, 2. aşama** ([plan](docs/tasarim/kotuye-kullanim-plani.md)): App Check'i zorunlu kılmak
  (App Attest yeteneği + DeviceCheck), toplu okumayı sınırlamak, yeni hesaplara yarım hak.
  3. aşama (Blaze): "… dendi" olunca işareti koyana ve görenlere bildirim, yeni bildirimlerde sahibe haber, itibar.
- Gizlilik politikasını ([taslak](docs/gizlilik-politikasi.md)) ve kullanım koşullarını ([taslak](docs/kullanim-kosullari.md))
  tamamlayıp herkese açık bir adreste yayımlamak (App Store ister); `AppInfo.supportEmail`'e iletişim adresini yazmak
  (dolunca açıklama ekranında, engel mesajında ve "⋯" menüsünde görünür).
- Karanlık harita stili, VoiceOver ince ayarları. (Simgenin kaynağı: [docs/app-icon.svg](docs/app-icon.svg))
- Android / web istemcisi (aynı Firestore kuralları ve `shared/` sözleşmesiyle).
