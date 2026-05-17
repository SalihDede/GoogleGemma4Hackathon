import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/tool_result.dart';
import 'image_service.dart';

const _sensorEndpoint = 'http://192.168.4.1/sensors';
const _cameraBaseEndpoint = 'http://192.168.4.1';
const _cameraStatusEndpoint = 'http://192.168.4.1/camera/status';
const _captureEndpoint = 'http://192.168.4.1/camera/capture';
const _platformChannel = MethodChannel('com.lumos/call');

class SensorHubSnapshot {
  final String temperatureC;
  final String pressureHpa;
  final String humidityPercent;
  final String accelX;
  final String accelY;
  final String accelZ;
  final String gyroX;
  final String gyroY;
  final String gyroZ;
  final String lux;

  const SensorHubSnapshot({
    this.temperatureC = '',
    this.pressureHpa = '',
    this.humidityPercent = '',
    this.accelX = '',
    this.accelY = '',
    this.accelZ = '',
    this.gyroX = '',
    this.gyroY = '',
    this.gyroZ = '',
    this.lux = '',
  });

  double? get _accelMagnitude {
    final x = double.tryParse(accelX);
    final y = double.tryParse(accelY);
    final z = double.tryParse(accelZ);
    if (x == null || y == null || z == null) return null;
    return (x * x + y * y + z * z);
  }

  double? get accelMagnitude {
    final squared = _accelMagnitude;
    if (squared == null) return null;
    return squared <= 0 ? 0 : _sqrt(squared);
  }

  double? get gyroMaxAbs {
    final values = [
      gyroX,
      gyroY,
      gyroZ,
    ].map(double.tryParse).whereType<double>();
    if (values.isEmpty) return null;
    return values.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
  }

  String get brightnessClass {
    final value = double.tryParse(lux);
    if (value == null) return '';
    if (value < 10) return 'dark';
    if (value < 50) return 'dim';
    if (value < 1000) return 'normal';
    if (value < 10000) return 'bright';
    return 'too_bright';
  }

  String get comfort {
    final temp = double.tryParse(temperatureC);
    final humidity = double.tryParse(humidityPercent);
    if (temp == null && humidity == null) return '';
    if (temp != null && temp < 18) return 'cold';
    if (temp != null && temp > 28) return 'hot';
    if (humidity != null && humidity > 70) return 'humid';
    if (humidity != null && humidity < 30) return 'dry';
    return 'comfortable';
  }

  String get stable {
    final accel = accelMagnitude;
    final gyro = gyroMaxAbs;
    if (accel == null && gyro == null) return '';
    final accelStable = accel == null || (accel >= 8.5 && accel <= 11.5);
    final gyroStable = gyro == null || gyro < 10;
    return (accelStable && gyroStable).toString();
  }

  String get motion {
    final accel = accelMagnitude;
    final gyro = gyroMaxAbs;
    if (accel == null && gyro == null) return '';
    if (accel != null && accel < 2.5) return 'free_fall';
    if (accel != null && accel > 25) return 'impact';
    if ((gyro ?? 0) > 150 || (accel ?? 0) > 18) return 'shaking';
    if ((gyro ?? 0) > 25 || (accel != null && (accel < 8 || accel > 12))) {
      return 'moving';
    }
    return 'still';
  }

  String get tilt {
    final x = double.tryParse(accelX);
    final y = double.tryParse(accelY);
    final z = double.tryParse(accelZ);
    if (x == null || y == null || z == null) return '';
    final ax = x.abs();
    final ay = y.abs();
    final az = z.abs();
    if (az >= ax && az >= ay) return z >= 0 ? 'flat' : 'upside_down';
    if (ay >= ax) return y >= 0 ? 'upright' : 'upside_down';
    return 'leaning';
  }
}

class SensorHubService {
  SensorHubService._();
  static final SensorHubService instance = SensorHubService._();

  final http.Client _client = http.Client();

  Future<SensorHubSnapshot> fetchSnapshot() async {
    await _bindWifiForEsp();
    try {
      final response = await _getWithRetries(
        Uri.parse(_sensorEndpoint),
        timeout: const Duration(seconds: 6),
        attempts: 3,
      );
      if (response.statusCode != 200) {
        throw Exception('Sensor hub HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Sensor hub response is not a JSON object');
      }

      final sensors = _sensorsMap(decoded);
      final bme = _map(sensors['bme_bmp280']);
      final mpu = _map(sensors['mpu6050']);
      final accel = _map(mpu['accel_mps2']);
      final gyro = _map(mpu['gyro_dps']);
      final light = _map(sensors['tsl2561']);

      return SensorHubSnapshot(
        temperatureC: _value(bme['temperature_c']),
        pressureHpa: _value(bme['pressure_hpa']),
        humidityPercent: _value(bme['humidity_percent']),
        accelX: _value(accel['x']),
        accelY: _value(accel['y']),
        accelZ: _value(accel['z']),
        gyroX: _value(gyro['x']),
        gyroY: _value(gyro['y']),
        gyroZ: _value(gyro['z']),
        lux: _value(light['lux']),
      );
    } finally {
      await _restoreInternetRoute();
    }
  }

  Future<CaptureImageResult> captureImage(String reason) async {
    try {
      await _bindWifiForEsp();
      try {
        await _warmCameraServer();
        final response = await _getWithRetries(
          Uri.parse(
            '$_captureEndpoint?t=${DateTime.now().millisecondsSinceEpoch}',
          ),
          timeout: const Duration(seconds: 8),
          attempts: 4,
        );
        if (response.statusCode != 200) {
          return CaptureImageResult(
            reason: reason,
            error: 'camera_http_${response.statusCode}',
          );
        }

        final contentType = response.headers['content-type'] ?? '';
        if (contentType.isNotEmpty &&
            !contentType.toLowerCase().contains('image')) {
          return CaptureImageResult(
            reason: reason,
            error: 'camera_response_not_image: $contentType',
          );
        }

        final prepared = await ImageService.instance.prepareFromBytes(
          response.bodyBytes,
        );
        if (prepared == null) {
          return CaptureImageResult(reason: reason, error: 'decode_failed');
        }
        return CaptureImageResult(imageBytes: prepared, reason: reason);
      } finally {
        await _restoreInternetRoute();
      }
    } on TimeoutException {
      return CaptureImageResult(reason: reason, error: 'camera_timeout');
    } catch (e) {
      return CaptureImageResult(reason: reason, error: e.toString());
    }
  }

  Future<void> _bindWifiForEsp() async {
    try {
      await _platformChannel
          .invokeMethod<String>('bindWifiForEsp')
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Non-Android platforms and devices that are already routed correctly can
      // continue with the normal HTTP request.
    }
  }

  Future<void> _releaseWifiForEsp() async {
    try {
      await _platformChannel
          .invokeMethod<String>('releaseWifiForEsp')
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> _restoreInternetRoute() async {
    try {
      await _platformChannel
          .invokeMethod<String>('bindMobileForInternet')
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      await _releaseWifiForEsp();
    }
  }

  Future<http.Response> _getWithRetries(
    Uri uri, {
    required Duration timeout,
    required int attempts,
  }) async {
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      try {
        return await _client
            .get(
              uri,
              headers: const {
                'Connection': 'close',
                'Cache-Control': 'no-cache',
              },
            )
            .timeout(timeout);
      } catch (e) {
        lastError = e;
        if (i == attempts - 1) break;
        await Future<void>.delayed(Duration(milliseconds: 250 * (i + 1)));
      }
    }
    throw lastError ?? TimeoutException('Request failed: $uri');
  }

  Future<void> _warmCameraServer() async {
    for (final endpoint in const [_cameraBaseEndpoint, _cameraStatusEndpoint]) {
      try {
        await _getWithRetries(
          Uri.parse(endpoint),
          timeout: const Duration(seconds: 3),
          attempts: 1,
        );
      } catch (_) {
        // The actual capture request below reports the user-facing error.
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }
}

Map<String, dynamic> _map(Object? value) {
  return value is Map<String, dynamic> ? value : const <String, dynamic>{};
}

Map<String, dynamic> _sensorsMap(Map<String, dynamic> decoded) {
  final rootSensors = _map(decoded['sensors']);
  if (rootSensors.isNotEmpty) return rootSensors;

  final dataSensors = _map(_map(decoded['data'])['sensors']);
  if (dataSensors.isNotEmpty) return dataSensors;

  return const <String, dynamic>{};
}

String _value(Object? value) {
  if (value == null) return '';
  if (value is num) return value.toString();
  if (value is bool) return value.toString();
  return value.toString().trim();
}

double _sqrt(double value) {
  var guess = value / 2;
  for (var i = 0; i < 12; i++) {
    guess = (guess + value / guess) / 2;
  }
  return guess;
}
