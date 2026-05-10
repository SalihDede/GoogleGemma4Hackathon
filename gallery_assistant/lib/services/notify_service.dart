import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Hatırlatıcı / alarm bildirimi: kısa sistem sesi + sesli okuma.
class NotifyService {
  NotifyService._();
  static final NotifyService instance = NotifyService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _ensureInit({String lang = 'en-US'}) async {
    if (_initialized) return;
    await _tts.setLanguage(lang);
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    _initialized = true;
  }

  /// Kısa alarm sesi + ardından hatırlatıcı metnini seslendirir.
  Future<void> remind(String note, {String lang = 'en-US'}) async {
    await _ensureInit(lang: lang);
    // 3 kısa "alert" tonu — dikkat çekici ama rahatsız etmeyen
    for (var i = 0; i < 3; i++) {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 250));
    }
    await Future.delayed(const Duration(milliseconds: 400));
    await _tts.stop();
    await _tts.speak('Reminder: $note');
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
