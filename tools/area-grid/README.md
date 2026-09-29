# Alan ızgarası: `shared/area-tr.bin`

Uygulama, yeni bir işaretin iğnesi **orman**, **yerleşim yeri dışı** ya da **deniz / göl** üstündeyse işareti
kaydettirmez. Denetim cihazda ve internetsiz yapılır; konum hiçbir yere gönderilmez. Bunun için Türkiye'yi kaplayan,
15″'lik (yaklaşık 464 m K–G × 345–375 m D–B) hücrelerden oluşan bir ızgara kullanılır ve her hücre dört sınıftan birini
taşır. Bu klasördeki script o ızgarayı **yalnızca OpenStreetMap ve Natural Earth** verisinden üretir.

| dosya | ne |
|---|---|
| `shared/area-tr.bin` | üretilen ızgara (1 825 224 bayt). Uygulama onu `Bundle.main`'den okur; dosya yoksa her yer izinli sayılır. |
| `shared/area-golden.json` | altın noktalar: script yazmadan önce, AnimalKit'in `AreaGridGoldenTests`'i de her `swift test`te denetler |
| `tools/area-grid/build_area_grid.py` | üretim ve denetim |
| `tools/area-grid/requirements.txt` | numpy, osmium (pyosmium), pyshp; GDAL gerekmez |

## Kaynaklar

| kullanım | veri | adres | boyut (yaklaşık) | lisans |
|---|---|---|---|---|
| yerleşim, orman | OpenStreetMap Türkiye özü (Geofabrik), `turkey-latest.osm.pbf` | https://download.geofabrik.de/europe/turkey-latest.osm.pbf ([sayfa](https://download.geofabrik.de/europe/turkey.html)) | 0,5–0,7 GB; kesin boyut sayfada | ODbL 1.0, © OpenStreetMap katkıcıları |
| özün sınırı | Geofabrik'in özü kestiği çokgen, `turkey.poly` (Osmosis biçimi) | https://download.geofabrik.de/europe/turkey.poly | birkaç KB | ODbL 1.0, © OpenStreetMap katkıcıları |
| kara | Natural Earth 10 m `ne_10m_land` | https://naciscdn.org/naturalearth/10m/physical/ne_10m_land.zip | birkaç MB | kamu malı |
| küçük adalar | Natural Earth 10 m `ne_10m_minor_islands` | https://naciscdn.org/naturalearth/10m/physical/ne_10m_minor_islands.zip | birkaç MB | kamu malı |
| göller | Natural Earth 10 m `ne_10m_lakes` | https://naciscdn.org/naturalearth/10m/physical/ne_10m_lakes.zip | birkaç MB | kamu malı |

GHSL, CORINE ve GeoNames kullanılmaz. Geofabrik özü `turkey.poly` ile kesilir; kutudaki komşu ülkelerin (Yunanistan
ve Ege adaları, Bulgaristan, Suriye, Irak, İran, Gürcistan, Ermenistan) bu sınırın dışında kalan yerlerinde OSM verisi
yoktur. Oradaki kara "bilinmiyor" sayılır ve **izinlidir** (kutunun dışı gibi, fail-open); yalnızca Natural Earth'ten
gelen su engellenir. Böylece Dedeağaç, Batum, Erivan, Halep, Musul ya da sınırın dışında kalan Ege adalarında bulunan
biri "yerleşim yeri dışı" engeline takılmaz. Sınırın içinde kalan komşu yerlerin OSM verisi özdedir; onlar Türkiye'deki
gibi sınıflanır.

### Girdi ve çıktı özetleri

Script her çalıştırmada her girdinin boyutunu ve SHA-256'sını, Geofabrik'ten indirdiği pbf'nin MD5'ini (Geofabrik'in
yayımladığı `.md5` dosyasıyla), pbf'nin tarihini ve çıktının SHA-256'sını yazar. Yayımlanan her ızgaranın değerleri
buraya işlenir. Aynı dosyalarla yeniden üretimde `--expect-sha256 DOSYA=SHA256` tutmayan girdiyi reddeder.

| veri sürümü | dosya | boyut | SHA-256 |
|---|---|---|---|
| 2026-09-29 | `turkey-latest.osm.pbf` (OSM 2026-09-28T20:23:05Z) | 618,2 MB | `0ed7f472a2310e3e6051840ea952a5c25788039def47b0f5e4b06b5dbb32226c` |
| 2026-09-29 | `turkey.poly` | 6 KB | `6c41ac3f661ce4764e3c7ba30a7e2f35e1bcbaa1b1f8b91f6d78a9c0e3344ea9` |
| 2026-09-29 | `ne_10m_land.zip` (5.1.1) | 3,1 MB | `e547d749445eaa0964aba76738090ec88f5e63c4585122170f98c67a7ea922dc` |
| 2026-09-29 | `ne_10m_minor_islands.zip` (4.1.0) | 307,6 KB | `47c0b3ce26df7b4dbabdbb251023918cb2f5c83462a426288f1f253da7284db2` |
| 2026-09-29 | `ne_10m_lakes.zip` (5.0.0) | 2,2 MB | `0803a06f9c3cb4671d89b68c48b142aad9366ba40f665245e12a913fbc61722a` |
| 2026-09-29 | **çıktı** `shared/area-tr.bin` | 1 825 224 bayt | `3a4f7130f4c7eba7f5d8c13f4ef67ec68708963553e42c167f6e750696d2ba12` |

## Lisans ve atıf

- **`shared/area-tr.bin`, OpenStreetMap verisinden türetilmiş bir veritabanıdır (derived database).** Bu depo açık
  olduğu için dosya [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/) ile sunulur; atıf
  "© OpenStreetMap katkıcıları"dır. Nasıl üretildiği (bu script, kurallar ve altın noktalar) dosyayla birlikte açıktadır.
  ODbL yalnızca bu veritabanını ve ondan türetilenleri bağlar; uygulamanın kodu kendi koşullarında kalır.
- Uygulamada ızgaradan üretilen sonuç (işaretin engellenmesi) bir "produced work"tür ve atıf ister. Açıklama ekranındaki
  satır: "Yerleşim ve orman verisi: © OpenStreetMap katkıcıları (ODbL) · Su: Natural Earth · Veri sürümü …".
- **Natural Earth** kamu malıdır (public domain); atıf zorunlu değildir, yine de yukarıdaki satırda anılır.
- `shared/area-golden.json` elle seçilmiş koordinatlardır. Bir kısmı (konteyner kentler, mezra) openstreetmap.org'da
  bakılarak seçildi; tek tek noktalardır, veritabanından toplu bir alıntı değildir.

## Kurallar

Her şey 15″ ızgarada değerlendirilir. Çokgenler 3″ alt ızgaraya (her 15″ hücre tam 5 × 5 alt hücre) hücre merkezi
kuralıyla işlenir: merkezi çokgenin içinde kalan alt hücre doludur, iç halkalar (delikler) boş kalır.

1. **Yerleşik (`settled`)**: şunlardan biri doğruysa.
   - Hücrede en az **3 bina** var (`building=*`, `building=no` hariç; alanlar dış halkalarının ortalama noktasıyla sayılır,
     düğüm olarak çizilmiş binalar da sayılır).
     Hücrenin yarısından fazlası ormansa en az **10 bina** gerekir: ormanın içindeki birkaç dağınık bina (piknik alanı,
     orman tesisi) yerleşim sayılmaz.
   - `landuse=residential/construction/industrial/commercial/retail/cemetery` hücrenin **merkezini** ya da 25 alt
     hücreden **en az 2'sini** kaplıyor.
   - Hücrede bir `place=city/town/village/hamlet/isolated_dwelling/farm/suburb/neighbourhood/quarter` **düğümü** var.
     `place=locality` alınmaz (çoğu kez ıssız bir yer adıdır); yer alanları (mahalle sınırları gibi) alınmaz.
2. **Kuşak (`fringe`)**: yerleşik hücrelerin 3 × 3 çekirdekle 1 kez genişletilmesi (~0,35–0,45 km). Daha geniş
   kuşak (0,8 km) köyler arası bozkır yollarını da açıyordu.
3. **Orman (`forest`)**: `landuse=forest` ya da `natural=wood` 25 alt hücrenin **en az 13'ünü** (≥ 0,5) kaplıyor, hücre
   yerleşik değil ve 8 komşusunun **hiçbiri** yerleşik değil. Böylece yerleşime değen orman hücreleri (ormanlık
   vadilerdeki Karadeniz köyleri, evlerle çevrili korular: Yoğurtçu, Fenerbahçe, Emirgan, Validebağ, Yıldız) açık kalır.
4. **Su (`water`)**: `kara` = Natural Earth kara + küçük adalar, değdiği her hücre (all_touched); `göl` = merkezi Natural
   Earth gölünde kalan hücreler. `su` = (kara değil ya da göl), 3 × 3 çekirdekle 2 kez aşındırılmış hâli: su kıyıdan
   en az ~0,7 km içeride başlar. Aşındırmada kutunun dışı kenardaki hücreyle aynı sayılır.
5. **Özün dışı (`unknown`)**: 3″ alt hücrelerinin hepsi `turkey.poly` içinde kalmayan (sınırın dışındaki ya da
   sınırına değen) ve su olmayan hücreler. Buralarda OSM verisi yok ya da eksiktir.
6. **Sınıf**, bu sırayla (sonraki öncekini ezer): hepsi `remote` → `water` → kuşak `allowed` → `forest` →
   yerleşik `allowed` → özün dışı `allowed`. Yerleşik her zaman kazanır, orman kuşağı, kuşak da suyu ezer; bu yüzden
   kıyılar, sahil yolları, iskeleler, İstanbul Boğazı ve Haliç açık kalır. Natural Earth'te olmayan küçük göller ve
   barajlar su sayılmaz.

| değer | sınıf | uygulamadaki sonuç |
|---|---|---|
| 0 | `remote` | "Gönüllülerin güvenliği için yerleşim yeri dışına şimdilik işaret konamaz." |
| 1 | `allowed` | işaret konabilir |
| 2 | `water` | "Denizin ya da gölün üstüne işaret konamaz." |
| 3 | `forest` | "Gönüllülerin güvenliği için ormanlık alanlara şimdilik işaret konamaz." |

Kutunun dışı ya da ızgara yoksa sonuç "bilinmiyor"dur ve işaret konabilir (fail-open). Kutunun içinde ama OSM özünün
dışında kalan kara da ızgarada `allowed` olarak yazılır (kural 5 ve 6).

## Kapılar

Script aşağıdakilerden biri geçmezse **hiçbir şey yazmaz** ve 1 ile çıkar:

1. **Altın noktalar**: `shared/area-golden.json`'daki her nokta, uygulamadaki aramayla bulunan hücrede beklenen
   sınıflardan birinde olmalı. Geçmeyen her nokta için 7 × 7 komşuluk (`#` izinli, `^` orman, `~` su, `.` yerleşim dışı)
   ve hücrenin bina, yerleşim kullanımı, yer düğümü, orman ve Natural Earth değerleri yazılır.
2. **Sağlık denetimleri**: en az bir orman, su ve izinli hücre; özün sınırı kutuyla kesişiyor; OSM'den okunmuş bina
   ve yer düğümü; okunamayan (eksik düğümlü ya da bozuk) alanların payı %5'ten az.
3. **Gidiş-dönüş**: paketlenen dosya başlığıyla birlikte yeniden okunur ve hesaplanan ızgarayla birebir aynı çıkmalı.

Her çalıştırmada sınıf payları (bütün kutu ve su dışında kalanlar), çıktının SHA-256'sı ve önbelleğe renkli bir
önizleme (`area-tr-<sürüm>-preview.png`, kuzey üstte) yazılır; önizleme kapı geçmese de yazılır.

## Çalıştırma (Windows, PowerShell)

İndirme **yalnızca `--download` verilirse** yapılır. İlk üretimden önce indirilecek dosyaları ve boyutlarını yukarıdaki
tablodan kontrol edin; Türkiye pbf'si yarım gigabaytın üstündedir.

```powershell
# Bir kez: sanal ortam OneDrive dışında
py -3.13 -m venv "$env:LOCALAPPDATA\PatiHarita\venv"
& "$env:LOCALAPPDATA\PatiHarita\venv\Scripts\python.exe" -m pip install -r tools/area-grid/requirements.txt

# Üretim (depo kökünden)
& "$env:LOCALAPPDATA\PatiHarita\venv\Scripts\python.exe" tools/area-grid/build_area_grid.py `
    --version 20261001 `
    --cache "$env:LOCALAPPDATA\PatiHarita\area-grid-cache" `
    --download

# Var olan ızgarayı denetleme: başlık, sınıf payları, SHA-256, altın noktalar (numpy gerekmez)
py -3.13 tools/area-grid/build_area_grid.py --verify-bin shared/area-tr.bin
```

| seçenek | anlamı |
|---|---|
| `--version YYYYMMDD` | veri sürümü (başlıktaki `dataVersion`, uygulamada "2026-10-01"); her yeniden üretimde artar |
| `--cache DİZİN` | ham veri klasörü (varsayılan `%LOCALAPPDATA%\PatiHarita\area-grid-cache`) |
| `--download` | önbellekte olmayan kaynakları indir; yoksa eksik dosyanın adı ve adresi yazılıp çıkılır |
| `--pbf YOL_YA_DA_ADRES` | başka bir pbf (ör. elle indirilmiş tarihli bir Geofabrik dosyası) |
| `--poly YOL_YA_DA_ADRES` | özün sınırı (varsayılan Geofabrik `turkey.poly`); başka bir öz verilirse onun `.poly`'si |
| `--ne DİZİN_YA_DA_ADRES` | Natural Earth `.zip` ya da `.shp` dosyalarının klasörü, ya da temel adres |
| `--expect-sha256 DOSYA=SHA256` | girdi özeti tutmalı (tekrarlanabilir) |
| `--out YOL` | çıktı (varsayılan `shared/area-tr.bin`) |
| `--golden YOL` | altın noktalar (varsayılan `shared/area-golden.json`) |
| `--no-write` | her şeyi yap, kapıları denetle, ama çıktıyı yazma |
| `--node-index` | pyosmium düğüm konumu deposu (varsayılan `flex_mem`) |
| `--verify-bin YOL` | üretmeden var olan bir ızgarayı denetle |

Tahmini kaynak: Türkiye özünün düğüm konumları için 1,5–2 GB bellek; süre çoğunlukla OSM okumasıdır (makineye göre
birkaç dakikadan yarım saate).

## Önbellek

- Varsayılan `%LOCALAPPDATA%\PatiHarita\area-grid-cache` (Windows dışında `~/.cache/pati-harita/area-grid`). İçinde
  `downloads/` (pbf, `.md5`, `turkey.poly`, Natural Earth zip'leri), `natural-earth/` (açılmış shapefile'lar) ve
  önizlemeler durur.
- Script, yolunda `OneDrive` geçen ya da depo içindeki bir önbelleği reddeder (depo OneDrive'da; gigabaytlar eşitlenir).
  Tek istisna, OneDrive dışındaki bir klonda `tools/area-grid/cache/`'tir; `.gitignore`'dadır.
- Ham veri asla commit'lenmez.

## Yeniden üretim politikası

- **Ne zaman**: yılda bir; doğrulanmış yanlış engel bildirimleri gelince ("Yanlış mı? Bize yaz"); kurallar ya da
  altın noktalar değişince. Boşuna üretmeyin: her üretim git geçmişine ~1,8 MB ekler.
- **Nasıl**:
  1. `turkey-latest` her gün değişir; yeniden üretilebilirlik için önbellekteki eski pbf'yi ve `.md5`'ini silip yenisini
     indirin ya da `--pbf` ile tarihli bir dosya verin.
  2. `--version` bugünün tarihi olsun ve öncekinden büyük olsun.
  3. Kapılar geçince yukarıdaki özet tablosuna girdilerin ve çıktının SHA-256'larını, `pip freeze` sürümlerini ekleyin.
  4. `shared/area-tr.bin`, altın nokta değişiklikleri ve bu tablo aynı commit'te gider; CI'daki `AreaGridGoldenTests`
     aynı noktaları uygulamanın Swift kodu ile yeniden denetler.
- **Doğrulanmış yanlış engel**: noktayı doğru sınıfla `shared/area-golden.json`'a ekleyin. Veri eksikse (köy, bina,
  yerleşim alanı ya da orman sınırı) önce openstreetmap.org'da düzeltin; herkesin işine yarar ve sonraki üretimde gelir.

## Altın noktalar (`shared/area-golden.json`)

```json
[{"name": "İstanbul, Kadıköy (arayüz testi noktası)", "lat": 40.9903, "lon": 29.0290, "expect": ["allowed"]}]
```

- `expect`, kabul edilen sınıflardır; birden çok sınıf "bunlardan biri" demektir (ör. dağ zirvesi: `["forest", "remote"]`).
- Kapsam: İstanbul sokakları, koruları, sahilleri, Adalar, Boğaz ve Haliç; Ankara, İzmir, Antalya kıyısı ve diğer il
  merkezleri; farklı bölgelerden köyler ve kasabalar; 2023 depremi sonrasının konteyner kentleri ve kalıcı konutları
  (Hatay, Kahramanmaraş, Adıyaman); bir Rize mezrası; Belgrad Ormanı içi ve Bahçeköy tarafındaki kenarı; Atatürk Kent
  Ormanı içi; Marmara, Karadeniz, Akdeniz ve Ege'de açık deniz; Van ve Beyşehir gölleri; dağ zirveleri; kasabalar arası
  yollar; özün dışındaki komşu ülke karası (izinli). Küçükçekmece ve Büyükçekmece gölleri bilerek yok (kuşak içindedir,
  su sayılmaz).
- Bahçeköy evlerinin ~300 m ötesindeki nokta `["forest", "allowed"]` bekler: yerleşik hücreye değen orman hücresi
  kuşakta kalır (`MAX_SETTLED_NEIGHBOURS_FOR_FOREST = 0`). ~800 m ötesindeki nokta ormandır. Konteyner kentler
  söküldükçe OSM'den kalkar; öyle bir nokta kapıda düşerse listeden çıkarılır.
- Koordinatlar yaklaşıktır. İlk üretimden önce, özellikle orman, köy ve yol noktalarını haritada kontrol edin; kapı
  geçmezse komşuluk çıktısı hangi noktanın, neden düştüğünü gösterir.
- Noktaları hücre kenarına (1/240 derecenin tam katları) koymayın: kenarda kayan nokta ayrıntısı hangi hücrenin
  seçileceğini belirler. Arayüz testinin açık denizdeki noktası (40.80, 28.50) bu yüzden iki tarafı da su olan bir yerdedir.

## Dosya biçimi

AnimalKit'teki `AreaGrid(data:)` ile aynıdır. 24 baytlık başlık, little-endian:

| konum | tür | değer |
|---|---|---|
| 0 | 4 × ASCII | `"PHAG"` |
| 4 | u8 | formatVersion = 1 |
| 5 | u8 | cellsPerDegree = 240 (15″) |
| 6 | u16 | rows = 1560 |
| 8 | u16 | cols = 4680 |
| 10 | u16 | reserved = 0 |
| 12 | i32 | south = 35 750 000 mikroderece |
| 16 | i32 | west = 25 500 000 mikroderece |
| 20 | u32 | dataVersion, YYYYMMDD (ör. 20261001) |

- Kutu: enlem [35.75, 42.25), boylam [25.50, 45.00). Satır 0 en güneydedir; hücreler satır satır dizilir.
- Bir baytta dört hücre: hücre *i*, `i / 4`. baytın `2 × (i % 4)` bitinden başlayan 2 bittir.
- Boyut tam 24 + 1 825 200 = **1 825 224** bayttır.
- Arama, uygulamadaki gibi önce çarpıp sonra çıkarır: `satır = ⌊enlem × 240 − 8580⌋`, `sütun = ⌊boylam × 240 − 6120⌋`
  (8580 = 35 750 000 × 240 / 10⁶). Güney ve batı kenarı dahil, kuzey ve doğu kenarı hariçtir.
