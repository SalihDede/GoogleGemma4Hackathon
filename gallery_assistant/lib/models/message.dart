import 'dart:typed_data';
import '../services/litert_service.dart';
import 'tool_result.dart';

enum MessageRole { user, assistant }

enum MessageStatus { sending, streaming, done, error }

class ChatMessage {
  final String id;
  final MessageRole role;
  String text;

  // Thinking bölümü (model <think>...</think> yazdığında)
  String? thinkingText;
  bool thinkingExpanded;

  // Kullanıcı görseli
  final Uint8List? imageBytes;

  // Tool call bilgisi
  ToolCall? toolCall;
  List<ToolInvocation> toolInvocations;
  ToolResult? toolResultData; // inline widget için yapısal sonuç

  MessageStatus status;
  final DateTime createdAt;

  // Yerel inference için backend + benchmark (TTFT, tok/s) — UI altta gösterir.
  InferenceStats? stats;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.thinkingText,
    this.thinkingExpanded = false,
    this.imageBytes,
    this.toolCall,
    List<ToolInvocation>? toolInvocations,
    this.toolResultData,
    this.status = MessageStatus.done,
    this.stats,
    DateTime? createdAt,
  }) : toolInvocations = List<ToolInvocation>.of(
         toolInvocations ?? const <ToolInvocation>[],
       ),
       createdAt = createdAt ?? DateTime.now();

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get hasImage => imageBytes != null;
  bool get hasThinking => thinkingText != null && thinkingText!.isNotEmpty;
  bool get hasToolInvocations => toolInvocations.isNotEmpty;
  bool get hasToolCall => toolCall != null || hasToolInvocations;
  bool get hasToolResult => toolResultData != null || hasToolInvocations;
}

class ToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall({required this.name, required this.arguments});

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      name: json['name'] as String,
      arguments: Map<String, dynamic>.from(json['arguments'] as Map? ?? {}),
    );
  }
}

class ToolInvocation {
  final ToolCall call;
  final ToolResult result;

  const ToolInvocation({required this.call, required this.result});
}
