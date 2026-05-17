import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/tool_result.dart';
import 'sensor_hub_service.dart';

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
  required String temperatureC,
  required String humidityPercent,
  required String pressureHpa,
  required String motion,
}) {
  final temp = _readingOrUnknown(temperatureC);
  final humidity = _readingOrUnknown(humidityPercent);
  final light = _readingOrUnknown(lux);
  final pressure = _readingOrUnknown(pressureHpa);
  final movement = _readingOrUnknown(motion);
  return 'Local sensor readings, not official weather: temperature $temp degrees Celsius, humidity $humidity percent, ambient light $light lux, pressure $pressure hPa, motion $movement. Speak these values naturally; humidity values are percentages, not one hundred percent unless the value is 100.';
}

String _brightnessSummary({
  required String lux,
  required String classification,
}) {
  final light = _readingOrUnknown(lux);
  final label = _readingOrUnknown(classification);
  return 'Local light reading: ambient light is $label at $light lux.';
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
        :final temperatureC,
        :final humidityPercent,
        :final pressureHpa,
        :final motion,
        :final accelX,
        :final accelY,
        :final accelZ,
        :final gyroX,
        :final gyroY,
        :final gyroZ,
      ) =>
        {
          'summary': _sensorContextSummary(
            lux: lux,
            temperatureC: temperatureC,
            humidityPercent: humidityPercent,
            pressureHpa: pressureHpa,
            motion: motion,
          ),
          'lux': lux,
          'temperature_c': temperatureC,
          'humidity_percent': humidityPercent,
          'pressure_hpa': pressureHpa,
          'motion': motion,
          'accel_mps2': {'x': accelX, 'y': accelY, 'z': accelZ},
          'gyro_dps': {'x': gyroX, 'y': gyroY, 'z': gyroZ},
        },
      BrightnessResult(:final lux, :final classification) => {
        'summary': _brightnessSummary(lux: lux, classification: classification),
        'lux': lux,
        'classification': classification,
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
      MotionStateResult(
        :final stable,
        :final tilt,
        :final motion,
        :final accelX,
        :final accelY,
        :final accelZ,
        :final gyroX,
        :final gyroY,
        :final gyroZ,
      ) =>
        {
          'summary': _motionSummary(stable: stable, tilt: tilt, motion: motion),
          'stable': stable,
          'tilt': tilt,
          'motion': motion,
          'accel_mps2': {'x': accelX, 'y': accelY, 'z': accelZ},
          'gyro_dps': {'x': gyroX, 'y': gyroY, 'z': gyroZ},
        },
      InertialSensorResult(
        :final accelX,
        :final accelY,
        :final accelZ,
        :final gyroX,
        :final gyroY,
        :final gyroZ,
        :final stable,
        :final tilt,
        :final motion,
      ) =>
        {
          'summary': _motionSummary(stable: stable, tilt: tilt, motion: motion),
          'accel_mps2': {'x': accelX, 'y': accelY, 'z': accelZ},
          'gyro_dps': {'x': gyroX, 'y': gyroY, 'z': gyroZ},
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
      description:
          'Captures a fresh ESP32-CAM image, then the model reads and transcribes visible text from that image.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async {
      return SensorHubService.instance.captureImage('task:read_text');
    },
  );

  r.register(
    const Tool(
      name: 'identify_object',
      description:
          'Captures a fresh ESP32-CAM image, then the model finds the requested object and its clock-face position.',
      parameters: {
        'type': 'object',
        'properties': {
          'object': {
            'type': 'string',
            'description':
                'Object to find (for example, door, chair, or exit sign)',
          },
        },
        'required': ['object'],
      },
    ),
    (args) async {
      final object = ((args['object'] as String?) ?? 'object').trim();
      final target = object.isEmpty ? 'object' : object;
      return SensorHubService.instance.captureImage(
        'task:identify_object:$target',
      );
    },
  );

  r.register(
    const Tool(
      name: 'check_sensor_context',
      description:
          'Combined snapshot of all external sensors: light(lux), '
          'temp(C), humidity(%), pressure(hPa), motion. Call FIRST for broad safety/'
          'environment questions ("is it safe here?", "how is the environment?"). '
          'Null/empty fields = sensor offline.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async {
      final snapshot = await SensorHubService.instance.fetchSnapshot();
      return SensorContextResult(
        lux: snapshot.lux,
        temperatureC: snapshot.temperatureC,
        humidityPercent: snapshot.humidityPercent,
        pressureHpa: snapshot.pressureHpa,
        motion: snapshot.motion,
        accelX: snapshot.accelX,
        accelY: snapshot.accelY,
        accelZ: snapshot.accelZ,
        gyroX: snapshot.gyroX,
        gyroY: snapshot.gyroY,
        gyroZ: snapshot.gyroZ,
      );
    },
  );

  r.register(
    const Tool(
      name: 'measure_brightness',
      description:
          'Ambient light. Returns lux and class (dark<10, dim<50, normal<1000, '
          'bright<10000, too_bright>10000). Use for darkness/light questions or '
          'to judge if camera image will be reliable. Light only; no motion.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async {
      final snapshot = await SensorHubService.instance.fetchSnapshot();
      return BrightnessResult(
        lux: snapshot.lux,
        classification: snapshot.brightnessClass,
      );
    },
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
    (args) async {
      final snapshot = await SensorHubService.instance.fetchSnapshot();
      return EnvironmentStatusResult(
        temperatureC: snapshot.temperatureC,
        humidityPercent: snapshot.humidityPercent,
        pressureHpa: snapshot.pressureHpa,
        comfort: snapshot.comfort,
      );
    },
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
    (args) async {
      final snapshot = await SensorHubService.instance.fetchSnapshot();
      return MotionStateResult(
        stable: snapshot.stable,
        tilt: snapshot.tilt,
        motion: snapshot.motion,
        accelX: snapshot.accelX,
        accelY: snapshot.accelY,
        accelZ: snapshot.accelZ,
        gyroX: snapshot.gyroX,
        gyroY: snapshot.gyroY,
        gyroZ: snapshot.gyroZ,
      );
    },
  );

  r.register(
    const Tool(
      name: 'read_inertial_sensors',
      description:
          'Reads raw accelerometer and gyroscope values from the external MPU6050. '
          'Returns accel_mps2 x/y/z, gyro_dps x/y/z, plus derived stable, tilt, '
          'and motion labels. Use for requests about acceleration, gyro, tilt, '
          'orientation, shaking, walking, falling, or device movement.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async {
      final snapshot = await SensorHubService.instance.fetchSnapshot();
      return InertialSensorResult(
        accelX: snapshot.accelX,
        accelY: snapshot.accelY,
        accelZ: snapshot.accelZ,
        gyroX: snapshot.gyroX,
        gyroY: snapshot.gyroY,
        gyroZ: snapshot.gyroZ,
        stable: snapshot.stable,
        tilt: snapshot.tilt,
        motion: snapshot.motion,
      );
    },
  );

  r.register(
    const Tool(
      name: 'capture_image',
      description:
          'Uses the ESP32-CAM to capture a fresh photo of what is in front '
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
      return SensorHubService.instance.captureImage(reason);
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

  r.register(
    const Tool(
      name: 'search_contact',
      description:
          'Looks up phone numbers in the device contacts. '
          'Call this tool whenever the user wants to call, phone, or reach someone. '
          'Never ask the user for a phone number, and never invent one. '
          'Pass only the person name or relation in base form, not the full sentence. '
          'Examples: "call my mom" -> "mom"; a request to call Ahmet -> "Ahmet". '
          'After the tool returns, let the model answer in the user language. '
          'If there is one match, ask for confirmation before make_call. '
          'If there are multiple matches, list them by number and ask which one to call.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'Root contact name to search (for example, mom, dad, or a contact name)',
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

  r.register(
    const Tool(
      name: 'cancel_action',
      description:
          'Cancels an ongoing background action. Call this whenever the user '
          'asks to stop, cancel, end, pause, or quit something in any language. '
          'Use the closest target: navigation, reminders, tts, or all.',
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
      return CancelActionResult(target: target, cancelledCount: 0);
    },
  );

  r.register(
    const Tool(
      name: 'get_date',
      description: 'Returns the current date on the device.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async => DateResult(dateTime: DateTime.now()),
  );

  r.register(
    const Tool(
      name: 'get_time',
      description: 'Returns the current time on the device.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    (args) async => TimeResult(dateTime: DateTime.now()),
  );

  r.register(
    const Tool(
      name: 'make_call',
      description:
          'Initiates a phone call after explicit user confirmation. Use either '
          'a literal phone number the user just provided, or a number returned '
          'earlier by search_contact. Never invent a number. Always ask the '
          'user to confirm the number or contact first; call make_call only '
          'after an affirmative reply in the user language.',
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
