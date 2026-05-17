#include "esp_camera.h"
#include <WiFi.h>
#include "esp_http_server.h"

const char *STA_SSID = "ESP-SENSOR-HUB";
const char *STA_PASSWORD = "localhub123";

IPAddress localIp(192, 168, 4, 10);
IPAddress gateway(192, 168, 4, 1);
IPAddress subnet(255, 255, 255, 0);

// AI Thinker ESP32-CAM pin map.
#define PWDN_GPIO_NUM 32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 0
#define SIOD_GPIO_NUM 26
#define SIOC_GPIO_NUM 27

#define Y9_GPIO_NUM 35
#define Y8_GPIO_NUM 34
#define Y7_GPIO_NUM 39
#define Y6_GPIO_NUM 36
#define Y5_GPIO_NUM 21
#define Y4_GPIO_NUM 19
#define Y3_GPIO_NUM 18
#define Y2_GPIO_NUM 5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM 23
#define PCLK_GPIO_NUM 22

httpd_handle_t server = nullptr;
bool cameraReady = false;
unsigned long lastReconnectAttemptMs = 0;

static esp_err_t captureHandler(httpd_req_t *req)
{
  if (!cameraReady) {
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_status(req, "503 Service Unavailable");
    return httpd_resp_sendstr(req, "{\"ok\":false,\"error\":\"camera_not_ready\"}");
  }

  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("Capture failed: esp_camera_fb_get returned null");
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_status(req, "500 Internal Server Error");
    return httpd_resp_sendstr(req, "{\"ok\":false,\"error\":\"capture_failed\"}");
  }

  Serial.printf("Capture OK: %u bytes\n", fb->len);

  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
  httpd_resp_set_hdr(req, "Content-Disposition", "inline; filename=capture.jpg");

  esp_err_t result = httpd_resp_send(req, (const char *)fb->buf, fb->len);
  esp_camera_fb_return(fb);
  return result;
}

static esp_err_t statusHandler(httpd_req_t *req)
{
  String json = "{";
  json += "\"ok\":true";
  json += ",\"device\":\"esp32-cam\"";
  json += ",\"role\":\"camera_station\"";
  json += ",\"mode\":\"sta\"";
  json += ",\"ssid\":\"";
  json += STA_SSID;
  json += "\"";
  json += ",\"wifi_connected\":";
  json += (WiFi.status() == WL_CONNECTED ? "true" : "false");
  json += ",\"ip\":\"";
  json += WiFi.localIP().toString();
  json += "\"";
  json += ",\"gateway\":\"";
  json += WiFi.gatewayIP().toString();
  json += "\"";
  json += ",\"rssi\":";
  json += String(WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : 0);
  json += ",\"camera_ready\":";
  json += (cameraReady ? "true" : "false");
  json += ",\"capture\":\"http://192.168.4.10/capture\"";
  json += "}";

  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
  return httpd_resp_send(req, json.c_str(), json.length());
}

static esp_err_t indexHandler(httpd_req_t *req)
{
  const char html[] =
      "<!doctype html><html><head>"
      "<meta name='viewport' content='width=device-width,initial-scale=1'>"
      "<title>ESP32-CAM</title>"
      "<style>"
      "body{font-family:Arial,sans-serif;margin:20px;background:#101418;color:#eef2f6}"
      "button{font-size:16px;padding:10px 12px;border:0;border-radius:6px;background:#38bdf8;color:#061018;margin:4px 4px 10px 0}"
      "pre{white-space:pre-wrap;background:#1b222b;padding:12px;border-radius:6px;overflow:auto}"
      "img{display:block;max-width:100%;margin-top:12px;border-radius:6px;background:#222}"
      "</style></head><body>"
      "<h1>ESP32-CAM</h1>"
      "<button onclick='status()'>Status</button>"
      "<button onclick='capture()'>Capture</button>"
      "<pre id='out'>Ready</pre>"
      "<img id='photo' alt='ESP32-CAM capture'>"
      "<script>"
      "async function status(){let r=await fetch('/status?t='+Date.now());document.getElementById('out').textContent=await r.text();}"
      "function capture(){document.getElementById('photo').src='/capture?t='+Date.now();}"
      "</script></body></html>";

  httpd_resp_set_type(req, "text/html");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, html, HTTPD_RESP_USE_STRLEN);
}

static bool startCamera()
{
  Serial.println("Starting camera...");

  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.grab_mode = CAMERA_GRAB_LATEST;

  if (psramFound()) {
    config.frame_size = FRAMESIZE_VGA;
    config.jpeg_quality = 10;
    config.fb_count = 2;
  } else {
    config.frame_size = FRAMESIZE_QVGA;
    config.jpeg_quality = 12;
    config.fb_count = 1;
  }

  esp_err_t error = esp_camera_init(&config);
  if (error != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x\n", error);
    return false;
  }

  sensor_t *sensor = esp_camera_sensor_get();
  if (sensor) {
    sensor->set_framesize(sensor, FRAMESIZE_VGA);
  }

  Serial.println("Camera ready.");
  return true;
}

static void connectToHub()
{
  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.setSleep(false);

  if (!WiFi.config(localIp, gateway, subnet)) {
    Serial.println("Static IP configuration failed.");
  }

  WiFi.begin(STA_SSID, STA_PASSWORD);
  Serial.printf("Connecting to %s", STA_SSID);

  unsigned long startedAt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startedAt < 20000) {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("ESP32-CAM URL: http://%s/\n", WiFi.localIP().toString().c_str());
    Serial.println("Capture URL: http://192.168.4.10/capture");
  } else {
    Serial.println("WiFi not connected yet. Keep ESPDuino hub powered; retrying in loop.");
  }
}

static void startServer()
{
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port = 80;
  config.ctrl_port = 32768;

  if (httpd_start(&server, &config) != ESP_OK) {
    Serial.println("HTTP server start failed");
    return;
  }

  httpd_uri_t rootUri = {};
  rootUri.uri = "/";
  rootUri.method = HTTP_GET;
  rootUri.handler = indexHandler;
  rootUri.user_ctx = nullptr;
  httpd_register_uri_handler(server, &rootUri);

  httpd_uri_t statusUri = {};
  statusUri.uri = "/status";
  statusUri.method = HTTP_GET;
  statusUri.handler = statusHandler;
  statusUri.user_ctx = nullptr;
  httpd_register_uri_handler(server, &statusUri);

  httpd_uri_t captureUri = {};
  captureUri.uri = "/capture";
  captureUri.method = HTTP_GET;
  captureUri.handler = captureHandler;
  captureUri.user_ctx = nullptr;
  httpd_register_uri_handler(server, &captureUri);

  Serial.println("HTTP camera server started.");
}

void setup()
{
  Serial.begin(115200);
  delay(500);

  Serial.println();
  Serial.println("ESP32-CAM capture server starting...");

  cameraReady = startCamera();
  connectToHub();
  startServer();
}

void loop()
{
  if (WiFi.status() != WL_CONNECTED && millis() - lastReconnectAttemptMs > 5000) {
    lastReconnectAttemptMs = millis();
    WiFi.disconnect();
    WiFi.config(localIp, gateway, subnet);
    WiFi.begin(STA_SSID, STA_PASSWORD);
    Serial.printf("Retrying WiFi connection to %s\n", STA_SSID);
  }

  delay(50);
}
