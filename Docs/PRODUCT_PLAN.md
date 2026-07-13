# SRT Forge Product Plan

## Product Positioning

SRT Forge is not positioned as a Wispr Flow clone.

Core positioning:
SRT Forge is a local-first subtitle and transcription production tool for video editors, creators, journalists, educators, lecturers, event teams, and production workflows.

Broader category:
SRT Forge is a local-first audio-to-text production tool. It works with everything where sound becomes text and that text must become a professional result.

Short English positioning:
Local-first subtitle production for creators, editors, journalists, and educators.

Short Lithuanian positioning:
Lokalus subtitrų gamybos įrankis video montuotojams, kūrėjams, žurnalistams ir mokymams.

Main promise:
- clean subtitles
- accurate timestamps
- editor-ready SRT
- strong Lithuanian workflow
- multilingual support
- no cloud processing
- works offline after setup

Product hierarchy:
1. Highest-class SRT quality is the core product.
2. Video editor workflow is the first commercial wedge.
3. Audio-to-text workflows expand the product category.
4. Live captions, dictation, local LLM polish, mobile, and translation are killer features that should support the core instead of distracting from it.

Primary product test:
Can a video editor trust the SRT timing and readability without spending half the job fixing it manually?

SRT Forge should not be described as only a Whisper wrapper. Whisper or another speech model is only the raw transcription engine. The product value is the full subtitle workflow and quality layer.

## Product Scope

SRT Forge should cover the audio + text workflow around:
- subtitles
- transcription
- translation
- live captions
- lecture/event captions
- interview transcripts
- speaker/dialogue text
- video-editor SRT files
- audio/video archive text
- summaries
- polished text
- voice dictation later

The center remains:

```text
sound -> text -> professional output
```

Do not let broad scope weaken the first product. The first product must be excellent at SRT.

## Primary Users

### Video editors

Most important early user group.

They need:
- accurate SRT files
- clean timestamps
- no subtitle overlap
- readable subtitle blocks
- Premiere / DaVinci / Final Cut / YouTube compatibility
- batch exports
- predictable file names
- subtitle quality checks
- future burn-in video export

### Creators

They need:
- quick subtitles for YouTube, TikTok, Reels, Shorts
- Lithuanian and English output
- readable captions
- MP4 subtitle track or burn-in export
- simple mode with minimal choices

### Journalists and interviewers

They need:
- private local transcription
- speaker/dialogue handling
- long interview transcripts
- Lithuanian-first support
- export to SRT, TXT, DOCX
- later speaker diarization

### Lecturers, teachers, events

They need:
- live captions on projector
- accessible lectures
- saved transcript after session
- Lithuanian live captions
- optional English live translation later
- high contrast display mode

## Main Product Difference

Competitors often focus on dictation, raw transcription, or cloud creator tools.

SRT Forge focuses on:
- editor-ready subtitles
- local privacy
- Lithuanian-first quality
- professional timing and readability
- video workflow
- batch workflow
- live captions as a Pro extension

Important distinction:
Wispr Flow is mainly voice-to-text in any app. SRT Forge is subtitle production and live captioning for media workflows.

## Core Workflow

File mode:
1. User drops in video or audio.
2. App makes a safe copy.
3. Audio is prepared locally.
4. Local speech model creates raw transcript and timestamps.
5. Subtitle Quality Engine repairs timing/readability.
6. User gets editor-ready outputs.

Outputs:
- `.srt`
- `.lt.srt`
- `.en.srt`
- `.vtt` later
- `.ass` later
- `.txt` transcript
- `.docx` transcript later
- `.mp4` with subtitle track
- burned-in MP4 later

## Subtitle Quality Engine

This is the most important technical differentiator.

Goal:
SRT Forge should create subtitles that are ready for real editing and publishing, not just raw speech-to-text output.

Required quality checks:
- no overlapping subtitle blocks
- minimum subtitle duration
- maximum subtitle duration
- minimum gap between subtitles
- maximum characters per line
- maximum 2 lines per subtitle block
- reading speed / CPS warnings
- language-aware line wrapping
- sentence-aware splitting
- punctuation cleanup
- dialogue dash cleanup
- speaker/dialogue formatting later

Suggested defaults:
- minimum duration: 1.0-1.2 seconds
- maximum duration: 5-7 seconds
- minimum gap: 80-120 ms
- max characters per line: 37-42 for Latin-script languages
- max lines: 2
- CPS: language-dependent, approximately 15-20 chars/sec for many European languages

Quality UI:
- "Timing: good"
- "0 overlaps"
- "3 subtitles too fast"
- "2 blocks too long"
- "Fix All"
- "Export is editor-ready"

Pipeline:
```text
Speech model timestamps
 -> segment cleanup
 -> sentence boundary detection
 -> line wrapping
 -> duration repair
 -> overlap/gap repair
 -> reading speed check
 -> final SRT validation
```

## Timing Accuracy

Accurate timestamps are a core product requirement.

The app must prioritize:
- correct start time
- correct end time
- no timestamp overlap
- stable ordering
- clean SRT numbering
- readable timing even when speech is fast
- no broken blocks caused by model noise

Future improvement:
- word-level timestamps
- forced alignment
- audio VAD segmentation
- model confidence warnings
- manual timing editor
- waveform preview

## Language Strategy

Brand identity:
Lithuanian-first, multilingual by design.

Tier 1 languages:
- Lithuanian
- English

These must be strongest:
- transcription
- punctuation
- line splitting
- subtitle timing
- LT <-> EN output
- live captions
- live translation later

Tier 2 European languages:
- German
- French
- Spanish
- Italian
- Polish
- Ukrainian
- Latvian
- Estonian
- Dutch
- Swedish / Norwegian / Danish
- Russian if useful for practical transcription workflows

Tier 3 global main languages:
- Chinese
- Japanese
- Korean
- Arabic
- Hindi
- Portuguese
- Turkish

Important:
Chinese, Japanese, and Korean need different subtitle rules. Do not use only space-based line breaking. Punctuation, density, and sentence boundaries must be language-aware.

Language-aware architecture:
```text
Language profile
 -> speech model language
 -> punctuation rules
 -> subtitle line breaking rules
 -> reading speed rules
 -> translation direction
 -> quality warnings
```

## Lithuanian Speech And Semantics Strategy

SRT Forge should treat Lithuanian quality as a product moat, not as a UI language setting.

Two Lithuanian-specific pillars matter:

1. LIEPA-3 for speech recognition quality.
2. SEMANTIKA-style linguistic analysis for text cleanup, punctuation, sentence structure, and meaning-aware subtitle polish.

### LIEPA-3

LIEPA-3 is strategically important because it is a large Lithuanian ASR/STT corpus, not just a small demo dataset.

Public information indicates:
- about 10,000 hours of annotated Lithuanian speech,
- FLAC audio at 44.1 kHz, 16-bit, mono,
- text annotations at phrase and word levels,
- Praat TextGrid phoneme-level annotations for part of the corpus,
- read speech, spontaneous speech, and dialect material,
- about 1.13 TB compressed release size split into large download parts,
- availability through Lithuanian open data / CLARIN-LT channels.

Product implication:
SRT Forge should not try to hand-build a small Lithuanian speech base first. The practical route is to evaluate LIEPA-3 as the foundation for Lithuanian ASR improvement.

Possible uses:
- evaluate current Whisper large-v3 Lithuanian errors against LIEPA-3 samples,
- fine-tune or train a Lithuanian-first ASR model if licensing and compute allow it,
- build a Lithuanian pronunciation / phrase correction layer,
- improve forced alignment and timestamp confidence using word-level annotations,
- create benchmark sets for production audio, spontaneous speech, and dialects.

Important constraints:
- verify license before any commercial training or redistribution,
- do not bundle the corpus inside the app,
- do not require normal users to download terabytes of training data,
- keep the shipped app local and lightweight,
- if a derived model is created, distribute only the model if the license allows it.

### SEMANTIKA-style Lithuanian text layer

SEMANTIKA points toward the second layer: the transcript may be phonetically recognized, but it still needs to become good Lithuanian written text.

This layer should help with:
- punctuation,
- capitalization,
- sentence boundary detection,
- Lithuanian morphology-aware cleanup,
- phrase meaning and context repair,
- speaker/dialogue readability,
- subtitle shortening without changing meaning,
- domain-specific cleanup for interviews, education, legal, medical, and administrative speech later.

Product implication:
The Lithuanian quality engine should become two-stage:

```text
ASR layer
 -> raw Lithuanian words and rough timestamps
 -> Lithuanian semantic/text polish layer
 -> subtitle timing and readability engine
 -> editor-ready SRT
```

This should be local-first. Existing online services are useful for research and benchmarking, but SRT Forge should not depend on cloud processing for private media.

### Near-term implementation path

For the current app, the next practical steps are:
- create a Lithuanian ASR benchmark folder with known WAV + expected transcript pairs,
- compare Whisper output against human reference text using WER/CER,
- store SRT quality metrics separately from ASR text accuracy metrics,
- add an internal "ASR Quality Report" for suspicious repeats, hallucinations, silence text, and likely wrong channels,
- use production WAV channel diagnostics before model-level changes,
- only then evaluate LIEPA-3-based model work.

This keeps the product focused: first fix the real production WAV pipeline, then build a stronger Lithuanian model strategy on real evidence.

## Local Privacy

Core rule:
No cloud processing.

Allowed:
- user can store files wherever they choose
- iCloud / Google Drive / Dropbox / Proton Drive can be storage folders
- app can read/write local files exposed through Finder

Not allowed:
- no remote transcription
- no remote subtitle cleanup
- no remote translation by default
- no hidden upload of audio/video

Product copy:
- "Your media stays on your device."
- "Cloud folders are only storage. Processing is local."
- "First setup needs internet. Work can run offline after setup."

## Live Captions

Live Captions should become a Pro/Advanced extension, not the initial core identity.

Killer scenario:
A lecturer connects a Mac to a projector, opens SRT Forge Live, speaks Lithuanian, and live subtitles appear on the projected screen. At the end, the app saves the transcript and optional SRT.

Use cases:
- lectures
- schools
- universities
- conferences
- churches
- municipal events
- company trainings
- interviews
- live news monitoring

Live Room Mode:
- control window on Mac
- clean projector/subtitle window
- font size controls
- high contrast mode
- language selector
- pause/resume
- save transcript
- save SRT
- optional LT/EN display
- latency vs accuracy control

Technical pipeline:
```text
Microphone / system audio
 -> VAD / silence detection
 -> streaming transcription chunks
 -> partial transcript
 -> punctuation cleanup
 -> live subtitle display
 -> saved transcript / SRT
 -> optional local translation
```

Target live latency:
- 1-3 seconds for lectures and events
- prioritize readability over ultra-low latency
- show stable captions, not flickering raw fragments

## Dictation / Whisper Flow-Like Feature

This can exist as an additional module, not the main product.

Feature:
User presses a shortcut, speaks, and SRT Forge writes clean text into clipboard or the active app.

Local pipeline:
```text
Voice input
 -> local speech model
 -> raw text
 -> local LLM polish
 -> paste/copy output
```

Modes:
- Raw transcript
- Clean Lithuanian text
- Email style
- Notes style
- Article draft
- Interview transcript
- Subtitle-friendly short text

This feature competes partly with Wispr Flow, but the product should still be marketed around subtitle/transcription production.

## Local LLM Polish Layer

Purpose:
Turn raw transcription into polished, usable text.

Possible local model families:
- Qwen
- Gemma
- Mistral
- Llama-family GGUF models

Runtime direction:
- llama.cpp / GGUF for Mac and possibly some mobile devices
- Apple/Core ML path for iPhone/iPad if practical
- smaller quantized models for mobile

Polish tasks:
- punctuation
- capitalization
- filler word removal
- sentence cleanup
- paragraphing
- summary
- translation
- title/chapters
- speaker-friendly transcript
- subtitle shortening

Important:
LLM polish must be optional. Raw transcript and raw SRT must still be available.

## Device Strategy

### Mac

Primary production platform.

Mac should support:
- large models
- batch processing
- editor-ready SRT
- MP4 subtitle track
- future burn-in
- local LLM polish
- live captions
- live dictation
- performance throttle

### iPad Pro / high-end tablets

Potential serious local device.

Good for:
- live captions
- recording
- transcription
- review
- light editing

### iPhone 15 Pro and newer

Possible but must be power-aware.

Good for:
- recording
- quick transcript
- smaller speech models
- companion workflow
- later live captions with battery limits

Use modes:
- Battery
- Balanced
- Max

### Snapdragon Elite / high-end Android/Windows ARM

Future platform.

Potential:
- local transcription
- local LLM polish
- live captions
- cross-platform product expansion

Do not start here until Mac workflow is strong.

## Roadmap

### Stage 1: Strong Mac SRT Product

Must be excellent:
- video/audio file import
- LT / EN / LT+EN SRT
- local setup
- no cloud processing
- batch
- performance mode
- SRT quality engine
- timing validation
- editor-ready export
- GitHub update check

### Stage 2: Video Editor Power Features

- MP4 subtitle track
- true burned-in subtitles
- ASS style presets
- SRT preview
- waveform preview
- line/timing editor
- export presets for Premiere / DaVinci / Final Cut / YouTube

### Stage 3: Local LLM Polish

- clean transcript
- punctuation polish
- filler removal
- summaries
- transcript formats
- local translation
- optional model download/setup
- Lithuanian semantic/text polish inspired by SEMANTIKA-style analysis
- ASR accuracy benchmark with Lithuanian reference transcripts

### Stage 4: Live Captions

- Mac live caption window
- projector mode
- save transcript
- save SRT
- LT live captions first
- EN live captions next
- live translation later

### Stage 5: Dictation Module

- shortcut/hotkey
- speak to clipboard
- paste into active app
- local text polish
- user style presets

### Stage 6: Mobile Companion

- iPhone/iPad recording
- local quick transcript on capable devices
- send project to Mac
- live captions on high-end devices
- Android/Snapdragon later

## Product Principle

SRT Forge should be judged by one main question:

Can a video editor, journalist, or lecturer trust the output without spending half the job fixing it manually?

If yes, the product is valuable.

If no, it is only another Whisper wrapper.
