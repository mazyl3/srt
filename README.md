# SRT Forge

Native macOS SwiftUI app for generating `.srt` subtitles from audio and video files with `ffmpeg` and `whisper.cpp`.

The default transcription model is intended to be Whisper `large-v3` in GGML format for maximum local Whisper accuracy.

## What It Does

SRT Forge is a local Mac power tool for subtitle generation:

- Select or drag in an audio/video file.
- The original file is not modified.
- The app creates a safe working copy.
- `ffmpeg` converts the copy to `16 kHz mono WAV`.
- `whisper.cpp` transcribes it with `ggml-large-v3.bin`.
- The final `.srt` is saved next to the original file, or in a folder you choose.
- Optionally create a new `.mp4` copy with an internal subtitle track.
- Optionally create a new burned-in `.mp4` copy when ffmpeg supports the subtitles/libass filter.
- Check for updates from a small GitHub-hosted manifest.

## SRT Quality Engine

The app includes a first subtitle quality pass after Whisper output:

- rewrites clean SRT numbering,
- repairs overlapping timestamps,
- enforces minimum and maximum subtitle duration,
- keeps a small gap between subtitle blocks,
- wraps subtitles to readable line lengths,
- splits blocks that exceed the configured line limit,
- splits long text on sentence/phrase boundaries when possible,
- balances two-line subtitles for better readability,
- reports CPS / reading-speed warnings in the log,
- shows an in-app SRT QA panel after export with block count, timing, CPS, line-length, and duration signals,
- shows concrete SRT QA issue examples with timecodes and text previews.

## Recognition Quality

For camera files with multiple audio tracks, the app can now prepare better Whisper input:

- use only the first audio track or mix all audio tracks,
- automatically choose the strongest audio track for multi-track camera files,
- show an audio diagnostics panel with track count, codec, channels, sample rate, volume level, and Auto best recommendation,
- manually force a specific audio track from the diagnostics panel,
- detect PolyWAV / multi-channel WAV files and choose or force individual channels such as BOOM or LAV,
- prefer dedicated BOOM/LAV channels over production MixL/MixR channels when Auto best selects a PolyWAV channel,
- use a safer no-prompt/no-speech Whisper profile for PolyWAV production WAVs to reduce silence and prompt hallucinations,
- apply speech-focused filters before Whisper,
- normalize loudness for speech,
- reduce steady noise,
- pass a language prompt to Whisper for better Lithuanian/English context.

## ASR Quality And Polish

The app now separates raw transcription quality from SRT formatting quality:

- ASR Quality Report flags suspicious repeated text, repeated phrases, prompt leakage, and unusual text density.
- The subtitle cleanup pass can remove obvious ASR prompt leakage and collapse adjacent repeated phrase loops.
- The cleanup is conservative and can be disabled in experienced/advanced settings when a raw transcript is needed.

## Modes

### Paprasta

For non-technical use:

- Pick a file.
- Pick a language or enable automatic detection.
- Press `Kurti SRT`.

### Power

For experienced users:

- Set language and translation mode.
- Choose thread count.
- Keep working files for diagnostics.
- Choose the output folder.
- Inspect full process logs.
- Manually point the app to `ffmpeg`, `whisper.cpp`, or the model file.

### Advanced

For multi-file work:

- The app checks the Mac specs: CPU, active cores, RAM, macOS version, and processor name.
- It recommends a safe number of parallel SRT jobs.
- You can select multiple audio/video files.
- Each file appears as a separate job card in one window.
- The queue runs only as many jobs at once as the machine should safely handle.
- If GPU/Metal crashes, the transcription retries in CPU mode.

## Install Dependencies

From this folder:

```bash
bash Scripts/install_dependencies.sh
```

This installs:

- `ffmpeg-full` with subtitles/libass support
- `whisper-cpp`
- Hugging Face downloader with `hf-xet`
- Whisper `ggml-large-v3.bin`

The model is stored here:

```text
~/Library/Application Support/SRT Forge/Models/ggml-large-v3.bin
```

The model file is large. The download can take a while.

If Hugging Face is slow without a token, the app and script still keep the setup resumable. The file must finish downloading before the default `large-v3` mode is ready.

## Build The Mac App

```bash
bash Scripts/build_app.sh
```

Then open:

```bash
open "dist/SRT Forge.app"
```

## Smoke Test

To verify the actual audio-to-SRT pipeline without waiting for the full 3.1 GB model:

```bash
bash Scripts/run_smoke_test.sh
```

This downloads a tiny test model, creates a short macOS voice sample, converts it with `ffmpeg-full`, transcribes it with `whisper-cli`, and writes:

```text
TestRuns/sample.srt
TestRuns/sample-subtitled.mp4
TestRuns/sample-burned.mp4
```

## Updates

The app can check a small manifest:

```text
https://raw.githubusercontent.com/mazyl3/srt/refs/heads/main/version.json
```

Current release DMG URL is stored in `version.json`. The app does not replace itself while running; it opens the download URL so the user can install the new DMG manually.

## Notes

This is the first working app version. It is designed so the next improvements can be added cleanly:

- in-app one-click dependency installer,
- batch processing,
- model picker with `large-v3` and faster alternatives,
- waveform preview,
- subtitle editor,
- subtitle preview and timing editor,
- export to `.vtt` and `.txt`.
