import 'package:flutter/material.dart';
import '../../models/message.dart';

const _toolLabels = {
  'describe_scene': 'Analyzing scene',
  'read_text': 'Reading text',
  'identify_object': 'Finding object',
  'get_location_info': 'Getting location',
  'get_directions': 'Getting directions',
  'set_reminder': 'Setting reminder',
  'search_contact': 'Searching contacts',
  'make_call': 'Starting call',
  'get_date': 'Getting date',
  'get_time': 'Getting time',
  'cancel_action': 'Cancelling action',
  'check_sensor_context': 'Checking sensors',
  'measure_brightness': 'Measuring brightness',
  'get_environment_status': 'Checking environment',
  'detect_motion_state': 'Checking motion',
  'read_inertial_sensors': 'Reading motion sensors',
  'capture_image': 'Capturing image',
};

const _toolIcons = {
  'describe_scene': Icons.visibility_outlined,
  'read_text': Icons.text_fields_outlined,
  'identify_object': Icons.search_outlined,
  'get_location_info': Icons.location_on_outlined,
  'get_directions': Icons.directions_outlined,
  'set_reminder': Icons.alarm_outlined,
  'search_contact': Icons.contacts_outlined,
  'make_call': Icons.call_outlined,
  'get_date': Icons.calendar_today_outlined,
  'get_time': Icons.access_time_outlined,
  'cancel_action': Icons.cancel_outlined,
  'check_sensor_context': Icons.sensors_outlined,
  'measure_brightness': Icons.wb_sunny_outlined,
  'get_environment_status': Icons.thermostat_outlined,
  'detect_motion_state': Icons.directions_walk_outlined,
  'read_inertial_sensors': Icons.screen_rotation_alt_outlined,
  'capture_image': Icons.photo_camera_outlined,
};

class ToolCallChip extends StatelessWidget {
  final ToolCall toolCall;

  const ToolCallChip({super.key, required this.toolCall});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = _toolLabels[toolCall.name] ?? toolCall.name;
    final icon = _toolIcons[toolCall.name] ?? Icons.build_outlined;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
