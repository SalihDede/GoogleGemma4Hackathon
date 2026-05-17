# Lumos Synthetic SFT Dataset

This folder defines the dataset pipeline for Lumos fine-tuning.

The immediate target is text/tool-reasoning SFT. We are not trying to teach the
visual encoder new perception. We want Gemma 4 to learn when Lumos should call
tools, which tool combinations are useful, how to summarize tool outputs, and
how to speak in short TTS-friendly sentences.

## Existing Hugging Face Datasets

Use the existing Lumos datasets before generating everything from scratch:

- `SalihHub/lumos-tool-messages-unsloth`: useful for text/tool-reasoning SFT, but its tool calls are stored as inline text tags. Convert it first.
- `SalihHub/lumos-vision-qa-unsloth`: useful for a later vision or multimodal phase. Do not mix it into a text-only tool-reasoning run unless image input is preserved, because the answer depends on visual evidence.

Convert the tool dataset to canonical OpenAI-style tool calls:

```powershell
pip install datasets
python tools\convert_hf_lumos_datasets.py --limit 200 --fix-mojibake --out data_generation\out\lumos_tool_train_200.jsonl
python tools\validate_lumos_sft.py data_generation\out\lumos_tool_train_200.jsonl
```

For actual Unsloth text SFT, prefer producing a `text` column instead:

```powershell
pip install datasets transformers ftfy
python tools\prepare_lumos_unsloth_text.py --limit 500 --fix-mojibake --out data_generation\out\lumos_unsloth_text_500.jsonl
python tools\inspect_unsloth_text_dataset.py data_generation\out\lumos_unsloth_text_500.jsonl
```

If the exact Gemma 4 tokenizer is available, render with it:

```powershell
python tools\prepare_lumos_unsloth_text.py --tokenizer-model google/gemma-4-E2B-it --fix-mojibake --out data_generation\out\lumos_unsloth_text_train.jsonl
```

Train with Unsloth:

```powershell
python tools\train_lumos_unsloth_text.py --model-name google/gemma-4-E2B-it --train-file data_generation\out\lumos_unsloth_text_train.jsonl --output-dir outputs\lumos-gemma4-tool-lora --max-steps 500
```

Important: inspect `text` before training. It must visibly contain system/user
turns, assistant turns, `<tool_call>`, `<tool_result>`, and final assistant
answers. If the tool tags are missing, the model is not learning tool use.

If validation loss stays high:

- Make sure you trained on the prepared file with a `text` column, not raw `messages`.
- Keep `train_on_responses_only` enabled so system, user, and tool-result tokens are masked from loss.
- Use the same tokenizer/chat template for preparing data and for inference/export.
- Do not mix `lumos-vision-qa-unsloth` into this text-only run unless images are included through a vision collator.
- Inspect skipped rows. If most rows are skipped because of old tool names, either add those tools to the app or regenerate/normalize that part of the dataset.

For a full train split:

```powershell
python tools\convert_hf_lumos_datasets.py --fix-mojibake --out data_generation\out\lumos_tool_train.jsonl
python tools\validate_lumos_sft.py data_generation\out\lumos_tool_train.jsonl
```

By default the converter skips rows that call tools not registered in the
current app, such as older `get_directions` or `internet_connection_status`
examples. This avoids teaching the model to call tools the Flutter app cannot
execute.

## OpenRouter Setup

Use an environment variable. Do not paste API keys into source files.

```powershell
$env:OPENROUTER_API_KEY="sk-or-..."
$env:OPENROUTER_MODEL="google/gemma-4-26b-a4b-it:nitro"
python tools\generate_lumos_sft_dataset.py --count 50 --batch-size 2 --out data_generation\out\lumos_sft_review_50.jsonl
python tools\validate_lumos_sft.py data_generation\out\lumos_sft_review_50.jsonl
```

## Dataset Mix

Recommended first pass:

- 20 percent no-tool conversation and identity examples.
- 30 percent single-tool examples.
- 25 percent multi-tool safety or environment reasoning.
- 10 percent tool failure or missing-permission examples.
- 10 percent high-stakes safety examples.
- 5 percent contact confirmation and cancellation flows.

For the first usable LoRA, prefer 5k to 10k high-quality examples over a noisy
50k set. Generate in batches, validate, inspect samples manually, then scale.
