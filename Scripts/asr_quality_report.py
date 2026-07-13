#!/usr/bin/env python3
import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Union


@dataclass
class SubtitleBlock:
    start: float
    end: float
    text: str
    lines: list[str]


PROMPT_MARKERS = [
    "tvarkinga transkripcija",
    "lietuviska skyryba",
    "sakiniais ir dialogais",
    "clear speech transcription",
    "readable subtitle",
    "punctuation and readable",
    "translated into natural english",
]


def parse_timestamp(value: str) -> Optional[float]:
    match = re.search(r"(\d{2}):(\d{2}):(\d{2}),(\d{3})", value.strip())
    if not match:
        return None
    hours, minutes, seconds, milliseconds = map(int, match.groups())
    return hours * 3600 + minutes * 60 + seconds + milliseconds / 1000


def parse_srt(path: Path) -> list[SubtitleBlock]:
    content = path.read_text(encoding="utf-8", errors="replace")
    content = content.replace("\r\n", "\n").replace("\r", "\n")
    blocks: list[SubtitleBlock] = []

    for raw_block in content.split("\n\n"):
        lines = [line.strip() for line in raw_block.split("\n") if line.strip()]
        time_index = next((index for index, line in enumerate(lines) if "-->" in line), None)
        if time_index is None:
            continue
        parts = lines[time_index].split("-->")
        if len(parts) != 2:
            continue
        start = parse_timestamp(parts[0])
        end = parse_timestamp(parts[1])
        if start is None or end is None:
            continue
        text_lines = lines[time_index + 1 :]
        text = " ".join(text_lines).strip()
        if text:
            blocks.append(SubtitleBlock(start=start, end=max(end, start), text=text, lines=text_lines))

    return blocks


def normalize_text(value: str) -> str:
    value = value.lower()
    value = value.replace("ą", "a").replace("č", "c").replace("ę", "e").replace("ė", "e")
    value = value.replace("į", "i").replace("š", "s").replace("ų", "u").replace("ū", "u").replace("ž", "z")
    value = re.sub(r"[^a-z0-9 ]+", " ", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def words(value: str) -> list[str]:
    normalized = normalize_text(value)
    return normalized.split() if normalized else []


def edit_distance(left: Union[list[str], str], right: Union[list[str], str]) -> int:
    a = list(left)
    b = list(right)
    previous = list(range(len(b) + 1))
    for i, left_value in enumerate(a, 1):
        current = [i] + [0] * len(b)
        for j, right_value in enumerate(b, 1):
            cost = 0 if left_value == right_value else 1
            current[j] = min(
                previous[j] + 1,
                current[j - 1] + 1,
                previous[j - 1] + cost,
            )
        previous = current
    return previous[-1]


def repeated_adjacent_phrase(normalized: str) -> Optional[str]:
    tokens = normalized.split()
    if len(tokens) < 6:
        return None
    for length in range(min(6, len(tokens) // 2), 1, -1):
        if len(tokens) < length * 2:
            continue
        for index in range(0, len(tokens) - length * 2 + 1):
            first = tokens[index : index + length]
            second = tokens[index + length : index + length * 2]
            if first == second:
                return " ".join(first)
    return None


def analyze_srt(path: Path, reference: Optional[Path] = None) -> dict:
    blocks = parse_srt(path)
    result = {
        "file": str(path),
        "blocks": len(blocks),
        "duration_seconds": 0.0,
        "text_characters": 0,
        "text_density_chars_per_second": 0.0,
        "asr": {
            "repeated_text": 0,
            "repeated_phrases": 0,
            "prompt_leakage": 0,
            "high_text_density": 0,
            "low_text_density": 0,
            "examples": [],
        },
        "srt": {
            "overlaps": 0,
            "too_fast": 0,
            "long_lines": 0,
            "too_many_lines": 0,
            "examples": [],
        },
        "reference": None,
    }

    if blocks:
        result["duration_seconds"] = max(0, blocks[-1].end - blocks[0].start)
    result["text_characters"] = sum(len(block.text) for block in blocks)
    if result["duration_seconds"] > 0:
        result["text_density_chars_per_second"] = round(
            result["text_characters"] / result["duration_seconds"], 3
        )

    seen: dict[str, int] = {}
    previous_text = ""
    previous_end: float | None = None

    def add_example(bucket: str, kind: str, block: SubtitleBlock, message: str) -> None:
        examples = result[bucket]["examples"]
        if len(examples) >= 10:
            return
        examples.append(
            {
                "kind": kind,
                "time": format_timestamp(block.start),
                "message": message,
                "text": block.text[:180],
            }
        )

    for block in blocks:
        normalized = normalize_text(block.text)
        if any(marker in normalized for marker in PROMPT_MARKERS):
            result["asr"]["prompt_leakage"] += 1
            add_example("asr", "prompt_leakage", block, "Looks like prompt/instruction text.")

        if normalized and normalized == previous_text:
            result["asr"]["repeated_text"] += 1
            add_example("asr", "repeated_text", block, "Same text repeated in adjacent blocks.")

        count = seen.get(normalized, 0) + 1
        seen[normalized] = count
        if normalized and count == 3:
            result["asr"]["repeated_text"] += 1
            add_example("asr", "repeated_text", block, "Same text appeared at least 3 times.")

        phrase = repeated_adjacent_phrase(normalized)
        if phrase:
            result["asr"]["repeated_phrases"] += 1
            add_example("asr", "repeated_phrase", block, f"Adjacent repeated phrase: {phrase}")

        duration = max(0.1, block.end - block.start)
        cps = len(block.text) / duration
        if cps > 34:
            result["asr"]["high_text_density"] += 1
            add_example("asr", "high_text_density", block, f"Very dense ASR text: {cps:.0f} chars/s.")
        if cps > 20:
            result["srt"]["too_fast"] += 1
            add_example("srt", "too_fast", block, f"Reading speed is {cps:.0f} CPS.")

        if previous_end is not None and block.start < previous_end + 0.10:
            result["srt"]["overlaps"] += 1
            add_example("srt", "overlap", block, "Starts too close to previous subtitle.")
        previous_end = block.end

        if len(block.lines) > 2:
            result["srt"]["too_many_lines"] += 1
            add_example("srt", "too_many_lines", block, "Subtitle block has more than 2 lines.")
        if any(len(line) > 42 for line in block.lines):
            result["srt"]["long_lines"] += 1
            add_example("srt", "long_line", block, "Line exceeds 42 characters.")

        previous_text = normalized

    if result["duration_seconds"] > 60 and result["text_density_chars_per_second"] < 0.8:
        result["asr"]["low_text_density"] = 1

    if reference:
        reference_text = reference.read_text(encoding="utf-8", errors="replace")
        hypothesis_text = " ".join(block.text for block in blocks)
        reference_words = words(reference_text)
        hypothesis_words = words(hypothesis_text)
        reference_chars = normalize_text(reference_text)
        hypothesis_chars = normalize_text(hypothesis_text)
        word_errors = edit_distance(reference_words, hypothesis_words)
        char_errors = edit_distance(reference_chars, hypothesis_chars)
        result["reference"] = {
            "file": str(reference),
            "reference_words": len(reference_words),
            "hypothesis_words": len(hypothesis_words),
            "word_errors": word_errors,
            "wer": round(word_errors / max(1, len(reference_words)), 4),
            "character_errors": char_errors,
            "cer": round(char_errors / max(1, len(reference_chars)), 4),
        }

    return result


def format_timestamp(value: float) -> str:
    milliseconds = max(0, round(value * 1000))
    hours = milliseconds // 3_600_000
    minutes = (milliseconds % 3_600_000) // 60_000
    seconds = (milliseconds % 60_000) // 1000
    ms = milliseconds % 1000
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{ms:03d}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze ASR and SRT quality signals.")
    parser.add_argument("srt", type=Path, help="SRT file to analyze")
    parser.add_argument("--reference", type=Path, help="Optional human transcript for WER/CER")
    parser.add_argument("--json", action="store_true", help="Print JSON instead of a concise summary")
    args = parser.parse_args()

    if not args.srt.exists():
        print(f"SRT not found: {args.srt}", file=sys.stderr)
        return 2
    if args.reference and not args.reference.exists():
        print(f"Reference not found: {args.reference}", file=sys.stderr)
        return 2

    result = analyze_srt(args.srt, args.reference)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    asr_issues = sum(
        value for key, value in result["asr"].items() if key != "examples" and isinstance(value, int)
    )
    srt_issues = sum(
        value for key, value in result["srt"].items() if key != "examples" and isinstance(value, int)
    )
    print(f"File: {result['file']}")
    print(f"Blocks: {result['blocks']} | duration: {result['duration_seconds']:.1f}s | density: {result['text_density_chars_per_second']:.2f} chars/s")
    print(f"ASR signals: {asr_issues} | SRT signals: {srt_issues}")
    if result["reference"]:
        ref = result["reference"]
        print(f"WER: {ref['wer']:.2%} | CER: {ref['cer']:.2%}")
    for bucket in ("asr", "srt"):
        for example in result[bucket]["examples"][:5]:
            print(f"- {bucket.upper()} {example['kind']} {example['time']}: {example['message']} :: {example['text']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
