# LUMOS - Olası Kullanım Senaryoları

Bu doküman, LUMOS'un görme engelli kullanıcıların günlük hayatta ve sosyal ortamlarda karşılaşabileceği küçük ama stresli krizleri nasıl çözebileceğini örnekler. Temel fikir, kullanıcının her şeyi tek başına tahmin etmek zorunda kalmaması; LUMOS'un kamera, mesafe, ışık, hareket ve çevre sensörlerinden kanıt toplayarak kısa, güvenli ve eyleme dönük cevap vermesidir.

## Sosyal Ortamdaki Küçük Krizler

### Üstümde fiyat etiketi kaldı mı?

Kullanıcı yeni aldığı kıyafetle dışarı çıkmadan önce sorar. ESP kamera yaka, kol ve bel çevresini kontrol eder; etiketi fark ederse konumuyla söyler.

Örnek cevap:

```text
Sol kolunun arkasında küçük bir etiket görünüyor.
```

### Çantam açık mı kaldı?

Kullanıcı kalabalık bir ortamda çantasının açık kalıp kalmadığını kontrol etmek ister. Kamera çantanın fermuarını veya kapağını inceler.

Örnek cevap:

```text
Çantanın üst fermuarı açık görünüyor.
```

### Yemeğim önümde mi, garson henüz getirmedi mi?

Restoranda kullanıcı önünde yemek olup olmadığını sorar. Kamera masayı kontrol eder ve tabak, bardak, peçete gibi nesneleri ayırır.

Örnek cevap:

```text
Önünde tabak yok, masada sadece bardak ve peçete var.
```

### Sessizce beni çağıran biri var mı?

Kullanıcı kalabalıkta birinin el sallayıp sallamadığını veya işaret edip etmediğini anlamak ister.

Örnek cevap:

```text
Sol tarafında biri elini kaldırmış gibi görünüyor.
```

### Kapının önünde mi bekliyorum, yoksa yolu mu kapatıyorum?

Kullanıcı bulunduğu yerin geçiş yolu olup olmadığını anlamak ister. Kamera kapı, koridor ve insan akışını; mesafe sensörü yakın engelleri değerlendirir.

Örnek cevap:

```text
Bulunduğun yer geçiş hattı gibi. Biraz sağa çekilmen daha rahat olabilir.
```

### Toplantıda bana gösterilen nesne hangisi?

Karşıdaki kişi "şunu imzala" veya "bunu al" dediğinde kullanıcı hangi nesnenin kastedildiğini sorar. Kamera masadaki nesneleri ve işaret edilen yönü analiz eder.

Örnek cevap:

```text
Önünde iki kağıt var. Parmak sağdaki belgeyi işaret ediyor gibi görünüyor.
```

### Sosyal mesafeyi fazla mı kapattım?

Kullanıcı karşısındaki kişiye çok yaklaşıp yaklaşmadığını anlamak ister. Mesafe sensörü ve kamera birlikte kullanılır.

Örnek cevap:

```text
Karşındaki kişiye oldukça yaklaşmışsın. Yarım adım geri durman daha rahat olabilir.
```

### Selfie'de herkes kadrajda mı?

Kullanıcı fotoğraf çekmeden önce kadrajı kontrol ettirir. Kamera yüzleri ve kadraj sınırlarını analiz eder.

Örnek cevap:

```text
Üç kişi kadrajda. Sağdaki kişinin yüzü biraz kesiliyor.
```

### Garson hesabı mı getirdi, menü mü?

Masaya bırakılan kağıdın ne olduğunu anlamak için kamera yazı ve düzeni inceler.

Örnek cevap:

```text
Bu menüden çok fiş veya hesap kağıdına benziyor.
```

### Elimdeki para doğru mu?

Kullanıcı banknotun değerini kontrol ettirmek ister. Kamera banknot üzerindeki değeri okumaya çalışır; para konusunda temkinli konuşur.

Örnek cevap:

```text
Yirmi lira gibi görünüyor, ama para konusunda lütfen gerekirse doğrulat.
```

### Birinin bana verdiği kart ne kartı?

Kullanıcı elindeki kartın ne olduğunu sorar. Kamera kart üzerindeki yazıyı ve tasarımı okur.

Örnek cevap:

```text
Bu bir ziyaret kartı gibi. Üzerinde doktor adı ve telefon numarası var.
```

### Yol tarif ederken insanlar hangi yönü işaret ediyor?

Kullanıcı karşıdaki kişinin el veya kol hareketinden yönü anlamak ister.

Örnek cevap:

```text
Kişi sağ ileriyi işaret ediyor gibi görünüyor.
```

### Saçımda toka var mı, gözlüğüm başımda mı?

Ayna veya karşı kamera görüntüsüyle kullanıcının üzerinde aradığı küçük aksesuarlar kontrol edilir.

Örnek cevap:

```text
Gözlüğün başında değil, yüzünde de görünmüyor.
```

### Bana ayrılan mikrofon nerede?

Toplantı, sahne veya sınıf ortamında kullanıcı konuşacağı mikrofonun yerini sorar.

Örnek cevap:

```text
Mikrofon masanın orta kısmında, sana göre biraz sol tarafta.
```

### Kuyruk hangi tarafta başlıyor?

Kullanıcı sıranın başlangıcını veya sonunu bulmak ister. Kamera insan dizilimini ve yönünü yorumlar.

Örnek cevap:

```text
Sıra sağ taraftan başlıyor gibi. Son kişi siyah montlu biri.
```

### Bir kutunun açma yeri nerede?

Kullanıcı ambalaj, kutu veya paketin açılacak yerini bulmak ister. Kamera bant, kapak veya çekme şeridini arar.

Örnek cevap:

```text
Açma bandı kutunun üst sağ kenarında.
```

### Masaya koyduğum bardak kenara çok yakın mı?

Kullanıcı bardağın dökülme veya düşme riski olup olmadığını sorar. Kamera masa kenarı ve bardak konumunu değerlendirir.

Örnek cevap:

```text
Bardak masanın kenarına yakın. Biraz içeri alman daha güvenli olur.
```

### Bir yere oturmadan önce sandalye temiz mi?

Kullanıcı sandalyede eşya, leke veya engel olup olmadığını kontrol ettirir.

Örnek cevap:

```text
Sandalyenin oturma kısmında belirgin bir eşya veya leke görünüyor.
```

### Yanlış kapıya mı elimi uzatıyorum?

Kullanıcı kapı üzerindeki yazıyı veya kapının işlevini sorar. Kamera tabela ve kapı üzerindeki metni okur.

Örnek cevap:

```text
Bu kapıda personel yazıyor. Giriş kapısı olmayabilir.
```

### Etkinlikte ismim listede var mı?

Kullanıcı kayıt masasında veya etkinlik girişinde listesini kontrol ettirir. Kamera listede adı arar.

Örnek cevap:

```text
Listede adın ikinci sütunda görünüyor.
```

## Günlük Bağımsızlık Senaryoları

### Kırmızı şapkamı bulamıyorum.

Kullanıcı evden çıkmadan önce kaybettiği eşyayı arar. LUMOS kullanıcıyla oda oda ilerler; her odada kamera görüntüsünü analiz eder.

Örnek cevap:

```text
Sağdaki sandalyenin üzerinde kırmızı bir şapka görünüyor.
```

### Hastaneye geldim ama girişi bulamıyorum.

Kullanıcı bina girişini veya doğru kapıyı bulmak ister. Kamera tabela, cam kapı, insan akışı ve giriş alanını analiz eder.

Örnek cevap:

```text
Ön tarafta geniş cam kapılar ve hastane tabelası görünüyor. Giriş büyük ihtimalle düz ileride.
```

### Asansör yukarı mı gidiyor, aşağı mı?

BME280 basınç trendi ve MPU6050 hareket verisi birlikte değerlendirilir.

Örnek cevap:

```text
Basınç azalıyor ve hareket algılanıyor. Büyük ihtimalle yukarı çıkıyorsun.
```

### Yağmur yağabilir mi?

İnternet yokken BME280 basınç ve nem trendi, ışık sensörüyle birlikte yorumlanır. Sistem kesin hava tahmini yapmaz; yalnızca yerel sensörlerden sınırlı çıkarım verir.

Örnek cevap:

```text
Kesin hava tahmini yapamam, ama basınç düşüyor ve nem yükseliyor. Bu yağmur ihtimalinin artmış olabileceğini gösterir.
```

### Önüm güvenli mi?

Mesafe sensörü, ışık sensörü, hareket sensörü ve gerekirse kamera birlikte kullanılır.

Örnek cevap:

```text
Önünde çok yakın bir engel algılanıyor. Şu an düz ilerleme.
```

### Oda havasız mı?

BME280 sıcaklık ve nem değerleri ortam konforu için yorumlanır.

Örnek cevap:

```text
Oda sıcak ve nemli. Havalandırmak iyi olabilir.
```

### Fotoğraf çekmek için ortam uygun mu?

Işık sensörü ve hareket sensörü kullanılır. ESP modülü çok sallanıyorsa veya ışık düşükse kullanıcı uyarılır.

Örnek cevap:

```text
Ortam loş ve modül biraz hareket ediyor. Daha net sonuç için bir saniye durup ışığa yönel.
```

## Proaktif Uyarı Senaryoları

### Sert darbe algılandı.

MPU6050 ani darbe veya düşme benzeri hareket algıladığında kullanıcı sormadan uyarı üretilebilir.

Örnek cevap:

```text
Sert bir darbe algıladım. İyi misin?
```

### Ortam bir anda karardı.

BH1750 veya TSL2561 ışık seviyesinde ani düşüş algılarsa sistem görsel analizin güvenilirliğinin azaldığını bildirir.

Örnek cevap:

```text
Ortam bir anda çok karardı. Kamera güvenilir olmayabilir.
```

### Çok yakın engel belirdi.

VL6180X belirlenen eşik altında mesafe ölçerse kullanıcıya durması söylenebilir.

Örnek cevap:

```text
Önünde çok yakın bir engel var. Durmanı öneririm.
```

### Sensör modülü bağlantısı koptu.

ESP modülü veri göndermeyi bıraktığında sistem kullanıcıyı yanıltmamak için bağlantı durumunu açıkça belirtir.

Örnek cevap:

```text
Sensör modülünden veri alamıyorum. Çevre hakkında güvenilir yorum yapamayabilirim.
```

## Savunma Cümlesi

LUMOS'un değeri yalnızca büyük görevleri çözmesinde değil, görme engelli kullanıcıların sosyal hayatta sık yaşadığı küçük belirsizlikleri azaltmasındadır. Kullanıcı bir restoranda, hastanede, toplantıda, markette veya evde tek bir kısa soru sorabilir; LUMOS gerekli tool'ları çağırıp kamera ve sensörlerden gelen kanıta dayalı, kısa ve güvenli bir cevap üretir.
