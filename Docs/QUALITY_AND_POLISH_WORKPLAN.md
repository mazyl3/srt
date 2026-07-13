# SRT Forge Quality And Polish Workplan

## Purpose

This document defines the concrete work needed to make SRT Forge a high-quality Lithuanian-first subtitle and transcription tool.

The goal is not only to produce technically valid `.srt` files. The goal is to produce editor-ready subtitles that a video editor, journalist, lecturer, or creator can trust.

Core quality layers:

```text
Audio source quality
 -> ASR text accuracy
 -> Lithuanian text polish
 -> SRT timing and readability
 -> export reliability
```

## Principles

- Local-first: user media is processed on the device.
- No cloud transcription or cloud text cleanup.
- LIEPA-3 is a research, benchmark, and possible model-training resource, not an app dependency.
- SEMANTIKA-style work is a direction for Lithuanian linguistic polish, not a mandatory online service dependency.
- Whisper large-v3 remains the current working ASR engine until a better local engine is proven.
- Every quality improvement must be measurable with real files.

## Current Known Problem From WAV Tests

The first real production WAV tests showed that technical SRT validity is not enough.

Observed issues:

- PolyWAV files can contain multiple channels with different usefulness.
- The loudest channel is not always the best transcription channel.
- MixL / MixR can be worse for ASR than dedicated BOOM / LAV channels.
- Whisper language prompts can leak into output on difficult production audio.
- Silence or low-confidence sections can produce repeated hallucinated text.
- Current SRT QA can validate structure, but it does not yet measure word accuracy.

Already implemented:

- PolyWAV channel diagnostics.
- Manual channel selection.
- Auto best channel selection with BOOM/LAV preference over MixL/MixR.
- Safer no-prompt PolyWAV Whisper profile.
- Stricter no-speech threshold for multi-channel production WAV.
- SRT structural QA panel with timing, CPS, line-length, and examples.
- ASR Quality Report for repeated text, repeated phrases, prompt leakage, and unusual text density.
- Conservative ASR artifact cleanup for prompt leakage and adjacent repeated phrase loops.
- TXT transcript export generated from the cleaned SRT output.
- VTT subtitle export generated from the cleaned SRT output.
- ASS styled subtitle export generated from the cleaned SRT output.
- Output manifest JSON generated for auditability and benchmark tracking.

## Workstream 1: ASR Quality Report

Purpose:
Detect when the raw speech-to-text output is suspicious, even if the SRT format is valid.

Checks to add:

- repeated phrase detection,
- repeated subtitle text over multiple blocks,
- prompt leakage detection,
- text generated during likely silence,
- extremely low text density for a long audio file,
- extremely high text density for a short interval,
- suspicious generic phrases repeated across unrelated files,
- language mismatch warnings,
- very short or empty output warnings,
- channel confidence warning when another channel likely performs better.

Output:

- in-app "ASR Quality Report",
- log entries with concrete timecodes and text snippets,
- a clear status such as:
  - "ASR looks usable",
  - "ASR has suspicious repeats",
  - "Possible wrong audio channel",
  - "Whisper hallucination likely",
  - "Manual review recommended".

Definition of done:

- The app can warn that a file like `69ET03.WAV` has repeated/hallucinated text instead of only saying the SRT is valid.
- The warning shows examples, not only a count.

## Workstream 2: WAV And PolyWAV Quality Engine

Purpose:
Make production audio source selection stronger before ASR starts.

Checks to add:

- channel label reading: BOOM, LAV, MixL, MixR, named speaker labels,
- mean volume per channel,
- peak/silence ratio per channel,
- speech-like activity score,
- clipping warning,
- noisy channel warning,
- likely empty channel warning,
- channel comparison report,
- optional quick 20-30 second transcription probe per candidate channel later.

Selection policy:

- Prefer dedicated BOOM/LAV/speaker channels when they are close enough in level.
- Avoid MixL/MixR when a clean dedicated channel exists.
- If channel scores are close, show the top candidates to the user.
- In Advanced mode, allow manual override.

Definition of done:

- For real production WAVs, the app explains why it picked a channel.
- The app can say "Auto best picked Ch3 BOOM 1 because Ch1 is a Mix channel."

## Workstream 3: Lithuanian Text Polish

Purpose:
Turn raw Lithuanian ASR text into written Lithuanian that reads naturally in subtitles.

Near-term rule-based polish:

- normalize spacing,
- fix obvious punctuation spacing,
- ensure sentence-ending punctuation,
- split long sentences at natural phrase boundaries,
- avoid overly long subtitle lines,
- preserve dialogue dashes,
- remove duplicated adjacent phrases when confidence is low,
- detect filler-heavy fragments but do not delete meaning without user choice.

Later local model polish:

- local small LLM for punctuation and sentence cleanup,
- Lithuanian-aware capitalization,
- optional filler cleanup,
- optional clean transcript mode,
- optional subtitle-shortening mode,
- optional style presets.

SEMANTIKA-style direction:

- morphology-aware cleanup,
- syntax-aware sentence boundaries,
- meaning-preserving shortening,
- domain-aware corrections,
- better Lithuanian punctuation.

Definition of done:

- Raw ASR text can be converted into cleaner Lithuanian without changing meaning.
- The user can choose between "faithful transcript" and "clean subtitle text".

## Workstream 4: SRT Timing Quality

Purpose:
Make subtitles comfortable for video editors and viewers.

Existing checks:

- valid SRT numbering,
- overlap repair,
- duration limits,
- minimum gaps,
- line wrapping,
- sentence-aware splitting,
- CPS warnings,
- concrete issue examples.

Next checks:

- subtitle block density heatmap,
- long silent gaps with text warning,
- fast-speech compression warning,
- scene-length summary,
- export preset profiles:
  - YouTube,
  - Premiere,
  - DaVinci Resolve,
  - Final Cut,
  - social burned captions.

Definition of done:

- The app can say whether the SRT is "editor-ready" or "needs review".
- The report distinguishes text accuracy problems from timing/readability problems.

## Workstream 5: Benchmark Discipline

Purpose:
Stop judging quality by feel only.

Benchmark folder structure:

```text
Benchmarks/
  cases/
    69ET02/
      source.wav
      reference.txt
      notes.md
    69ET03/
      source.wav
      reference.txt
      notes.md
  outputs/
    whisper-large-v3/
      69ET02.srt
      69ET03.srt
  reports/
    asr-quality.json
    srt-quality.json
```

Metrics:

- WER: word error rate,
- CER: character error rate,
- repeated phrase count,
- hallucinated prompt count,
- subtitle overlap count,
- CPS warnings,
- line-length warnings,
- manual review notes.

Manual reference requirement:

- Each serious benchmark case needs a human reference transcript.
- If there is no reference text, the result can be inspected but not treated as measured accuracy.

Definition of done:

- We can compare build-to-build quality on the same WAV files.
- We can prove whether a change improved or damaged Lithuanian recognition.

## Workstream 6: LIEPA-3 Research Path

Purpose:
Use LIEPA-3 without making the normal app huge or cloud-dependent.

Rules:

- Do not bundle LIEPA-3 in the app.
- Do not require users to download LIEPA-3.
- Verify license before commercial model training or redistribution.
- Use small subsets first.
- Use it for benchmarks before model training.

Possible stages:

1. License and format review.
2. Download a small subset for internal tests.
3. Build conversion scripts for audio + annotation pairs.
4. Create Lithuanian ASR benchmark cases.
5. Compare Whisper large-v3 against LIEPA-3 references.
6. Evaluate whether fine-tuning or a derived local model is worth it.

Definition of done:

- We know whether LIEPA-3 can improve the product in practice.
- We have a legal and technical path before using it commercially.

## Workstream 7: User Experience For Quality

Purpose:
Make quality understandable to non-professional and advanced users.

Minimal mode:

- Show simple status only:
  - "Good",
  - "Needs review",
  - "Possible wrong channel".

Paprasta mode:

- Show summary cards:
  - audio source,
  - ASR quality,
  - subtitle timing,
  - output files.

Patyrusiems mode:

- Show warnings with examples.
- Let the user choose another channel.
- Let the user rerun with safer settings.

Advanced mode:

- Full channel diagnostics.
- Full ASR report.
- SRT issue table.
- Benchmark/export diagnostics.
- Keep working files.

Definition of done:

- Beginners understand what to do next.
- Advanced users can see why the app made a decision.

## Near-Term Priority Order

1. Add ASR Quality Report for repeated/hallucinated text.
2. Add better channel scoring report for PolyWAV.
3. Create a benchmark folder and first two cases from `69ET02.WAV` and `69ET03.WAV`.
4. Add WER/CER script for reference transcript comparison.
5. Add UI summary for ASR Quality separately from SRT Quality.
6. Improve Lithuanian punctuation and duplicate phrase cleanup.
7. Add richer `.txt` transcript formatting and optional paragraph merge controls.
8. Start LIEPA-3 license/format research as a separate research task.

## What We Should Not Do Yet

- Do not train a large model from scratch.
- Do not download all of LIEPA-3 just to experiment.
- Do not send user media to external services.
- Do not add cloud processing.
- Do not hide ASR uncertainty from the user.
- Do not treat "valid SRT" as "good SRT".

## Success Criteria

SRT Forge quality work is succeeding when:

- the app picks the right WAV channel more often,
- hallucinations are detected and clearly reported,
- Lithuanian punctuation and sentence structure improve,
- SRT timing is editor-ready,
- quality changes are measured on stable benchmark files,
- the user understands what happened and what to do next,
- privacy stays local-first.
