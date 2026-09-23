# Mimari

Her teknik karar tek bir hedefe göre verildi: **sokakta, telefon elde, birkaç saniyede işaretleme** ve
**haritanın kendiliğinden güncel kalması**.

```
 iOS (SwiftUI)                                   Firebase
┌─────────────────────────────────┐            ┌──────────────────────────────────────┐
│ MapScreen ── GoogleMapView      │            │ Firestore: reports/{id}              │
│     │        (GMSMapView)       │  canlı     │   Güvenlik kuralları = durum makinesi│
│ MapViewModel ─ ReportRepository ├◀─dinleme───┤                                      │
│     │          (Firestore/Demo) ├──yazma────▶│ Cloud Function (10 dk'da bir)        │
│ AnimalKit (saf Swift)           │            │   süresi dolanları kapatır           │
│   ReportLifecycle · Geohash     │            │ TTL politikası: kapananları siler    │
│   Formatting                    │            │ Auth (anonim) · App Check            │
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
- **Google Maps SDK**: istenen harita sağlayıcısı. SwiftUI'da `UIViewRepresentable` ile sarılır.
  (MapKit'e geçmek gerekirse yalnızca `GoogleMapView.swift` değişir.)
- **AnimalKit paketi**: tüm iş kuralları ağdan ve arayüzden bağımsızdır, `swift test` ile saniyeler içinde test edilir.
  Firestore kuralları aynı kuralların sunucu karşılığıdır.

## Veri modeli

Tek koleksiyon: `reports/{reportId}`. Kurallar alanların **hepsinin** bulunmasını ister (boşlar `null`).

| Alan | Tür | Açıklama |
| --- | --- | --- |
| `species` | string | `cat`, `dog`, `bird`, `other` |
| `need` | string | `emergency`, `injured`, `babies`, `vet`, `food`, `shelter`, `other` |
| `lat`, `lng` | number | Konum |
| `geohash` | string(10) | Konum sorgusu için |
| `status` | string | `open` · `claimed` · `closed` |
| `closedReason` | string? | `resolved` · `gone` · `expired` |
| `reporterId` | string | İşareti koyanın anonim kimliği |
| `createdAt` | timestamp | Görüldüğü an (çevrimdışı işaretlemede de korunur) |
| `lastSeenAt` | timestamp | Son "Hâlâ orada" |
| `expiresAt` | timestamp | Bu andan sonra haritada gösterilmez |
| `claimedBy`, `claimedAt`, `claimExpiresAt` | string?, timestamp? | "İlgileniyorum" |
| `goneReports` | string[] | "Artık yok" diyenler |
| `closedAt`, `purgeAt` | timestamp? | Kapanış ve TTL ile silinme zamanı |

Fotoğraf, açıklama, kullanıcı profili **bilerek yok**: hem akışı uzatır hem de depolama/moderasyon yükü getirir.

## Yaşam döngüsü

```
            İlgileniyorum                Çözüldü
   open ─────────────────▶ claimed ─────────────────▶ closed(resolved)
    ▲                        │
    └─ Vazgeç / 3 sa doldu ──┘
   open|claimed ── Artık yok (2 kişi, ya da koyan/ilgilenen) ──▶ closed(gone)
   open|claimed ── expiresAt geçti (Cloud Function) ───────────▶ closed(expired)
   open (dokunulmamış) ── Geri al ──▶ silinir
```

| Eylem | Kim | Etki |
| --- | --- | --- |
| Oluştur | Herkes | `expiresAt = createdAt + ihtiyacın ömrü` |
| İlgileniyorum | Aktif sahibi yoksa herkes | 3 sa sahiplik; `expiresAt` en az sahiplik bitişine uzar |
| Vazgeç | İlgilenen | Tekrar `open` |
| Çözüldü | İlgilenen ya da koyan | `closed(resolved)` |
| Hâlâ orada | Herkes | `expiresAt = şimdi + ömür` (asla kısalmaz) |
| Artık yok | Herkes, bir kez | 2. bildirimde (ya da koyan/ilgilenen ise hemen) `closed(gone)` |

İstemci: `ios/Packages/AnimalKit/Sources/AnimalKit/ReportLifecycle.swift`
Sunucu: `firebase/firestore.rules`

İstemci eylemleri bir **Firestore işlemi (transaction)** içinde uygular: güncel doküman okunur, `ReportLifecycle`
yeni hâli hesaplar ve **yalnızca değişen alanlar** yazılır (`Report.changedFields`). Tüm dokümanı geri yazmak
hatalı olurdu: Timestamp → Date → Timestamp dönüşümü mikro saniye kaydırır ve kurallar değişmemesi gereken
alanı (ör. `createdAt`) değişmiş sayıp işlemi reddeder. AnimalKit testleri her eylemin yalnızca kuralların izin
verdiği alanları değiştirdiğini doğrular. İki kişi aynı anda "İlgileniyorum" derse biri kazanır, diğerine
"Az önce başka biri ilgilenmeye başladı" gösterilir. Kurallar, istemci atlatılsa bile aynı geçişleri zorunlu kılar.

## Zaman

Zaman damgalarını istemci yazar (sunucu zaman damgası kullanılmaz), çünkü:

- çevrimdışı koyulan işaret, hayvanın **görüldüğü anı** taşımalı;
- ömür hesabı (`createdAt + 12 sa`) istemcide yapılabilmeli.

Kurallar bunu sınırlar: `createdAt` en fazla 24 sa geçmişte / 15 dk gelecekte olabilir, "şimdi" anlamına gelen alanlar
sunucu saatine ±15 dk yakın olmalı, ömürler ve sahiplik süresi sözleşmedeki üst sınırları aşamaz.

## Eski işaretler

1. **İstemci**: `expiresAt` geçmiş ya da süresi dolmuş sahiplikler, sunucu temizliği beklenmeden gizlenir / "yardım bekliyor" sayılır.
2. **Solma**: işaretin opaklığı `lastSeenAt → expiresAt` aralığında azalır; eskidiği görünür.
3. **Topluluk**: "Hâlâ orada" ömrü yeniler, "Artık yok" işareti kapatır.
4. **Sunucu**: `sweepStaleReports` (10 dk'da bir) süresi dolanları `closed(expired)` yapar, terk edilmiş sahiplikleri bırakır.
5. **Silme**: kapanan işaretin `purgeAt` alanı (30 gün sonrası) Firestore TTL politikasıyla silinir.

## Konum sorgusu

Firestore coğrafi sorgu desteklemez; standart çözüm **geohash aralıklarıdır**.
Görünen harita alanının yarıçapının 1,5 katı için `Geohash.queryBounds` 4–9 aralık üretir; her biri
`status in [open, claimed] AND geohash in [start, end)` olarak ayrı dinlenir ve sonuçlar birleştirilir.

- Küçük kaydırmalarda yeniden sorgu yapılmaz (dinlenen alan görünen alanı hâlâ kapsıyorsa).
- 25 km'den geniş alan görünüyorsa sorgu yapılmaz, "yakınlaştır" denir.
- `Geohash.swift`, Firebase'in `geofire-common` kütüphanesinin birebir karşılığıdır; `shared/geohash-vectors.json`
  referans değerleri Node tarafında geofire-common'a karşı, iOS tarafında Swift koduna karşı test edilir.

Gerekli bileşik indeks: `status ASC, geohash ASC` (`firestore.indexes.json`).

## Güvenlik ve gizlilik

- Okuma/yazma için oturum gerekir (anonim dahil). **App Check** botları ve betikleri keser; yayından önce zorunlu kılınmalı.
- Hiçbir kişisel veri tutulmaz: kullanıcı konumu saklanmaz, yalnızca hayvanın işaretlendiği nokta saklanır.
  `reporterId`/`claimedBy` rastgele anonim kimliklerdir.
- Kurallar alan listesini sabitler (fazla alan, uzun metin yazılamaz), kimlik alanlarının (tür, ihtiyaç, konum, koyan)
  sonradan değiştirilmesini engeller.
- Bilinen sınır: kurallar `geohash`'in `lat/lng` ile tutarlılığını doğrulayamaz. Tutarsız bir kayıt yalnızca yanlış
  bölgede listelenir; ileride bir Cloud Function tetikleyicisiyle düzeltilebilir.

## Maliyet ve ölçek

İşaretler kısa ömürlü olduğu için aktif veri küçük kalır. Maliyeti belirleyen, dinlenen doküman sayısıdır:
her kullanıcı yalnızca görünen bölgedeki aktif işaretleri dinler. Çok yoğun şehirlerde bir sonraki adım
işaret kümeleme ve görünen alana göre sınırlı sorgulardır.
