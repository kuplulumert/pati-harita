# Mimari

Her teknik karar tek bir hedefe göre verildi: **sokakta, telefon elde, birkaç saniyede işaretleme** ve
**haritanın kendiliğinden güncel kalması**.

```
 iOS (SwiftUI)                                   Firebase
┌─────────────────────────────────┐            ┌──────────────────────────────────────┐
│ MapScreen ── ReportMapView      │            │ Firestore: reports/{id}              │
│     │        (MKMapView)        │  canlı     │   Güvenlik kuralları = durum makinesi│
│ MapViewModel ─ ReportRepository ├◀─dinleme───┤   users · flags · banned · config    │
│     │          (Firestore/Demo) ├──yazma────▶│ Cloud Function (10 dk'da bir)        │
│ AnimalKit (saf Swift)           │            │   süresi dolanları kapatır           │
│   ReportLifecycle · Geohash     │            │ TTL politikası: kapananları siler    │
│   GentleCheck · Formatting      │            │ Auth (anonim) · App Check            │
│ DeviceState (yalnızca cihazda)  │            │                                      │
└─────────────────────────────────┘            └──────────────────────────────────────┘
                    ▲                                         ▲
                    └──── shared/report-contract.json ────────┘
                         (ortak sabitler, iki tarafta test edilir)
```

## Neden bu yığın?

- **Firestore**: haritanın "yaşaması" için gerçek zamanlı dinleyiciler hazır gelir; çevrimdışı önbellek sayesinde
  zayıf bağlantıda da işaret anında görünür ve bağlantı gelince gönderilir. Yönetilecek sunucu yoktur.
- **Doğrudan yazma + güvenlik kuralları** (callable Cloud Function yerine): fonksiyonun soğuk başlangıcı 1–3 sn
  ekler ve çevrimdışı çalışmaz. Kurallar aynı güvenceyi (geçerli durum geçişleri) gecikmesiz sağlar.
- **Anonim oturum**: kullanıcıdan hiçbir şey istenmez. Kimlik yalnızca "işareti kim koydu / kim ilgileniyor"
  ayrımı içindir; ileride hesap bağlama (Apple ile giriş) aynı kimliği korur.
- **Apple Haritalar (MapKit)**: iOS'ta yerleşik; API anahtarı, faturalandırma hesabı ve ek SDK gerekmez.
  SwiftUI'da `UIViewRepresentable` ile sarılır; harita sağlayıcısı değişirse yalnızca `ReportMapView.swift` değişir.
  Yakınlaştırma web haritası ölçeğindedir (`CameraRequest.zoom`), kamera hedefi alt panelin üstünde kalan alanın ortasıdır.
- **AnimalKit paketi**: tüm iş kuralları ağdan ve arayüzden bağımsızdır, `swift test` ile saniyeler içinde test edilir.
  Firestore kuralları aynı kuralların sunucu karşılığıdır.

## Veri modeli

Ana koleksiyon: `reports/{reportId}`. Kurallar alanların **hepsinin** bulunmasını ister (boşlar `null`; yalnızca
`editCount` bu sürümden önce konan işaretlerde yoktur ve 0 sayılır).

| Alan | Tür | Açıklama |
| --- | --- | --- |
| `species` | string | `cat`, `dog` |
| `need` | string | `emergency`, `injured`, `babies`, `vet`, `food`, `shelter` (ekrandaki adları: Acil yardım, Yaralı / hasta, Yavrular tehlikede, Veteriner desteği, Aç ve zayıf, Terk edilmiş / bakıma muhtaç). Yalnızca `food` hafif (düşük öncelikli) ihtiyaçtır |
| `lat`, `lng` | number | Konum |
| `geohash` | string(10) | Konum sorgusu için |
| `status` | string | `open` · `claimed` · `closing` ("… dendi") · `closed` |
| `closedReason` | string? | `resolved` · `gone` · `expired` · `unneeded` ("Yanlış alarmdı"). Uygulama tanımadığı nedeni (ör. sahibin konsoldan yazdığı `removed`) kapalı sayar |
| `reporterId` | string | İşareti koyanın anonim kimliği |
| `createdAt` | timestamp | Görüldüğü an (çevrimdışı işaretlemede de korunur) |
| `lastSeenAt` | timestamp | Son "Hâlâ orada" |
| `expiresAt` | timestamp | Bu andan sonra haritada gösterilmez |
| `claimedBy`, `claimedAt`, `claimExpiresAt` | string?, timestamp? | "İlgileniyorum" (`claimedAt` sunucu saati) |
| `goneReports` | string[] | "Artık yok" diyenler |
| `seenBy` | string[] | Hayvanı bildiren farklı kişiler; oluşturan + Hâlâ orada diyenler, en fazla 100 (`maxSeenBy`). Haritadaki "N kişi bildirdi" sayısı bunun uzunluğudur |
| `closedAt`, `purgeAt` | timestamp? | Kapanış ve TTL ile silinme zamanı |
| `closingReason`, `closingBy`, `closingAt`, `closingCredible` | string?, string?, timestamp?, bool? | Kapatma önerisi (`resolved` "Çözüldü dendi" · `gone` "Artık yok dendi" · `unneeded` "Yardım gerekmiyor dendi"); `closingAt` sunucu saati; `closingCredible` = günlük haktan düşülerek yapıldı. Kapanınca geçmiş olarak kalır. Uygulama tanımadığı nedeni genel "… dendi" olarak gösterir |
| `objectors` | string[] (≤ 10) | İşareti koyan dışında itiraz edenler (her biri bir kez) |
| `disputed` | string[] (≤ 10) | Önerisine itiraz edilenler: bu işareti bir daha üstlenemez, kapatamaz |
| `editCount` | int (0–3) | İşareti koyanın kaç kez düzelttiği; oluştururken 0 |

`users/{uid}` (yalnızca sahibi okur): `createdAt` (sunucu saati, hesap yaşı), `createWindow`/`createUsed`/`createLast`
(24 saatlik yeni işaret hakkı: ilk gün 5, sonra 10), `closeWindow`/`closeUsed`/`closeLast` (24 saatte 8 puanlık kanıtlı
kapatma hakkı). Her harcama `{t: sunucu saati, id: işaret}` ile tek bir işarete bağlanır; kurallar işaret yazımında bunu
`getAfter` ile doğrular, bu yüzden işaret ve harcama aynı toplu yazımda (batch/transaction) gider.

`flags/{reportId}_{uid}` ("Bu işareti bildir"): `reportId`, `reason` (`fake` · `unsafe` · `misuse`), `at` (sunucu saati).
İstemciler yalnızca oluşturabilir; okuyamaz, değiştiremez, silemez. Kişi başına işaret başına bir bildirim (ikincisi
reddedilir, uygulama bunu başarı sayar). Haritada hiçbir etkisi yoktur; sahibi konsoldan inceler.

`banned/{uid}` (yalnızca konsoldan yazılır): varsa o kimlik yazamaz. Kişi yalnızca kendi kaydını okuyabilir; uygulama
bir yazımı reddedilince bakar ve üst etikette söyler.

`config/public` (yalnızca konsoldan yazılır): `closingMode` = `demote` · `label` · `strict`; `minBuild` = desteklenen en
düşük derleme numarası (CFBundleVersion), daha eskisi kapatılamayan bir "Güncelleme gerekli" sayfası gösterir.

Fotoğraf, açıklama, kullanıcı profili **bilerek yok**: hem akışı uzatır hem de depolama/moderasyon yükü getirir.

### Yalnızca cihazda

`DeviceState` (`UserDefaults`) sunucuya gitmez: kabul edilen kurallar sürümü (`acceptedTermsVersion`), "Yardıma
ihtiyacı var mı?" için hafif işaret sayacı ve son 24 saatin işaretleri, kişinin bildirip gizlediği işaretler (8 gün
sonra unutulur; haritadan, sayılardan ve "Aynı hayvan mı?" önerilerinden çıkar), gece hatırlatmasının son gösterimi ve
bilinen engel durumu. Demo modunda işaret kimliklerine bağlı olanlar (gizlenen ve son 24 saatin işaretleri) ve engel
durumu yalnızca bellektedir, çünkü örnek işaretlerin kimlikleri her açılışta aynıdır; `-demo` argümanıyla (arayüz
testi) hiçbir şey saklanmaz.

## Yaşam döngüsü

```
   open ──İlgileniyorum──▶ claimed ──(Vazgeç / 3 sa / koyan: 45 dk haber yok)──▶ open
   open|claimed ──Çözüldü / Artık yok / Yardım gerekmiyor──▶ closing ("… dendi"; haritada kalır, ömrü kısalmaz)
   closing ──Hâlâ yardım gerekiyor (kapatan dışında herkes)──▶ open
   closing ──Evet (ikinci kişi)──▶ closed      closing ──Geri al (kapatan, 10 dk)──▶ claimed|open
   open|claimed ──Çözüldü / Artık yok / Yardım gerekmiyor (koyan; başka gören yoksa)──▶ closed
   open|claimed|closing ──expiresAt geçti (herkes; Blaze'de sunucu da)──▶ closed
   open (kimse dokunmadı, ilk 30 dk, en fazla 3 kez) ── Düzenle ──▶ open (tür, ihtiyaç, konum değişir)
   open (koyandan başka gören yok) ── Geri al / İşareti sil ──▶ silinir
```

Değişmez kural: başkasının da gördüğü bir işareti tek bir kişi süresinden önce kaldıramaz.

| Eylem | Kim | Etki |
| --- | --- | --- |
| Oluştur | Herkes | `expiresAt = createdAt + ihtiyacın ömrü`; `seenBy = [koyan]`; `editCount = 0` |
| Düzenle | Yalnızca koyan; `open`, `seenBy == [koyan]`, oy/itiraz yok, `createdAt`'ten 30 dk içinde, `editCount < 3` | Tür, ihtiyaç ve konum (her seferinde en fazla ±0,0018° enlem, ±0,0024° boylam ≈ 200 m; `geohash` yeniden hesaplanır); `editCount + 1`. İhtiyaç değişirse `expiresAt = şimdi + yeni ömür` (7 gün sınırı içinde) |
| İlgileniyorum | Aktif sahibi yoksa herkes | 3 sa sahiplik; `expiresAt` en az sahiplik bitişine uzar |
| Vazgeç | İlgilenen; 45 dk'dır haber yoksa koyan da | Tekrar `open` |
| Çözüldü | Koyan tek tanıksa | `closed(resolved)` |
| Çözüldü | Başka herkes (başkasının 45 dk'dan genç sahipliği yoksa; itiraz edilmemişse) | `closing(resolved)`; hak varsa `closingCredible` |
| Yardım gerekmiyor | Yalnızca `food`; "Çözüldü" ile aynı kişiler ve koşullar | Koyan tek tanıksa `closed(unneeded)`, değilse `closing(unneeded)` (aynı hak, itiraz, onay, geri alma, süre dolumu) |
| Hâlâ orada | Herkes | `expiresAt = şimdi + ömür` (asla kısalmaz, oluşturmadan 7 günü geçmez); kişi `seenBy`'a bir kez eklenir; "Artık yok" oylarını sıfırlar |
| Artık yok | Herkes, bir kez | Koyan tek tanıksa `closed(gone)`; koyan/ilgilenen ya da (sahiplik yokken) 3. oy `closing(gone)` |
| Hâlâ yardım gerekiyor | Kapatan dışında herkes (koyan dışındakiler bir kez) | `open`; kapatan `disputed`'a eklenir |
| Evet (onay) | Kapatan başkasıysa koyan; kapatan koyansa hayvanı gören biri | `closed(closingReason)` |
| Geri al (öneri) | Kapatan, 10 dk içinde | Sahiplik canlıysa `claimed`, değilse `open` |
| Geri al / İşareti sil | Koyan; `open` ve kimse dokunmamışken | Doküman silinir |
| Süresi doldu | Herkes, `expiresAt` geçince | `closed(expired)` ya da `closed(closingReason)` |

İstemci: `ios/Packages/AnimalKit/Sources/AnimalKit/ReportLifecycle.swift`
Sunucu: `firebase/firestore.rules`

İstemci eylemleri bir **Firestore işlemi (transaction)** içinde uygular: güncel doküman okunur, `ReportLifecycle`
yeni hâli hesaplar ve **yalnızca değişen alanlar** yazılır (`Report.changedFields`). Tüm dokümanı geri yazmak
hatalı olurdu: Timestamp → Date → Timestamp dönüşümü mikro saniye kaydırır ve kurallar değişmemesi gereken
alanı (ör. `createdAt`) değişmiş sayıp işlemi reddeder. AnimalKit testleri her eylemin yalnızca kuralların izin
verdiği alanları değiştirdiğini doğrular. İki kişi aynı anda "İlgileniyorum" derse biri kazanır, diğerine
"Az önce başka biri ilgilenmeye başladı" gösterilir. Kurallar, istemci atlatılsa bile aynı geçişleri zorunlu kılar.
Düzeltme de aynı yoldan gider (`ReportLifecycle.edit`); değişiklik yoksa hiçbir şey yazılmaz.

### Kuralların özeti

- `reports` güncellemesi: `validShape(sonra)` ve ya (kimlik alanları değişmeden) durum makinesinin eylemlerinden biri
  ya da `isEdit()`. Kimlik alanları (`species`, `need`, `lat`, `lng`, `geohash`, `reporterId`, `createdAt`) yalnızca
  `isEdit` ile, yalnızca koyan tarafından ve yukarıdaki sınırlar içinde değişir.
- `notBanned()` (`banned/{me}` yok) şu yazımlarda aranır: işaret oluşturma, `open`/`claimed`/`closing` üzerindeki her
  eylem, düzeltme, silme, bildirim ve `users` harcamaları. Süresi dolanı kapatmak (`isExpire`) herkese açıktır.
- `flags`: yalnızca oluşturma; doküman kimliği `reportId + '_' + uid` olmalı, işaret var olmalı, alanlar tam olarak
  `reportId`, `reason`, `at`.
- `banned/{uid}`, `config/{doc}`: istemci yalnızca okur (`banned`'da yalnızca kendi kaydını).
- Kişi kimliği tutan alanlar (`reporterId`, `claimedBy`, `closingBy`, `seenBy`, `goneReports`, `objectors`, `disputed`)
  sorgu için indekslenmez (`firestore.indexes.json` `fieldOverrides`); uygulamanın tek sorgusu `status + geohash`'tir.

## Zaman

Çoğu zaman damgasını istemci yazar, çünkü:

- çevrimdışı koyulan işaret, hayvanın **görüldüğü anı** taşımalı;
- ömür hesabı (`createdAt + 12 sa`) istemcide yapılabilmeli.

Kurallar bunu sınırlar: `createdAt` en fazla 24 sa geçmişte / 15 dk gelecekte olabilir, "şimdi" anlamına gelen alanlar
sunucu saatine ±15 dk yakın olmalı, ömürler ve sahiplik süresi sözleşmedeki üst sınırları aşamaz.

İstisna: süre hesabı kötüye kullanılabilecek damgalar **sunucu saatiyle** yazılır (`serverTimestamp()`, kurallar
`== request.time` ister): `claimedAt` (45 dakikalık sahiplik), `closingAt` (10 dakikalık "Geri al" ve gündüz saati),
`users` belgesindeki pencereler ve harcama damgaları. Bu eylemler zaten çevrimiçi işlemle (transaction) yapılır.

## Eski işaretler

1. **İstemci**: `expiresAt` geçmiş ya da süresi dolmuş sahiplikler, sunucu temizliği beklenmeden gizlenir / "yardım bekliyor" sayılır.
2. **Solma**: işaretin opaklığı `lastSeenAt → expiresAt` aralığında azalır; eskidiği görünür.
3. **Topluluk**: "Hâlâ orada" ömrü yeniler, "Artık yok", "Çözüldü" ve "Yardım gerekmiyor" önerileri ikinci kişiyle kapatır.
4. **Tembel kapatma**: istemci, haritadaki süresi dolmuş en fazla 3 işareti 0–30 sn rastgele gecikmeyle `closed`
   yapar (ücretsiz planda sunucu temizliği yok; kurallar bunu herkese yalnızca `expiresAt` geçtikten sonra izin verir).
5. **Sunucu (Blaze)**: `sweepStaleReports` (10 dk'da bir) süresi dolanları (`closing` dahil) kapatır, terk edilmiş sahiplikleri bırakır.
6. **Silme (Blaze)**: kapanan işaretin `purgeAt` alanı (30 gün sonrası) Firestore TTL politikasıyla silinir.

## Konum sorgusu

Firestore coğrafi sorgu desteklemez; standart çözüm **geohash aralıklarıdır**.
Görünen harita alanının yarıçapının 1,5 katı için `Geohash.queryBounds` 4–9 aralık üretir; her biri
`status in [open, claimed, closing] AND geohash in [start, end)` olarak ayrı dinlenir ve sonuçlar birleştirilir.

- Küçük kaydırmalarda yeniden sorgu yapılmaz (dinlenen alan görünen alanı hâlâ kapsıyorsa).
- 25 km'den geniş alan görünüyorsa sorgu yapılmaz, "yakınlaştır" denir.
- `Geohash.swift`, Firebase'in `geofire-common` kütüphanesinin birebir karşılığıdır; `shared/geohash-vectors.json`
  referans değerleri Node tarafında geofire-common'a karşı, iOS tarafında Swift koduna karşı test edilir.

Gerekli bileşik indeks: `status ASC, geohash ASC` (`firestore.indexes.json`).


## Güvenlik ve gizlilik

- Okuma/yazma için oturum gerekir (anonim dahil). **App Check** botları ve betikleri keser; yayından önce zorunlu kılınmalı.
  Yayın sürümü şimdilik DeviceCheck kullanır; App Attest, App ID'ye App Attest yeteneği ve imza dosyasına
  `appattest-environment` eklenince, zorunlu kılmayla birlikte açılacak.
- **Kötüye kullanım**: başkasının da gördüğü işareti tek kişi süresinden önce kaldıramaz ("… dendi", itiraz,
  ikinci kişi onayı); kanıtlı kapatma ve yeni işaret, `users/{uid}` belgesindeki 24 saatlik haklarla sınırlıdır ve
  her harcama kurallarca tek bir işarete bağlanır. Oturum kapatma bilerek yok: her cihaz tek anonim kimlikle kalır.
  Ayrıntılar: [tasarim/kotuye-kullanim-plani.md](tasarim/kotuye-kullanim-plani.md),
  [tasarim/cozuldu-kalabalik.md](tasarim/cozuldu-kalabalik.md), uygulanan hâl: [tasarim/SPEC.md](tasarim/SPEC.md).
- **Kurallar ve denetim**: ilk açılışta kurallar kabul edilir ([kullanım koşulları](kullanim-kosullari.md)). Şüpheli
  işaretler "⋯ → Bu işareti bildir" ile `flags`'e yazılır; sahibi konsoldan inceler, gerekirse işareti
  `closedReason: 'removed'` ile kapatır ve kimliği `banned/{uid}` ile engeller. Bildirimlerin haritada otomatik bir etkisi
  yoktur. Kişinin "gizle" dediği işaretler yalnızca onun cihazında saklanır.
- **Gürültüye karşı** (yalnızca istemci): ana düğme ve ihtiyaç adları yardım ihtiyacını sorar ("Yardım gereken hayvan",
  "Aç ve zayıf"); hafif ihtiyaçlarda bazen "Yardıma ihtiyacı var mı?" sorulur; iğne taze konumdan 1 km'den uzaksa bir
  kez sorulur; "Aç ve zayıf" işaretleri küçük, altta ve başlıkta ayrı sayılır; bu işaretlerde "Yardım gerekmiyor" ile
  dürüstçe kapatılabilir. Hiçbiri işaretlemeyi engellemez.
- **Saklanan veri**: hesap, ad, iletişim bilgisi, fotoğraf, serbest metin yoktur. İşaretin noktası (çoğu zaman koyanın
  bulunduğu yer) ve eylemleri yapan anonim kimlikler işaretle birlikte saklanır; `reporterId`, `claimedBy` gibi alanlar
  rastgele anonim kimliklerdir. Kişinin sürekli konumu gönderilmez. Ayrıntı: [gizlilik-politikasi.md](gizlilik-politikasi.md).
- Kurallar alan listesini sabitler (fazla alan, uzun metin yazılamaz); kimlik alanları (tür, ihtiyaç, konum) yalnızca
  koyanın sınırlı düzeltmesiyle değişir, koyan ve oluşturma anı hiç değişmez.
- `seenBy` yalnızca "Hâlâ orada" ile ve yalnızca yazanın kendi kimliği sona eklenerek büyür; başkasının kimliğini
  eklemek, kimlik silmek ya da sırayı değiştirmek kurallarca reddedilir. Böylece bir kullanıcı sayıyı yalnızca bir kez artırabilir.
- Bilinen sınır: kurallar `geohash`'in `lat/lng` ile tutarlılığını doğrulayamaz. Tutarsız bir kayıt yalnızca yanlış
  bölgede listelenir; ileride bir Cloud Function tetikleyicisiyle düzeltilebilir.

## Maliyet ve ölçek

İşaretler kısa ömürlü olduğu için aktif veri küçük kalır. Maliyeti belirleyen, dinlenen doküman sayısıdır:
her kullanıcı yalnızca görünen bölgedeki aktif işaretleri dinler. Çok yoğun şehirlerde bir sonraki adım
işaret kümeleme ve görünen alana göre sınırlı sorgulardır.
