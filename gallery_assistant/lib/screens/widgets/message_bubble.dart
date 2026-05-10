import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/message.dart';
import '../../services/litert_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/breakpoints.dart';
import 'thinking_section.dart';
import 'tool_call_chip.dart';
import 'tool_result_card.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = message.isUser;
    final toolInvocations = message.toolInvocations;
    final sideInset = context.isCompact ? AppSpacing.xl : AppSpacing.xxxl;
    final bubbleMaxWidth = context.isCompact
        ? MediaQuery.sizeOf(context).width - sideInset - AppSpacing.md
        : 560.0;

    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? sideInset : 0,
        right: isUser ? 0 : sideInset,
        bottom: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Kullanıcı görseli
          if (message.hasImage && isUser) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Image.memory(
                message.imageBytes!,
                width: 220,
                cacheWidth: 440,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],

          // Thinking bölümü (asistan)
          if (message.hasThinking && !isUser)
            ThinkingSection(
              text: message.thinkingText!,
              expanded: message.thinkingExpanded,
              onToggle: () =>
                  message.thinkingExpanded = !message.thinkingExpanded,
            ),

          // Tool call chip + inline result card
          if (!isUser && toolInvocations.isNotEmpty) ...[
            for (final invocation in toolInvocations) ...[
              ToolCallChip(toolCall: invocation.call),
              ToolResultCard(result: invocation.result),
            ],
          ] else if (!isUser) ...[
            if (message.toolCall != null)
              ToolCallChip(toolCall: message.toolCall!),
            if (message.toolResultData != null)
              ToolResultCard(result: message.toolResultData!),
          ],

          // Ana balon — geniş ekranda max-width sınırı, M3 conversation shape.
          if (message.text.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: isUser ? scheme.primary : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(AppRadius.xl),
                    topRight: const Radius.circular(AppRadius.xl),
                    bottomLeft: Radius.circular(
                      isUser ? AppRadius.xl : AppRadius.xs,
                    ),
                    bottomRight: Radius.circular(
                      isUser ? AppRadius.xs : AppRadius.xl,
                    ),
                  ),
                ),
                child: isUser
                    ? Text(
                        message.text,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onPrimary,
                        ),
                      )
                    : MarkdownBody(
                        data: message.text,
                        styleSheet: MarkdownStyleSheet(
                          p: theme.textTheme.bodyLarge,
                          code: TextStyle(
                            backgroundColor: scheme.surfaceContainerHighest,
                            fontFamily: 'monospace',
                            fontSize: 14,
                          ),
                        ),
                      ),
              ),
            ),

          // Backend + benchmark altyazısı (sadece yerel inference için)
          if (!isUser &&
              message.status == MessageStatus.done &&
              message.stats != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _StatsFooter(stats: message.stats!),
          ],

          // Streaming göstergesi
          if (message.status == MessageStatus.streaming && message.text.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: const _TypingIndicator(),
            ),
        ],
      ),
    );
  }
}

class _StatsFooter extends StatelessWidget {
  final InferenceStats stats;
  const _StatsFooter({required this.stats});

  IconData _backendIcon() {
    switch (stats.backend) {
      case 'NPU':
        return Icons.bolt;
      case 'GPU':
        return Icons.memory;
      default:
        return Icons.developer_board;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tps = stats.decodeTokPerSec;
    final tpsStr = tps > 0 ? '${tps.toStringAsFixed(1)} tok/s' : '— tok/s';
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_backendIcon(), size: 12, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '${stats.backend} · TTFT ${stats.ttftMs}ms · $tpsStr',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) {
            final phase = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 8,
              height: 8 + phase * 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          },
        );
      }),
    );
  }
}
