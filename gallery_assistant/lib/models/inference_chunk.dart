// Lokal LiteRT ve bulut OpenRouter arka uçları için ortak yanıt parçası.
sealed class InferenceChunk {
  const InferenceChunk();
}

class TextChunk extends InferenceChunk {
  final String token;
  const TextChunk(this.token);
}

class ThinkingChunk extends InferenceChunk {
  final String content;
  const ThinkingChunk(this.content);
}

class FunctionCallChunk extends InferenceChunk {
  final String name;
  final Map<String, dynamic> args;
  const FunctionCallChunk(this.name, this.args);
}

/// Bulut modu: tool zaten servis içinde koşturuldu, UI sadece göstersin.
class ToolInvokedChunk extends InferenceChunk {
  final String name;
  final Map<String, dynamic> args;
  final Object result; // ToolResult; tip avoidance için Object
  const ToolInvokedChunk({
    required this.name,
    required this.args,
    required this.result,
  });
}
