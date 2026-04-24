import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:companion_app/agent_app/agents/decision_agent.dart';

void main() => runApp(const CompanionApp());

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Erişim Asistanı',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true, brightness: Brightness.dark),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  final decisionAgent = DecisionAgent();
  final msgs = <Map<String, dynamic>>[];
  bool loading = false;

  Future<void> handleSend() async {
    final text = controller.text.trim();
    if (text.isEmpty || loading) return;
    
    // 1. Add user message
    msgs.add({'role': 'user', 'text': text});
    setState(() => loading = true);

    // 2. Decision Agent analyzes query
    final decision = await decisionAgent.analyze(text);
    
    // 3. Show decision result
    msgs.add({'decision': decision});
    setState(() => loading = false);
    _scrollToBottom();

    // 4. Send to LLM with correct system prompt
    final payload = {
      'model': 'unsloth/gemma-4-E2B-it-GGUF',
      'messages': [
        {'role': 'system', 'content': decision.systemPrompt},
        ...msgs.where((m) => m.containsKey('text')).map((m) => {'role': m['role'] ?? 'user', 'content': m['text']}).toList(),
      ],
      'max_tokens': 512,
      'temperature': 0.7,
    };

    // Unsloth vLLM backend: top-level enable_thinking bool
    payload['enable_thinking'] = decision.mode == ThinkingMode.on;

    print('[LLM] thinking_mode=${decision.mode.name} payload_thinking=${payload['thinking']}');
    final t0 = DateTime.now();

    final resp = await http.post(
      Uri.parse('http://localhost:8888/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer sk-unsloth-a4ddf6784a34b565be31c8c8f42e2790',
      },
      body: jsonEncode(payload),
    );

    final elapsed = DateTime.now().difference(t0).inMilliseconds;
    print('[LLM] status=${resp.statusCode} elapsed=${elapsed}ms');
    print('[LLM] raw_body=${resp.body}');

    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body);
      final rawContent = decoded['choices'][0]['message']['content'] as String;
      final usage = decoded['usage'];
      print('[LLM] usage=$usage');

      final hasThinkBlock = rawContent.contains('<think>');
      print('[LLM] has_think_block=$hasThinkBlock mode=${decision.mode.name}');

      String answer = rawContent;
      if (decision.mode == ThinkingMode.off) {
        answer = answer.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();
      }
      setState(() {
        msgs.add({'role': 'assistant', 'text': answer});
      });
      _scrollToBottom();
    } else {
      setState(() {
        msgs.add({'role': 'assistant', 'text': 'Bağlantı hatası: ${resp.statusCode}'});
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Widget buildMessage(Map m, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? Colors.blue.shade700 : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(m['text'], style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget buildDecision(AgentDecision decision) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: decision.mode == ThinkingMode.on 
                  ? Colors.orange.shade200 
                  : Colors.green.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '[DUSINME: ${decision.thinkingStatus}] Raw: ${decision.rawModelAnswer ?? "N/A"}',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Erişim Asistanı', style: TextStyle(fontSize: 20))),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final msg = msgs[i];
                if (msg.containsKey('decision')) {
                  return buildDecision(msg['decision']);
                }
                return buildMessage(msg, msg['role'] == 'user');
              },
            ),
          ),
          if (loading) const Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onSubmitted: (_) => handleSend(),
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yazın...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: handleSend,
                  icon: const Icon(Icons.send),
                  color: Colors.blue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
