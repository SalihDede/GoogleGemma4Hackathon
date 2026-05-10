import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:image_picker/image_picker.dart';

import '../models/tool_result.dart';
import 'image_service.dart';

const _callChannel = MethodChannel('com.lumos/call');

Future<String> _makeDirectCall(String phone) async {
  try {
    final res = await _callChannel.invokeMethod<String>('makeCall', {
      'phone': phone,
    });
    return res ?? 'unknown';
  } catch (e) {
    // ignore: avoid_print
    print('[make_call] platform error: $e');
    rethrow;
  }
}

typedef ToolHandler = Future<ToolResult> Function(Map<String, dynamic> args);

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

final _imagePicker = ImagePicker();

Future<CaptureImageResult> _captureFromCamera(String reason) async {
  try {
    final shot = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (shot == null) {
      return CaptureImageResult(reason: reason, error: 'cancelled');
    }
    final raw = await shot.readAsBytes();
    final prepared = await ImageService.instance.prepareFromBytes(raw);
    if (prepared == null) {
      return CaptureImageResult(reason: reason, error: 'decode_failed');
    }
    return CaptureImageResult(imageBytes: prepared, reason: reason);
  } catch (e) {
    return CaptureImageResult(reason: reason, error: e.toString());
  }
}

class ToolRunner {
  ToolRunner._();
  static final ToolRunner instance = ToolRunner._();

  final Map<String, ToolHandler> _handlers = {};
  final List<Tool> _tools = [];

  List<Tool> get tools => List.unmodifiable(_tools);

  void register(Tool tool, ToolHandler handler) {
    _tools.add(tool);
    _handlers[tool.name] = handler;
  }

  Future<ToolResult> run(ToolCallRequest request) async {
    final handler = _handlers[request.name];
    if (handler == null) {
      return TextReadResult('Tool "${request.name}" is not registered.');
    }
    try {
      return await handler(request.args);
    } catch (e) {
      return TextReadResult('Tool ${request.name} failed: $e');
    }
  }

  Map<String, dynamic> serializeResult(ToolResult result) {
    return switch (result) {
      ContactSearchResult(:final query, :final contacts) => {
        'query': query,
        'count': contacts.length,
        'contacts': contacts
            .map((c) => {'name': c.name, 'phone': c.phone})
            .toList(),
      },
      CallResult(:final name, :final phone) => {
        'status': 'calling',
        'name': name,
        'phone': phone,
      },
      DateResult(:final dateTime) => {
        'date': dateTime.toIso8601String().split('T').first,
      },
      TimeResult(:final dateTime) => {
        'time':
            '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}',
      },
      CaptureImageResult(:final imageBytes, :final reason, :final error) => {
        'captured': imageBytes != null,
        'reason': reason,
        'error': error,
        'note': imageBytes != null
            ? 'Camera image captured; it will be sent as the next user message for you to analyse.'
            : 'Camera capture failed.',
      },
      InternetConnectionStatusResult() => {'unavailable': true},
      SensorContextResult(
        :final lux,
        :final distanceMm,
        :final temperatureC,
        :final humidityPercent,
        :final pressureHpa,
        :final motion,
      ) =>
        {
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
        },
      BrightnessResult(:final lux, :final classification) => {
        'summary': _brightnessSummary(lux: lux, classification: classification),
        'lux': lux,
        'classification': classification,
      },
      NearObstacleResult(:final distanceMm, :final obstacle) => {
        'summary': _nearObstacleSummary(
          distanceMm: distanceMm,
          obstacle: obstacle,
        ),
        'distance_mm': distanceMm,
        'obstacle': obstacle,
      },
      EnvironmentStatusResult(
        :final temperatureC,
        :final humidityPercent,
        :final pressureHpa,
        :final comfort,
      ) =>
        {
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
        },
      MotionStateResult(:final stable, :final tilt, :final motion) => {
        'summary': _motionSummary(stable: stable, tilt: tilt, motion: motion),
        'stable': stable,
        'tilt': tilt,
        'motion': motion,
      },
      ReminderResult(:final text, :final minutes) => {
        'set': true,
        'text': text,
        'minutes': minutes,
      },
      LocationResult() => {'unavailable': true},
      RouteResult() => {'unavailable': true},
      ObjectFoundResult(:final objectName, :final clockPosition) => {
        'object': objectName,
        'position': clockPosition ?? 'unknown',
      },
      SceneResult(:final focus) => {'focus': focus ?? 'general scene'},
      TextReadResult(:final extractedText) => {'text': extractedText},
      NavigationStoppedResult() => {'stopped': true},
      CancelActionResult(:final target, :final cancelledCount) => {
        'target': target,
        'cancelled': cancelledCount,
      },
    };
  }

  // flutter_gemma'nın FunctionCallResponse'unu ToolCallRequest'e çevir
  ToolCallRequest fromFunctionCall(String name, Map<String, dynamic> args) {
    return ToolCallRequest(name: name, args: args);
  }
}

class ToolCallRequest {
  final String name;
  final Map<String, dynamic> args;
  const ToolCallRequest({required this.name, required this.args});
}

void registerDefaultTools() {
  final r = ToolRunner.instance;

  r.register(
    const Tool(
      name: 'describe_scene',
      description:
          'Describes the current scene or image in detail for a visually impaired user.',
      parameters: {
        'type': 'object',
        'properties': {
          'focus': {
            'type': 'string',
            'description':
                'Optional: specific aspect to focus on (obstacles, text, people, exit)',
          },
        },
      },
    ),
    (args) async {
      final focus = args['focus'] as String?;
      return SceneResult(focus: focus);
    },
  );

  r.register(
    const Tool(
      name: 'read_text',
      description: 'Reads and transcribes all visible text in the image.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async {
      // Model metni doğrudan TextResponse olarak üretecek;
      // bu result sadece UI kartı için tetikleyici
      return const TextReadResult('');
    },
  );

  r.register(
    const Tool(
      name: 'identify_object',
      description:
          'Identifies a specific object and its clock-face position in the scene.',
      parameters: {
        'type': 'object',
        'properties': {
          'object': {
            'type': 'string',
            'description': 'Object to find (e.g. "door", "chair", "exit sign")',
          },
        },
        'required': ['object'],
      },
    ),
    (args) async {
      final object = (args['object'] as String?) ?? 'object';
      return ObjectFoundResult(objectName: object);
    },
  );

  r.register(
    const Tool(
      name: 'check_sensor_context',
      description:
          'Combined snapshot of all external sensors: light(lux), distance(mm), '
          'temp(C), humidity(%), pressure(hPa), motion. Call FIRST for broad safety/'
          'environment questions ("is it safe here?", "how is the environment?"). '
          'Null fields = sensor offline.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async => const SensorContextResult(
      lux: '320.5',
      distanceMm: '1450',
      temperatureC: '23.4',
      humidityPercent: '46.0',
      pressureHpa: '1012.8',
      motion: 'still',
    ),
  );

  r.register(
    const Tool(
      name: 'measure_brightness',
      description:
          'Ambient light. Returns lux and class (dark<10, dim<50, normal<1000, '
          'bright<10000, too_bright>10000). Use for darkness/light questions or '
          'to judge if camera image will be reliable. Light only — no distance/motion.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async =>
        const BrightnessResult(lux: '320.5', classification: 'normal'),
  );

  r.register(
    const Tool(
      name: 'detect_near_obstacle',
      description:
          'Short-range distance sensor (reliable up to ~200mm/arm reach). Returns '
          'distance_mm and obstacle bool. Use for "is something right in front?", '
          '"within reach?", "safe to step?". Beyond ~20cm reports clear. '
          'Distance only — does not identify the object.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async =>
        const NearObstacleResult(distanceMm: '1450', obstacle: 'false'),
  );

  r.register(
    const Tool(
      name: 'get_environment_status',
      description:
          'Climate sensor: temperature_c, humidity_percent, pressure_hpa, comfort. '
          'Use for hot/cold/humid/stuffy/comfortable questions. Pressure changes hint '
          'at altitude/floor change (relative only). Air only — no gas/smoke detection.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async => const EnvironmentStatusResult(
      temperatureC: '23.4',
      humidityPercent: '46.0',
      pressureHpa: '1012.8',
      comfort: 'comfortable',
    ),
  );

  r.register(
    const Tool(
      name: 'detect_motion_state',
      description:
          'Motion sensor: stable bool, tilt (upright/leaning/flat/upside_down), '
          'motion (still/walking/shaking/free_fall/impact). Use for stability before '
          'photo, fall/impact detection, walking vs still. free_fall or impact = '
          'safety critical, check on user first. Movement only — no light/temp.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async => const MotionStateResult(
      stable: 'true',
      tilt: 'upright',
      motion: 'still',
    ),
  );

  r.register(
    const Tool(
      name: 'capture_image',
      description:
          'Opens the phone camera and captures a fresh photo of what is in front '
          'of the user, then sends that image back so you can analyse it. Call '
          'whenever visible evidence would help answer the question (the user is '
          'asking about their surroundings, an object, text, weather outside, '
          'their clothes, a sign, a face, a hazard) and there is no recent image '
          'already attached. After the image arrives, describe or reason about '
          'it directly — do not call describe_scene afterward.',
      parameters: {
        'type': 'object',
        'properties': {
          'reason': {
            'type': 'string',
            'description':
                'Short reason why a photo is needed (e.g. "check weather outside", "read label", "scan path ahead").',
          },
        },
      },
    ),
    (args) async {
      final reason = ((args['reason'] as String?) ?? '').trim();
      return _captureFromCamera(reason);
    },
  );

  r.register(
    const Tool(
      name: 'set_reminder',
      description: 'Sets a timed in-app reminder for the user.',
      parameters: {
        'type': 'object',
        'properties': {
          'text': {'type': 'string', 'description': 'Reminder message'},
          'minutes': {'type': 'integer', 'description': 'Minutes from now'},
        },
        'required': ['text', 'minutes'],
      },
    ),
    (args) async {
      final text = (args['text'] as String?) ?? '';
      final minutes = (args['minutes'] as int?) ?? 5;
      return ReminderResult(text: text, minutes: minutes);
    },
  );

  // ── Rehberde kişi ara ─────────────────────────────────────────────────────
  r.register(
    const Tool(
      name: 'search_contact',
      description:
          'Looks up phone numbers in the device contacts. '
          'CALL THIS TOOL whenever the user wants to call, phone, or reach someone. '
          'Never ask the user for a phone number, never invent one. '
          '\n\nQUERY — pass ONLY the person\'s name or relation, in its base/dictionary form, '
          'as it would most likely appear in the contact list. Strip any verbs and grammatical '
          'markers from the user\'s sentence yourself. Examples:'
          '\n  • "annemi ara" → "anne"   (not "annemi", not "ara annemi")'
          '\n  • "call my mom" → "mom"'
          '\n  • "llama a mi mamá" → "mamá"'
          '\n  • "ruf meine Mutter an" → "Mutter"'
          '\n  • "Ahmet\'i ara" → "Ahmet"'
          '\nDo NOT pass the full sentence. Just the person/relation name in base form.'
          '\n\nAFTER THE TOOL RETURNS — respond in the SAME language the user wrote in '
          '(Turkish input → Turkish reply, English input → English reply, etc.).'
          '\n• If 0 contacts: tell the user no match was found, do not ask for a number.'
          '\n• If exactly 1 contact: ALWAYS ASK FOR CONFIRMATION before calling. Say the '
          'matched contact name and ask the user to confirm in their language (e.g. '
          '"Rehberde Anne buldum, arayayım mı?" / "I found Mom in your contacts, '
          'should I call?"). Do NOT call make_call yet — wait for an affirmative reply '
          '("evet", "ara", "yes", "call", etc.). Only after the user confirms, call '
          'make_call with that phone and name. If the user declines, do nothing.'
          '\n• If 2 or more contacts: list them numbered like "1 X, 2 Y, 3 Z" and ask the '
          'user to say the number of the one to call (e.g. "Birden fazla kişi buldum: 1 Anne, '
          '2 Anneanne, 3 Babaanne. Hangisini aramak istediğinin numarasını söyle." / '
          '"I found several: 1 Mom, 2 Grandma, 3 Aunt. Say the number of the one you want."). '
          'Do NOT call make_call yet — the app handles the user\'s numeric selection.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'Root contact name to search (e.g. "anne", "baba", "abi")',
          },
        },
        'required': ['query'],
      },
    ),
    (args) async {
      final query = ((args['query'] as String?) ?? '').trim();
      if (query.isEmpty) {
        return const ContactSearchResult(query: '', contacts: []);
      }

      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        return ContactSearchResult(query: query, contacts: []);
      }

      final all = await FlutterContacts.getContacts(withProperties: true);
      final q = query.toLowerCase();

      final matches = all
          .where((c) => c.displayName.toLowerCase().contains(q))
          .take(5)
          .map((c) {
            final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
            return ContactEntry(name: c.displayName, phone: phone);
          })
          .where((e) => e.phone.isNotEmpty)
          .toList();

      return ContactSearchResult(query: query, contacts: matches);
    },
  );

  // ── Genel iptal / durdur ──────────────────────────────────────────────────
  r.register(
    const Tool(
      name: 'cancel_action',
      description:
          'Cancels an ongoing background action. Call this whenever the user '
          'asks to stop, cancel, end, pause, or quit something in ANY language '
          '(e.g. "navigasyonu durdur", "hatırlatıcıyı iptal et", "stop talking", '
          '"cancel reminders", "yeter, sus", "hepsini durdur"). Pick the closest '
          'target value:\n'
          '  • "navigation" — active turn-by-turn navigation loop\n'
          '  • "reminders" — all pending scheduled reminders\n'
          '  • "tts" — stop the current text-to-speech playback only\n'
          '  • "all" — cancel everything currently running',
      parameters: {
        'type': 'object',
        'properties': {
          'target': {
            'type': 'string',
            'description': 'One of: navigation, reminders, tts, all',
          },
        },
        'required': ['target'],
      },
    ),
    (args) async {
      final target = ((args['target'] as String?) ?? 'all')
          .toLowerCase()
          .trim();
      // Asıl iptal işi chat_provider'da yapılır; tool sadece niyeti taşır.
      return CancelActionResult(target: target, cancelledCount: 0);
    },
  );

  // ── Tarih ─────────────────────────────────────────────────────────────────
  r.register(
    const Tool(
      name: 'get_date',
      description: 'Returns the current date on the device.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async => DateResult(dateTime: DateTime.now()),
  );

  // ── Saat ──────────────────────────────────────────────────────────────────
  r.register(
    const Tool(
      name: 'get_time',
      description: 'Returns the current time on the device.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async => TimeResult(dateTime: DateTime.now()),
  );

  // ── Kişiyi ara ────────────────────────────────────────────────────────────
  r.register(
    const Tool(
      name: 'make_call',
      description:
          'Initiates a phone call. Two valid sources for the number:\n'
          '1) A literal phone number the user just spoke or typed (digits, '
          '   possibly with spaces, dashes or "+", e.g. "117", "0532 123 45 67", '
          '   "+90 212…", "call 911"). Do NOT call search_contact in this case — '
          '   use the digits directly; for the name argument use a short label '
          '   like the number itself or "Acil"/"Emergency".\n'
          '2) A number returned earlier by search_contact for a named person.\n'
          '\n'
          'CRITICAL — HUMAN IN THE LOOP: Before calling make_call, ALWAYS ask the '
          'user to confirm the number / contact in their own language '
          '(e.g. "117\'yi arayayım mı?" / "Should I call 117?" / "Anne\'yi '
          'arayayım mı?"). Only call make_call after the user replies '
          'affirmatively ("evet", "ara", "yes", "call", "sí", "oui"…). If they '
          'decline, do nothing. This applies to BOTH direct numbers AND '
          'search_contact results — no exceptions.\n'
          '\n'
          'Never invent a number the user did not say.',
      parameters: {
        'type': 'object',
        'properties': {
          'phone': {'type': 'string', 'description': 'Phone number to call'},
          'name': {'type': 'string', 'description': 'Contact name for display'},
        },
        'required': ['phone', 'name'],
      },
    ),
    (args) async {
      final phone = (args['phone'] as String?) ?? '';
      final name = (args['name'] as String?) ?? '';
      await _makeDirectCall(phone);
      return CallResult(name: name, phone: phone);
    },
  );
}
