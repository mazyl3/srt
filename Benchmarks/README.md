# SRT Forge Benchmarks

This folder defines small, repeatable quality cases for real-world ASR/SRT testing.

Large private media files are not committed here. Keep source WAV/video files in their original local location and document the path in each case `notes.md`.

## Why This Exists

SRT Forge needs to measure two different things:

- ASR accuracy: did the speech model recognize the right words?
- SRT quality: are timing, line length, CPS, and subtitle structure editor-ready?

A technically valid SRT can still have bad ASR text. Benchmarks keep that visible.

## Case Structure

```text
Benchmarks/
  cases/
    CASE_NAME/
      notes.md
      reference.txt
```

`reference.txt` should contain a human-verified transcript. Without it, scripts can still flag suspicious ASR/SRT signals, but WER/CER cannot be trusted.

## Run A Report

Analyze a single SRT:

```bash
Scripts/asr_quality_report.py /path/to/file.srt
```

Analyze with reference transcript:

```bash
Scripts/asr_quality_report.py /path/to/file.srt --reference Benchmarks/cases/69ET02/reference.txt
```

Analyze existing debug SRTs:

```bash
Scripts/run_debug_srt_reports.sh
```

## Quality Signals

The benchmark script checks:

- repeated subtitle text,
- repeated adjacent phrases,
- prompt leakage,
- unusual text density,
- subtitle overlaps,
- high CPS,
- long lines,
- too many lines,
- WER/CER when reference text exists.

## Rule

Do not judge Lithuanian ASR quality by feel only. Put hard cases here and compare build-to-build.
