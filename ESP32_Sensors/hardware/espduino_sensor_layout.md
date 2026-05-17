# ESPDuino Sensor Layout

Bu plan ESPDuino-32 kartini sensor merkezi olarak kullanir. ESP32-CAM sadece kamera icin ayridir.

## Temel Pin Plani

| Gorev | ESPDuino pini | Baglanacak yer | Not |
| --- | --- | --- | --- |
| I2C SDA | GPIO21 | Tum I2C sensorlerin SDA pini | Ortak veri hatti |
| I2C SCL | GPIO22 | Tum I2C sensorlerin SCL pini | Ortak saat hatti |
| Analog ses | GPIO34 | CZN15E AO / analog output | ADC1, Wi-Fi ile cakismayan giris |
| Dijital ses | GPIO27 | CZN15E DO / digital output | Opsiyonel esik cikisi |
| Sensor gucu | 3V3 | Sensor VCC/VIN | Sensorleri 3.3V ile besle |
| Toprak | GND | Tum sensor GND pinleri | Ortak GND sart |

## I2C Sensor Baglantisi

Tum I2C sensorler paralel baglanir:

```text
ESPDuino GPIO21 SDA -> BME/BMP280 SDA
                     -> MPU6050 SDA
                     -> TSL2561 SDA
                     -> VL6180X SDA

ESPDuino GPIO22 SCL -> BME/BMP280 SCL
                     -> MPU6050 SCL
                     -> TSL2561 SCL
                     -> VL6180X SCL

ESPDuino 3V3        -> sensor VCC/VIN
ESPDuino GND        -> sensor GND
```

Baslangicta harici pull-up direnci takma. I2C taramasi kararsiz olursa SDA ve SCL hatlarina 3.3V'a dogru 4.7k pull-up ekle:

```text
GPIO21 SDA -> 4.7k -> 3V3
GPIO22 SCL -> 4.7k -> 3V3
```

## I2C Adres Plani

| Sensor | Hedef adres | Ayar |
| --- | --- | --- |
| MPU6050 | `0x68` | AD0 GND veya bos/default |
| BME/BMP280 | `0x76` veya `0x77` | Modulun SDO/adres ayarina gore |
| TSL2561 / GY-2561 | `0x39` veya `0x49` | `0x29` kullanma; VL6180X ile cakisir |
| VL6180X | `0x29` | Default adres |

Onemli: TSL2561 ve VL6180X ikisi de `0x29` olabilir. Bu projede `0x29` VL6180X'e ayrildi. TSL2561 adres pinini/padini `0x39` veya `0x49` olacak sekilde ayarla. Eger kart uzerinde adres secimi yoksa ikisini ayni I2C hattina birlikte takmadan once haberlesmeyi tek tek test et.

## CZN15E Ses Sensoru

CZN15E'nin uzerindeki pinleri netlestirmeden gucu 5V vermeyelim. Ilk tercih 3.3V besleme:

```text
CZN15E VCC -> ESPDuino 3V3
CZN15E GND -> ESPDuino GND
CZN15E AO  -> ESPDuino GPIO34
CZN15E DO  -> ESPDuino GPIO27  (opsiyonel)
```

Eger modul sadece 5V ile duzgun calisiyorsa AO/DO cikislarini dogrudan ESP32'ye baglama. Sinyal 3.3V seviyesine dusurulmeli.

## Fiziksel Yerlesim

- BME/BMP280'i ESP32-CAM, MT3608 ve regulatorlerden uzak tut. Isi olcumunu bozmasin.
- TSL2561 ve VL6180X disari bakacak sekilde, golgelenmeyecek bir noktada dursun.
- VL6180X'in onunde seffaf olmayan plastik, kablo veya kasa parcasi olmasin.
- MPU6050 cihaz govdesine sabit, titresimsiz ve eksenleri belli olacak sekilde yerlestirilsin.
- CZN15E mikrofon deligi dis ortama bakacak sekilde kenara yakin dursun.
- MT3608 guc modulu ile analog ses hattini fiziksel olarak ayir; analog kabloyu kisa tut.

## Baglama Sirasi

1. ESPDuino tek basina calissin ve `http://192.168.4.1/status` acilsin.
2. I2C hattina sadece MPU6050 bagla, `http://192.168.4.1/sensors` ile `0x68` gor.
3. BME/BMP280 ekle, `0x76` veya `0x77` gor.
4. TSL2561'i `0x39` veya `0x49` adresinde olacak sekilde ekle.
5. VL6180X'i ekle ve `0x29` gor.
6. CZN15E analog cikisini GPIO34'e bagla.
