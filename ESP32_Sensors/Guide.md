# ESP32 Sensör Envanteri

Bu liste, eldeki parçaların projede ne işe yaradığını kısa şekilde özetler.

## Ana Kartlar

| Parça | Ne için kullanılır? |
| --- | --- |
| ESP32-CAM | Kamera görüntüsü almak, Wi-Fi üzerinden görüntü/telemetri göndermek, küçük görüntü işleme denemeleri yapmak için. |
| ESP32-CAM-MB | ESP32-CAM'i USB üzerinden programlamak ve seri porttan debug almak için kullanılan adaptör kartı. |
| ESP32 Duino | Sensörleri okumak, verileri işlemek ve Wi-Fi/Bluetooth ile haberleşmek için ana geliştirme kartı. |

## Sensörler

| Parça | Ne için kullanılır? |
| --- | --- |
| VL6180X | Kısa mesafeli uzaklık/yakınlık ölçümü ve ortam ışığı algılama için. |
| CZN15E | Muhtemelen elektret mikrofon/ses algılama bileşeni; ortam sesi veya ses tetikleme için. Üzerindeki yazı/fotoğrafla netleştirilmeli. |
| MPU6050 | İvme ve jiroskop ölçümü için; hareket, eğim, titreşim ve yönelim takibi yapılabilir. |
| TSL2561 / GY-2561 | Ortam ışık şiddetini lux cinsinden ölçmek için. |
| BME280 / BMP280 | Sıcaklık ve hava basıncı ölçümü için. BME280 varsa ek olarak nem de ölçer; BMP280 nem ölçmez. |

## Güç ve Enerji

| Parça | Ne için kullanılır? |
| --- | --- |
| MT3608 | Pil voltajını yükseltmek için kullanılan step-up voltaj dönüştürücü. |
| Li-ion 18650 2200mAh pil | Taşınabilir güç kaynağı olarak kullanılır. Listede 16850 yazıyor; büyük ihtimalle 18650 pil. |
| Pil yuvası | 18650 pili devreye güvenli ve sökülebilir şekilde bağlamak için. |
| Pil korumalı şarj kartı | Li-ion pili USB'den şarj etmek ve aşırı deşarj/aşırı akım gibi durumlara karşı korumak için. Genelde TP4056 tabanlı olur. |

## Pasif Devre Elemanları

| Parça | Ne için kullanılır? |
| --- | --- |
| 1000uF 16V elektrolitik kondansatör | Besleme hattındaki ani akım değişimlerini yumuşatmak ve voltaj düşmelerini azaltmak için. |
| 2200uF 16V kondansatör | Daha büyük güç tamponlama için; motor, kamera veya Wi-Fi akım sıçramalarında yardımcı olabilir. |
| 100nF / 0.1uF seramik kondansatör | Entegre ve sensörlerin besleme pinlerine yakın konularak parazit filtreleme için. |
| 4.7k ohm dirençler | I2C hatlarında pull-up direnci, buton/lojik hatlarında yardımcı direnç olarak kullanılabilir. |
| 2.2k ohm dirençler | Daha güçlü pull-up gereken I2C hatları veya genel sinyal hatları için kullanılabilir. |

## Montaj ve Prototipleme

| Parça | Ne için kullanılır? |
| --- | --- |
| Delikli pertinaks / bakırlı plaket | Devreyi breadboard dışına alıp daha kalıcı prototip yapmak için. |
| Erkek-dişi header seti | Modülleri sökülebilir bağlamak, kartlara pin çıkışı eklemek ve jumper bağlantısı yapmak için. |
| Kaliteli lehim pastası | Lehimleme kalitesini artırmak, oksitlenmeyi azaltmak ve lehimin yüzeye daha iyi yayılmasını sağlamak için. |
| Lehim emme fitili/pompası | Hatalı lehimleri temizlemek ve pinleri sökmek için. |

## Ölçüm ve Test

| Parça | Ne için kullanılır? |
| --- | --- |
| Dijital multimetre | Voltaj, direnç, süreklilik ve temel akım kontrolleri için. |
| USB akım/gerilim ölçer | USB hattından beslenen devrelerin çektiği akımı ve aldığı voltajı hızlıca görmek için. |

