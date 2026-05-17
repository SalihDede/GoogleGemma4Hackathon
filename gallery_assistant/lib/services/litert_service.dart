import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tool_result.dart';
import 'litert_prompt_builder.dart';
import 'tool_runner.dart';

enum LiteRtBackendPreference { auto, gpu, cpu, npu }

extension LiteRtBackendPreferenceX on LiteRtBackendPreference {
  String get label => switch (this) {
    LiteRtBackendPreference.auto => 'Auto',
    LiteRtBackendPreference.gpu => 'GPU',
    LiteRtBackendPreference.cpu => 'CPU',
    LiteRtBackendPreference.npu => 'NPU',
  };
}

class InferenceStats {
  final String backend;
  final int ttftMs;
  final int totalMs;
  final int tokenCount;
  final double decodeTokPerSec;
  final String requestKind;
  final String promptSignature;
  final List<String> toolNames;
  final bool hadImage;
  final int maxOutputChunks;
  final bool stoppedByOutputLimit;
  final int functionCallCount;
  final int approxPromptChars;
  final int memorySummaryChars;
  final int recentContextChars;
  const InferenceStats({
    required this.backend,
    required this.ttftMs,
    required this.totalMs,
    required this.tokenCount,
    required this.decodeTokPerSec,
    this.requestKind = 'unknown',
    this.promptSignature = '',
    this.toolNames = const [],
    this.hadImage = false,
    this.maxOutputChunks = 0,
    this.stoppedByOutputLimit = false,
    this.functionCallCount = 0,
    this.approxPromptChars = 0,
    this.memorySummaryChars = 0,
    this.recentContextChars = 0,
  });
}

class InsufficientMemoryException implements Exception {
  final double availableGb;
  final double requiredGb;
  InsufficientMemoryException(this.availableGb, this.requiredGb);
  @override
  String toString() =>
      'Device RAM is insufficient: ${availableGb.toStringAsFixed(1)} GB available, '
      'at least ${requiredGb.toStringAsFixed(1)} GB required.';
}

class LiteRtService {
  LiteRtService._();
  static final LiteRtService instance = LiteRtService._();

  // Gemma-4 .task quantization ~3GB; engine + KV cache + image encoder
  static const double _minRequiredRamGb = 3.5;

  // mevcutsa shader cache bozuk demektir; ilk init'te temizleriz.
  static const String _legacyBenchKey = 'lumos_fastest_backend_v1';
  static const String _stableBackendKey = 'lumos_stable_backend_v2';
  static const String _backendPreferenceKey = 'lumos_backend_preference_v1';
  static const String _backendProfilePrefix = 'lumos_backend_profile_v2_';

  InferenceModel? _model;
  InferenceChat? _chat;
  String? _chatSignature;
  LiteRtPromptPlan? _activePlan;
  bool _initialized = false;
  bool _loading = false;
  String _activeBackend = 'CPU';
  LiteRtBackendPreference _backendPreference = LiteRtBackendPreference.auto;
  InferenceStats? _lastStats;
  String? _memorySummary;
  String? _recentContext;

  bool get isReady => _initialized;
  bool get isLoading => _loading;
  String get activeBackend => _activeBackend;
  LiteRtBackendPreference get backendPreference => _backendPreference;
  InferenceStats? get lastStats => _lastStats;

  /// Bu cihazlarda support dir'i tek seferlik silip pref key'i temizleriz.
  Future<void> _migrateLegacyBenchCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_legacyBenchKey)) return;

    debugPrint('[migrate] legacy bench cache detected, cleaning');
    try {
      final dir = await getApplicationSupportDirectory();
      await for (final ent in dir.list()) {
        final name = ent.path.split(Platform.pathSeparator).last;
        if (name.contains('xnnpack_cache') ||
            name.contains('opencl') ||
            name.contains('serialized') ||
            name.endsWith('.bin') && !name.contains('gemma')) {
          try {
            await ent.delete(recursive: true);
            debugPrint('[migrate] deleted: $name');
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[migrate] cache cleanup error: $e');
    }
    await prefs.remove(_legacyBenchKey);
  }

  Future<String?> _loadStableBackend() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_stableBackendKey);
  }

  Future<LiteRtBackendPreference> loadBackendPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_backendPreferenceKey);
    _backendPreference = LiteRtBackendPreference.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => LiteRtBackendPreference.auto,
    );
    return _backendPreference;
  }

  Future<void> setBackendPreference(LiteRtBackendPreference preference) async {
    _backendPreference = preference;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendPreferenceKey, preference.name);
  }

  List<(PreferredBackend, String)> _backendCandidates({
    required LiteRtBackendPreference preference,
    String? stableBackend,
  }) {
    final autoBase = <(PreferredBackend, String)>[
      (PreferredBackend.gpu, 'GPU'),
      (PreferredBackend.cpu, 'CPU'),
    ];
    return switch (preference) {
      LiteRtBackendPreference.auto => _prioritizeStableBackend(
        autoBase,
        stableBackend,
      ),
      LiteRtBackendPreference.gpu => autoBase,
      LiteRtBackendPreference.cpu => [(PreferredBackend.cpu, 'CPU')],
      LiteRtBackendPreference.npu => [
        (PreferredBackend.npu, 'NPU'),
        (PreferredBackend.gpu, 'GPU'),
        (PreferredBackend.cpu, 'CPU'),
      ],
    };
  }

  List<(PreferredBackend, String)> _prioritizeStableBackend(
    List<(PreferredBackend, String)> base,
    String? stableBackend,
  ) {
    if (stableBackend == null) return base;
    final stableIndex = base.indexWhere((entry) => entry.$2 == stableBackend);
    if (stableIndex <= 0) return base;
    return [
      base[stableIndex],
      ...base.where((entry) => entry.$2 != stableBackend),
    ];
  }

  Future<void> _saveStableBackend(String backend) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stableBackendKey, backend);
  }

  Future<void> _recordBackendSample(InferenceStats stats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix = '$_backendProfilePrefix${stats.backend}_';
      final previousTtft = prefs.getDouble('${prefix}ttft_ms');
      final previousTps = prefs.getDouble('${prefix}tok_s');
      final nextTtft = previousTtft == null
          ? stats.ttftMs.toDouble()
          : previousTtft * 0.7 + stats.ttftMs * 0.3;
      final nextTps = previousTps == null
          ? stats.decodeTokPerSec
          : previousTps * 0.7 + stats.decodeTokPerSec * 0.3;
      await prefs.setDouble('${prefix}ttft_ms', nextTtft);
      await prefs.setDouble('${prefix}tok_s', nextTps);
      final samples = (prefs.getInt('${prefix}samples') ?? 0) + 1;
      await prefs.setInt('${prefix}samples', samples);
      if (_backendPreference == LiteRtBackendPreference.auto) {
        await prefs.setString(_stableBackendKey, stats.backend);
      }
    } catch (e) {
      debugPrint('[backend profile] sample could not be saved: $e');
    }
  }

  Future<double?> _readDeviceTotalRamGb() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await File('/proc/meminfo').readAsString();
      final m = RegExp(r'MemTotal:\s+(\d+)\s*kB').firstMatch(raw);
      if (m == null) return null;
      final kb = int.parse(m.group(1)!);
      return kb / (1024.0 * 1024.0);
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize({required String modelPath}) async {
    if (_initialized || _loading) return;
    _loading = true;
    try {
      final ramGb = await _readDeviceTotalRamGb();
      if (ramGb != null && ramGb < _minRequiredRamGb) {
        throw InsufficientMemoryException(ramGb, _minRequiredRamGb);
      }

      // 1.5) Eski bench cache'ini varsa temizle (segfault recovery).
      await _migrateLegacyBenchCache();

      // 2) Backend selection: try the latest stable backend first, then fallback.
      // Sentetik benchmark yok; gercek isteklerden EWMA profil topluyoruz.
      final preference = await loadBackendPreference();
      final stableBackend = preference == LiteRtBackendPreference.auto
          ? await _loadStableBackend()
          : null;
      final candidates = _backendCandidates(
        preference: preference,
        stableBackend: stableBackend,
      );
      debugPrint(
        '[backend profile] preference=${preference.label}, '
        'stable=${stableBackend ?? 'none'}, '
        'order=${candidates.map((entry) => entry.$2).join('>')}',
      );

      Object? lastError;
      for (final (backend, label) in candidates) {
        try {
          _model = await FlutterGemma.getActiveModel(
            maxTokens: 8192,
            supportImage: true,
            maxNumImages: 1,
            preferredBackend: backend,
          );
          _activeBackend = label;
          debugPrint('[backend] selected: $label');
          if (preference == LiteRtBackendPreference.auto && lastError != null) {
            await _saveStableBackend(label);
          }
          break;
        } catch (e) {
          lastError = e;
          _model = null;
        }
      }
      if (_model == null) {
        throw StateError('No backend model could be loaded: $lastError');
      }

      _initialized = true;
    } finally {
      _loading = false;
    }
  }

  Stream<ModelResponse> sendMessage({
    required String text,
    Uint8List? imageBytes,
  }) async* {
    if (_model == null) {
      yield* Stream.error(StateError('Model has not been loaded yet.'));
      return;
    }

    final chat = await _ensureChatFor(text: text, imageBytes: imageBytes);
    final plan = _activePlan!;

    final msg = imageBytes != null
        ? Message.withImage(text: text, imageBytes: imageBytes, isUser: true)
        : Message.text(text: text, isUser: true);

    await chat.addQuery(msg);

    yield* _generateAndTrackStats(
      chat,
      plan: plan,
      hadImage: imageBytes != null,
      isToolContinuation: false,
    );
  }

  Stream<ModelResponse> sendToolResponse({
    required String toolName,
    required ToolResult result,
  }) async* {
    final chat = _chat;
    if (chat == null) {
      yield* Stream.error(
        StateError('There is no active LiteRT chat for the tool result.'),
      );
      return;
    }

    await chat.addQuery(
      Message.toolResponse(
        toolName: toolName,
        response: ToolRunner.instance.serializeResult(result),
      ),
    );

    yield* _generateAndTrackStats(
      chat,
      plan: _activePlan ?? _fallbackPlan(),
      hadImage: false,
      isToolContinuation: true,
    );
  }

  Stream<ModelResponse> _generateAndTrackStats(
    InferenceChat chat, {
    required LiteRtPromptPlan plan,
    required bool hadImage,
    required bool isToolContinuation,
  }) async* {
    final totalSw = Stopwatch()..start();
    int? ttftMs;
    int textChunkCount = 0;
    int functionCallCount = 0;
    int? firstTextAtMs;
    var stoppedByOutputLimit = false;
    final maxOutputChunks = isToolContinuation
        ? plan.toolContinuationMaxOutputChunks
        : plan.maxOutputChunks;
    _lastStats = null;

    await for (final r in chat.generateChatResponseAsync()) {
      if (r is TextResponse) {
        if (ttftMs == null) {
          ttftMs = totalSw.elapsedMilliseconds;
          firstTextAtMs = ttftMs;
        }
        textChunkCount++;
        yield r;
        if (textChunkCount >= maxOutputChunks) {
          stoppedByOutputLimit = true;
          break;
        }
        continue;
      }
      if (r is FunctionCallResponse) {
        functionCallCount++;
      }
      yield r;
    }

    final totalMs = totalSw.elapsedMilliseconds;
    final decodeMs = (firstTextAtMs == null) ? 0 : (totalMs - firstTextAtMs);
    final tps = (decodeMs > 0 && textChunkCount > 1)
        ? (textChunkCount - 1) * 1000.0 / decodeMs
        : 0.0;
    _lastStats = InferenceStats(
      backend: _activeBackend,
      ttftMs: ttftMs ?? totalMs,
      totalMs: totalMs,
      tokenCount: textChunkCount,
      decodeTokPerSec: tps,
      requestKind: plan.requestKind,
      promptSignature: plan.signature,
      toolNames: plan.toolNames.toList()..sort(),
      hadImage: hadImage,
      maxOutputChunks: maxOutputChunks,
      stoppedByOutputLimit: stoppedByOutputLimit,
      functionCallCount: functionCallCount,
      approxPromptChars: plan.approxPromptChars,
      memorySummaryChars: plan.memorySummaryChars,
      recentContextChars: plan.recentContextChars,
    );
    await _recordBackendSample(_lastStats!);
    _logInferenceStats(_lastStats!);
  }

  Future<InferenceChat> _ensureChatFor({
    required String text,
    Uint8List? imageBytes,
  }) async {
    final model = _model;
    if (model == null) {
      throw StateError('Model has not been loaded yet.');
    }

    final plan = LiteRtPromptBuilder.build(
      text: text,
      hasImage: imageBytes != null,
      memorySummary: _memorySummary,
      recentContext: _recentContext,
    );
    _activePlan = plan;
    if (_chat != null && _chatSignature == plan.signature) {
      return _chat!;
    }

    await _chat?.close();

    final tools = LiteRtPromptBuilder.selectTools(
      ToolRunner.instance.tools,
      plan.toolNames,
    );
    debugPrint(
      '[litert prompt] kind=${plan.requestKind}, bucket=${plan.signature}, '
      'promptChars=${plan.approxPromptChars}, '
      'memoryChars=${plan.memorySummaryChars}, '
      'recentChars=${plan.recentContextChars}, '
      'maxOut=${plan.maxOutputChunks}, '
      'tools=${tools.map((t) => t.name).join(',')}',
    );

    _chat = await model.createChat(
      systemInstruction: plan.systemPrompt,
      supportImage: true,
      isThinking: false,
      supportsFunctionCalls: tools.isNotEmpty,
      tools: tools,
      modelType: ModelType.gemma4,
      tokenBuffer: 256,
    );
    _chatSignature = plan.signature;
    return _chat!;
  }

  LiteRtPromptPlan _fallbackPlan() {
    return LiteRtPromptBuilder.build(
      text: '',
      hasImage: false,
      memorySummary: _memorySummary,
      recentContext: _recentContext,
    );
  }

  void _logInferenceStats(InferenceStats stats) {
    debugPrint(
      '[perf][litert] backend=${stats.backend} kind=${stats.requestKind} '
      'ttft=${stats.ttftMs}ms total=${stats.totalMs}ms '
      'chunks=${stats.tokenCount}/${stats.maxOutputChunks} '
      'tok_s=${stats.decodeTokPerSec.toStringAsFixed(1)} '
      'stopped=${stats.stoppedByOutputLimit} image=${stats.hadImage} '
      'fn=${stats.functionCallCount} promptChars=${stats.approxPromptChars} '
      'memoryChars=${stats.memorySummaryChars} '
      'recentChars=${stats.recentContextChars} '
      'tools=${stats.toolNames.join(',')} sig=${stats.promptSignature}',
    );
  }

  Future<void> setCompactedContext({
    required String memorySummary,
    required String recentContext,
  }) async {
    final nextMemory = memorySummary.trim();
    final nextRecent = recentContext.trim();
    if (_memorySummary == nextMemory && _recentContext == nextRecent) return;

    _memorySummary = nextMemory.isEmpty ? null : nextMemory;
    _recentContext = nextRecent.isEmpty ? null : nextRecent;
    _activePlan = null;
    _chatSignature = null;
    await _chat?.close();
    _chat = null;
    debugPrint(
      '[litert memory] compacted memory=${_memorySummary?.length ?? 0} chars, '
      'recent=${_recentContext?.length ?? 0} chars',
    );
  }

  Future<void> clearHistory() async {
    await _chat?.clearHistory();
    _chatSignature = null;
    _activePlan = null;
    _memorySummary = null;
    _recentContext = null;
  }

  void dispose() {
    _chat?.close();
    _model?.close();
    _chat = null;
    _chatSignature = null;
    _model = null;
    _initialized = false;
    _activePlan = null;
    _memorySummary = null;
    _recentContext = null;
  }
}
