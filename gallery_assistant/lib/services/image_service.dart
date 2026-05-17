import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const int _maxDimension = 512;
const int _jpegQuality = 76;

class ImageService {
  ImageService._();
  static final ImageService instance = ImageService._();

  Future<Uint8List?> prepareForModel(File file) async {
    try {
      final raw = await file.readAsBytes();
      return compute(_resizeIsolate, raw);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> prepareFromBytes(Uint8List raw) async {
    try {
      return compute(_resizeIsolate, raw);
    } catch (_) {
      return null;
    }
  }
}

Uint8List _resizeIsolate(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) throw Exception('Image could not be decoded');

  if (decoded.width <= _maxDimension && decoded.height <= _maxDimension) {
    return Uint8List.fromList(img.encodeJpg(decoded, quality: _jpegQuality));
  }

  final resized = img.copyResize(
    decoded,
    width: decoded.width > decoded.height ? _maxDimension : null,
    height: decoded.height >= decoded.width ? _maxDimension : null,
    interpolation: img.Interpolation.linear,
  );

  return Uint8List.fromList(img.encodeJpg(resized, quality: _jpegQuality));
}
