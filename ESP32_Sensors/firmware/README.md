# Local HTTP Architecture

This firmware set keeps sensor and camera data on the local Wi-Fi network. It does not use cloud services, MQTT brokers, or an internet connection.

## Roles

```text
ESPDuino-32
  - Opens the local Wi-Fi AP: ESP-SENSOR-HUB
  - Serves sensor HTTP endpoints
  - IP: 192.168.4.1

ESP32-CAM
  - Connects to the ESP-SENSOR-HUB network
  - Serves camera HTTP endpoints
  - IP: 192.168.4.10

Phone
  - Connects to ESP-SENSOR-HUB
  - Reaches hub and camera endpoints from the browser or app
```

## Endpoint Map

| Device | URL | Purpose | Requires Token |
| --- | --- | --- | --- |
| ESPDuino | `http://192.168.4.1/` | Simple control page | No |
| ESPDuino | `http://192.168.4.1/status` | Hub status (IP, SSID, stations) | Yes |
| ESPDuino | `http://192.168.4.1/devices` | Hub and camera addresses | Yes |
| ESPDuino | `http://192.168.4.1/sensors` | All sensor readings (I2C scan, BME/BMP, MPU6050, TSL2561, VL6180X, CZN15E) | Yes |
| ESPDuino | `http://192.168.4.1/camera/status` | Proxied ESP32-CAM status | Yes |
| ESPDuino | `http://192.168.4.1/camera/capture` | Proxied ESP32-CAM JPEG capture | Yes |
| ESP32-CAM | `http://192.168.4.10/` | Camera test page (Status & Capture buttons) | No |
| ESP32-CAM | `http://192.168.4.10/status` | Camera status (IP, WiFi RSSI, camera ready state) | No |
| ESP32-CAM | `http://192.168.4.10/capture` | Instant JPEG photo (returns 503 if not ready) | No |

## Setup Order

1. Wire the ESPDuino-32 to power and sensors (see [hardware/espduino_sensor_layout.md](../hardware/espduino_sensor_layout.md)).
2. Upload the `espduino_sensor_hub` sketch to the ESPDuino-32 board.
3. Open Serial Monitor (`115200` baud) to watch initialization messages.
4. Connect the phone to the `ESP-SENSOR-HUB` Wi-Fi network.
5. Test the hub with `http://192.168.4.1/status`.
6. Check sensor discovery with `http://192.168.4.1/sensors` (I2C scan shows detected addresses).
7. Upload the `esp32_cam_capture_server` sketch to the ESP32-CAM.
8. Wait for the ESP32-CAM to connect to the network (watch Serial Monitor).
9. Test the camera through the hub with `http://192.168.4.1/camera/status`.
10. Capture a photo through the hub with `http://192.168.4.1/camera/capture`.

### Expected Sensors

The hub automatically detects these sensors on the I2C bus:

- **BME280/BMP280** (address `0x76` or `0x77`) — temperature, pressure, humidity (BME280 only)
- **MPU6050** (address `0x68` or `0x69`) — accelerometer, gyroscope, temperature
- **TSL2561** (address `0x39` or `0x49`) — ambient light level (lux)
- **VL6180X** (address `0x29`) — distance, ambient light
- **CZN15E** (GPIO 34 analog, GPIO 27 digital) — sound level

If a sensor is not detected, check I2C address conflicts using the `http://192.168.4.1/sensors` I2C scan.

## Authentication

By default, endpoints are open (no token required). For optional URL-based authentication:

1. Set `API_TOKEN = "your-secret-token"` in `espduino_sensor_hub.ino` (line 21)
2. Access protected endpoints with: `http://192.168.4.1/sensors?token=your-secret-token`
3. Leave empty string `""` to disable token protection

Protected endpoints (when token is enabled): `/status`, `/devices`, `/sensors`, `/camera/status`, `/camera/capture`.

## Privacy

Data stays inside the local AP. To change the AP password, update the `localhub123` value in both sketches.

The system uses local HTTP only and does not send data to the internet. HTTPS/TLS can be added later if needed.
