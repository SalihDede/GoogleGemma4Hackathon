import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/chat_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/setup_screen.dart';
import 'services/model_manager_service.dart';
import 'services/tool_runner.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  registerDefaultTools();
  runApp(const ProviderScope(child: GalleryAssistantApp()));
}

class GalleryAssistantApp extends ConsumerWidget {
  const GalleryAssistantApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'LUMOS',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const _AppStartup(),
    );
  }
}

// Açılışta model kurulu mu kontrol et → uygun ekrana yönlendir
class _AppStartup extends ConsumerStatefulWidget {
  const _AppStartup();

  @override
  ConsumerState<_AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends ConsumerState<_AppStartup> {
  bool _checking = true;
  bool _modelInstalled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkModel());
  }

  Future<void> _checkModel() async {
    final installed = await ModelManagerService.instance.isModelInstalled();
    if (!mounted) return;

    if (installed) {
      // Yerel model kurulu: hem buluta (öncelik) hem yerele (fallback) hazırla.
      await ModelManagerService.instance.installOrActivate();
      if (!mounted) return;
      ref.read(chatProvider.notifier).useCloudMode();
      // Yerel engine LAZY: sadece internet yokken ilk mesajda yüklenecek.
      setState(() {
        _modelInstalled = true;
        _checking = false;
      });
      return;
    }

    // Model kurulu değil: internet varsa setup (indirme) ekranı, yoksa hata.
    final online = await _hasInternet();
    if (!mounted) return;
    setState(() {
      _modelInstalled = false; // SetupScreen
      _checking = false;
    });
    if (!online) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'İnternet yok ve yerel model indirilmemiş. '
              'Lütfen internete bağlanıp modeli indirin.',
            ),
          ),
        );
      });
    }
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('huggingface.co')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const _SplashScreen();
    if (!_modelInstalled) return const SetupScreen();
    return const ChatScreen();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BrandMark(scheme: scheme),
              const SizedBox(height: 32),
              Text(
                'LUMOS',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enlight Your World',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// LUMOS marka işareti — yumuşak parıltılı dairesel rozet.
class _BrandMark extends StatelessWidget {
  final ColorScheme scheme;
  const _BrandMark({required this.scheme});

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
      child: Icon(
        Icons.auto_awesome_rounded,
        size: 44,
        color: scheme.primary,
      ),
    );
  }
}

