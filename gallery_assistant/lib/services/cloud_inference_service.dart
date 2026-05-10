import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/inference_chunk.dart';
import '../models/tool_result.dart';
import 'litert_prompts.dart';
import 'tool_runner.dart';

const _openRouterApiKey =
    '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';
const _model = 'google/gemma-4-26b-a4b-it:nitro';
const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';
const _maxToolHops = 4;

String _readingOrUnknown(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'unknown' : trimmed;
}

String _sensorContextSummary({
  required String lux,
  required String distanceMm,
  required String temperatureC,
  required String humidityPercent,
  required String pressureHpa,
  required String motion,
}) {
  final temp = _readingOrUnknown(temperatureC);
  final humidity = _readingOrUnknown(humidityPercent);
  final light = _readingOrUnknown(lux);
  final distance = _readingOrUnknown(distanceMm);
  final pressure = _readingOrUnknown(pressureHpa);
  final movement = _readingOrUnknown(motion);
  return 'Local sensor readings, not official weather: temperature $temp degrees Celsius, humidity $humidity percent, ambient light $light lux, distance reading $distance mm, pressure $pressure hPa, motion $movement. Speak these values naturally; humidity values are percentages, not one hundred percent unless the value is 100.';
}

String _brightnessSummary({
  required String lux,
  required String classification,
}) {
  final light = _readingOrUnknown(lux);
  final label = _readingOrUnknown(classification);
  return 'Local light reading: ambient light is $label at $light lux.';
}

String _nearObstacleSummary({
  required String distanceMm,
  required String obstacle,
}) {
  final distance = _readingOrUnknown(distanceMm);
  final hasObstacle = obstacle.trim().toLowerCase() == 'true';
  final status = hasObstacle
      ? 'near obstacle detected'
      : 'no near obstacle detected';
  return 'Local short-range distance reading: $status. Distance value is $distance mm; use it only as a short-range cue, not as exact room measurement.';
}

String _environmentSummary({
  required String temperatureC,
  required String humidityPercent,
  required String pressureHpa,
  required String comfort,
}) {
  final temp = _readingOrUnknown(temperatureC);
  final humidity = _readingOrUnknown(humidityPercent);
  final pressure = _readingOrUnknown(pressureHpa);
  final comfortLabel = _readingOrUnknown(comfort);
  return 'Local environment reading, not official weather: temperature $temp degrees Celsius, humidity $humidity percent, pressure $pressure hPa, comfort $comfortLabel.';
}

String _motionSummary({
  required String stable,
  required String tilt,
  required String motion,
}) {
  final stableLabel = _readingOrUnknown(stable);
  final tiltLabel = _readingOrUnknown(tilt);
  final movement = _readingOrUnknown(motion);
  return 'Local motion reading: stable $stableLabel, tilt $tiltLabel, motion $movement.';
}

Map<String, dynamic> _routeResultPayload({
  required String origin,
  required String destination,
  required String mode,
  required String? error,
}) {
  final payload = <String, dynamic>{
    'origin': origin,
    'destination': destination,
    'mode': mode,
  };
  if (error == null) {
    payload['note'] =
        'Route screenshot captured; will be sent as the next user image — describe step-by-step.';
  } else {
    payload['error'] = error;
  }
  return payload;
}

String get _systemPrompt => [
  LiteRtPrompts.base,
  LiteRtPrompts.visual,
  LiteRtPrompts.safety,
  LiteRtPrompts.contacts,
  LiteRtPrompts.offline,
  LiteRtPrompts.sensors,
  LiteRtPrompts.reminders,
  LiteRtPrompts.dateTime,
  LiteRtPrompts.cancellation,
].join('\n');

class CloudInferenceService {
  CloudInferenceService._();
  static final CloudInferenceService instance = CloudInferenceService._();

  final List<Map<String, dynamic>> _history = [];
  final http.Client _client = http.Client();

  bool get isConfigured =>
      _openRouterApiKey.isNotEmpty && _openRouterApiKey.startsWith('sk-or-');

  void clearHistory() => _history.clear();

  List<Map<String, dynamic>> _buildTools() {
    return ToolRunner.instance.tools.map((t) {
      return {
        'type': 'function',
        'function': {
          'name': t.name,
          'description': t.description,
          'parameters': t.parameters,
        },
      };
    }).toList();
  }

  Map<String, dynamic> _buildUserMessage(String text, Uint8List? imageBytes) {
    if (imageBytes == null) {
      return {'role': 'user', 'content': text};
    }
    final b64 = base64Encode(imageBytes);
    return {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': text},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,$b64'},
        },
      ],
    };
  }

  Stream<InferenceChunk> sendMessage({
    required String text,
    Uint8List? imageBytes,
  }) async* {
    _history.add(_buildUserMessage(text, imageBytes));

    for (var hop = 0; hop < _maxToolHops; hop++) {
      final turn = _TurnState();
      await for (final chunk in _streamOneTurn(turn)) {
        yield chunk;
      }

      if (turn.toolCalls.isEmpty) {
        if (turn.assistantText.isNotEmpty) {
          final assistantMessage = <String, dynamic>{
            'role': 'assistant',
            'content': turn.assistantText.toString(),
          };
          _history.add(assistantMessage);
        }
        return;
      }

      // 2) tool çağrılarını history'ye ekle (assistant-side)
      final assistTxt = turn.assistantText.toString();
      final assistantMessage = <String, dynamic>{
        'role': 'assistant',
        'content': assistTxt.isEmpty ? null : assistTxt,
        'tool_calls': turn.toolCalls
            .map(
              (c) => {
                'id': c.id,
                'type': 'function',
                'function': {'name': c.name, 'arguments': c.argsJson},
              },
            )
            .toList(),
      };
      _history.add(assistantMessage);

      // 3) her tool'u çalıştır, result'ı yield et + history'ye ekle
      for (final call in turn.toolCalls) {
        final args = _safeJson(call.argsJson);
        final result = await ToolRunner.instance.run(
          ToolCallRequest(name: call.name, args: args),
        );
        yield ToolInvokedChunk(name: call.name, args: args, result: result);

        _history.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'name': call.name,
          'content': _serializeToolResult(result),
        });
      }

      // loop: model şimdi result'ları görüp final cevabı üretsin
    }
  }

  Stream<InferenceChunk> _streamOneTurn(_TurnState turn) async* {
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ..._history,
    ];

    final body = jsonEncode({
      'model': _model,
      'messages': messages,
      'stream': true,
      'tools': _buildTools(),
      'tool_choice': 'auto',
    });

    final request = http.Request('POST', Uri.parse(_endpoint));
    request.headers.addAll({
      'Authorization': 'Bearer $_openRouterApiKey',
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://lumos.local',
      'X-Title': 'LUMOS',
    });
    request.body = body;

    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final errBody = await response.stream.bytesToString();
      dev.log(
        '[OpenRouter HTTP ${response.statusCode}] $errBody',
        name: 'cloud',
      );
      throw Exception('OpenRouter ${response.statusCode}: $errBody');
    }

    final toolAccum = <int, _ToolAccum>{};

    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    var sawAnyData = false;
    await for (final line in lineStream) {
      if (!line.startsWith('data:')) {
        if (line.trim().isNotEmpty) {
          dev.log('[non-SSE line] $line', name: 'cloud');
        }
        continue;
      }
      final data = line.substring(5).trim();
      if (data == '[DONE]') break;
      if (data.isEmpty) continue;
      sawAnyData = true;

      Map<String, dynamic> json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } catch (e) {
        dev.log('[JSON parse fail] $data', name: 'cloud');
        continue;
      }

      // Mid-stream error
      if (json['error'] != null) {
        dev.log('[stream error] ${json['error']}', name: 'cloud');
        throw Exception('OpenRouter stream error: ${json['error']}');
      }

      final choices = json['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final choice = choices[0] as Map<String, dynamic>;
      final delta = choice['delta'];
      if (delta is! Map<String, dynamic>) continue;

      final reasoning = _reasoningTextFromDelta(delta);
      if (reasoning.isNotEmpty) {
        turn.assistantReasoning.write(reasoning);
        yield ThinkingChunk(reasoning);
      }

      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
        turn.assistantText.write(content);
        yield TextChunk(content);
      }

      final toolCalls = delta['tool_calls'];
      if (toolCalls is List) {
        for (final tc in toolCalls) {
          if (tc is! Map<String, dynamic>) continue;
          final idx = (tc['index'] as int?) ?? 0;
          final acc = toolAccum.putIfAbsent(idx, _ToolAccum.new);
          if (tc['id'] is String) acc.id = tc['id'] as String;
          final fn = tc['function'];
          if (fn is Map<String, dynamic>) {
            if (fn['name'] is String) acc.name = fn['name'] as String;
            if (fn['arguments'] is String) {
              acc.argsBuffer.write(fn['arguments']);
            }
          }
        }
      }
    }

    if (!sawAnyData) {
      dev.log('[no SSE data received]', name: 'cloud');
    }
    dev.log(
      '[turn done] text=${turn.assistantText.length} chars, tools=${toolAccum.length}',
      name: 'cloud',
    );

    turn.toolCalls.addAll(
      toolAccum.values
          .where((a) => a.name != null)
          .map(
            (a) => _ToolCall(
              id: a.id ?? 'call_${a.name}_${a.argsBuffer.hashCode}',
              name: a.name!,
              argsJson: a.argsBuffer.toString(),
            ),
          ),
    );
  }

  String _reasoningTextFromDelta(Map<String, dynamic> delta) {
    for (final key in const ['reasoning', 'reasoning_content', 'thinking']) {
      final value = delta[key];
      if (value is String && value.isNotEmpty) return value;
    }

    final details = delta['reasoning_details'];
    if (details is! List) return '';

    final buffer = StringBuffer();
    for (final item in details) {
      if (item is! Map) continue;
      final value = item['text'] ?? item['summary'];
      if (value is String && value.isNotEmpty) {
        buffer.write(value);
      }
    }
    return buffer.toString();
  }

  Map<String, dynamic> _safeJson(String s) {
    if (s.trim().isEmpty) return {};
    try {
      final v = jsonDecode(s);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  String _serializeToolResult(ToolResult r) {
    return switch (r) {
      ContactSearchResult(:final query, :final contacts) => jsonEncode({
        'query': query,
        'count': contacts.length,
        'contacts': contacts
            .map((c) => {'name': c.name, 'phone': c.phone})
            .toList(),
      }),
      CallResult(:final name, :final phone) => jsonEncode({
        'status': 'calling',
        'name': name,
        'phone': phone,
      }),
      DateResult(:final dateTime) => jsonEncode({
        'date': dateTime.toIso8601String().split('T').first,
      }),
      TimeResult(:final dateTime) => jsonEncode({
        'time':
            '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}',
      }),
      CaptureImageResult(:final imageBytes, :final reason, :final error) =>
        jsonEncode({
          'captured': imageBytes != null,
          'reason': reason,
          'error': error,
          'note': imageBytes != null
              ? 'Camera image captured; it will be sent as the next user image for analysis.'
              : 'Camera capture failed.',
        }),
      InternetConnectionStatusResult(
        :final hasInternet,
        :final connectionType,
        :final checkedHost,
        :final info,
      ) =>
        jsonEncode({
          'has_internet': hasInternet,
          'connection_type': connectionType,
          'checked_host': checkedHost,
          'info': info,
        }),
      SensorContextResult(
        :final lux,
        :final distanceMm,
        :final temperatureC,
        :final humidityPercent,
        :final pressureHpa,
        :final motion,
      ) =>
        jsonEncode({
          'summary': _sensorContextSummary(
            lux: lux,
            distanceMm: distanceMm,
            temperatureC: temperatureC,
            humidityPercent: humidityPercent,
            pressureHpa: pressureHpa,
            motion: motion,
          ),
          'lux': lux,
          'distance_mm': distanceMm,
          'temperature_c': temperatureC,
          'humidity_percent': humidityPercent,
          'pressure_hpa': pressureHpa,
          'motion': motion,
        }),
      BrightnessResult(:final lux, :final classification) => jsonEncode({
        'summary': _brightnessSummary(lux: lux, classification: classification),
        'lux': lux,
        'classification': classification,
      }),
      NearObstacleResult(:final distanceMm, :final obstacle) => jsonEncode({
        'summary': _nearObstacleSummary(
          distanceMm: distanceMm,
          obstacle: obstacle,
        ),
        'distance_mm': distanceMm,
        'obstacle': obstacle,
      }),
      EnvironmentStatusResult(
        :final temperatureC,
        :final humidityPercent,
        :final pressureHpa,
        :final comfort,
      ) =>
        jsonEncode({
          'summary': _environmentSummary(
            temperatureC: temperatureC,
            humidityPercent: humidityPercent,
            pressureHpa: pressureHpa,
            comfort: comfort,
          ),
          'temperature_c': temperatureC,
          'humidity_percent': humidityPercent,
          'pressure_hpa': pressureHpa,
          'comfort': comfort,
        }),
      MotionStateResult(:final stable, :final tilt, :final motion) =>
        jsonEncode({
          'summary': _motionSummary(stable: stable, tilt: tilt, motion: motion),
          'stable': stable,
          'tilt': tilt,
          'motion': motion,
        }),
      ReminderResult(:final text, :final minutes) => jsonEncode({
        'set': true,
        'text': text,
        'minutes': minutes,
      }),
      LocationResult(:final query, :final info) => jsonEncode({
        'query': query,
        'info': info,
      }),
      ObjectFoundResult(:final objectName, :final clockPosition) => jsonEncode({
        'object': objectName,
        'position': clockPosition ?? 'unknown',
      }),
      SceneResult(:final focus) => jsonEncode({
        'focus': focus ?? 'general scene',
      }),
      TextReadResult(:final extractedText) => jsonEncode({
        'text': extractedText,
      }),
      NavigationStoppedResult() => jsonEncode({'stopped': true}),
      CancelActionResult(:final target, :final cancelledCount) => jsonEncode({
        'target': target,
        'cancelled': cancelledCount,
      }),
      RouteResult(
        :final origin,
        :final destination,
        :final mode,
        :final error,
      ) =>
        jsonEncode(
          _routeResultPayload(
            origin: origin,
            destination: destination,
            mode: mode,
            error: error,
          ),
        ),
    };
  }
}

class _ToolAccum {
  String? id;
  String? name;
  final StringBuffer argsBuffer = StringBuffer();
}

class _ToolCall {
  final String id;
  final String name;
  final String argsJson;
  const _ToolCall({
    required this.id,
    required this.name,
    required this.argsJson,
  });
}

class _TurnState {
  final StringBuffer assistantText = StringBuffer();
  final StringBuffer assistantReasoning = StringBuffer();
  final List<_ToolCall> toolCalls = [];
}
