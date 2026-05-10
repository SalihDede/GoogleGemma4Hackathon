# LUMOS - Proje Özeti

## Projenin Amacı

LUMOS, görme engelli kullanıcıların çevrelerini daha güvenli ve bağımsız şekilde anlamalarına yardımcı olmak için geliştirilen yapay zeka destekli bir mobil asistandır. Projenin temel hedefi, kullanıcının kamerası, sesi, konumu ve telefon işlevleriyle etkileşime girerek günlük hayatta ihtiyaç duyabileceği bilgileri doğal bir sohbet deneyimi içinde sunmaktır.

Uygulama, kullanıcının etrafındaki sahneyi yorumlayabilir, metinleri okuyabilir, nesneleri tarif edebilir, rota ve konum bilgisi sağlayabilir, rehberden kişi bulup arama akışını başlatabilir ve hatırlatıcı kurabilir. Bu özellikler özellikle görsel bilgiye erişimin zor olduğu durumlarda kullanıcıya pratik bir yardımcı olmayı amaçlar.

## Hedef Kullanıcı

Proje öncelikli olarak görme engelli veya az gören bireyler için tasarlanmıştır. Bu nedenle uygulamanın cevap dili, ekranda okunmaktan çok sesli olarak dinlenmeye uygun olacak şekilde kurgulanmıştır. LUMOS kısa, anlaşılır, yön tariflerinde konum odaklı ve gerektiğinde güvenlik uyarısı veren bir yardımcı gibi davranır.

## Neler Yapabiliyor?

### Görsel Anlama

- ESP 32 Cam üzerinden verilen görüntüleri analiz eder.
- Kullanıcının önündeki sahneyi doğal dille tarif eder.
- Nesnelerin yerini saat yönü mantığıyla anlatabilir.
- Kapı, sandalye, tabela, çıkış, engel gibi önemli unsurları belirtebilir.
- Görüntüdeki yazıları okumaya çalışır.
- Kullanıcının belirli bir nesneyi sorması durumunda o nesneye odaklanır.

### Sesli ve Yazılı Sohbet

- Kullanıcıyla sohbet ekranı üzerinden etkileşim kurar.
- Yanıtları akış halinde üretir.
- Modelin düşünme veya araç çağırma süreçlerini kullanıcı arayüzünde gösterebilir.
- Görme engelli kullanıcılar için sesli çıktı mantığına uygun kısa ve açık cevaplar üretir.

### Hibrit Yapay Zeka Çalışma Modeli

- İnternet bağlantısı varken bulut tabanlı model üzerinden hızlı yanıt verebilir.
- İnternet olmadığında cihaz üzerinde çalışan yerel Gemma modeliyle devam edebilir.
- Yerel model sayesinde temel yapay zeka deneyimi çevrimdışı kullanılabilir.
- Uygulama bağlantı durumuna göre bulut ve yerel model arasında yönlendirme yapar.

### Cihaz Üzerinde Model Kullanımı

- Gemma 4 E2B tabanlı LiteRT-LM modelini cihaz üzerinde çalıştırmayı hedefler.
- Model ilk kurulumda Hugging Face üzerinden indirilir.
- Model indirildikten sonra tekrar indirme gerekmeden yerel olarak kullanılabilir.
- CPU, GPU veya NPU gibi uygun cihaz backend'leri denenerek model çalıştırılır.
- Yetersiz RAM gibi durumlar için koruma ve hata yönetimi içerir.

### Araç Kullanımı

LUMOS yalnızca metin üretmekle kalmaz; bazı gerçek cihaz işlevlerini araçlar üzerinden çalıştırabilir:

- `describe_scene`: Sahneyi tarif eder.
- `read_text`: Görüntüdeki metni okumaya odaklanır.
- `identify_object`: Belirli bir nesneyi bulmaya çalışır.
- `get_location_info`: Konum veya yakın yer bilgisi sağlar.
- `get_directions`: Google Maps üzerinden rota görüntüsü oluşturup açıklatır.
- `search_contact`: Rehberde kişi arar.
- `make_call`: Kullanıcı onayından sonra telefon araması başlatır.
- `set_reminder`: Hatırlatıcı kurar.
- `get_date` ve `get_time`: Cihazdan tarih ve saat bilgisi alır.
- `cancel_action`: Navigasyon, hatırlatıcı veya sesli okuma gibi aktif işlemleri iptal eder.
- `internet_connection_status`: Telefonun Wi-Fi veya mobil veri üzerinden internete erişimi olup olmadığını döndürür.

### Güncel Offline Davranış Notları

- Tool çağrıları sohbet içinde ayrı ayrı saklanır ve her çağrı kendi kartıyla gösterilir.
- Yerel model tool adını düz metin olarak yazarsa uygulama bunu kullanıcıya göstermeden ilgili tool'u çalıştırmaya çalışır.
- "Şu an ne görüyorsun?", "Önümde ne var?" gibi görsel sorularda sensör tool'larına sapma olursa istek kamera yakalama akışına yönlendirilir.
- Sensör sonuçları modele ham `humidity_percent` veya `temperature_c` alanlarıyla değil, önce doğal dilli bir `summary` alanıyla verilir. Böylece cevapta "nem yüzde kırk altı" gibi okunabilir ifadeler hedeflenir.
- Offline hava ve kıyafet sorularında LUMOS resmi hava durumu tahmini yaptığını iddia etmez; yalnızca telefondaki/harici sensördeki yerel sıcaklık, nem, ışık ve gerekirse kamera kanıtına göre pratik öneri verir.
- Modelin düşünme metni sınırlanır; final cevapta taslak, kontrol listesi veya kendi kendini düzeltme metni gösterilmemesi hedeflenir.
- Cevap başında gereksiz "Lumos," ifadesi temizlenir; bu TTS çıktısının daha doğal duyulmasını sağlar.
- `appIcon.png` kaynak alınarak Android ve iOS uygulama ikonları güncellendi; Android adaptive icon inset değeri daha büyük logo görünümü için düşürüldü.

### Rehber ve Arama Desteği

Kullanıcı bir kişiyi aramak istediğinde uygulama doğrudan numara uydurmaz. Önce cihaz rehberinde arama yapar. Tek kişi bulunursa kullanıcıdan onay ister. Birden fazla kişi bulunursa seçenekleri listeler ve kullanıcının seçim yapmasını bekler. Arama işlemi Android tarafındaki native MethodChannel entegrasyonu ile gerçekleştirilir.

### Konum ve Rota Desteği

Uygulama kullanıcının konumunu alabilir, yakın yerleri sorgulayabilir ve Google Maps tabanlı rota bilgisi oluşturabilir. Rota ekran görüntüsü model tarafından yorumlanarak görme engelli kullanıcıya adım adım anlatılabilir. Aktif navigasyon sırasında belirli aralıklarla rota güncellemesi yapılması için bir döngü de bulunur.

## Nasıl Çalışıyor?

### 1. İlk Kurulum

Uygulama açıldığında kullanıcıya iki seçenek sunulur:

- Bulut modunu kullanmak
- Yerel Gemma modelini indirip cihaz üzerinde çalıştırmak

Yerel model seçilirse yaklaşık 2.4 GB boyutundaki `gemma-4-E2B-it.litertlm` modeli indirilir ve aktif model olarak hazırlanır. Sonraki açılışlarda bu işlem tekrar yapılmaz.

### 2. Kullanıcı Girdisi

Kullanıcı metin, ses veya görüntü tabanlı bir istek gönderebilir. Örneğin:

- "Önümde ne var?"
- "Bu yazıyı oku."
- "Kapı nerede?"
- "Yakınımdaki eczaneyi bul."
- "Annemi ara."
- "On dakika sonra ilacımı hatırlat."

Bu istek sohbet sağlayıcısı tarafından alınır ve uygun yapay zeka akışına gönderilir.

### 3. Akıllı Yönlendirme

`InferenceRouter`, isteğin hangi model tarafında çalışacağını belirler:

- Bulut modu seçiliyse ve internet varsa OpenRouter üzerinden bulut modeline gider.
- Bulut modu seçili ama internet yoksa yerel model hazırsa yerel modele düşer.
- Yerel mod seçiliyse cihaz üzerindeki LiteRT/Gemma modeli kullanılır.

Bu yapı, uygulamanın hem hızlı bulut yanıtlarından yararlanmasını hem de internet olmadığında çalışmaya devam edebilmesini sağlar.

### 4. Modelin Yanıt Üretmesi

Model kullanıcının mesajını işler ve yanıtı stream olarak üretir. Yanıt parçaları uygulamada anlık olarak gösterilir. Model gerektiğinde normal metin cevabı üretmek yerine bir araç çağırabilir. Örneğin kullanıcı "Annemi ara" dediğinde model `search_contact` aracını çağırabilir.

### 5. Araçların Çalışması

Araç çağrıları `ToolRunner` tarafından çalıştırılır. Araçlar cihaz kaynaklarına veya harici servislere erişebilir:

- Rehber için `flutter_contacts`
- Konum için `geolocator`
- Harita ve rota için WebView tabanlı servisler
- Arama için Android native `MethodChannel`
- Hatırlatıcı için uygulama içi zamanlayıcı ve bildirim/ses servisi

Araç sonucu tekrar sohbete bağlanır ve kullanıcıya anlaşılır bir cevap olarak sunulur.

### 6. Cevabın Kullanıcıya Sunulması

Yanıt sohbet arayüzünde gösterilir. Uygulama, görme engelli kullanıcı deneyimine uygun şekilde kısa, doğrudan, konum odaklı ve sesli okumaya elverişli cevaplar üretmeye çalışır.

## Teknik Mimari

### Flutter Katmanı

Uygulamanın ana arayüzü Flutter ile geliştirilmiştir. Durum yönetimi için Riverpod kullanılır. Sohbet ekranı, kurulum ekranı, mesaj balonları, araç çağrısı kartları ve düşünme bölümleri Flutter widget'ları olarak yapılandırılmıştır.

Öne çıkan dosyalar:

- `lib/main.dart`
- `lib/screens/setup_screen.dart`
- `lib/screens/chat_screen.dart`
- `lib/providers/chat_provider.dart`
- `lib/services/inference_router.dart`
- `lib/services/litert_service.dart`
- `lib/services/cloud_inference_service.dart`
- `lib/services/tool_runner.dart`

### Yerel Model Katmanı

Yerel model çalıştırma tarafında `flutter_gemma` paketi kullanılır. `LiteRtService`, aktif modeli yükler, chat oturumu oluşturur, görsel desteği açar, function calling araçlarını modele tanıtır ve yanıtları stream olarak uygulamaya iletir.

Model yapılandırması:

- Model tipi: Gemma 4
- Dosya tipi: LiteRT-LM `.litertlm`
- Görsel destek: Var
- Function calling desteği: Var
- Maksimum token bağlamı: 4096
- Backend sırası: Cihaza göre NPU, GPU veya CPU

### Bulut Model Katmanı

Bulut tarafında OpenRouter API kullanılır. `CloudInferenceService`, mesaj geçmişini, görsel girdiyi, araç tanımlarını ve stream yanıtları yönetir. Bulut modeli araç çağırdığında ilgili araç çalıştırılır, sonucu modele geri verilir ve final cevap üretilir.

### Android Native Katmanı

Android tarafında `MainActivity.kt`, Flutter ile native Android arasında `com.lumos/call` kanalı kurar. Bu kanal üzerinden telefon araması başlatılır. Önce doğrudan arama denenir; izin yoksa Android arama ekranı numara doldurulmuş şekilde açılır.

### İnternet Bağlantısı Tool'u

LUMOS'a eklenmesi planlanan sade araçlardan biri `internet_connection_status` tool'udur. Bu tool'un görevi yalnızca telefonun internete erişimi olup olmadığını ve erişim türünü döndürmektir.

Bu tool şu bilgileri sağlayabilir:

- İnternet erişimi var mı?
- Bağlantı türü Wi-Fi mı?
- Bağlantı türü mobil veri mi?
- Bağlantı var gibi görünse bile gerçek internet erişimi çalışıyor mu?

Örnek tool sonucu:

```json
{
  "has_internet": true,
  "connection_type": "wifi"
}
```

Olası değerler:

- `connection_type: "wifi"`: Telefon Wi-Fi üzerinden internete erişiyor.
- `connection_type: "mobile"`: Telefon mobil veri üzerinden internete erişiyor.
- `connection_type: "none"`: Aktif internet erişimi yok.
- `has_internet: true`: Gerçek internet erişimi doğrulandı.
- `has_internet: false`: İnternet erişimi yok veya doğrulama başarısız.

Bu araç özellikle modelin bulut/yerel kararlarını açıklamak, internet gerektiren işlemlerde kullanıcıyı uyarmak ve harita/konum gibi online özelliklerin çalışıp çalışmayacağını net söylemek için kullanılabilir.

## Planlanan Harici Sensör Desteği

LUMOS'un bir sonraki geliştirme adımlarından biri, harici sensör modülleriyle çevresel farkındalığını artırmaktır. Bu sensörler doğrudan telefona değil, ESP32 veya benzeri bir mikrodenetleyiciye bağlanacak şekilde düşünülmüştür. Mikrodenetleyici sensörleri I2C üzerinden okuyacak, ardından verileri Bluetooth BLE, Wi-Fi veya USB serial üzerinden Flutter uygulamasına gönderecektir.

Planlanan sensörler:

- `TSL2561 / GY-2561`: Kızılötesi ve görünür ışık ölçümü, lux değeri, ortam parlaklığı analizi.
- `VL6180X`: Kısa mesafe Time-of-Flight ölçümü, çok yakın engel algılama, proximity bilgisi.
- `BME280`: Sıcaklık, nem, atmosfer basıncı ve yaklaşık yükseklik değişimi.
- `MPU6050`: İvme, gyro, cihaz eğimi, hareket, sarsıntı ve düşme benzeri olayların algılanması.
- `BH1750 / GY-302`: Ortam ışık yoğunluğu, lux bazlı parlaklık ölçümü.

Bu sensörlerle LUMOS yalnızca kamera görüntüsünü yorumlayan bir asistan olmaktan çıkarak, kullanıcının bulunduğu ortamı fiziksel sensör verileriyle de anlayabilen daha güçlü bir yardımcıya dönüşebilir.

### Sensör Verilerinden Alınabilecek Bilgiler

Harici sensör sistemiyle şu veriler çekilebilir:

- Ortamın karanlık, loş, normal, parlak veya aşırı parlak olup olmadığı.
- Kamera analizi için ışığın yeterli olup olmadığı.
- Sensörün önünde çok yakın bir engel bulunup bulunmadığı.
- Ortam sıcaklığı ve nem seviyesi.
- Basınç değişimine göre yaklaşık yükseklik veya kat değişimi.
- Cihazın sabit mi, hareketli mi, eğik mi veya sarsılmış mı olduğu.
- Düşme, ani hareket veya cihazın fotoğraf çekmek için yeterince stabil olup olmadığı.

Bu bilgiler özellikle görme engelli kullanıcılar için önemlidir. Kullanıcı yalnızca "Önüm güvenli mi?", "Burası karanlık mı?", "Telefon sabit mi?" veya "Ortam nasıl?" diye sorabilir; LUMOS gerekli sensör verilerini arka planda toplayıp anlaşılır bir cevap üretebilir.

### Sensör Tool Mimarisi

Sensörleri modele doğrudan ham donanım adlarıyla açmak yerine, kullanıcı niyetine göre anlamlı tool'lar tanımlanması planlanmaktadır. Yani model `read_bme280` veya `read_mpu6050` gibi düşük seviyeli araçlar yerine, kullanıcının sorusunu cevaplayan daha anlamlı araçlar çağıracaktır.

Planlanan tool seti:

- `check_sensor_context`: Tüm harici sensörlerden birleşik bir çevre özeti alır. Kullanıcı genel güvenlik veya çevre farkındalığı sorusu sorduğunda önce bu tool çağrılır.
- `measure_brightness`: Ortam ışığını lux olarak ölçer ve karanlık/parlaklık sınıflandırması yapar.
- `detect_near_obstacle`: VL6180X üzerinden çok yakın engel olup olmadığını kontrol eder.
- `get_environment_status`: BME280 üzerinden sıcaklık, nem, basınç ve konfor durumunu döndürür.
- `detect_motion_state`: MPU6050 üzerinden cihazın hareket, eğim, sarsıntı ve stabilite durumunu analiz eder.

Bu yapı sayesinde model gerekli gördüğünde birden fazla tool'u sırayla çağırabilir. Örneğin kullanıcı "Şu an çevrem güvenli mi?" dediğinde LUMOS önce genel sensör bağlamını alabilir, ardından ışık seviyesi düşükse `measure_brightness`, çok yakın bir engel ihtimali varsa `detect_near_obstacle` aracını ayrıca çağırabilir.

Örnek tool davranışları:

- "Ortam karanlık mı?" sorusunda `measure_brightness` çağrılır.
- "Önümde engel var mı?" sorusunda `detect_near_obstacle` çağrılır.
- "Hava sıcak mı?" sorusunda `get_environment_status` çağrılır.
- "Telefon sabit mi?" sorusunda `detect_motion_state` çağrılır.
- "Çevrem güvenli mi?" gibi genel bir soruda `check_sensor_context` çağrılır ve gerekirse diğer araçlarla detaylandırılır.

### Toolset ve Responder Agent Mantığı

LUMOS mimarisinde kamera, sensörler, internet durumu, konum, rehber, arama ve hatırlatıcı gibi tüm yetenekler aynı genel `Toolset` içinde düşünülür. Kamera da bu yapıda bir tool'dur; diğer sensörlerden ayrı veya her zaman zorunlu bir kaynak değildir.

Responder agent, kullanıcı sorgusunu aldıktan sonra cevabı üretmek için hangi tool'lara ihtiyaç olduğunu belirler. Eğer soru basit bir selamlaşma veya genel sohbet ise hiçbir tool çağırmadan cevap verebilir. Eğer cevap güncel fiziksel çevre, cihaz durumu, bağlantı, konum veya kullanıcı güvenliğiyle ilgiliyse yalnızca gerekli tool'ları çağırır.

Genel akış:

```text
User Query
    │
    ▼
Responder Agent
    │  kullanıcının niyetini anlar
    │  gerekli tool'ları seçer
    ▼
Toolset
    │  kamera, sensörler, internet, konum, rehber, arama, hatırlatıcı
    ▼
Tool Results
    │
    ▼
Responder Agent
    │  sonuçları birleştirir
    ▼
Final Response
```

Örnek tool seçimleri:

- "Merhaba" sorusunda tool çağrılmaz.
- "Ortam karanlık mı?" sorusunda `measure_brightness` çağrılır.
- "Önümde engel var mı?" sorusunda `detect_near_obstacle` çağrılır.
- "Önümde ne var?" sorusunda kamera tabanlı sahne anlama tool'u çağrılır.
- "Yürüyebilir miyim?" sorusunda `detect_near_obstacle`, `measure_brightness`, `detect_motion_state` ve gerekirse kamera tool'u birlikte kullanılabilir.
- "İnternet var mı?" sorusunda `internet_connection_status` çağrılır.
- "Annemi ara" sorusunda `search_contact`, onay sonrasında `make_call` çağrılır.

Bu yaklaşımda temel prensip şudur: LUMOS tahmin etmek yerine gerektiğinde tool çağırır, fakat gereksiz tool çağırmaz. Kamera dahil tüm veri kaynakları yalnızca kullanıcının niyetini cevaplamak için gerekli olduğunda kullanılır.

### Proaktif Anomali Algılama Akışı

LUMOS yalnızca kullanıcı soru sorduğunda çalışan bir asistan olarak değil, donanım seviyesinde oluşan önemli olayları fark edebilen proaktif bir sistem olarak da tasarlanabilir. Harici sensörlerden gelen bazı sinyaller doğrudan bir kullanıcı sorgusu olmadan da risk veya anomali gösterebilir.

Örneğin:

- MPU6050 ani darbe veya düşme benzeri hareket algılayabilir.
- VL6180X sensörün önünde çok yakın bir engel algılayabilir.
- BH1750 veya TSL2561 ışığın aniden kaybolduğunu gösterebilir.
- BME280 hızlı basınç değişimiyle asansör veya kat değişimi ihtimali verebilir.
- ESP32 veya sensör bağlantısı koparsa donanım iletişim hatası oluşabilir.

Bu durumda sistem bir "hardware level interrupt" üretir. Bu interrupt, zaman damgası ve ilgili sensör sinyaliyle birlikte anomali akışını başlatır.

Planlanan anomali akışı:

```text
Hardware Level Interrupt
    │
    │ timestamp + sensor signal
    ▼
Anomaly Analyzer
    │  olası sebepleri çıkarır
    ▼
Investigation Planner
    │  doğrulama için gerekli tool'ları belirler
    ▼
Toolset
    │  ilgili kamera/sensör/bağlantı tool'ları çağrılır
    ▼
Risk Evaluator
    │  tool sonuçlarından mantıklı risk sonucu üretir
    ▼
User Responder
    │  kullanıcıya kısa, güvenli ve eyleme dönük uyarı verir
```

Bu akışta her anomali için kamera kullanılmak zorunda değildir. Kamera da diğerleri gibi yalnızca gerekli olduğunda çağrılan bir tool'dur. Örneğin ışık seviyesi aniden düştüğünde yalnızca ışık sensörü yeterli olabilir; düşme şüphesinde ise hareket sensörü, yakın engel sensörü ve gerekirse kamera birlikte kullanılabilir.

Örnek anomali senaryoları:

#### Ani Darbe veya Düşme

MPU6050 yüksek ivme ve sert darbe algıladığında sistem kullanıcının düşmüş olabileceğini veya telefonun yere düşmüş olabileceğini değerlendirir.

Olası tool çağrıları:

- `detect_motion_state`
- `detect_near_obstacle`
- `measure_brightness`
- Gerekirse kamera tabanlı sahne anlama tool'u

Olası kullanıcı yanıtı:

```text
Sert bir darbe algıladım. İyi misin? Yardım istememi istersen söyle.
```

#### Çok Yakın Engel

VL6180X belirli bir eşik değerinin altında mesafe ölçerse sistem yakın engel uyarısı üretebilir.

Olası tool çağrıları:

- `detect_near_obstacle`
- `detect_motion_state`
- Gerekirse kamera tabanlı sahne anlama tool'u

Olası kullanıcı yanıtı:

```text
Önünde çok yakın bir engel algıladım. Şu an düz ilerleme; önce durup telefonu biraz yana çevir.
```

#### Işığın Aniden Kaybolması

BH1750 veya TSL2561 lux değerinde ani düşüş algılarsa sistem ortamın karardığını veya sensörün kapanmış olabileceğini değerlendirir.

Olası tool çağrıları:

- `measure_brightness`
- `detect_motion_state`
- Gerekirse kamera tabanlı sahne anlama tool'u

Olası kullanıcı yanıtı:

```text
Ortam bir anda çok karardı. Kamera veya görsel analiz güvenilir olmayabilir. Olduğun yerde durup ışık kaynağına yönelmen daha güvenli olur.
```

#### Basınç Değişimi

BME280 hızlı basınç değişimi algılarsa sistem kullanıcının asansörde, merdivende veya farklı bir kata geçiyor olabileceğini değerlendirebilir.

Olası tool çağrıları:

- `get_environment_status`
- `detect_motion_state`

Olası kullanıcı yanıtı:

```text
Basınç değişimine göre yukarı veya aşağı hareket etmiş olabilirsin. Bu asansör ya da kat değişimiyle ilişkili olabilir.
```

Bu proaktif yapı sayesinde LUMOS yalnızca soru cevaplayan bir uygulama değil, çevresel ve donanımsal değişimleri izleyip kullanıcı güvenliği için gerektiğinde uyarı üretebilen bir erişilebilirlik ajanı haline gelir.

### Sensör Veri Akışı

Planlanan veri akışı şu şekildedir:

```text
Harici sensörler
    │
    ▼
ESP32 veya benzeri mikrodenetleyici
    │  I2C üzerinden sensör okuma
    ▼
Bluetooth BLE / Wi-Fi / USB serial
    │
    ▼
Flutter SensorHubService
    │  son sensör snapshot'ını tutar
    ▼
ToolRunner
    │  modelin çağırdığı sensor tool'larını çalıştırır
    ▼
LUMOS yanıtı
```

Mikrodenetleyiciden Flutter tarafına örnek sensör snapshot'ı şu formatta gelebilir:

```json
{
  "lux": 184.5,
  "infrared": 52,
  "distance_mm": 86,
  "temperature_c": 25.8,
  "humidity_percent": 48.2,
  "pressure_hpa": 1009.4,
  "accel": {
    "x": 0.01,
    "y": 0.04,
    "z": 0.98
  },
  "gyro": {
    "x": 0.2,
    "y": -0.1,
    "z": 0.0
  }
}
```

Bu snapshot, `SensorHubService` tarafından tutulur. Tool çağrıldığında doğrudan en güncel snapshot okunur ve modelin anlayacağı şekilde yapılandırılmış sonuç döndürülür.

### Sensörlerle Oluşacak Yeni Kullanım Senaryoları

Harici sensör desteği eklendiğinde LUMOS şu yeni senaryolarda daha güçlü hale gelir:

- Kullanıcı karanlık bir alana girdiğinde bunu fark edip uyarabilir.
- Kamera analizi için ışığın yetersiz olduğunu söyleyebilir.
- Cihazın önünde çok yakın bir engel varsa kısa mesafe uyarısı verebilir.
- Telefon çok hareketliyse fotoğraf çekmeden önce sabit tutmayı önerebilir.
- Ortam çok sıcak, nemli veya konforsuzsa bunu kullanıcıya bildirebilir.
- Basınç değişimiyle asansör veya kat değişimi gibi durumları tahmin etmek için ek bağlam sağlayabilir.
- Kamera görüntüsü ile fiziksel sensör verisini birleştirerek daha güvenilir çevre açıklaması yapabilir.

## Güvenlik ve Erişilebilirlik Yaklaşımı

LUMOS, görme engelli kullanıcılar için geliştirildiği için bazı güvenlik kurallarına sahiptir:

- Tehlikeli sahnelerde kesin yönlendirme yapmak yerine kullanıcıyı uyarır.
- İlaç, doz, para, son kullanma tarihi veya alerjen gibi yüksek riskli konularda kesinlik iddiasından kaçınır.
- Telefon aramalarında kullanıcı onayı olmadan arama başlatmaması hedeflenir.
- Numara uydurmaz; rehberden arama yapar veya kullanıcının söylediği numarayı kullanır.
- Görsel tariflerde "gördüğünüz gibi" yerine kullanıcının konumuna göre "önünüzde", "sağınızda", "iki adım ileride" gibi ifadeler kullanır.

## Projenin Hackathon Değeri

Bu proje, yapay zekayı yalnızca sohbet eden bir sistem olarak değil, gerçek mobil cihaz yetenekleriyle birleşen erişilebilirlik odaklı bir yardımcı olarak ele alır. En güçlü tarafı, hibrit mimarisidir: internet varsa buluttan hızlı ve güçlü yanıt alabilir, internet yoksa yerel Gemma modeliyle çalışmaya devam edebilir.

LUMOS, görsel algılama, sesli etkileşim, konum, rota, rehber, arama ve hatırlatıcı özelliklerini tek bir asistan deneyiminde birleştirerek görme engelli kullanıcıların günlük yaşamındaki küçük ama kritik anlara destek olmayı amaçlar.

## Kısa Özet

LUMOS, görme engelli kullanıcılar için geliştirilmiş Flutter tabanlı bir mobil yapay zeka asistanıdır. Kamera görüntülerini anlayabilir, metin okuyabilir, nesne ve sahne tarif edebilir, konum ve rota bilgisi sağlayabilir, rehberden kişi bulup arama başlatabilir ve hatırlatıcı kurabilir. Bulut modeliyle hızlı çalışabilir; yerel Gemma LiteRT modeliyle internet olmadan da temel yapay zeka yeteneklerini sürdürebilir.
