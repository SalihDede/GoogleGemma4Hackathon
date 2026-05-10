import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/tool_result.dart';

const _callChannel = MethodChannel('com.lumos/call');

class ToolResultCard extends StatelessWidget {
  final ToolResult result;

  const ToolResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return switch (result) {
      SceneResult r => _SceneCard(result: r),
      TextReadResult r => _TextReadCard(result: r),
      ObjectFoundResult r => _ObjectCard(result: r),
      LocationResult r => _LocationCard(result: r),
      ContactSearchResult r => _ContactSearchCard(result: r),
      CallResult r => _CallResultCard(result: r),
      ReminderResult r => _ReminderCard(result: r),
      DateResult r => _DateCard(result: r),
      TimeResult r => _TimeCard(result: r),
      InternetConnectionStatusResult r => _InternetStatusCard(result: r),
      SensorContextResult r => _SensorReadingsCard(
        title: 'Sensor context',
        readings: {
          'lux': r.lux,
          'distance_mm': r.distanceMm,
          'temperature_c': r.temperatureC,
          'humidity_percent': r.humidityPercent,
          'pressure_hpa': r.pressureHpa,
          'motion': r.motion,
        },
      ),
      BrightnessResult r => _SensorReadingsCard(
        title: 'Brightness',
        readings: {'lux': r.lux, 'classification': r.classification},
      ),
      NearObstacleResult r => _SensorReadingsCard(
        title: 'Near obstacle',
        readings: {'distance_mm': r.distanceMm, 'obstacle': r.obstacle},
      ),
      EnvironmentStatusResult r => _SensorReadingsCard(
        title: 'Environment',
        readings: {
          'temperature_c': r.temperatureC,
          'humidity_percent': r.humidityPercent,
          'pressure_hpa': r.pressureHpa,
          'comfort': r.comfort,
        },
      ),
      MotionStateResult r => _SensorReadingsCard(
        title: 'Motion state',
        readings: {'stable': r.stable, 'tilt': r.tilt, 'motion': r.motion},
      ),
      CaptureImageResult r => _CaptureImageCard(result: r),
      RouteResult r => _RouteCard(result: r),
      NavigationStoppedResult _ => const _SimpleInfoCard(
        icon: Icons.stop_circle_outlined,
        title: 'Navigation stopped',
        message: 'Active route updates were cancelled.',
      ),
      CancelActionResult r => _SimpleInfoCard(
        icon: Icons.cancel_outlined,
        title: 'Cancelled',
        message: 'Target: ${r.target}. Cancelled: ${r.cancelledCount}',
      ),
    };
  }
}

// ── Ortak kart çerçevesi ────────────────────────────────────────────────────
class _CardFrame extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? accentColor;
  final Widget child;

  const _CardFrame({
    required this.icon,
    required this.title,
    required this.child,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = accentColor ?? scheme.primary;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardMaxWidth = screenWidth < 600 ? screenWidth - 32 : 560.0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: cardMaxWidth),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(7),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.all(12), child: child),
          ],
        ),
      ),
    );
  }
}

// ── Sahne betimi ─────────────────────────────────────────────────────────────
class _SceneCard extends StatelessWidget {
  final SceneResult result;
  const _SceneCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _CardFrame(
      icon: Icons.visibility_outlined,
      title: result.focus != null ? 'Focus: ${result.focus}' : 'Scene analysis',
      child: Text(
        'The model is analyzing the scene...',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
    );
  }
}

// ── Metin okuma ──────────────────────────────────────────────────────────────
class _TextReadCard extends StatelessWidget {
  final TextReadResult result;
  const _TextReadCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = result.extractedText.isNotEmpty;

    return _CardFrame(
      icon: Icons.text_fields_rounded,
      title: 'Read Text',
      accentColor: scheme.tertiary,
      child: hasText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    result.extractedText,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: result.extractedText),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Text copied'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            )
          : Text(
              'The model will read the visible text...',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
    );
  }
}

// ── Nesne tanımlama ──────────────────────────────────────────────────────────
class _ObjectCard extends StatelessWidget {
  final ObjectFoundResult result;
  const _ObjectCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _CardFrame(
      icon: Icons.search_rounded,
      title: 'Finding Object',
      accentColor: Colors.orange,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              result.objectName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          if (result.clockPosition != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.near_me_outlined,
              size: 15,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                result.clockPosition!,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Konum bilgisi (gömülü harita) ───────────────────────────────────────────
class _LocationCard extends StatefulWidget {
  final LocationResult result;
  const _LocationCard({required this.result});

  @override
  State<_LocationCard> createState() => _LocationCardState();
}

class _LocationCardState extends State<_LocationCard> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse(widget.result.mapsEmbedUrl));
  }

  Future<void> _openExternal() async {
    final uri = Uri.parse(widget.result.mapsUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _CardFrame(
      icon: Icons.location_on_outlined,
      title: 'Location',
      accentColor: Colors.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.search, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.result.query,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 220,
              child: WebViewWidget(controller: _controller),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _openExternal,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open in Maps'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.green.shade700,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hatırlatıcı ──────────────────────────────────────────────────────────────
class _ReminderCard extends StatefulWidget {
  final ReminderResult result;
  const _ReminderCard({required this.result});

  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  late int _remaining; // saniye
  Timer? _timer;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.result.minutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) {
          _remaining--;
        } else if (!_fired) {
          _fired = true;
          _timer?.cancel();
          _showAlert();
        }
      });
    });
  }

  void _showAlert() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⏰ ${widget.result.text}'),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timeLabel {
    if (_fired) return 'Reminded';
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _fired ? scheme.primary : Colors.deepPurple;

    return _CardFrame(
      icon: Icons.alarm_rounded,
      title: 'Reminder',
      accentColor: accent,
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.result.text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _fired ? Icons.check_circle_rounded : Icons.timer_outlined,
                  size: 15,
                  color: accent,
                ),
                const SizedBox(width: 5),
                Text(
                  _timeLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rehber arama sonucu — teyit bekleniyor ───────────────────────────────────
class _ContactSearchCard extends StatelessWidget {
  final ContactSearchResult result;
  const _ContactSearchCard({required this.result});

  Future<void> _call(String phone) async {
    try {
      await _callChannel.invokeMethod('makeCall', {'phone': phone});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (result.contacts.isEmpty) {
      return _CardFrame(
        icon: Icons.contacts_outlined,
        title: 'Search: "${result.query}"',
        accentColor: Colors.teal,
        child: Text(
          'No matching contact was found for "${result.query}".',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      );
    }

    return _CardFrame(
      icon: Icons.contacts_outlined,
      title: '"${result.query}" - ${result.contacts.length} contacts found',
      accentColor: Colors.teal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Which one do you want to call?',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          ...result.contacts.asMap().entries.map((e) {
            final idx = e.key + 1;
            final contact = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _call(contact.phone),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.teal.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$idx',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.teal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              contact.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              contact.phone,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.call_outlined,
                        color: Colors.teal,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          Text(
            'Tap a contact, or say "one", "two", and so on.',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Tarih ────────────────────────────────────────────────────────────────────
class _DateCard extends StatelessWidget {
  final DateResult result;
  const _DateCard({required this.result});

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final d = result.dateTime;
    final day = _weekdays[d.weekday - 1];
    final month = _months[d.month - 1];
    final label = '$day, ${d.day} $month ${d.year}';

    return _CardFrame(
      icon: Icons.calendar_today_rounded,
      title: 'Date',
      accentColor: Colors.indigo,
      child: Text(
        label,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Saat ─────────────────────────────────────────────────────────────────────
class _TimeCard extends StatelessWidget {
  final TimeResult result;
  const _TimeCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final d = result.dateTime;
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');

    return _CardFrame(
      icon: Icons.access_time_rounded,
      title: 'Time',
      accentColor: Colors.deepOrange,
      child: Text(
        '$h:$m',
        style: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.bold,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ── Arama başlatıldı ─────────────────────────────────────────────────────────
class _InternetStatusCard extends StatelessWidget {
  final InternetConnectionStatusResult result;
  const _InternetStatusCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = result.hasInternet ? Colors.green : scheme.error;
    return _CardFrame(
      icon: result.hasInternet ? Icons.wifi_rounded : Icons.wifi_off_rounded,
      title: 'Internet',
      accentColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.hasInternet ? 'Connected' : 'Not connected',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Type: ${result.connectionType}. Checked: ${result.checkedHost}.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(result.info, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _SensorReadingsCard extends StatelessWidget {
  final String title;
  final Map<String, Object?> readings;
  const _SensorReadingsCard({required this.title, required this.readings});

  String _labelFor(String key) {
    return switch (key) {
      'lux' => 'light',
      'distance_mm' => 'distance',
      'temperature_c' => 'temperature',
      'humidity_percent' => 'humidity',
      'pressure_hpa' => 'pressure',
      'classification' => 'level',
      'obstacle' => 'obstacle',
      'stable' => 'stable',
      'tilt' => 'tilt',
      'motion' => 'motion',
      'comfort' => 'comfort',
      _ => key,
    };
  }

  String _valueFor(String key, Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return 'unknown';
    return switch (key) {
      'lux' => '$raw lux',
      'distance_mm' => '$raw mm',
      'temperature_c' => '$raw C',
      'humidity_percent' => '$raw%',
      'pressure_hpa' => '$raw hPa',
      'obstacle' =>
        raw.toLowerCase() == 'true'
            ? 'yes'
            : raw.toLowerCase() == 'false'
            ? 'no'
            : raw,
      _ => raw,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const accent = Colors.green;
    return _CardFrame(
      icon: Icons.sensors_rounded,
      title: title,
      accentColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (readings.isEmpty)
            Text('', style: TextStyle(color: scheme.onSurfaceVariant))
          else ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: readings.entries.map((entry) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_labelFor(entry.key)}: ${_valueFor(entry.key, entry.value)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _CaptureImageCard extends StatelessWidget {
  final CaptureImageResult result;
  const _CaptureImageCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = result.imageBytes != null && result.imageBytes!.isNotEmpty;

    return _CardFrame(
      icon: Icons.photo_camera_outlined,
      title: hasImage ? 'Image captured' : 'Camera capture failed',
      accentColor: hasImage ? Colors.blue : scheme.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (result.reason.isNotEmpty)
            Text(
              result.reason,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          if (result.error != null) ...[
            if (result.reason.isNotEmpty) const SizedBox(height: 6),
            Text(
              result.error!,
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          ],
          if (hasImage) ...[
            if (result.reason.isNotEmpty) const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                Uint8List.fromList(result.imageBytes!),
                height: MediaQuery.sizeOf(context).width < 600 ? 160 : 220,
                cacheWidth: 720,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CallResultCard extends StatefulWidget {
  final CallResult result;
  const _CallResultCard({required this.result});

  @override
  State<_CallResultCard> createState() => _CallResultCardState();
}

class _CallResultCardState extends State<_CallResultCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _CardFrame(
      icon: Icons.call_rounded,
      title: 'Calling',
      accentColor: Colors.green,
      child: Row(
        children: [
          // Nabız animasyonu
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) =>
                Opacity(opacity: 0.4 + _pulse.value * 0.6, child: child),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.call_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.result.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  widget.result.phone,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'The phone call is continuing in the background.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── A→B Rota kartı ──────────────────────────────────────────────────────────
class _RouteCard extends StatelessWidget {
  final RouteResult result;
  const _RouteCard({required this.result});

  Future<void> _openExternal() async {
    final uri = Uri.parse(result.mapsUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = result.imageBytes != null && result.imageBytes!.isNotEmpty;
    return _CardFrame(
      icon: Icons.directions_outlined,
      title: 'Route',
      accentColor: Colors.indigo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${result.origin} to ${result.destination}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Mode: ${result.mode}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (hasImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                Uint8List.fromList(result.imageBytes!),
                height: MediaQuery.sizeOf(context).width < 600 ? 180 : 240,
                cacheWidth: 720,
                fit: BoxFit.cover,
              ),
            )
          else if (result.error != null)
            Text(
              result.error!,
              style: TextStyle(fontSize: 12, color: Colors.red.shade400),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open in Google Maps'),
          ),
        ],
      ),
    );
  }
}

class _SimpleInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _SimpleInfoCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      icon: icon,
      title: title,
      accentColor: Colors.grey,
      child: Text(message, style: const TextStyle(fontSize: 13)),
    );
  }
}
