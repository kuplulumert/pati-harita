# Pati Harita Gizlilik Politikası

> **TASLAK.** Yayından önce gözden geçirin, `[...]` ile işaretli yerleri doldurun ve herkese açık bir adreste
> yayımlayın (App Store Connect bu adresi ister). Hukuki danışmanlık yerine geçmez; KVKK kapsamında
> veri sorumlusu bilgilerinizin doğru olduğundan emin olun.

Son güncelleme: [tarih]

Pati Harita, sokakta yardıma ihtiyacı olan hayvanları haritada işaretlemeye yarayan bir uygulamadır.
Uygulama **hesap, ad, e-posta, telefon numarası, fotoğraf ya da açıklama istemez.**

## Hangi verileri işliyoruz?

| Veri | Ne zaman | Neden |
| --- | --- | --- |
| **Hayvanın işaretlendiği nokta** (enlem/boylam) | Bir işaret koyduğunuzda | İşaretin haritada gösterilmesi |
| İşaretin türü ve ihtiyacı (ör. "Kedi · Mama / su") | Bir işaret koyduğunuzda | Yardım edeceklerin ne gerektiğini bilmesi |
| **Rastgele anonim kimlik** | Uygulamayı ilk açtığınızda otomatik | "İşareti kim koydu / kim ilgileniyor" ayrımı; ör. yalnızca ilgilenen kişinin "Çözüldü" diyebilmesi |
| Yaptığınız eylemler (İlgileniyorum, Hâlâ orada, Artık yok, Çözüldü) ve zamanları | Bu düğmelere bastığınızda | İşaretin durumunun güncel tutulması |
| Cihaz bütünlüğü doğrulaması (Apple DeviceCheck / App Check) | Sunucuya her istekte | Sahte istemcileri ve botları engellemek |

**Konumunuz saklanmaz.** Konum izni yalnızca haritayı bulunduğunuz yere getirmek, işaretleme iğnesini oraya
yerleştirmek ve işaretlere uzaklığı göstermek için cihazınızda kullanılır. Sunucuya yalnızca sizin seçtiğiniz
işaret noktası gönderilir. Bu nokta çoğu zaman bulunduğunuz yere yakın olduğundan, işaret koymadan önce
iğneyi dilediğiniz yere kaydırabilirsiniz.

Anonim kimlik adınızla, e-postanızla ya da cihazınızın reklam kimliğiyle ilişkilendirilmez. Uygulama
reklam, analitik ya da izleme (tracking) aracı içermez.

## Kimler görebilir?

- İşaretler (nokta, tür, ihtiyaç, durum ve zamanlar) **uygulamayı kullanan herkese açıktır**; amacı budur.
- Anonim kimlik diğer kullanıcılara gösterilmez; uygulama yalnızca "Sen ilgileniyorsun" / "Biri ilgileniyor"
  gibi ayrımlar için kullanır.

## Ne kadar süre saklanır?

- Her işaretin ihtiyaca göre bir ömrü vardır (12–72 saat). Süre dolunca, çözüldüğünde ya da "Artık yok"
  denildiğinde işaret haritadan kalkar.
- Kapanan işaretler **30 gün sonra otomatik olarak silinir.**
- Anonim kimlik uygulamayı sildiğinizde cihazınızdan kaldırılır. Uygulamayı yeniden kurduğunuzda yeni bir kimlik oluşur.

## Hizmet sağlayıcılar

Veriler aşağıdaki hizmet sağlayıcıların altyapısında işlenir:

- **Firebase (Google LLC)**: veritabanı (Cloud Firestore, [bölge: ör. Avrupa / eur3]), anonim oturum
  (Firebase Authentication) ve App Check. Firebase, hizmeti sunmak için IP adresi gibi teknik verileri işleyebilir.
  Ayrıntılar: https://firebase.google.com/support/privacy
- **Apple Haritalar (MapKit)**: harita görüntüleri ve yol tarifi. Apple'ın gizlilik politikası:
  https://www.apple.com/legal/privacy/
- **Apple DeviceCheck**: cihaz bütünlüğü doğrulaması.

## Haklarınız

KVKK ve GDPR kapsamında verilerinize erişme, düzeltilmesini ya da silinmesini isteme haklarınız vardır.
Uygulama sizi tanımlayan bir bilgi tutmadığından, bir işaretin kaldırılmasını istiyorsanız işaretin konumunu ve
yaklaşık zamanını bize yazmanız yeterlidir.

## Çocuklar

Uygulama çocuklara yönelik değildir ve bilerek çocuklardan kişisel veri toplamaz.

## İletişim

Veri sorumlusu: [ad / kurum]
E-posta: [iletişim e-postası]

Bu politikada değişiklik olursa bu sayfa güncellenir.
