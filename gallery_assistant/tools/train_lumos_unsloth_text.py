#!/usr/bin/env python3
"""Train a Lumos text/tool-reasoning LoRA with Unsloth.

Expected input is a JSONL file with a `text` column produced by
tools/prepare_lumos_unsloth_text.py.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def infer_response_markers(sample_text: str) -> tuple[str, str] | None:
    candidates = [
        ("<start_of_turn>user\n", "<start_of_turn>model\n"),
        ("<start_of_turn>user\n", "<start_of_turn>assistant\n"),
        ("<|im_start|>user\n", "<|im_start|>assistant\n"),
        ("### User:\n", "### Assistant:\n"),
        (">>> User: ", ">>> Assistant: "),
    ]
    for instruction_part, response_part in candidates:
        if instruction_part in sample_text and response_part in sample_text:
            return instruction_part, response_part
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-name", default="google/gemma-4-E2B-it")
    parser.add_argument("--train-file", type=Path, required=True)
    parser.add_argument("--eval-file", type=Path)
    parser.add_argument("--output-dir", default="outputs/lumos-gemma4-tool-lora")
    parser.add_argument("--max-seq-length", type=int, default=4096)
    parser.add_argument("--max-steps", type=int, default=500)
    parser.add_argument("--epochs", type=float)
    parser.add_argument("--batch-size", type=int, default=1)
    parser.add_argument("--grad-accum", type=int, default=4)
    parser.add_argument("--learning-rate", type=float, default=2e-4)
    parser.add_argument("--r", type=int, default=16)
    parser.add_argument("--lora-alpha", type=int, default=16)
    parser.add_argument("--load-in-4bit", action="store_true")
    parser.add_argument("--no-response-only", action="store_true")
    parser.add_argument("--instruction-part")
    parser.add_argument("--response-part")
    args = parser.parse_args()

    from datasets import load_dataset
    from trl import SFTConfig, SFTTrainer
    from unsloth import FastLanguageModel

    train_dataset = load_dataset("json", data_files=str(args.train_file), split="train")
    eval_dataset = None
    if args.eval_file:
        eval_dataset = load_dataset("json", data_files=str(args.eval_file), split="train")

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=args.model_name,
        max_seq_length=args.max_seq_length,
        load_in_4bit=args.load_in_4bit,
        load_in_16bit=not args.load_in_4bit,
        full_finetuning=False,
    )

    model = FastLanguageModel.get_peft_model(
        model,
        r=args.r,
        target_modules=[
            "q_proj",
            "k_proj",
            "v_proj",
            "o_proj",
            "gate_proj",
            "up_proj",
            "down_proj",
        ],
        lora_alpha=args.lora_alpha,
        lora_dropout=0,
        bias="none",
        use_gradient_checkpointing="unsloth",
        random_state=3407,
        max_seq_length=args.max_seq_length,
    )

    trainer_args = SFTConfig(
        max_seq_length=args.max_seq_length,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        learning_rate=args.learning_rate,
        warmup_ratio=0.03,
        logging_steps=5,
        eval_steps=25 if eval_dataset is not None else None,
        save_steps=100,
        output_dir=args.output_dir,
        optim="adamw_8bit",
        seed=3407,
        dataset_num_proc=1,
        dataset_text_field="text",
        packing=False,
        report_to="none",
        num_train_epochs=args.epochs if args.epochs is not None else 1,
        max_steps=args.max_steps if args.epochs is None else -1,
    )

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=train_dataset,
        eval_dataset=eval_dataset,
        args=trainer_args,
    )

    if not args.no_response_only:
        from unsloth.chat_templates import train_on_responses_only

        if args.instruction_part and args.response_part:
            markers = (args.instruction_part, args.response_part)
        else:
            markers = infer_response_markers(train_dataset[0]["text"])
        if markers is None:
            raise RuntimeError(
                "Could not infer chat response markers for train_on_responses_only. "
                "Inspect the prepared text and pass --instruction-part and --response-part, "
                "or use --no-response-only for debugging."
            )
        instruction_part, response_part = markers
        print(f"Using response-only mask: instruction_part={instruction_part!r}, response_part={response_part!r}")
        trainer = train_on_responses_only(
            trainer,
            instruction_part=instruction_part,
            response_part=response_part,
        )

    trainer.train()
    trainer.save_model(args.output_dir)
    tokenizer.save_pretrained(args.output_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
