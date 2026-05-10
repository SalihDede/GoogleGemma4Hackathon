import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/image_service.dart';
import '../../theme/app_spacing.dart';

class InputBar extends StatefulWidget {
  final bool enabled;
  final void Function({required String text, Uint8List? imageBytes}) onSend;

  const InputBar({super.key, required this.enabled, required this.onSend});

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();
  final _stt = SpeechToText();
  final _picker = ImagePicker();

  Uint8List? _pendingImage;
  bool _sttAvailable = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _initStt();
  }

  Future<void> _initStt() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      // ignore: avoid_print
      print('[stt] microphone permission denied: $mic');
      if (mounted) setState(() => _sttAvailable = false);
      return;
    }
    final ok = await _stt.initialize(
      onStatus: (s) {
        // ignore: avoid_print
        print('[stt status] $s');
      },
      onError: (e) {
        // ignore: avoid_print
        print('[stt error] ${e.errorMsg} permanent=${e.permanent}');
        if (mounted) setState(() => _listening = false);
      },
    );
    if (mounted) setState(() => _sttAvailable = ok);
  }

  String _deviceSpeechLocale() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final language = locale.languageCode.isEmpty ? 'en' : locale.languageCode;
    final country = locale.countryCode;
    if (country != null && country.isNotEmpty) return '${language}_$country';
    return switch (language) {
      'tr' => 'tr_TR',
      'en' => 'en_US',
      _ => 'en_US',
    };
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;
    final bytes = await ImageService.instance.prepareForModel(
      File(picked.path),
    );
    if (bytes != null && mounted) setState(() => _pendingImage = bytes);
  }

  void _toggleListening() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _stt.listen(
      onResult: (result) {
        // Show partial and final speech recognition text.
        _controller.text = result.recognizedWords;
        if (result.finalResult) {
          if (mounted) setState(() => _listening = false);
        }
      },
      localeId: _deviceSpeechLocale(),
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      ),
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingImage == null) return;
    widget.onSend(text: text, imageBytes: _pendingImage);
    _controller.clear();
    setState(() => _pendingImage = null);
  }

  @override
  void dispose() {
    _controller.dispose();
    _stt.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final hasContent =
        _controller.text.trim().isNotEmpty || _pendingImage != null;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: Image.memory(
                        _pendingImage!,
                        height: 120,
                        width: MediaQuery.sizeOf(context).width * 0.42,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: scheme.scrim.withValues(alpha: 0.6),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => _pendingImage = null),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: scheme.onInverseSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _AttachMenu(
                  enabled: widget.enabled,
                  onCamera: () => _pickImage(ImageSource.camera),
                  onGallery: () => _pickImage(ImageSource.gallery),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: widget.enabled,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) => setState(() {}),
                    style: Theme.of(context).textTheme.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: 'Ask anything, or tap the microphone...',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                if (_sttAvailable && !hasContent)
                  _MicButton(
                    listening: _listening,
                    enabled: widget.enabled,
                    onTap: _toggleListening,
                  )
                else
                  _SendButton(
                    enabled: widget.enabled && hasContent,
                    onTap: _send,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Camera and gallery live in one compact menu.
class _AttachMenu extends StatelessWidget {
  final bool enabled;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  const _AttachMenu({
    required this.enabled,
    required this.onCamera,
    required this.onGallery,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Add image',
      hint: 'Choose camera or gallery',
      child: PopupMenuButton<String>(
        enabled: enabled,
        tooltip: 'Add image',
        icon: Icon(Icons.add_rounded, color: scheme.onSurfaceVariant),
        iconSize: 28,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        onSelected: (v) {
          if (v == 'camera') onCamera();
          if (v == 'gallery') onGallery();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'camera',
            child: ListTile(
              leading: Icon(Icons.camera_alt_outlined),
              title: Text('Camera'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'gallery',
            child: ListTile(
              leading: Icon(Icons.image_outlined),
              title: Text('Gallery'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

/// Voice input button.
class _MicButton extends StatefulWidget {
  final bool listening;
  final bool enabled;
  final VoidCallback onTap;

  const _MicButton({
    required this.listening,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.listening) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listening && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.listening && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = widget.listening ? scheme.error : scheme.secondaryContainer;
    final fg = widget.listening ? scheme.onError : scheme.onSecondaryContainer;
    return Semantics(
      button: true,
      label: widget.listening ? 'Stop listening' : 'Start voice input',
      child: Tooltip(
        message: widget.listening ? 'Stop listening' : 'Voice input',
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) {
            final scale = widget.listening ? 1.0 + _ctrl.value * 0.08 : 1.0;
            return Transform.scale(
              scale: scale,
              child: Material(
                color: bg,
                shape: const CircleBorder(),
                elevation: widget.listening ? 2 : 0,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.enabled ? widget.onTap : null,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      widget.listening
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                      color: fg,
                      size: 22,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Send button.
class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _SendButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = enabled ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = enabled ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: 'Send message',
      child: Tooltip(
        message: 'Send',
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          elevation: enabled ? 1 : 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.arrow_upward_rounded, color: fg, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}
