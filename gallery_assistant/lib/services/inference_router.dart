import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart' as fg;

import '../models/inference_chunk.dart';
import '../models/tool_result.dart';
import 'cloud_inference_service.dart';
import 'litert_service.dart';

enum InferenceMode { cloud, local }

class InferenceRouter {
  InferenceRouter._();
  static final InferenceRouter instance = InferenceRouter._();

  InferenceMode mode = InferenceMode.cloud;

  bool get cloudConfigured => CloudInferenceService.instance.isConfigured;
  bool get localReady => LiteRtService.instance.isReady;
  bool get localInstalling => LiteRtService.instance.isLoading;

  Future<bool> _hasInternet() async {
    try {
      final r = await InternetAddress.lookup(
        'openrouter.ai',
      ).timeout(const Duration(seconds: 2));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureLocalReady() async {
    if (localReady) return;
    if (!localInstalling) {
      // Lazy init — ilk offline mesajda yükle.
      try {
        await LiteRtService.instance.initialize(modelPath: '');
      } catch (_) {
        // sessizce yut; çağıran tarafta localReady kontrol ediliyor
      }
      return;
    }
    // Başka bir çağrı zaten yüklüyor: hazır olana kadar bekle.
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (!localReady &&
        localInstalling &&
        DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Stream<InferenceChunk> sendMessage({
    required String text,
    Uint8List? imageBytes,
  }) async* {
    final preferCloud = mode == InferenceMode.cloud && cloudConfigured;

    // Bulut tercih ediliyor ama internet yoksa hiç deneme — direkt yerele git.
    if (preferCloud && !await _hasInternet()) {
      await _ensureLocalReady();
      if (localReady) {
        yield* _localStream(text: text, imageBytes: imageBytes);
        return;
      }
      throw StateError('İnternet yok ve yerel model hazır değil.');
    }

    if (preferCloud) {
      // İnternet var ve buluta gidiyoruz — yerel model RAM'de duruyorsa boşalt.
      if (localReady) {
        LiteRtService.instance.dispose();
      }
      var firstChunkSeen = false;
      try {
        await for (final c in CloudInferenceService.instance.sendMessage(
          text: text,
          imageBytes: imageBytes,
        )) {
          firstChunkSeen = true;
          yield c;
        }
        return;
      } catch (e) {
        // İlk token akmadan hata aldıysak yerele düşmek güvenli.
        if (firstChunkSeen) rethrow;
        await _ensureLocalReady();
        if (!localReady) rethrow;
      }
    }

    if (!localReady) {
      throw StateError('Yerel model hazır değil ve buluta ulaşılamıyor.');
    }
    yield* _localStream(text: text, imageBytes: imageBytes);
  }

  Stream<InferenceChunk> sendToolResponse({
    required String name,
    required ToolResult result,
  }) async* {
    if (!localReady) {
      throw StateError('Yerel model hazir degil.');
    }

    yield* _mapLocalResponses(
      LiteRtService.instance.sendToolResponse(toolName: name, result: result),
    );
  }

  Stream<InferenceChunk> _localStream({
    required String text,
    Uint8List? imageBytes,
  }) async* {
    final stream = LiteRtService.instance.sendMessage(
      text: text,
      imageBytes: imageBytes,
    );
    yield* _mapLocalResponses(stream);
  }

  Stream<InferenceChunk> _mapLocalResponses(
    Stream<fg.ModelResponse> stream,
  ) async* {
    await for (final r in stream) {
      if (r is fg.TextResponse) {
        yield TextChunk(r.token);
      } else if (r is fg.ThinkingResponse) {
        yield ThinkingChunk(r.content);
      } else if (r is fg.FunctionCallResponse) {
        yield FunctionCallChunk(r.name, Map<String, dynamic>.from(r.args));
        return;
      }
    }
  }

  Future<void> clearHistory() async {
    CloudInferenceService.instance.clearHistory();
    await LiteRtService.instance.clearHistory();
  }
}
