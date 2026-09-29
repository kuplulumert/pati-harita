# Pati Harita Gizlilik Politikası

> **TASLAK.** Yayından önce gözden geçirin, `[...]` ile işaretli yerleri doldurun ve herkese açık bir adreste
> yayımlayın (App Store Connect bu adresi ister). Hukuki danışmanlık yerine geçmez; KVKK kapsamında
> veri sorumlusu bilgilerinizin doğru olduğundan emin olun.

Son güncelleme: [tarih]

Pati Harita, sokakta yardıma ihtiyacı olan hayvanları haritada işaretlemeye yarayan bir uygulamadır.
Uygulama **hesap, ad, e-posta, telefon numarası, fotoğraf ya da açıklama istemez.** Kullanım kuralları:
[Kullanım Koşulları](kullanim-kosullari.md).

## Hangi verileri işliyoruz?

| Veri | Ne zaman | Neden |
| --- | --- | --- |
| **İşaretin konumu** (enlem/boylam) | Bir işaret koyduğunuzda ya da düzelttiğinizde | İşaretin haritada gösterilmesi |
| İşaretin türü ve ihtiyacı (ör. "Kedi · Aç ve zayıf") | Bir işaret koyduğunuzda ya da düzelttiğinizde | Yardım edeceklerin ne gerektiğini bilmesi |
| **Rastgele anonim kimlik** | Uygulamayı ilk açtığınızda otomatik | "İşareti kim koydu / kim ilgileniyor" ayrımı; ör. yalnızca işareti koyanın düzeltebilmesi, günlük işaret hakkı |
| Yaptığınız eylemler (İlgileniyorum, Hâlâ orada, Artık yok, Çözüldü, Yardım gerekmiyor, itiraz; "Hâlâ orada mı?" sorusuna verdiğiniz Evet ya da Hayır) ve zamanları | Bu düğmelere bastığınızda | İşaretin durumunun güncel tutulması |
| Bildirdiğiniz işaretler (hangi işaret, seçtiğiniz neden, zaman ve anonim kimliğiniz) | "Bu işareti bildir" dediğinizde | Kurallara aykırı işaretleri incelemek |
| Günlük haklarınızın sayaçları (hesap yaşı, son 24 saatte konan ve kapatılan işaretler) | İşaret koyduğunuzda ya da kapattığınızda | Kötüye kullanımı sınırlamak |
| Cihaz bütünlüğü doğrulaması (Apple DeviceCheck / App Check) | Sunucuya her istekte | Sahte istemcileri ve botları engellemek |

**İşaretin konumu anonim kimliğinizle birlikte saklanır.** İşaret yalnızca bulunduğunuz yerin yaklaşık 150 m (konum
doğruluğuna göre en fazla 225 m) çevresine konabilir; bu yüzden saklanan nokta, işareti koyduğunuz anda bulunduğunuz
yere yakındır ve anonim kimliğinizle birlikte saklanır. Bunun dışında konumunuz yalnızca cihazınızda kullanılır:
haritayı bulunduğunuz yere getirmek, işaretlere uzaklığı göstermek, iğnenin çevrenizde olup olmadığını denetlemek,
"Çözüldü" gibi yanıtların hayvanın yanında verildiğini denetlemek ve yanından geçtiğiniz işaretler için "Hâlâ orada mı?"
diye sormak için. Orman, yerleşim yeri dışı ve deniz denetimi
uygulamanın içindeki haritayla cihazda yapılır; bunun için konumunuz hiçbir yere gönderilmez. Sürekli konumunuz
sunucuya gönderilmez ve saklanmaz.

'Hâlâ orada mı?' sorusuna Evet ya da Hayır derseniz yanıtınız, diğer eylemler gibi anonim kimliğinizle işarette
saklanır (görenler ya da 'artık yok' diyenler listesi) ve o işaretin yakınından geçtiğinizi gösterebilir. İşaretler ve
bu listeler uygulamayı kullanan herkesçe okunabilir; anonim kimliğiniz adınızla ilişkilendirilmez, ancak aynı kimliğin
koyduğu işaretler bir araya getirilirse sık bulunduğunuz bölge hakkında fikir verebilir. "Yanlış mı? Bize yaz" ile
e-posta gönderirseniz iğnenin yaklaşık yeri (~1 km) e-postada yer alır.

Anonim kimlik adınızla, e-postanızla ya da cihazınızın reklam kimliğiyle ilişkilendirilmez. Uygulama
reklam, analitik ya da izleme (tracking) aracı içermez.

Şu bilgiler **yalnızca cihazınızda** tutulur ve sunucuya gönderilmez: kuralları kabul ettiğiniz sürüm, son işaretlerinizin
sayısı ("Yardıma ihtiyacı var mı?" sorusu için), gizlediğiniz ya da bildirdiğiniz işaretlerin listesi, gece güvenlik
hatırlatmasının en son ne zaman gösterildiği, 'Hâlâ orada mı?' sorulan işaretler ve sorunun ne sıklıkla gösterildiği ve
son 24 saatte hangi işaretlerin yanında en son ne zaman bulunduğunuz (konumunuz değil; yalnızca işaret ve zaman).

## Kimler görebilir?

- İşaretler (nokta, tür, ihtiyaç, durum ve zamanlar) **uygulamayı kullanan herkese açıktır**; amacı budur.
- İşaretle birlikte saklanan **anonim kimlikler** (işareti koyan, ilgilenen, "Hâlâ orada", "Artık yok" ya da benzerlerini
  diyenler) de işaret verisinin parçasıdır ve uygulamayı kullanan diğer kişilerin erişebildiği veride yer alır. Uygulama
  bu kimlikleri ekranda göstermez; yalnızca "Sen ilgileniyorsun" / "Biri ilgileniyor" gibi ayrımlar için kullanır. Kimlik
  sizi doğrudan tanımlamaz, ancak aynı kimlikle yapılan işaretler ve eylemler birbirine bağlanabilir.
- Bildirimler ("Bu işareti bildir") yalnızca uygulamanın sahibi tarafından görülür; diğer kullanıcılar göremez ve
  haritada hiçbir etkisi yoktur.

## Ne kadar süre saklanır?

- Her işaretin ihtiyaca göre bir ömrü vardır (12–72 saat, en fazla 7 gün). Süre dolunca, çözüldüğünde ya da "Artık yok"
  / "Yardım gerekmiyor" denildiğinde işaret haritadan kalkar.
- Kapanan işaretler, otomatik silme etkinleştirildiğinde **en fazla 30 gün** saklanır ve sonra silinir. Otomatik silme
  etkinleştirilene kadar kapanan işaretler talep üzerine elle silinir.
- Bildirimler inceleme için [süre] saklanır.
- Kurallara aykırı kullanım nedeniyle engellenen anonim kimlikler engel listesinde tutulur.
- Anonim kimlik cihazın anahtar zincirinde (Keychain) saklanır; uygulamayı silip yeniden kurduğunuzda aynı kimlik
  kullanılmaya devam edebilir. Kimliğinizle ilişkili işaretlerin silinmesini istemek için bize yazabilirsiniz.

## Hizmet sağlayıcılar

Veriler aşağıdaki hizmet sağlayıcıların altyapısında işlenir:

- **Firebase (Google LLC)**: veritabanı (Cloud Firestore, [bölge: ör. Avrupa / eur3]), anonim oturum
  (Firebase Authentication) ve App Check. Firebase, hizmeti sunmak için IP adresi gibi teknik verileri işleyebilir.
  Ayrıntılar: https://firebase.google.com/support/privacy
- **Apple Haritalar (MapKit)**: harita görüntüleri ve yol tarifi. Apple'ın gizlilik politikası:
  https://www.apple.com/legal/privacy/
- **Apple DeviceCheck**: cihaz bütünlüğü doğrulaması.

"Konumu paylaş" düğmesini kullanırsanız, seçtiğiniz uygulama ve kişiyle yalnızca işaretin konum bağlantısı paylaşılır;
bu paylaşım sizin kontrolünüzdedir.

## Haklarınız

KVKK ve GDPR kapsamında verilerinize erişme, düzeltilmesini ya da silinmesini isteme haklarınız vardır.
Uygulama adınızı ya da iletişim bilginizi tutmadığından, bir işaretin kaldırılmasını istiyorsanız işaretin konumunu ve
yaklaşık zamanını bize yazmanız yeterlidir. Açıklama ekranının altında görünen kimlik başlangıcını da eklerseniz
kayıtlarınızı daha kolay buluruz.

## Çocuklar

Uygulama çocuklara yönelik değildir ve bilerek çocuklardan kişisel veri toplamaz.

## İletişim

Veri sorumlusu: [ad / kurum]
E-posta: [iletişim e-postası]

Bu politikada değişiklik olursa bu sayfa güncellenir.
