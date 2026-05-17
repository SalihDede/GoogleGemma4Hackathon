sealed class ToolResult {
  const ToolResult();
}

class SceneResult extends ToolResult {
  final String? focus;
  const SceneResult({this.focus});
}

class TextReadResult extends ToolResult {
  final String extractedText;
  const TextReadResult(this.extractedText);
}

class ObjectFoundResult extends ToolResult {
  final String objectName;
  final String? clockPosition; // "2 o'clock", "directly ahead" vs.
  const ObjectFoundResult({required this.objectName, this.clockPosition});
}

class LocationResult extends ToolResult {
  final String query;
  final String info;
  final double? lat;
  final double? lng;
  const LocationResult({
    required this.query,
    required this.info,
    this.lat,
    this.lng,
  });

  String get mapsUrl {
    final q = Uri.encodeComponent(query);
    if (lat != null && lng != null) {
      return 'https://www.google.com/maps/search/?api=1&query=$q&query_place_id=&center=$lat,$lng';
    }
    return 'https://www.google.com/maps/search/?api=1&query=$q';
  }

  String get mapsEmbedUrl {
    final q = Uri.encodeComponent(query);
    if (lat != null && lng != null) {
      return 'https://www.google.com/maps?q=$q&ll=$lat,$lng&z=15&output=embed';
    }
    return 'https://www.google.com/maps?q=$q&output=embed';
  }
}

class ReminderResult extends ToolResult {
  final String text;
  final int minutes;
  const ReminderResult({required this.text, required this.minutes});
}

class ContactEntry {
  final String name;
  final String phone; // E.164 veya ham format
  const ContactEntry({required this.name, required this.phone});
}

class ContactSearchResult extends ToolResult {
  final String query;
  final List<ContactEntry> contacts;
  const ContactSearchResult({required this.query, required this.contacts});
}

class CallResult extends ToolResult {
  final String name;
  final String phone;
  const CallResult({required this.name, required this.phone});
}

class RouteResult extends ToolResult {
  final String origin;
  final String destination;
  final String mode; // walking | driving | transit | bicycling
  final List<int>? imageBytes;
  final String? error;
  const RouteResult({
    required this.origin,
    required this.destination,
    required this.mode,
    this.imageBytes,
    this.error,
  });

  String get mapsUrl {
    final o = Uri.encodeComponent(origin);
    final d = Uri.encodeComponent(destination);
    return 'https://www.google.com/maps/dir/?api=1&origin=$o&destination=$d&travelmode=$mode';
  }
}

class NavigationStoppedResult extends ToolResult {
  const NavigationStoppedResult();
}

class CancelActionResult extends ToolResult {
  final String target; // 'navigation' | 'reminders' | 'tts' | 'all'
  final int cancelledCount;
  const CancelActionResult({
    required this.target,
    required this.cancelledCount,
  });
}

// Tarih sorgusu
class DateResult extends ToolResult {
  final DateTime dateTime;
  const DateResult({required this.dateTime});
}

// Saat sorgusu
class TimeResult extends ToolResult {
  final DateTime dateTime;
  const TimeResult({required this.dateTime});
}

class InternetConnectionStatusResult extends ToolResult {
  final bool hasInternet;
  final String connectionType; // wifi | mobile | unknown | none
  final String checkedHost;
  final String info;
  const InternetConnectionStatusResult({
    required this.hasInternet,
    required this.connectionType,
    required this.checkedHost,
    required this.info,
  });
}

class SensorContextResult extends ToolResult {
  final String lux;
  final String temperatureC;
  final String humidityPercent;
  final String pressureHpa;
  final String motion;
  final String accelX;
  final String accelY;
  final String accelZ;
  final String gyroX;
  final String gyroY;
  final String gyroZ;
  const SensorContextResult({
    this.lux = '',
    this.temperatureC = '',
    this.humidityPercent = '',
    this.pressureHpa = '',
    this.motion = '',
    this.accelX = '',
    this.accelY = '',
    this.accelZ = '',
    this.gyroX = '',
    this.gyroY = '',
    this.gyroZ = '',
  });
}

class BrightnessResult extends ToolResult {
  final String lux;
  final String classification;
  const BrightnessResult({this.lux = '', this.classification = ''});
}

class EnvironmentStatusResult extends ToolResult {
  final String temperatureC;
  final String humidityPercent;
  final String pressureHpa;
  final String comfort;
  const EnvironmentStatusResult({
    this.temperatureC = '',
    this.humidityPercent = '',
    this.pressureHpa = '',
    this.comfort = '',
  });
}

class CaptureImageResult extends ToolResult {
  final List<int>? imageBytes;
  final String reason;
  final String? error;
  const CaptureImageResult({this.imageBytes, this.reason = '', this.error});
}

class MotionStateResult extends ToolResult {
  final String stable;
  final String tilt;
  final String motion;
  final String accelX;
  final String accelY;
  final String accelZ;
  final String gyroX;
  final String gyroY;
  final String gyroZ;
  const MotionStateResult({
    this.stable = '',
    this.tilt = '',
    this.motion = '',
    this.accelX = '',
    this.accelY = '',
    this.accelZ = '',
    this.gyroX = '',
    this.gyroY = '',
    this.gyroZ = '',
  });
}

class InertialSensorResult extends ToolResult {
  final String accelX;
  final String accelY;
  final String accelZ;
  final String gyroX;
  final String gyroY;
  final String gyroZ;
  final String stable;
  final String tilt;
  final String motion;
  const InertialSensorResult({
    this.accelX = '',
    this.accelY = '',
    this.accelZ = '',
    this.gyroX = '',
    this.gyroY = '',
    this.gyroZ = '',
    this.stable = '',
    this.tilt = '',
    this.motion = '',
  });
}
