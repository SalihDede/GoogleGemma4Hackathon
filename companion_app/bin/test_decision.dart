import '../lib/agent_app/agents/decision_agent.dart';

Future<void> runTests() async {
  final agent = DecisionAgent();

  print('=== KARAR JAGENTSİ TESTİ ===\n');

  // Test soruları: [giriş, beklenen mod]
  final tests = [
    ['İstanbul\'da hava durumu nedir?', ThinkingMode.off],
    ['Matematik probleminin çözümü nedir ve neden bu cevabı bulduk?', ThinkingMode.on],
    ['Merhaba, nasılsın?', ThinkingMode.off],
    ['A ve B arasında en uygun yol hangisi ve neden?', ThinkingMode.on],
    ['Saat kaç?', ThinkingMode.off],
    ['Düşme tehlikesi olan birini kurtarmak için hangi strateji uygulanmalıdır?', ThinkingMode.on],
    ['Yardım istiyorum, yardım edebilir misin?', ThinkingMode.off],
    ['Neden yere düşüyorum? Acil prosedür nedir?', ThinkingMode.on],
  ];

  int correctCount = 0;
  for (var i = 0; i < tests.length; i++) {
    final query = tests[i][0] as String;
    final expected = tests[i][1] as ThinkingMode;
    final decision = await agent.analyze(query);
    
    final icon = decision.mode.name == expected.name ? '✅' : '❌';
    
    print('Test ${i + 1}: $icon');
    print('Girdi: "$query"');
    print('Beklenen: ${expected.name} | Sonuç: ${decision.mode.name}');
    final shortPrompt = decision.systemPrompt.length > 120 
        ? decision.systemPrompt.substring(0, 120) 
        : decision.systemPrompt;
    print('Sistem Promptu (ilk 120 karakter):');
    print('  $shortPrompt\n');
    
    if (decision.mode.name == expected.name) {
      correctCount++;
    }
  }

  print('Toplam: ${tests.length} test çalıştırıldı.');
  print('Doğru olanlar: $correctCount/${tests.length}');
}

void main() {
  runTests();
}
