# AGENTS.md

## Target Model

- **Model**: `unsloth/gemma-4-E2B-it-GGUF`
- **GGUF Variant**: `gemma-4-E2B-it-UD-Q4_K_XL.gguf` (Q4_K_XL quantization)
- **Backend**: Unsloth vLLM server
- **Endpoint**: `http://localhost:8888/v1/chat/completions`
- **Load Endpoint**: `http://localhost:8888/api/inference/load`
- **API Key**: `sk-unsloth-a4ddf6784a34b565be31c8c8f42e2790`

## Model Capabilities

- **Chat / Conversational AI**: Multi-turn prompts with system/user/assistant roles
- **Thinking (Extended Reasoning)**: Model supports `<think>...</think>` extended reasoning blocks
- **Tool / Function Calling**: Supports `tools` and `tool_choice`; returns `tool_calls` with `name`, `arguments`, `id`
- **Quantization**: Q4_K_XL 4-bit — minor quality tradeoff vs full precision

---

## Agent Architecture

### DecisionAgent (`companion_app/lib/agent_app/agents/decision_agent.dart`)

A lightweight classifier agent that runs **before every user query** to decide whether the main model needs extended reasoning.

**Flow:**
```
User query
    │
    ▼
DecisionAgent.analyze(query)
    │  ├─ sends query to classifier LLM (same model, max_tokens=8, temp=0.1)
    │  ├─ classifier prompt asks for only "on" or "off"
    │  └─ strips <think>...</think> from classifier response before parsing
    │
    ▼
ThinkingMode (on | off)
    │
    ▼
AgentDecision { mode, systemPrompt }
    │
    ▼
Main LLM call with enable_thinking=true/false
```

**Classifier logic:**
- `on` → analysis, math, planning, multi-step reasoning, comparison
- `off` → greetings, simple commands, factual lookups, emotional expressions

**Parsing:** checks `contains('off')` first, then `contains('on')` — this order prevents false positives where "on" appears as a substring in words like "response" or "based on".

---

## Thinking Mode Control

### Working parameter (confirmed via testing)

```json
{
  "enable_thinking": true   // or false
}
```

This is a **top-level** field in the request body, **not** nested under `"thinking"`.

### What does NOT work on this server

| Format | Result |
|--------|--------|
| `"thinking": {"enabled": true/false}` | Ignored |
| `"thinking": {"type": "disabled", "budget_tokens": 0}` | Ignored |
| `/no_think` in system prompt | Treated as plain text, not a control token |

### Performance impact (measured)

| Mode | Typical response time |
|------|-----------------------|
| `enable_thinking: true` | ~4000–5000ms |
| `enable_thinking: false` | ~500–700ms |

### Fallback strip

Even with `enable_thinking: false`, if the model emits `<think>...</think>` for any reason, the app strips them from the displayed response:

```dart
if (decision.mode == ThinkingMode.off) {
  answer = answer.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();
}
```

---

## Request Payload Structure

```json
{
  "model": "unsloth/gemma-4-E2B-it-GGUF",
  "messages": [
    { "role": "system", "content": "<decision-agent generated system prompt>" },
    { "role": "user",   "content": "<user message>" }
  ],
  "max_tokens": 512,
  "temperature": 0.7,
  "enable_thinking": false
}
```

---

## Key Constraints

- Model must be loaded via `/api/inference/load` before first use (or rely on auto-load)
- `usage` field in responses returns `{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}` — server does not report token counts
- Keep `max_tokens` at 512+ for tool calling to allow structured `arguments` JSON output
- Tool call arguments are returned as JSON strings; parse with `json.decode()` before use
- Classifier call uses `max_tokens: 8` and `temperature: 0.1` for deterministic on/off output
