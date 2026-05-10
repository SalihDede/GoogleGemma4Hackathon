import 'package:flutter/material.dart';

import '../../services/litert_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/breakpoints.dart';

class BackendSelector extends StatelessWidget {
  final LiteRtBackendPreference value;
  final ValueChanged<LiteRtBackendPreference> onChanged;
  final bool enabled;
  final String? activeBackend;

  const BackendSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.activeBackend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final helper = _helperText(value, activeBackend);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.memory_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('Local backend', style: theme.textTheme.labelLarge),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (context.isCompact)
          DropdownButtonFormField<LiteRtBackendPreference>(
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
            items: LiteRtBackendPreference.values
                .map(
                  (preference) => DropdownMenuItem(
                    value: preference,
                    child: Text(_labelFor(preference)),
                  ),
                )
                .toList(),
            onChanged: enabled
                ? (preference) {
                    if (preference != null) onChanged(preference);
                  }
                : null,
          )
        else
          SegmentedButton<LiteRtBackendPreference>(
            showSelectedIcon: false,
            selected: {value},
            segments: LiteRtBackendPreference.values
                .map(
                  (preference) => ButtonSegment(
                    value: preference,
                    icon: Icon(_iconFor(preference)),
                    label: Text(preference.label),
                    tooltip: _labelFor(preference),
                  ),
                )
                .toList(),
            onSelectionChanged: enabled
                ? (selected) => onChanged(selected.first)
                : null,
          ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          helper,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String _labelFor(LiteRtBackendPreference preference) {
    return switch (preference) {
      LiteRtBackendPreference.auto => 'Auto: use the saved fastest stable path',
      LiteRtBackendPreference.gpu => 'GPU: prefer graphics acceleration',
      LiteRtBackendPreference.cpu => 'CPU: most compatible, usually slower',
      LiteRtBackendPreference.npu =>
        'NPU: experimental, falls back if unsupported',
    };
  }

  static IconData _iconFor(LiteRtBackendPreference preference) {
    return switch (preference) {
      LiteRtBackendPreference.auto => Icons.auto_mode_rounded,
      LiteRtBackendPreference.gpu => Icons.memory_rounded,
      LiteRtBackendPreference.cpu => Icons.developer_board_rounded,
      LiteRtBackendPreference.npu => Icons.bolt_rounded,
    };
  }

  static String _helperText(
    LiteRtBackendPreference preference,
    String? activeBackend,
  ) {
    final active = activeBackend == null || activeBackend.isEmpty
        ? ''
        : ' Active: $activeBackend.';
    final base = switch (preference) {
      LiteRtBackendPreference.auto =>
        'Auto tries the profiled stable backend first.',
      LiteRtBackendPreference.gpu =>
        'GPU tries acceleration first and can fall back to CPU.',
      LiteRtBackendPreference.cpu =>
        'CPU avoids delegate issues but is usually slower.',
      LiteRtBackendPreference.npu =>
        'NPU is hardware and model dependent; unsupported devices fall back.',
    };
    return '$base$active';
  }
}
