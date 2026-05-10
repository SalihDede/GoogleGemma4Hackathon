import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/message.dart';
import '../providers/chat_provider.dart';
import '../services/litert_service.dart';
import '../theme/app_spacing.dart';
import '../theme/breakpoints.dart';
import '../widgets/responsive_body.dart';
import 'widgets/input_bar.dart';
import 'widgets/message_bubble.dart';

typedef _TtsSnapshot = ({
  String? id,
  bool isAssistant,
  String text,
  MessageStatus? status,
  bool enabled,
});

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollCtrl = ScrollController();
  final _tts = FlutterTts();
  bool _ttsReady = false;
  String? _ttsMessageId;
  int _ttsOffset = 0;
  int _ttsRun = 0;
  String _ttsPendingText = '';
  Future<void> _ttsQueue = Future.value();

  @override
  void initState() {
    super.initState();
    _initTts();
    unawaited(ref.read(chatProvider.notifier).loadBackendPreference());
  }

  Future<void> _initTts() async {
    await _tts.setLanguage(_deviceTtsLanguage());
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    if (mounted) setState(() => _ttsReady = true);
  }

  String _deviceTtsLanguage() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final language = locale.languageCode.isEmpty ? 'en' : locale.languageCode;
    final country = locale.countryCode;
    if (country != null && country.isNotEmpty) return '$language-$country';
    return switch (language) {
      'tr' => 'tr-TR',
      'en' => 'en-US',
      _ => 'en-US',
    };
  }

  String _ttsNormalize(String text) {
    return text.replaceAll(RegExp(r'\bLUMOS\b'), 'Lumos');
  }

  void _resetStreamingTts({bool stop = false}) {
    _ttsRun++;
    _ttsMessageId = null;
    _ttsOffset = 0;
    _ttsPendingText = '';
    _ttsQueue = Future.value();
    if (stop) unawaited(_tts.stop());
  }

  void _handleTtsSnapshot(_TtsSnapshot next) {
    if (!_ttsReady) return;
    if (!next.enabled) {
      _resetStreamingTts(stop: true);
      return;
    }
    if (!next.isAssistant || next.id == null) return;

    if (_ttsMessageId != next.id) {
      _resetStreamingTts(stop: true);
      _ttsMessageId = next.id;
    }

    if (next.text.length < _ttsOffset) {
      _ttsOffset = 0;
      _ttsPendingText = '';
    }

    if (next.text.length > _ttsOffset) {
      _ttsPendingText += next.text.substring(_ttsOffset);
      _ttsOffset = next.text.length;
      _drainSpeakableText();
    }

    if (next.status == MessageStatus.done &&
        _ttsPendingText.trim().isNotEmpty) {
      _queueSpeak(_ttsPendingText);
      _ttsPendingText = '';
    }
  }

  void _drainSpeakableText() {
    while (true) {
      final boundary = _sentenceBoundary(_ttsPendingText);
      if (boundary <= 0) break;
      final chunk = _ttsPendingText.substring(0, boundary).trim();
      _ttsPendingText = _ttsPendingText.substring(boundary).trimLeft();
      _queueSpeak(chunk);
    }

    if (_ttsPendingText.length < 140) return;
    final softBoundary = _ttsPendingText.lastIndexOf(' ', 110);
    if (softBoundary < 60) return;
    final chunk = _ttsPendingText.substring(0, softBoundary).trim();
    _ttsPendingText = _ttsPendingText.substring(softBoundary).trimLeft();
    _queueSpeak(chunk);
  }

  int _sentenceBoundary(String text) {
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '\n' || ch == '.' || ch == '!' || ch == '?' || ch == ';') {
        return i + 1;
      }
    }
    return -1;
  }

  void _queueSpeak(String raw) {
    final text = _ttsNormalize(raw).trim();
    if (text.isEmpty) return;
    final run = _ttsRun;
    _ttsQueue = _ttsQueue.then((_) async {
      if (!mounted || run != _ttsRun) return;
      if (!ref.read(chatProvider).ttsEnabled) return;
      try {
        await _tts.speak(text);
      } catch (_) {
        // Some engines reject interrupted or very short chunks.
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _resetStreamingTts(stop: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);

    // Sadece mesaj sayısı değiştiğinde scroll — her token'da değil
    ref.listen<int>(
      chatProvider.select((s) => s.messages.length),
      (_, _) => _scrollToBottom(),
    );

    ref.listen<_TtsSnapshot>(
      chatProvider.select((s) {
        if (s.messages.isEmpty) {
          return (
            id: null,
            isAssistant: false,
            text: '',
            status: null,
            enabled: s.ttsEnabled,
          );
        }
        final last = s.messages.last;
        return (
          id: last.id,
          isAssistant: last.isAssistant,
          text: last.text,
          status: last.status,
          enabled: s.ttsEnabled,
        );
      }),
      (_, next) => _handleTtsSnapshot(next),
    );

    final scheme = Theme.of(context).colorScheme;
    final isStreaming = chatState.messages.any(
      (m) => m.status == MessageStatus.streaming,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('LUMOS'),
        centerTitle: true,
        actions: [
          PopupMenuButton<LiteRtBackendPreference>(
            tooltip: chatState.activeBackend.isEmpty
                ? 'Local backend'
                : 'Local backend: ${chatState.activeBackend}',
            enabled: !isStreaming && !chatState.modelLoading,
            icon: const Icon(Icons.tune_rounded),
            initialValue: chatState.backendPreference,
            onSelected: (preference) {
              unawaited(notifier.setBackendPreference(preference));
            },
            itemBuilder: (_) => LiteRtBackendPreference.values
                .map(
                  (preference) => PopupMenuItem(
                    value: preference,
                    child: Row(
                      children: [
                        Icon(_backendMenuIcon(preference), size: 20),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Text(_backendMenuLabel(preference))),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          IconButton(
            tooltip: chatState.ttsEnabled
                ? 'Turn speech off'
                : 'Turn speech on',
            icon: Icon(
              chatState.ttsEnabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
            ),
            onPressed: () {
              notifier.toggleTts();
              if (chatState.ttsEnabled) _resetStreamingTts(stop: true);
            },
          ),
          IconButton(
            tooltip: 'Clear chat',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: chatState.messages.isEmpty
                ? null
                : () => _showClearDialog(notifier),
          ),
        ],
      ),
      body: Column(
        children: [
          // Model yükleme banner
          if (chatState.modelLoading) _ModelLoadingBanner(scheme: scheme),

          if (chatState.modelError != null)
            _ErrorBanner(error: chatState.modelError!, scheme: scheme),

          // Mesaj listesi (geniş ekranda ortalanmış, max-width okunabilir)
          Expanded(
            child: chatState.messages.isEmpty
                ? _EmptyState(modelReady: chatState.modelReady)
                : ResponsiveBody(
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.sm,
                      ),
                      itemCount: chatState.messages.length,
                      itemBuilder: (_, i) =>
                          MessageBubble(message: chatState.messages[i]),
                    ),
                  ),
          ),

          const Divider(height: 1),

          // Giriş çubuğu — geniş ekranda da ortalanmış
          ResponsiveBody(
            child: InputBar(
              enabled: chatState.modelReady && !isStreaming,
              onSend: ({required String text, Uint8List? imageBytes}) {
                notifier.sendMessage(text: text, imageBytes: imageBytes);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(ChatNotifier notifier) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear chat'),
        content: const Text('All messages will be deleted. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              _resetStreamingTts(stop: true);
              unawaited(notifier.clearHistory());
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  IconData _backendMenuIcon(LiteRtBackendPreference preference) {
    return switch (preference) {
      LiteRtBackendPreference.auto => Icons.auto_mode_rounded,
      LiteRtBackendPreference.gpu => Icons.memory_rounded,
      LiteRtBackendPreference.cpu => Icons.developer_board_rounded,
      LiteRtBackendPreference.npu => Icons.bolt_rounded,
    };
  }

  String _backendMenuLabel(LiteRtBackendPreference preference) {
    return switch (preference) {
      LiteRtBackendPreference.auto => 'Auto',
      LiteRtBackendPreference.gpu => 'GPU',
      LiteRtBackendPreference.cpu => 'CPU',
      LiteRtBackendPreference.npu => 'NPU',
    };
  }
}

class _ModelLoadingBanner extends StatelessWidget {
  final ColorScheme scheme;
  const _ModelLoadingBanner({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: scheme.primaryContainer,
      padding: AppPadding.h16v12,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: context.readableContentMaxWidth,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Loading model. The first launch may take a few seconds.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;
  final ColorScheme scheme;
  const _ErrorBanner({required this.error, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: AppPadding.h16v12,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: context.readableContentMaxWidth,
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: scheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  error,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool modelReady;
  const _EmptyState({required this.modelReady});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.cardMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 40,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                modelReady ? 'Hi. How can I help?' : 'Getting ready...',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (modelReady) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Type, speak, or send a photo.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
