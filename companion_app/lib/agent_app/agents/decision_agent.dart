import 'dart:convert';
import 'package:http/http.dart' as http;

/// Kullanıcının düşünmesi gerekip gerekmediğini belirten mod.
enum ThinkingMode {
  /// Derin düşünme gerekiyor (analiz, mantik, hesaplama, planlama)
  on,
  /// Doğrudan cevap yeterli (selamlama, basit soru, bilgi)
  off,
}

/// Karar sonucu: mod + system prompt
class AgentDecision {
  final ThinkingMode mode;
  final String systemPrompt;
  final String? rawModelAnswer; // Classifier'dan dönen ham cevab

  AgentDecision(this.mode, this.systemPrompt, [this.rawModelAnswer]);

  String get thinkingStatus => mode == ThinkingMode.on ? 'ON' : 'OFF';

  @override
  String toString() => 'Decision: thinking=$thinkingStatus';
}

/// Karar Katanı Agentı
///
/// Gorev: Gelen sorguyu analiz et > LLM'e classifier gonder >
/// ThinkingMode ona karar ver > 
/// ona gore system promptunu olustur > LLM'e gonderilecek sekilde hazirla.
class DecisionAgent {
  static final DecisionAgent _instance = DecisionAgent._internal();
  factory DecisionAgent() => _instance;
  DecisionAgent._internal();

  /// Classifier promptu: LLM'den sadece "on" veya "off" istiyoruz
  static const String _classifierPrompt = '''
Sen bir dusunme modu karar vericisisin. Kullaninin sorusunu analiz et ve "thinking" modunu belirle.

KARAR KRITERLERI:
- "on": Analiz, mantik, hesaplama, karsilastirma, planlama, oneri, strateji, neden-sonuc, cok adimli dusunme gerektiren sorular.
- "off": Durdudan bilgi, selamlama, basit komut, duygu ifadesi, kisa yanit yeterli sorular.

KURALLAR:
1. Acil durum ifadeleri ("yardim", "tehlike", "dusunuyorum") > thinking: off (hizli yanit)
2. Matematik/analiz/planlama/siniflandirma > thinking: on (derin yanit)
3. Merhaba/tesekkur/soru degil > thinking: off
4. Net kriter yoksa > thinking: on (guvenli yol)

CEVIRIMEZCE SADECE "on" veya "off" yaz. Baska hicbir sey yazma.
''';

  /// Ollama API endpoint
  static const String _ollamaEndpoint = 'http://localhost:8888/v1/chat/completions';

  /// API anahtari
  static const String _apiKey = 'sk-unsloth-a4ddf6784a34b565be31c8c8f42e2790';

  /// Kullanicinin sorusunu analiz et ve karar uret
  Future<AgentDecision> analyze(String userQuery) async {
    final query = userQuery.trim();

    // 1. Adim: LLM'e classifier promptu gonder
    ThinkingMode mode;
    String? rawAnswer;
    try {
      final resp = await http.post(
        Uri.parse(_ollamaEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'unsloth/gemma-4-E2B-it-GGUF',
          'messages': [
            {'role': 'system', 'content': _classifierPrompt},
            {'role': 'user', 'content': query},
          ],
          'max_tokens': 8,
          'temperature': 0.1, // Deterministik cevap icin dusuk temp
        }),
      );

      if (resp.statusCode == 200) {
        final answer = jsonDecode(resp.body)['choices'][0]['message']['content'];
        rawAnswer = answer;

        // Strip <think>...</think> blocks — classifier model may wrap its
        // reasoning in these tags before emitting the actual "on"/"off" token.
        final stripped = answer.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();

        final lowerAnswer = stripped.toLowerCase();
        if (lowerAnswer.contains('off')) {
          mode = ThinkingMode.off;
        } else if (lowerAnswer.contains('on')) {
          mode = ThinkingMode.on;
        } else {
          mode = ThinkingMode.on; // default: safe fallback
        }
      } else {
        // API hatasi: default thinking on
        mode = ThinkingMode.on;
        rawAnswer = 'Error: ${resp.statusCode}';
      }
    } catch (e) {
      print('DecisionAgent error: $e - Defaulting to thinking: ON');
      mode = ThinkingMode.on;
      rawAnswer = 'Exception: $e';
    }

    // 2. Adim: Mode'a gore tam sistem promptunu olustur
    // NOTE: thinking parametresi model'e hicbir sekilde gonderilmez!
    final commonBase = '''
Sen 'Erisim Asistani' olarak bilinen bir asistansin. Turkce yanit ver. 
Amac: Kullaninin güvenligi, navigasyonu ve gunluk yasamini koordine et.
'''
.toString().trim();

    final modeSpecific = mode == ThinkingMode.on
        ? '''

/think
[DUSUNME GEREKLI]:
- Soruyu cevaplamadan ONCE adim adim mantigini cikar.
- Her adimi actikca goster.
- Son adimda net bir sonuc ver.
'''
        : '''

/no_think
[DOGRUDAN YANIT]:
- Soru basittir. Gereksiz aciklamalar yapma.
- Durdudan cevabi ver.
- Kisa ve oz ol.
''';

    final fullSystemPrompt = commonBase + modeSpecific + '\n\n[KULLANICI SORUSU]: $query';

    return AgentDecision(mode, fullSystemPrompt, rawAnswer);
  }
}
