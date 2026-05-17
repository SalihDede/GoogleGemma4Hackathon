import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as fg;

import '../models/inference_chunk.dart';
import '../models/tool_result.dart';
import 'cloud_inference_service.dart';
import 'litert_service.dart';
import 'model_manager_service.dart';

enum InferenceMode { cloud, local }

const _platformChannel = MethodChannel('com.lumos/call');

class InferenceRouter {
  InferenceRouter._();
  static final InferenceRouter instance = InferenceRouter._();

  InferenceMode mode = InferenceMode.cloud;

  bool get localReady => LiteRtService.instance.isReady;
  bool get localInstalling => LiteRtService.instance.isLoading;

  Future<void> _bindMobileForInternet() async {
    try {
      await _platformChannel
          .invokeMethod<String>('bindMobileForInternet')
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // If mobile data is unavailable, the internet check below will fail and
      // the router will use the local model.
    }
  }

  Future<bool> _hasInternet() async {
    try {
      await _bindMobileForInternet();
      final r = await InternetAddress.lookup(
        'openrouter.ai',
      ).timeout(const Duration(seconds: 2));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<Object?> _ensureLocalReady() async {
    if (localReady) return null;
    if (!await ModelManagerService.instance.isModelInstalled()) {
      return StateError('The offline model has not been downloaded yet.');
    }
    await ModelManagerService.instance.activateInstalled();
    if (!localInstalling) {
      try {
        await LiteRtService.instance.initialize(modelPath: '');
      } catch (e) {
        return e;
      }
      return null;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (!localReady &&
        localInstalling &&
        DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return localReady
        ? null
        : StateError('The offline model is still loading.');
  }

  Stream<InferenceChunk> sendMessage({
    required String text,
    Uint8List? imageBytes,
  }) async* {
    final cloudConfigured = await CloudInferenceService.instance.isConfigured();
    final preferCloud = mode == InferenceMode.cloud && cloudConfigured;

    if (preferCloud && !await _hasInternet()) {
      final localError = await _ensureLocalReady();
      if (localReady) {
        yield* _localStream(text: text, imageBytes: imageBytes);
        return;
      }
      throw StateError(
        'No internet connection. Offline model could not be loaded: $localError',
      );
    }

    if (preferCloud) {
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
        if (firstChunkSeen) rethrow;
        await _ensureLocalReady();
        if (!localReady) rethrow;
      }
    }

    if (!localReady) {
      await _ensureLocalReady();
    }
    if (!localReady) {
      throw StateError(
        'Offline mode is not ready yet. Please wait a moment and try again.',
      );
    }
    yield* _localStream(text: text, imageBytes: imageBytes);
  }

  Stream<InferenceChunk> sendToolResponse({
    required String name,
    required ToolResult result,
  }) async* {
    if (!localReady) {
      throw StateError('The local model is not ready.');
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
