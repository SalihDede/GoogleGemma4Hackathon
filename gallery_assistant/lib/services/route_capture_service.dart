import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';

class RouteCaptureService {
  RouteCaptureService._();
  static final RouteCaptureService instance = RouteCaptureService._();

  /// Google Maps directions URL'ini headless WebView'da yükler ve PNG döner.
  /// API key gerekmez — public Maps URL endpoint kullanılır.
  String get _mapsUserAgent {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS =>
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
            'Mobile/15E148 Safari/604.1',
      _ =>
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile',
    };
  }

  Future<Uint8List?> capture({
    required String origin,
    required String destination,
    String mode = 'walking',
    Duration extraSettle = const Duration(seconds: 3),
  }) async {
    final url =
        'https://www.google.com/maps/dir/?api=1&origin=${Uri.encodeComponent(origin)}'
        '&destination=${Uri.encodeComponent(destination)}&travelmode=$mode';

    final completer = Completer<Uint8List?>();
    HeadlessInAppWebView? webView;

    webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: _mapsUserAgent,
      ),
      onLoadStop: (controller, _) async {
        // Maps JS rotayı çizmesi için biraz bekle
        await Future.delayed(extraSettle);
        try {
          final bytes = await controller.takeScreenshot();
          if (!completer.isCompleted) completer.complete(bytes);
        } catch (e) {
          if (!completer.isCompleted) completer.complete(null);
        }
      },
      onReceivedError: (_, _, _) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );

    await webView.run();
    await webView.setSize(const Size(1080, 1920));

    // Güvenlik timeout
    final result = await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => null,
    );

    await webView.dispose();
    return result;
  }

  /// from boşsa cihaz konumunu "lat,lng" string olarak verir.
  Future<String?> currentLocationString() async {
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return '${pos.latitude},${pos.longitude}';
    } catch (_) {
      return null;
    }
  }
}
