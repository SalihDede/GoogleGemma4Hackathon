import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final String huggingFaceToken;
  final String openRouterApiKey;

  const AppSettings({
    required this.huggingFaceToken,
    required this.openRouterApiKey,
  });

  bool get hasHuggingFaceToken => huggingFaceToken.trim().isNotEmpty;
  bool get hasOpenRouterApiKey => openRouterApiKey.trim().isNotEmpty;
}

class AppSettingsService {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  static const _huggingFaceTokenKey = 'lumos_hugging_face_token_v1';
  static const _openRouterApiKeyKey = 'lumos_openrouter_api_key_v1';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      huggingFaceToken: prefs.getString(_huggingFaceTokenKey) ?? '',
      openRouterApiKey: prefs.getString(_openRouterApiKeyKey) ?? '',
    );
  }

  Future<void> save({
    required String huggingFaceToken,
    required String openRouterApiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_huggingFaceTokenKey, huggingFaceToken.trim());
    await prefs.setString(_openRouterApiKeyKey, openRouterApiKey.trim());
  }

  Future<String?> huggingFaceTokenOrNull() async {
    final token = (await load()).huggingFaceToken.trim();
    return token.isEmpty ? null : token;
  }

  Future<String?> openRouterApiKeyOrNull() async {
    final key = (await load()).openRouterApiKey.trim();
    return key.isEmpty ? null : key;
  }
}
