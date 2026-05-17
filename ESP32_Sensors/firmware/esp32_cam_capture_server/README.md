# ESP32-CAM Capture Server

This firmware turns the AI Thinker ESP32-CAM into a camera station connected to the ESPDuino local-only Wi-Fi network.

## Network

- Wi-Fi SSID: `ESP-SENSOR-HUB`
- Wi-Fi password: `localhub123`
- ESP32-CAM static IP: `192.168.4.10`
- Gateway: `192.168.4.1`

## Endpoints

- `GET /`: simple test page for a phone browser (includes Capture button and Status display).
- `GET /status`: camera and Wi-Fi status JSON (includes IP, RSSI, camera ready state).
- `GET /capture`: captures a fresh frame and returns it as `image/jpeg` (returns 503 if camera not ready, 500 on capture failure).

## Arduino IDE Settings

- Board: AI Thinker ESP32-CAM
- Upload Speed: `115200` or `921600`
- CPU Frequency: `240MHz`
- Flash Frequency: `80MHz`
- Partition Scheme: Huge APP if available
- PSRAM: Enabled

Connect the ESP32-CAM-MB adapter over USB, select the correct COM port, and upload the sketch.

## Camera Modes

The firmware automatically adapts based on PSRAM availability:

| Feature | With PSRAM | Without PSRAM |
| --- | --- | --- |
| Frame Size | VGA (640×480) | QVGA (320×240) |
| JPEG Quality | 10 | 12 |
| Frame Buffer Count | 2 | 1 |

If PSRAM is enabled in Arduino IDE settings but not soldered on the board, the code defaults to QVGA mode.

## WiFi Reconnection

The firmware retries WiFi connection every 5 seconds if disconnected. The camera will be unavailable (HTTP 503) until WiFi connects and the camera initializes.

## Phone Test

1. Upload the ESPDuino firmware first and confirm that `ESP-SENSOR-HUB` is active.
2. Open the Serial Monitor at `115200` baud to watch boot messages.
3. Upload the ESP32-CAM firmware.
4. Wait for the serial output to confirm WiFi connection and camera initialization.
5. Connect the phone to the `ESP-SENSOR-HUB` Wi-Fi network.
6. Prefer the hub proxy URLs: `http://192.168.4.1/camera/status` and `http://192.168.4.1/camera/capture`.
7. Direct camera URLs are also available for debugging: `http://192.168.4.10/status` and `http://192.168.4.10/capture`.

## Privacy

This system uses local HTTP and does not send data to the internet. The local AP and WPA2 password are the first privacy layer; HTTPS/TLS can be added later if needed.
