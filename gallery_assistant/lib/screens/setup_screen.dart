import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_provider.dart';
import '../services/inference_router.dart';
import '../services/litert_service.dart';
import '../services/model_manager_service.dart';
import '../theme/app_spacing.dart';
import '../widgets/responsive_body.dart';
import 'chat_screen.dart';
import 'widgets/backend_selector.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  _Phase _phase = _Phase.ready;
  int _progress = 0;
  String? _error;
  CancelToken? _cancelToken;
  LiteRtBackendPreference _backendPreference = LiteRtBackendPreference.auto;

  @override
  void initState() {
    super.initState();
    _loadBackendPreference();
  }

  Future<void> _loadBackendPreference() async {
    final preference = await LiteRtService.instance.loadBackendPreference();
    if (mounted) setState(() => _backendPreference = preference);
  }

  Future<void> _setBackendPreference(LiteRtBackendPreference preference) async {
    setState(() => _backendPreference = preference);
    await LiteRtService.instance.setBackendPreference(preference);
  }

  void _useCloud() {
    InferenceRouter.instance.mode = InferenceMode.cloud;
    ref.read(chatProvider.notifier).useCloudMode();
    _goToChat();
  }

  Future<void> _startDownload() async {
    InferenceRouter.instance.mode = InferenceMode.local;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _error = null;
    });

    _cancelToken = CancelToken();

    try {
      await ModelManagerService.instance.installOrActivate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancelToken: _cancelToken,
      );

      if (mounted) {
        setState(() => _phase = _Phase.done);
        ref.read(chatProvider.notifier).initModel('');
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) _goToChat();
      }
    } on DownloadCancelledException {
      if (mounted) setState(() => _phase = _Phase.ready);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.ready;
          _error = _humanizeError(e.toString());
        });
      }
    }
  }

  void _cancel() {
    _cancelToken?.cancel('User cancelled');
    setState(() {
      _phase = _Phase.ready;
      _progress = 0;
    });
  }

  void _goToChat() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const ChatScreen()));
  }

  String _humanizeError(String raw) {
    if (raw.contains('401') || raw.contains('403')) {
      return 'Access denied. Please check your internet connection.';
    }
    if (raw.contains('SocketException') || raw.contains('network')) {
      return 'Connection error. Please check your internet connection.';
    }
    return 'Download failed: $raw';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ResponsiveCardBody(
          child: switch (_phase) {
            _Phase.ready => _buildReady(theme, scheme),
            _Phase.downloading => _buildDownloading(theme, scheme),
            _Phase.done => _buildDone(theme, scheme),
          },
        ),
      ),
    );
  }

  Widget _buildReady(ThemeData theme, ColorScheme scheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _BrandBadge(scheme: scheme)),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'LUMOS',
          style: theme.textTheme.displaySmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Enlight Your World',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
            letterSpacing: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          'The Gemma-4 E2B model, about 2.4 GB, can be downloaded once for offline use. '
          'After that, it stays on this device.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _ErrorCard(message: _error!, scheme: scheme),
        ],
        const SizedBox(height: AppSpacing.xxl),
        BackendSelector(
          value: _backendPreference,
          onChanged: _setBackendPreference,
          enabled: _phase == _Phase.ready,
        ),
        const SizedBox(height: AppSpacing.xxl),
        FilledButton.icon(
          onPressed: _useCloud,
          icon: const Icon(Icons.cloud_rounded),
          label: const Text('Use Cloud'),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _startDownload,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download Offline Model'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Cloud is faster and needs internet.\nOffline mode works without internet after setup.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDownloading(ThemeData theme, ColorScheme scheme) {
    final sizeMb = (_progress / 100 * 2400).toStringAsFixed(0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: _BrandBadge(
            scheme: scheme,
            icon: Icons.cloud_download_rounded,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Downloading model',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'This only needs to happen once.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxl),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: LinearProgressIndicator(value: _progress / 100),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '$_progress%  ·  $sizeMb MB / 2400 MB',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxl),
        OutlinedButton.icon(
          onPressed: _cancel,
          icon: const Icon(Icons.close_rounded),
          label: const Text('Cancel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildDone(ThemeData theme, ColorScheme scheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Center(
          child: _BrandBadge(scheme: scheme, icon: Icons.check_rounded),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Ready',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _BrandBadge extends StatelessWidget {
  final ColorScheme scheme;
  final IconData icon;
  const _BrandBadge({
    required this.scheme,
    this.icon = Icons.auto_awesome_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            scheme.primaryContainer,
            scheme.primaryContainer.withValues(alpha: 0.4),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(icon, size: 44, color: scheme.primary),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final ColorScheme scheme;
  const _ErrorCard({required this.message, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
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
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Phase { ready, downloading, done }
