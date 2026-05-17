# ESPDuino Sensor Hub

This firmware turns the ESPDuino-32 board into a local-only Wi-Fi access point and sensor HTTP server.

## Network

- SSID: `ESP-SENSOR-HUB`
- Password: `localhub123`
- Hub IP: `192.168.4.1`
- Expected ESP32-CAM IP: `192.168.4.10`

The phone and ESP32-CAM connect to this network. Data is not sent through the internet.

## Endpoints

- `GET /`: simple control page for the phone.
- `GET /status`: hub status JSON (requires `?token=...` if `API_TOKEN` is set).
- `GET /devices`: hub and camera addresses (requires `?token=...` if `API_TOKEN` is set).
- `GET /sensors`: all sensor readings as JSON (requires `?token=...` if `API_TOKEN` is set).
- `GET /camera/status`: proxied ESP32-CAM status (requires `?token=...` if `API_TOKEN` is set).
- `GET /camera/capture`: proxied ESP32-CAM JPEG capture (requires `?token=...` if `API_TOKEN` is set).

## Arduino IDE Settings

- Board: ESP32 Dev Module or the matching ESPDuino profile
- Upload Speed: `115200` or `921600`
- CPU Frequency: `240MHz`
- Flash Frequency: `80MHz`
- Partition Scheme: default is enough

## Wiring Notes

| Sensor | ESPDuino Pin | Note |
| --- | --- | --- |
| I2C SDA | GPIO 21 | Shared by BME/BMP280, MPU6050, TSL2561, VL6180X |
| I2C SCL | GPIO 22 | Shared I2C clock |
| Sound Analog (CZN15E) | GPIO 34 | Analog sound level input (ADC1) |
| Sound Digital (CZN15E) | GPIO 27 | Digital sound threshold output (optional) |
| 3V3 | 3V3 | Sensor power |
| GND | GND | Common ground for all boards and sensors |

Expected I2C addresses:

- BME/BMP280: `0x76` or `0x77`
- MPU6050: `0x68` or `0x69`
- TSL2561: `0x39` or `0x49` (avoid `0x29` — reserved for VL6180X)
- VL6180X: `0x29` (fixed address)

## Test Order

1. Upload the ESPDuino sketch.
2. Connect the phone to `ESP-SENSOR-HUB`.
3. Open `http://192.168.4.1/status`.
4. Open `http://192.168.4.1/sensors` and check the I2C device list.
5. Upload the ESP32-CAM sketch.
6. Test `http://192.168.4.1/camera/status` and `http://192.168.4.1/camera/capture`.
