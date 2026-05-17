#include <Adafruit_BME280.h>
#include <Adafruit_BMP280.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_TSL2561_U.h>
#include <Adafruit_VL6180X.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <WiFi.h>
#include <Wire.h>
#include <cstring>
#include <math.h>

const char *AP_SSID = "ESP-SENSOR-HUB";
const char *AP_PASSWORD = "localhub123";
const int AP_CHANNEL = 6;
const int AP_MAX_CLIENTS = 4;

// Leave empty for password-only local access. Set the same value on both boards
// if you want endpoint URLs to require ?token=YOUR_TOKEN.
const char *API_TOKEN = "";
const char *CAMERA_BASE_URL = "http://192.168.4.10";

const int I2C_SDA_PIN = 21;
const int I2C_SCL_PIN = 22;
const int SOUND_ANALOG_PIN = 34;
const int SOUND_DIGITAL_PIN = 27;
const float SEA_LEVEL_PRESSURE_HPA = 1013.25;

IPAddress apIp(192, 168, 4, 1);
IPAddress apGateway(192, 168, 4, 1);
IPAddress apSubnet(255, 255, 255, 0);

WebServer server(80);

Adafruit_BME280 bme280;
Adafruit_BMP280 bmp280;
Adafruit_MPU6050 mpu6050;
Adafruit_TSL2561_Unified tslLow(TSL2561_ADDR_LOW, 25610);
Adafruit_TSL2561_Unified tslFloat(TSL2561_ADDR_FLOAT, 25611);
Adafruit_TSL2561_Unified tslHigh(TSL2561_ADDR_HIGH, 25612);
Adafruit_TSL2561_Unified *activeTsl2561 = nullptr;
Adafruit_VL6180X vl6180x = Adafruit_VL6180X();

bool bme280Ready = false;
bool bmp280Ready = false;
bool mpu6050Ready = false;
bool mpu6050RawReady = false;
bool tsl2561Ready = false;
bool vl6180xReady = false;
uint8_t environmentAddress = 0;
uint8_t mpu6050Address = 0;
uint8_t tsl2561Address = 0;
unsigned long lastSensorInitAttemptMs = 0;

static void addCommonHeaders()
{
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  server.sendHeader("Cache-Control", "no-store");
}

static bool isAuthorized()
{
  if (strlen(API_TOKEN) == 0) {
    return true;
  }
  return server.hasArg("token") && server.arg("token") == API_TOKEN;
}

static bool rejectUnauthorized()
{
  if (isAuthorized()) {
    return false;
  }

  addCommonHeaders();
  server.send(401, "application/json", "{\"ok\":false,\"error\":\"unauthorized\"}");
  return true;
}

static String quoted(const String &value)
{
  String out = "\"";
  for (size_t i = 0; i < value.length(); i++) {
    char c = value[i];
    if (c == '"' || c == '\\') {
      out += '\\';
    }
    out += c;
  }
  out += "\"";
  return out;
}

static String hexAddress(uint8_t address)
{
  char addressText[5];
  snprintf(addressText, sizeof(addressText), "%02X", address);
  return "0x" + String(addressText);
}

static bool hasI2cDevice(uint8_t address)
{
  Wire.beginTransmission(address);
  return Wire.endTransmission() == 0;
}

static bool writeI2cRegister(uint8_t address, uint8_t reg, uint8_t value)
{
  Wire.beginTransmission(address);
  Wire.write(reg);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

static bool readI2cRegisters(uint8_t address, uint8_t reg, uint8_t *buffer, size_t length)
{
  Wire.beginTransmission(address);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) {
    return false;
  }

  size_t index = 0;
  Wire.requestFrom(address, (uint8_t)length);
  while (Wire.available() && index < length) {
    buffer[index++] = Wire.read();
  }

  return index == length;
}

static int16_t readInt16Be(const uint8_t *buffer)
{
  return (int16_t)((buffer[0] << 8) | buffer[1]);
}

static void appendFloatValue(String &json, float value, int decimals)
{
  if (isnan(value) || isinf(value)) {
    json += "null";
    return;
  }

  json += String(value, decimals);
}

static void appendFloatField(String &json, const char *name, float value, int decimals)
{
  json += ",\"";
  json += name;
  json += "\":";
  appendFloatValue(json, value, decimals);
}

static void appendAddressField(String &json, const char *name, uint8_t address)
{
  json += ",\"";
  json += name;
  json += "\":";
  json += quoted(hexAddress(address));
}

static void initEnvironmentSensor()
{
  bme280Ready = false;
  bmp280Ready = false;
  environmentAddress = 0;

  const uint8_t addresses[] = {0x76, 0x77};
  for (size_t i = 0; i < sizeof(addresses); i++) {
    uint8_t address = addresses[i];
    if (!hasI2cDevice(address)) {
      continue;
    }

    if (bme280.begin(address)) {
      bme280Ready = true;
      environmentAddress = address;
      Serial.printf("BME280 ready at %s\n", hexAddress(address).c_str());
      return;
    }

    if (bmp280.begin(address)) {
      bmp280Ready = true;
      environmentAddress = address;
      Serial.printf("BMP280 ready at %s\n", hexAddress(address).c_str());
      return;
    }
  }
}

static void initMpu6050()
{
  mpu6050Ready = false;
  mpu6050RawReady = false;
  mpu6050Address = 0;

  const uint8_t addresses[] = {0x68, 0x69};
  for (size_t i = 0; i < sizeof(addresses); i++) {
    uint8_t address = addresses[i];
    if (!hasI2cDevice(address)) {
      continue;
    }

    if (mpu6050.begin(address)) {
      mpu6050Ready = true;
      mpu6050Address = address;
      mpu6050.setAccelerometerRange(MPU6050_RANGE_8_G);
      mpu6050.setGyroRange(MPU6050_RANGE_500_DEG);
      mpu6050.setFilterBandwidth(MPU6050_BAND_21_HZ);
      Serial.printf("MPU6050 ready at %s\n", hexAddress(address).c_str());
      return;
    }

    uint8_t whoAmI = 0;
    if (readI2cRegisters(address, 0x75, &whoAmI, 1) && (whoAmI == 0x68 || whoAmI == 0x70)) {
      writeI2cRegister(address, 0x6B, 0x00);
      writeI2cRegister(address, 0x19, 0x07);
      writeI2cRegister(address, 0x1A, 0x03);
      writeI2cRegister(address, 0x1B, 0x08);
      writeI2cRegister(address, 0x1C, 0x10);
      delay(100);
      mpu6050RawReady = true;
      mpu6050Address = address;
      Serial.printf("MPU6050 raw reader ready at %s, WHO_AM_I=0x%02X\n", hexAddress(address).c_str(), whoAmI);
      return;
    }
  }
}

static bool tryStartTsl2561(Adafruit_TSL2561_Unified &sensor, uint8_t address)
{
  if (!hasI2cDevice(address)) {
    return false;
  }

  if (!sensor.begin()) {
    return false;
  }

  sensor.enableAutoRange(true);
  sensor.setIntegrationTime(TSL2561_INTEGRATIONTIME_402MS);
  activeTsl2561 = &sensor;
  tsl2561Ready = true;
  tsl2561Address = address;
  Serial.printf("TSL2561 ready at %s\n", hexAddress(address).c_str());
  return true;
}

static void initTsl2561()
{
  activeTsl2561 = nullptr;
  tsl2561Ready = false;
  tsl2561Address = 0;

  if (tryStartTsl2561(tslFloat, 0x39)) {
    return;
  }
  if (tryStartTsl2561(tslLow, 0x29)) {
    return;
  }
  tryStartTsl2561(tslHigh, 0x49);
}

static void initVl6180x()
{
  vl6180xReady = false;

  if (!hasI2cDevice(0x29)) {
    return;
  }

  if (vl6180x.begin()) {
    vl6180xReady = true;
    Serial.println("VL6180X ready at 0x29");
  }
}

static void initSensors(bool force)
{
  if (!force && millis() - lastSensorInitAttemptMs < 5000) {
    return;
  }

  lastSensorInitAttemptMs = millis();
  if (force || (!bme280Ready && !bmp280Ready)) {
    initEnvironmentSensor();
  }
  if (force || !mpu6050Ready) {
    initMpu6050();
  }
  if (force || !tsl2561Ready) {
    initTsl2561();
  }
  if (force || !vl6180xReady) {
    initVl6180x();
  }
}

static String i2cScanJson()
{
  String json = "[";
  bool first = true;

  for (uint8_t address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    uint8_t error = Wire.endTransmission();

    if (error == 0) {
      char addressText[7];
      snprintf(addressText, sizeof(addressText), "\"0x%02X\"", address);

      if (!first) {
        json += ",";
      }
      json += addressText;
      first = false;
    }
  }

  json += "]";
  return json;
}

static void appendEnvironmentSensorJson(String &json)
{
  json += "\"bme_bmp280\":{\"implemented\":true";
  json += ",\"present\":";
  json += (bme280Ready || bmp280Ready ? "true" : "false");
  json += ",\"expected_addresses\":[\"0x76\",\"0x77\"]";

  if (bme280Ready || bmp280Ready) {
    appendAddressField(json, "address", environmentAddress);
    json += ",\"type\":";
    json += quoted(bme280Ready ? "bme280" : "bmp280");

    if (bme280Ready) {
      appendFloatField(json, "temperature_c", bme280.readTemperature(), 2);
      appendFloatField(json, "pressure_hpa", bme280.readPressure() / 100.0, 2);
      appendFloatField(json, "humidity_percent", bme280.readHumidity(), 2);
      appendFloatField(json, "altitude_m", bme280.readAltitude(SEA_LEVEL_PRESSURE_HPA), 2);
    } else {
      appendFloatField(json, "temperature_c", bmp280.readTemperature(), 2);
      appendFloatField(json, "pressure_hpa", bmp280.readPressure() / 100.0, 2);
      json += ",\"humidity_percent\":null";
      appendFloatField(json, "altitude_m", bmp280.readAltitude(SEA_LEVEL_PRESSURE_HPA), 2);
    }
  }

  json += "}";
}

static void appendMpu6050Json(String &json)
{
  json += "\"mpu6050\":{\"implemented\":true";
  json += ",\"present\":";
  json += (mpu6050Ready || mpu6050RawReady ? "true" : "false");
  json += ",\"expected_addresses\":[\"0x68\",\"0x69\"]";

  if (mpu6050Ready || mpu6050RawReady) {
    appendAddressField(json, "address", mpu6050Address);

    if (mpu6050RawReady) {
      uint8_t raw[14];
      if (readI2cRegisters(mpu6050Address, 0x3B, raw, sizeof(raw))) {
        int16_t accelX = readInt16Be(&raw[0]);
        int16_t accelY = readInt16Be(&raw[2]);
        int16_t accelZ = readInt16Be(&raw[4]);
        int16_t tempRaw = readInt16Be(&raw[6]);
        int16_t gyroX = readInt16Be(&raw[8]);
        int16_t gyroY = readInt16Be(&raw[10]);
        int16_t gyroZ = readInt16Be(&raw[12]);

        json += ",\"reader\":\"raw_registers\"";
        appendFloatField(json, "temperature_c", (tempRaw / 340.0) + 36.53, 2);

        json += ",\"accel_mps2\":{";
        json += "\"x\":";
        appendFloatValue(json, (accelX / 4096.0) * 9.80665, 3);
        json += ",\"y\":";
        appendFloatValue(json, (accelY / 4096.0) * 9.80665, 3);
        json += ",\"z\":";
        appendFloatValue(json, (accelZ / 4096.0) * 9.80665, 3);
        json += "}";

        json += ",\"gyro_dps\":{";
        json += "\"x\":";
        appendFloatValue(json, gyroX / 65.5, 3);
        json += ",\"y\":";
        appendFloatValue(json, gyroY / 65.5, 3);
        json += ",\"z\":";
        appendFloatValue(json, gyroZ / 65.5, 3);
        json += "}";
      } else {
        json += ",\"read_error\":true";
      }

      json += "}";
      return;
    }

    sensors_event_t accel;
    sensors_event_t gyro;
    sensors_event_t temp;
    mpu6050.getEvent(&accel, &gyro, &temp);

    json += ",\"reader\":\"adafruit\"";
    appendFloatField(json, "temperature_c", temp.temperature, 2);

    json += ",\"accel_mps2\":{";
    json += "\"x\":";
    appendFloatValue(json, accel.acceleration.x, 3);
    json += ",\"y\":";
    appendFloatValue(json, accel.acceleration.y, 3);
    json += ",\"z\":";
    appendFloatValue(json, accel.acceleration.z, 3);
    json += "}";

    json += ",\"gyro_dps\":{";
    json += "\"x\":";
    appendFloatValue(json, gyro.gyro.x * 57.29578, 3);
    json += ",\"y\":";
    appendFloatValue(json, gyro.gyro.y * 57.29578, 3);
    json += ",\"z\":";
    appendFloatValue(json, gyro.gyro.z * 57.29578, 3);
    json += "}";
  }

  json += "}";
}

static void appendTsl2561Json(String &json)
{
  json += "\"tsl2561\":{\"implemented\":true";
  json += ",\"present\":";
  json += (tsl2561Ready ? "true" : "false");
  json += ",\"expected_addresses\":[\"0x29\",\"0x39\",\"0x49\"]";

  if (tsl2561Ready && activeTsl2561 != nullptr) {
    sensors_event_t event;
    activeTsl2561->getEvent(&event);
    appendAddressField(json, "address", tsl2561Address);
    appendFloatField(json, "lux", event.light, 2);
  }

  json += "}";
}

static void appendVl6180xJson(String &json)
{
  json += "\"vl6180x\":{\"implemented\":true";
  json += ",\"present\":";
  json += (vl6180xReady ? "true" : "false");
  json += ",\"expected_addresses\":[\"0x29\"]";

  if (vl6180xReady) {
    uint8_t rangeMm = vl6180x.readRange();
    uint8_t rangeStatus = vl6180x.readRangeStatus();
    float lux = vl6180x.readLux(VL6180X_ALS_GAIN_5);

    json += ",\"address\":\"0x29\"";
    json += ",\"range_status\":";
    json += String(rangeStatus);
    json += ",\"range_mm\":";
    if (rangeStatus == VL6180X_ERROR_NONE) {
      json += String(rangeMm);
    } else {
      json += "null";
    }
    appendFloatField(json, "ambient_lux", lux, 2);
  }

  json += "}";
}

static void appendCzn15eJson(String &json)
{
  int analogRaw = analogRead(SOUND_ANALOG_PIN);
  int digitalState = digitalRead(SOUND_DIGITAL_PIN);
  float voltage = analogRaw * (3.3 / 4095.0);

  json += "\"czn15e\":{\"implemented\":true";
  json += ",\"analog_pin\":";
  json += String(SOUND_ANALOG_PIN);
  json += ",\"digital_pin\":";
  json += String(SOUND_DIGITAL_PIN);
  json += ",\"analog_raw\":";
  json += String(analogRaw);
  appendFloatField(json, "analog_voltage_v", voltage, 3);
  json += ",\"digital_high\":";
  json += (digitalState == HIGH ? "true" : "false");
  json += "}";
}

static void sendOptions()
{
  addCommonHeaders();
  server.send(204);
}

static void sendIndex()
{
  const char html[] PROGMEM =
      "<!doctype html><html><head>"
      "<meta name='viewport' content='width=device-width,initial-scale=1'>"
      "<title>ESP Sensor Hub</title>"
      "<style>"
      "body{font-family:Arial,sans-serif;margin:20px;background:#101418;color:#eef2f6}"
      "button{font-size:16px;padding:10px 12px;border:0;border-radius:6px;background:#22c55e;color:#07110b;margin:4px 4px 10px 0}"
      "pre{white-space:pre-wrap;background:#1b222b;padding:12px;border-radius:6px;overflow:auto}"
      "img{display:block;max-width:100%;margin-top:12px;border-radius:6px;background:#222}"
      "a{color:#93c5fd}"
      "</style></head><body>"
      "<h1>ESP Sensor Hub</h1>"
      "<p>Local AP: ESP-SENSOR-HUB</p>"
      "<button onclick='loadSensors()'>Sensors</button>"
      "<button onclick='loadStatus()'>Hub Status</button>"
      "<button onclick='capture()'>Camera Capture</button>"
      "<pre id='out'>Ready</pre>"
      "<img id='photo' alt='ESP32-CAM capture'>"
      "<script>"
      "async function show(url){let r=await fetch(url);let t=await r.text();try{t=JSON.stringify(JSON.parse(t),null,2);}catch(e){}document.getElementById('out').textContent=t;}"
      "function loadSensors(){show('/sensors');}"
      "function loadStatus(){show('/status');}"
      "function capture(){document.getElementById('photo').src='/camera/capture?t='+Date.now();}"
      "</script></body></html>";

  addCommonHeaders();
  server.send(200, "text/html", html);
}

static void sendStatus()
{
  if (rejectUnauthorized()) {
    return;
  }

  String json = "{";
  json += "\"ok\":true";
  json += ",\"device\":\"espduino-32\"";
  json += ",\"role\":\"sensor_hub_ap\"";
  json += ",\"ip\":\"";
  json += WiFi.softAPIP().toString();
  json += "\"";
  json += ",\"ssid\":";
  json += quoted(AP_SSID);
  json += ",\"stations\":";
  json += String(WiFi.softAPgetStationNum());
  json += ",\"uptime_ms\":";
  json += String(millis());
  json += ",\"endpoints\":[\"/\",\"/status\",\"/sensors\",\"/devices\",\"/camera/status\",\"/camera/capture\"]";
  json += "}";

  addCommonHeaders();
  server.send(200, "application/json", json);
}

static void sendDevices()
{
  if (rejectUnauthorized()) {
    return;
  }

  String json = "{";
  json += "\"ok\":true";
  json += ",\"network\":\"local_only_ap\"";
  json += ",\"hub\":{\"name\":\"espduino-32\",\"ip\":\"192.168.4.1\",\"status\":\"/status\",\"sensors\":\"/sensors\"}";
  json += ",\"camera\":{\"name\":\"esp32-cam\",\"ip\":\"192.168.4.10\",\"status\":\"/camera/status\",\"capture\":\"/camera/capture\",\"upstream\":\"http://192.168.4.10\"}";
  json += "}";

  addCommonHeaders();
  server.send(200, "application/json", json);
}

static void proxyCameraStatus()
{
  if (rejectUnauthorized()) {
    return;
  }

  HTTPClient http;
  String url = String(CAMERA_BASE_URL) + "/status";
  http.setTimeout(4000);
  http.begin(url);
  int statusCode = http.GET();

  addCommonHeaders();
  if (statusCode <= 0) {
    String json = "{\"ok\":false,\"error\":\"camera_status_unreachable\",\"detail\":";
    json += quoted(http.errorToString(statusCode));
    json += "}";
    http.end();
    server.send(502, "application/json", json);
    return;
  }

  String payload = http.getString();
  http.end();
  server.send(statusCode, "application/json", payload);
}

static void proxyCameraCapture()
{
  if (rejectUnauthorized()) {
    return;
  }

  HTTPClient http;
  String url = String(CAMERA_BASE_URL) + "/capture";
  http.setTimeout(8000);
  http.begin(url);
  int statusCode = http.GET();

  if (statusCode != HTTP_CODE_OK) {
    addCommonHeaders();
    String json = "{\"ok\":false,\"error\":\"camera_capture_unreachable\",\"status\":";
    json += String(statusCode);
    json += ",\"detail\":";
    json += quoted(statusCode <= 0 ? http.errorToString(statusCode) : http.getString());
    json += "}";
    http.end();
    server.send(502, "application/json", json);
    return;
  }

  int length = http.getSize();
  WiFiClient *stream = http.getStreamPtr();
  WiFiClient client = server.client();
  uint8_t buffer[1024];

  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Cache-Control", "no-store");
  server.sendHeader("Content-Disposition", "inline; filename=capture.jpg");
  if (length > 0) {
    server.setContentLength(length);
  } else {
    server.setContentLength(CONTENT_LENGTH_UNKNOWN);
  }
  server.send(200, "image/jpeg", "");

  unsigned long lastReadMs = millis();
  while (http.connected() && (length > 0 || length == -1)) {
    size_t available = stream->available();
    if (available) {
      int readCount = stream->readBytes(buffer, min(available, sizeof(buffer)));
      client.write(buffer, readCount);
      if (length > 0) {
        length -= readCount;
      }
      lastReadMs = millis();
    } else if (millis() - lastReadMs > 8000) {
      break;
    } else {
      delay(1);
    }
  }

  http.end();
}

static void sendSensors()
{
  if (rejectUnauthorized()) {
    return;
  }

  initSensors(false);

  String json = "{";
  json += "\"ok\":true";
  json += ",\"device\":\"espduino-32\"";
  json += ",\"uptime_ms\":";
  json += String(millis());
  json += ",\"i2c\":{\"sda\":";
  json += String(I2C_SDA_PIN);
  json += ",\"scl\":";
  json += String(I2C_SCL_PIN);
  json += ",\"devices\":";
  json += i2cScanJson();
  json += "}";
  json += ",\"sensors\":{";
  appendEnvironmentSensorJson(json);
  json += ",";
  appendMpu6050Json(json);
  json += ",";
  appendTsl2561Json(json);
  json += ",";
  appendVl6180xJson(json);
  json += ",";
  appendCzn15eJson(json);
  json += "}}";

  addCommonHeaders();
  server.send(200, "application/json", json);
}

static void sendNotFound()
{
  addCommonHeaders();
  server.send(404, "application/json", "{\"ok\":false,\"error\":\"not_found\"}");
}

static void startAccessPoint()
{
  WiFi.mode(WIFI_AP);
  WiFi.softAPConfig(apIp, apGateway, apSubnet);
  WiFi.softAP(AP_SSID, AP_PASSWORD, AP_CHANNEL, false, AP_MAX_CLIENTS);

  Serial.println();
  Serial.println("ESPDuino local-only AP started.");
  Serial.printf("SSID: %s\n", AP_SSID);
  Serial.printf("Password: %s\n", AP_PASSWORD);
  Serial.printf("Hub URL: http://%s/\n", WiFi.softAPIP().toString().c_str());
  Serial.println("Expected ESP32-CAM URL: http://192.168.4.10/");
}

void setup()
{
  Serial.begin(115200);
  delay(500);

  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setClock(100000);
  analogReadResolution(12);
  pinMode(SOUND_DIGITAL_PIN, INPUT);
  initSensors(true);

  startAccessPoint();

  server.on("/", HTTP_GET, sendIndex);
  server.on("/status", HTTP_GET, sendStatus);
  server.on("/sensors", HTTP_GET, sendSensors);
  server.on("/devices", HTTP_GET, sendDevices);
  server.on("/camera/status", HTTP_GET, proxyCameraStatus);
  server.on("/camera/capture", HTTP_GET, proxyCameraCapture);
  server.onNotFound([]() {
    if (server.method() == HTTP_OPTIONS) {
      sendOptions();
      return;
    }
    sendNotFound();
  });

  server.begin();
  Serial.println("HTTP server started.");
}

void loop()
{
  server.handleClient();
}
