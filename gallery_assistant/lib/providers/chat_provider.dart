import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/inference_chunk.dart';
import '../models/message.dart';
import '../models/tool_result.dart';
import '../services/inference_router.dart';
import '../services/litert_service.dart';
import '../services/notify_service.dart';
import '../services/route_capture_service.dart';
import '../services/tool_runner.dart';

const _uuid = Uuid();

const _kUiThrottleMs = 50;
const _kMaxLocalToolHops = 8;
const _kLocalKeepLastMessages = 6;
const _kLocalCompactAfterMessages = 8;
const _kLocalCompactStride = 2;
const _kMaxThinkingChars = 1200;
const _kTextLeakedToolFallbacks = {
  'check_sensor_context',
  'measure_brightness',
  'get_environment_status',
  'detect_motion_state',
  'read_inertial_sensors',
  'capture_image',
  'get_date',
  'get_time',
};
const _kSensorOnlyToolNames = {
  'check_sensor_context',
  'measure_brightness',
  'get_environment_status',
  'detect_motion_state',
  'read_inertial_sensors',
};

class ChatState {
  final List<ChatMessage> messages;
  final bool modelReady;
  final bool modelLoading;
  final String? modelError;
  final bool ttsEnabled;
  final LiteRtBackendPreference backendPreference;
  final String activeBackend;

  const ChatState({
    this.messages = const [],
    this.modelReady = false,
    this.modelLoading = false,
    this.modelError,
    this.ttsEnabled = true,
    this.backendPreference = LiteRtBackendPreference.auto,
    this.activeBackend = '',
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? modelReady,
    bool? modelLoading,
    String? modelError,
    bool? ttsEnabled,
    LiteRtBackendPreference? backendPreference,
    String? activeBackend,
  }) => ChatState(
    messages: messages ?? this.messages,
    modelReady: modelReady ?? this.modelReady,
    modelLoading: modelLoading ?? this.modelLoading,
    modelError: modelError ?? this.modelError,
    ttsEnabled: ttsEnabled ?? this.ttsEnabled,
    backendPreference: backendPreference ?? this.backendPreference,
    activeBackend: activeBackend ?? this.activeBackend,
  );
}

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier() : super(const ChatState());

  Timer? _navTimer;
  RouteResult? _activeRoute;
  final List<Timer> _reminderTimers = [];
  int _lastLocalCompactionAt = 0;
  bool _startupPromptSent = false;

  Future<void> sendStartupPrompt() async {
    if (_startupPromptSent || !state.modelReady) return;
    _startupPromptSent = true;

    await sendMessage(text: '.');
  }

  void stopNavigation() {
    _navTimer?.cancel();
    _navTimer = null;
    _activeRoute = null;
  }

  int cancelAllReminders() {
    final n = _reminderTimers.length;
    for (final t in _reminderTimers) {
      t.cancel();
    }
    _reminderTimers.clear();
    return n;
  }

  void scheduleReminder(String text, int minutes) {
    final t = Timer(Duration(minutes: minutes), () async {
      await NotifyService.instance.remind(text);
      final msg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        text: 'Reminder: $text',
        status: MessageStatus.done,
      );
      state = state.copyWith(messages: [...state.messages, msg]);
    });
    _reminderTimers.add(t);
  }

  /// target: navigation | reminders | tts | all
  int cancelAction(String target) {
    var count = 0;
    if (target == 'navigation' || target == 'all') {
      if (_navTimer != null) count++;
      stopNavigation();
    }
    if (target == 'reminders' || target == 'all') {
      count += cancelAllReminders();
    }
    return count;
  }

  void _startNavigationLoop(RouteResult route) {
    _navTimer?.cancel();
    _activeRoute = route;
    _navTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      final r = _activeRoute;
      if (r == null) return;
      final currentOrigin =
          await RouteCaptureService.instance.currentLocationString() ??
          r.origin;
      final shot = await RouteCaptureService.instance.capture(
        origin: currentOrigin,
        destination: r.destination,
        mode: r.mode,
      );
      if (shot == null) return;
      await _narrateRouteImage(
        shot,
        prefix:
            'Navigation update. Based on the current location, describe the remaining route briefly. '
            'Use one paragraph, focus only on the next maneuver and distance. '
            'If the user has arrived, say that the destination has been reached.',
      );
    });
  }

  Future<void> _narrateRouteImage(
    Uint8List bytes, {
    String prefix =
        'This is a Google Maps route screenshot from point A to point B. '
        'Describe it for a visually impaired user with short step-by-step guidance, distances, and directions. '
        'Use clock-face directions and phrases like ahead, left, and right. Keep street names as written.',
  }) async {
    await sendMessage(text: prefix, imageBytes: bytes);
  }

  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  void _patchThrottled(
    String id, {
    required String text,
    String? thinkingText,
  }) {
    final now = DateTime.now();
    if (now.difference(_lastUiUpdate).inMilliseconds >= _kUiThrottleMs) {
      _lastUiUpdate = now;
      _patch(id, text: text, thinkingText: thinkingText);
    }
  }

  Future<void> initModel(String modelPath) async {
    state = state.copyWith(modelLoading: true, modelError: null);
    try {
      final backendPreference = await LiteRtService.instance
          .loadBackendPreference();
      state = state.copyWith(backendPreference: backendPreference);
      await LiteRtService.instance.initialize(modelPath: modelPath);
      state = state.copyWith(
        modelReady: true,
        modelLoading: false,
        activeBackend: LiteRtService.instance.activeBackend,
      );
    } catch (e) {
      state = state.copyWith(
        modelLoading: false,
        modelError: 'Model could not be loaded: $e',
      );
    }
  }

  void useCloudMode() {
    InferenceRouter.instance.mode = InferenceMode.cloud;
    state = state.copyWith(modelReady: true, modelLoading: false);
  }

  Future<void> loadBackendPreference() async {
    final backendPreference = await LiteRtService.instance
        .loadBackendPreference();
    state = state.copyWith(
      backendPreference: backendPreference,
      activeBackend: LiteRtService.instance.activeBackend,
    );
  }

  Future<void> setBackendPreference(LiteRtBackendPreference preference) async {
    if (preference == state.backendPreference) return;

    await LiteRtService.instance.setBackendPreference(preference);
    state = state.copyWith(backendPreference: preference);

    if (InferenceRouter.instance.mode != InferenceMode.local ||
        !LiteRtService.instance.isReady) {
      return;
    }

    state = state.copyWith(
      modelReady: false,
      modelLoading: true,
      modelError: null,
      activeBackend: '',
    );

    try {
      LiteRtService.instance.dispose();
      await LiteRtService.instance.initialize(modelPath: '');
      await _compactLocalHistoryIfNeeded(force: true);
      state = state.copyWith(
        modelReady: true,
        modelLoading: false,
        activeBackend: LiteRtService.instance.activeBackend,
      );
    } catch (e) {
      state = state.copyWith(
        modelLoading: false,
        modelError: 'Backend could not be changed: $e',
      );
    }
  }

  Future<void> _compactLocalHistoryIfNeeded({bool force = false}) async {
    final messageCount = state.messages.length;
    if (messageCount == 0) return;
    if (!force && messageCount < _kLocalCompactAfterMessages) return;
    if (!force &&
        messageCount - _lastLocalCompactionAt < _kLocalCompactStride) {
      return;
    }

    final splitAt = math.max(0, messageCount - _kLocalKeepLastMessages);
    final older = state.messages.take(splitAt).toList(growable: false);
    final recent = state.messages.skip(splitAt).toList(growable: false);
    final memorySummary = _buildMemorySummary(older);
    final recentContext = _buildRecentContext(recent);

    await LiteRtService.instance.setCompactedContext(
      memorySummary: memorySummary,
      recentContext: recentContext,
    );
    _lastLocalCompactionAt = messageCount;
  }

  String _buildMemorySummary(List<ChatMessage> messages) {
    if (messages.isEmpty) return '';
    final facts = <String>[];
    String? latestUser;
    for (final msg in messages.reversed) {
      if (msg.isUser && msg.text.trim().isNotEmpty) {
        latestUser = _compactText(msg.text, 120);
        break;
      }
    }
    if (latestUser != null) {
      facts.add('Earlier user request: $latestUser');
    }

    for (final msg in messages.reversed) {
      final lines = _toolMemoryLines(msg).toList(growable: false).reversed;
      for (final line in lines) {
        if (!facts.contains(line)) {
          facts.add(line);
        }
        if (facts.length >= 6) break;
      }
      if (facts.length >= 6) break;
    }

    facts.add('Keep replies concise, spoken, and accessibility-focused.');
    return facts.take(7).join(' | ');
  }

  String _buildRecentContext(List<ChatMessage> messages) {
    final lines = <String>[];
    for (final msg in messages) {
      final pieces = <String>[];
      final text = _compactText(msg.text, 140);
      if (text.isNotEmpty) pieces.add(text);
      if (msg.hasImage) pieces.add('[image attached]');
      pieces.addAll(_toolMemoryLines(msg));
      if (pieces.isEmpty) continue;
      lines.add('${_roleName(msg)}: ${pieces.join(' ')}');
    }
    return lines.take(_kLocalKeepLastMessages).join(' / ');
  }

  String _roleName(ChatMessage message) => message.isUser ? 'User' : 'Lumos';

  String _compactText(String value, int maxChars) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= maxChars) return cleaned;
    return '${cleaned.substring(0, maxChars - 1).trimRight()}...';
  }

  Iterable<ToolResult> _toolResultsFor(ChatMessage message) {
    if (message.toolInvocations.isNotEmpty) {
      return message.toolInvocations
          .map((invocation) => invocation.result)
          .toList(growable: false);
    }
    final result = message.toolResultData;
    return result == null ? const <ToolResult>[] : [result];
  }

  Iterable<String> _toolMemoryLines(ChatMessage message) sync* {
    for (final result in _toolResultsFor(message)) {
      final line = _toolMemoryLine(result);
      if (line != null) yield line;
    }
  }

  String? _toolMemoryLine(ToolResult? result) {
    return switch (result) {
      null => null,
      ContactSearchResult(:final query, :final contacts) =>
        'Contact search "$query": ${contacts.length} result(s).',
      CallResult(:final name) => 'Call started for $name.',
      ReminderResult(:final text, :final minutes) =>
        'Reminder set: "${_compactText(text, 80)}" in $minutes minute(s).',
      LocationResult(:final query, :final info) =>
        'Location "$query": ${_compactText(info, 100)}.',
      RouteResult(:final origin, :final destination, :final mode) =>
        'Route requested from $origin to $destination by $mode.',
      CancelActionResult(:final target, :final cancelledCount) =>
        'Cancelled $cancelledCount $target action(s).',
      DateResult(:final dateTime) => 'Date tool returned $dateTime.',
      TimeResult(:final dateTime) => 'Time tool returned $dateTime.',
      InternetConnectionStatusResult(
        :final hasInternet,
        :final connectionType,
      ) =>
        'Internet status: ${hasInternet ? 'online' : 'offline'} via $connectionType.',
      SensorContextResult() => 'Sensor context returned default values.',
      BrightnessResult() => 'Brightness sensor returned default values.',
      EnvironmentStatusResult() =>
        'Environment sensors returned default values.',
      MotionStateResult() => 'Motion sensor returned default values.',
      InertialSensorResult() => 'Inertial sensors returned default values.',
      CaptureImageResult(:final reason, :final error) =>
        error == null
            ? 'Camera image captured: ${_compactText(reason, 80)}.'
            : 'Camera capture failed: ${_compactText(error, 80)}.',
      TextReadResult(:final extractedText) =>
        'Read text: ${_compactText(extractedText, 100)}.',
      ObjectFoundResult(:final objectName, :final clockPosition) =>
        'Object found: $objectName ${clockPosition ?? ''}.',
      SceneResult(:final focus) => 'Scene analyzed: ${focus ?? 'general'}.',
      NavigationStoppedResult() => 'Navigation stopped.',
    };
  }

  void _appendThinking(StringBuffer buffer, String content) {
    if (buffer.length >= _kMaxThinkingChars) return;
    final remaining = _kMaxThinkingChars - buffer.length;
    if (content.length <= remaining) {
      buffer.write(content);
      return;
    }
    buffer.write(content.substring(0, remaining).trimRight());
    buffer.write('\n...');
  }

  String _cleanAssistantText(String value) {
    final leadingName = RegExp(r'^\s*Lumos\b[,\s:;.\-]*', caseSensitive: false);
    final match = leadingName.firstMatch(value);
    if (match == null) return value;

    final rest = value.substring(match.end).trimLeft();
    return rest.isEmpty ? value.trimLeft() : rest;
  }

  String _visibleAssistantText(String value) {
    if (_leakedToolName(value) != null) return '';
    return _cleanAssistantText(value);
  }

  String? _leakedToolName(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;

    for (final name in _kTextLeakedToolFallbacks) {
      final bareLine = RegExp(
        '^`?${RegExp.escape(name)}`?'
        r'(\s*\(\s*\))?\s*[.!?。！？]*$',
        caseSensitive: false,
      );
      if (text.split('\n').map((line) => line.trim()).any(bareLine.hasMatch)) {
        return name;
      }

      final endsWithTool = RegExp(
        '${RegExp.escape(name)}'
        r'(\s*\(\s*\))?\s*[.!?。！？]*$',
        caseSensitive: false,
      );
      if (text.length <= 220 && endsWithTool.hasMatch(text)) return name;
    }
    return null;
  }

  Map<String, dynamic> _fallbackToolArgs(String name, String userText) {
    if (name != 'capture_image') return const <String, dynamic>{};

    final reason = _compactText(userText, 80);
    return {'reason': reason.isEmpty ? 'current view' : reason};
  }

  bool _isCurrentViewRequest(String value) {
    final text = value.toLowerCase();
    return text.contains('what do you see') ||
        text.contains('what is in front of me') ||
        text.contains('what is around me') ||
        text.contains("what's in front of me");
  }

  String _effectiveToolName(String name, String userText) {
    if (_isCurrentViewRequest(userText) &&
        _kSensorOnlyToolNames.contains(name)) {
      return 'capture_image';
    }
    return name;
  }

  Map<String, dynamic> _effectiveToolArgs(
    String name,
    Map<String, dynamic> args,
    String userText,
  ) {
    if (name != 'capture_image') return args;

    final reason = args['reason'];
    if (reason is String && reason.trim().isNotEmpty) return args;

    return {...args, ..._fallbackToolArgs(name, userText)};
  }

  Future<int> _consumeLeakedToolCall({
    required String assistantId,
    required StringBuffer textBuffer,
    required StringBuffer thinkBuffer,
    required int toolHops,
    required String userText,
  }) async {
    if (toolHops >= _kMaxLocalToolHops) return toolHops;

    final leakedName = _leakedToolName(textBuffer.toString());
    if (leakedName == null) return toolHops;
    final toolName = _effectiveToolName(leakedName, userText);

    textBuffer.clear();
    _patch(assistantId, text: '');

    final args = _effectiveToolArgs(
      toolName,
      _fallbackToolArgs(toolName, userText),
      userText,
    );
    final result = await ToolRunner.instance.run(
      ToolCallRequest(name: toolName, args: args),
    );
    _patch(
      assistantId,
      toolCall: ToolCall(name: toolName, arguments: args),
      toolResultData: result,
    );

    final nextHops = toolHops + 1;
    return _consumeToolContinuation(
      stream: InferenceRouter.instance.sendToolResponse(
        name: toolName,
        result: result,
      ),
      assistantId: assistantId,
      textBuffer: textBuffer,
      thinkBuffer: thinkBuffer,
      toolHops: nextHops,
      userText: userText,
    );
  }

  Future<void> sendMessage({
    required String text,
    Uint8List? imageBytes,
  }) async {
    if (!state.modelReady) return;
    if (text.trim().isEmpty && imageBytes == null) return;

    await _compactLocalHistoryIfNeeded();

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      text: text,
      imageBytes: imageBytes,
    );
    final assistantMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      text: '',
      status: MessageStatus.streaming,
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg, assistantMsg],
    );

    final textBuffer = StringBuffer();
    final thinkBuffer = StringBuffer();
    var localToolHops = 0;
    _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

    try {
      await for (final response in InferenceRouter.instance.sendMessage(
        text: text,
        imageBytes: imageBytes,
      )) {
        if (response is TextChunk) {
          textBuffer.write(response.token);
          _patchThrottled(
            assistantMsg.id,
            text: _visibleAssistantText(textBuffer.toString()),
          );
        } else if (response is ThinkingChunk) {
          _appendThinking(thinkBuffer, response.content);
          _patchThrottled(
            assistantMsg.id,
            text: _cleanAssistantText(textBuffer.toString()),
            thinkingText: thinkBuffer.toString(),
          );
        } else if (response is ToolInvokedChunk) {
          textBuffer.clear();
          _patchThrottled(assistantMsg.id, text: '');
          _patch(
            assistantMsg.id,
            toolCall: ToolCall(name: response.name, arguments: response.args),
            toolResultData: response.result as ToolResult,
          );
        } else if (response is FunctionCallChunk) {
          textBuffer.clear();
          _patchThrottled(assistantMsg.id, text: '');

          final toolName = _effectiveToolName(response.name, text);
          final args = _effectiveToolArgs(toolName, response.args, text);
          final result = await ToolRunner.instance.run(
            ToolCallRequest(name: toolName, args: args),
          );
          _patch(
            assistantMsg.id,
            toolCall: ToolCall(name: toolName, arguments: args),
            toolResultData: result,
          );

          if (localToolHops < _kMaxLocalToolHops) {
            localToolHops++;
            localToolHops = await _consumeToolContinuation(
              stream: InferenceRouter.instance.sendToolResponse(
                name: toolName,
                result: result,
              ),
              assistantId: assistantMsg.id,
              textBuffer: textBuffer,
              thinkBuffer: thinkBuffer,
              toolHops: localToolHops,
              userText: text,
            );
          } else {
            textBuffer.write(
              'Too many tool calls happened in a row, so I stopped here.',
            );
            _patchThrottled(assistantMsg.id, text: textBuffer.toString());
          }

          // Tool sonucu tekrar LiteRT sohbetine verildi; model final yaniti uretir.
        }
      }

      localToolHops = await _consumeLeakedToolCall(
        assistantId: assistantMsg.id,
        textBuffer: textBuffer,
        thinkBuffer: thinkBuffer,
        toolHops: localToolHops,
        userText: text,
      );

      _patch(
        assistantMsg.id,
        text: _cleanAssistantText(textBuffer.toString()),
        thinkingText: thinkBuffer.isEmpty ? null : thinkBuffer.toString(),
        status: MessageStatus.done,
        stats: LiteRtService.instance.lastStats,
      );

      final lastMsg = state.messages.lastWhere((m) => m.id == assistantMsg.id);
      for (final toolData in _toolResultsFor(lastMsg)) {
        await _handleToolSideEffect(toolData);
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('[chat error] $e\n$st');
      _patch(assistantMsg.id, text: 'Error: $e', status: MessageStatus.error);
    }
  }

  Future<void> _handleToolSideEffect(ToolResult toolData) async {
    if (toolData is CaptureImageResult && toolData.imageBytes != null) {
      await sendMessage(
        text: _captureFollowUpPrompt(toolData.reason),
        imageBytes: Uint8List.fromList(toolData.imageBytes!),
      );
    } else if (toolData is RouteResult && toolData.imageBytes != null) {
      await _narrateRouteImage(Uint8List.fromList(toolData.imageBytes!));
      _startNavigationLoop(toolData);
    } else if (toolData is NavigationStoppedResult) {
      stopNavigation();
    } else if (toolData is CancelActionResult) {
      cancelAction(toolData.target);
    } else if (toolData is ReminderResult) {
      scheduleReminder(toolData.text, toolData.minutes);
    }
  }

  String _captureFollowUpPrompt(String reason) {
    if (reason == 'task:read_text') {
      return 'OCR task: read and transcribe all visible text in this ESP32-CAM image. Answer in the user language. If no readable text is visible, say that clearly. Do not describe unrelated scene details unless they help identify the text.';
    }

    const prefix = 'task:identify_object:';
    if (reason.startsWith(prefix)) {
      final object = reason.substring(prefix.length).trim();
      final target = object.isEmpty ? 'requested object' : object;
      return 'Object search task: inspect this ESP32-CAM image and determine whether "$target" is visible. Answer in the user language. If it is visible, give its clock-face direction and approximate distance if possible. If it is not visible or uncertain, say so clearly.';
    }

    return 'Analyze this ESP32-CAM image for the previous user request. Answer directly in the user language.';
  }

  Future<int> _consumeToolContinuation({
    required Stream<InferenceChunk> stream,
    required String assistantId,
    required StringBuffer textBuffer,
    required StringBuffer thinkBuffer,
    required int toolHops,
    required String userText,
  }) async {
    var hops = toolHops;

    await for (final response in stream) {
      if (response is TextChunk) {
        textBuffer.write(response.token);
        _patchThrottled(
          assistantId,
          text: _visibleAssistantText(textBuffer.toString()),
        );
      } else if (response is ThinkingChunk) {
        _appendThinking(thinkBuffer, response.content);
        _patchThrottled(
          assistantId,
          text: _cleanAssistantText(textBuffer.toString()),
          thinkingText: thinkBuffer.toString(),
        );
      } else if (response is ToolInvokedChunk) {
        textBuffer.clear();
        _patchThrottled(assistantId, text: '');
        _patch(
          assistantId,
          toolCall: ToolCall(name: response.name, arguments: response.args),
          toolResultData: response.result as ToolResult,
        );
      } else if (response is FunctionCallChunk) {
        textBuffer.clear();
        _patchThrottled(assistantId, text: '');

        if (hops >= _kMaxLocalToolHops) {
          textBuffer.write(
            'Too many tool calls happened in a row, so I stopped here.',
          );
          _patchThrottled(assistantId, text: textBuffer.toString());
          continue;
        }

        hops++;
        final toolName = _effectiveToolName(response.name, userText);
        final args = _effectiveToolArgs(toolName, response.args, userText);
        final result = await ToolRunner.instance.run(
          ToolCallRequest(name: toolName, args: args),
        );
        _patch(
          assistantId,
          toolCall: ToolCall(name: toolName, arguments: args),
          toolResultData: result,
        );

        hops = await _consumeToolContinuation(
          stream: InferenceRouter.instance.sendToolResponse(
            name: toolName,
            result: result,
          ),
          assistantId: assistantId,
          textBuffer: textBuffer,
          thinkBuffer: thinkBuffer,
          toolHops: hops,
          userText: userText,
        );
      }
    }

    hops = await _consumeLeakedToolCall(
      assistantId: assistantId,
      textBuffer: textBuffer,
      thinkBuffer: thinkBuffer,
      toolHops: hops,
      userText: userText,
    );

    return hops;
  }

  void toggleTts() => state = state.copyWith(ttsEnabled: !state.ttsEnabled);

  Future<void> clearHistory() async {
    await InferenceRouter.instance.clearHistory();
    _lastLocalCompactionAt = 0;
    state = state.copyWith(messages: []);
  }

  void _patch(
    String id, {
    String? text,
    String? thinkingText,
    ToolCall? toolCall,
    ToolResult? toolResultData,
    MessageStatus? status,
    InferenceStats? stats,
  }) {
    final msgs = state.messages;
    final idx = msgs.indexWhere((m) => m.id == id);
    if (idx == -1) return;

    final m = msgs[idx];
    if (text != null) m.text = text;
    if (thinkingText != null) m.thinkingText = thinkingText;
    if (toolCall != null) m.toolCall = toolCall;
    if (toolResultData != null) m.toolResultData = toolResultData;
    if (toolCall != null && toolResultData != null) {
      m.toolInvocations = [
        ...m.toolInvocations,
        ToolInvocation(call: toolCall, result: toolResultData),
      ];
    }
    if (status != null) m.status = status;
    if (stats != null) m.stats = stats;

    final updated = List<ChatMessage>.of(msgs);
    updated[idx] = m;
    state = state.copyWith(messages: updated);
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>(
  (_) => ChatNotifier(),
);
