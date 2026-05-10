import 'package:flutter_gemma/flutter_gemma.dart';

import 'litert_prompts.dart';

class LiteRtPromptPlan {
  final String systemPrompt;
  final Set<String> toolNames;
  final String signature;
  final String requestKind;
  final int maxOutputChunks;
  final int toolContinuationMaxOutputChunks;
  final int approxPromptChars;
  final int memorySummaryChars;
  final int recentContextChars;

  const LiteRtPromptPlan({
    required this.systemPrompt,
    required this.toolNames,
    required this.signature,
    required this.requestKind,
    required this.maxOutputChunks,
    required this.toolContinuationMaxOutputChunks,
    required this.approxPromptChars,
    required this.memorySummaryChars,
    required this.recentContextChars,
  });
}

class LiteRtPromptBuilder {
  LiteRtPromptBuilder._();

  static const _allRegisteredTools = '*';

  static LiteRtPromptPlan build({
    required String text,
    required bool hasImage,
    String? memorySummary,
    String? recentContext,
  }) {
    final memory = (memorySummary ?? '').trim();
    final recent = (recentContext ?? '').trim();
    final parts = <String>[
      LiteRtPrompts.base,
      LiteRtPrompts.visual,
      LiteRtPrompts.safety,
      LiteRtPrompts.contacts,
      LiteRtPrompts.offline,
      LiteRtPrompts.sensors,
      LiteRtPrompts.reminders,
      LiteRtPrompts.dateTime,
      LiteRtPrompts.cancellation,
    ];

    final contextPrompt = LiteRtPrompts.context(
      memorySummary: memory,
      recentContext: recent,
    );
    final tags = <String>{'model_routed'};
    if (contextPrompt.trim().isNotEmpty) {
      parts.add(contextPrompt);
      tags.add('ctx:${_stableHash('$memory\n$recent')}');
    }

    final signature = (tags.toList()..sort()).join('+');
    final systemPrompt = parts.join('\n');
    return LiteRtPromptPlan(
      systemPrompt: systemPrompt,
      toolNames: const {_allRegisteredTools},
      signature: signature,
      requestKind: 'model_routed',
      maxOutputChunks: 320,
      toolContinuationMaxOutputChunks: 220,
      approxPromptChars: systemPrompt.length,
      memorySummaryChars: memory.length,
      recentContextChars: recent.length,
    );
  }

  static List<Tool> selectTools(List<Tool> availableTools, Set<String> names) {
    if (names.contains(_allRegisteredTools)) return availableTools;
    if (names.isEmpty) return const [];
    return availableTools.where((tool) => names.contains(tool.name)).toList();
  }

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
