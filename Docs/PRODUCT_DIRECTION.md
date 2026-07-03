# SRT Forge Product Direction

## Core idea

SRT Forge should become a local-first subtitle and transcription power tool for video creators, editors, interviewers, journalists, podcasters, educators, and small production teams.

The product should not be only a Whisper wrapper. The goal is to create a complete workflow:

1. Drop in a video/audio file.
2. Generate accurate subtitles.
3. Clean sentence punctuation and dialogue structure.
4. Translate when needed.
5. Export editor-ready files.
6. Optionally burn subtitles directly into the video.
7. Work offline after first setup.

## Positioning

Short positioning:

> A local Mac power tool for creating, cleaning, translating, and exporting professional subtitles.

Important promise:

- Local-first.
- Offline after setup.
- Good Lithuanian workflow.
- Useful for real video editing.
- Beginner-friendly, but powerful in Advanced mode.
- Privacy-first: media stays on the user's device during transcription, translation, and cleanup.
- Lithuanian-created and Lithuanian-first, while still being strong in English.

## Target users

### Video editors

They need:
- `.srt` files for Premiere, DaVinci Resolve, Final Cut, YouTube, TikTok, Instagram.
- Clean timing.
- Burned-in subtitles for social clips.
- Fast batch processing.
- LT subtitles, EN subtitles, or both.
- Reliable export naming.

### Interview / dialogue creators

They need:
- Speaker 1 / Speaker 2 style output.
- Dialogue cleanup.
- Paragraph text export.
- Clean punctuation.
- Possibly speaker diarization later.

### Journalists / content teams

They need:
- Fast local transcription.
- Privacy.
- Searchable text.
- Good Lithuanian support.
- Translation to English.
- Clear proof that sensitive recordings are not uploaded for processing.

### Lithuanian creators and teams

They need:
- Lithuanian UI.
- Lithuanian subtitle quality as a first-class goal.
- Lithuanian to English workflow.
- English UI/output when needed.
- Later support for more languages without weakening the Lithuanian workflow.

### Power users

They need:
- Batch queue.
- Mac specs detection.
- Performance throttle.
- Model control.
- Logs and diagnostics.

## Local privacy and optional storage

The product can work with files that are stored anywhere the user chooses, including cloud-synced folders, but cloud is only storage. It is not processing.

Core rule:
Transcription, translation, subtitle cleanup, diarization, quality checks, and video export always run locally on the user's device. The app should not have a cloud processing mode.

Supported storage locations:

- iCloud Drive
- Google Drive
- Dropbox
- Proton Drive
- OneDrive later if useful
- any normal Finder folder
- external drives
- NAS/network folders later

Initial implementation should be Finder-based:

1. User picks a file from any folder that macOS can see.
2. If the file is in iCloud/Google Drive/Dropbox/Proton Drive, macOS or that provider downloads it locally first.
3. SRT Forge copies it into a local working folder.
4. Processing happens locally.
5. Results can be saved back to the same cloud-synced folder.

This avoids complex provider APIs and keeps the privacy model simple. Cloud tools already expose files through Finder, so the app can treat them like normal folders.

Future storage convenience:

- remember cloud export folders
- watch folders for new files
- auto-create project folders
- show whether source files are local or still cloud-only
- warn before processing if a cloud-stored file is not downloaded locally yet
- save generated SRT/video/transcript outputs to the user's chosen folder

Privacy copy should be explicit:

- "Your media is processed locally."
- "Cloud folders can be used for storage, but SRT Forge does not upload your video or audio for processing."
- "First setup needs internet. After setup, transcription can work offline."
- "If a file is stored in a cloud drive, that provider may sync the file according to your own cloud settings."
- "No cloud processing. No remote transcription."

## Mobile and lighter devices

The Mac app is the first serious product because video/audio transcription is heavy.

Mobile direction:

- iPhone app later can record audio, collect clips, and send projects to Mac.
- iPhone 15 Pro and newer devices may handle lighter local transcription, but should not be the baseline for the full power workflow.
- Older phones should use capture/review/sync workflows, not heavy batch transcription.
- Phone should be treated as a companion tool first, not the main render engine.

Journalist scenario:

1. Record interview on phone.
2. Sync or AirDrop to Mac.
3. Mac generates LT transcript/SRT.
4. Optional EN translation.
5. Export text, SRT, or burned-in video.

Future iPhone features:

- local recording
- quick notes
- transfer projects to Mac through the user's chosen storage method
- lightweight transcript preview on capable devices
- privacy status indicators
- local-only mode where practical

## Language strategy

Primary languages:

- Lithuanian
- English

Main product promise:
Lithuanian is not an afterthought. The app should treat Lithuanian transcription, punctuation cleanup, and Lithuanian-to-English output as a core workflow.

Required first workflows:

- Lithuanian audio/video to Lithuanian SRT.
- Lithuanian audio/video to English SRT.
- Lithuanian audio/video to both Lithuanian and English SRT.
- English audio/video to English SRT.
- English audio/video to Lithuanian SRT later if local translation quality is good enough.

UI language direction:

- Lithuanian UI first.
- English UI should be available before wider sharing.
- Advanced technical labels can stay understandable in both languages.
- Help text should explain terms in plain language.

Future language expansion:

- add more source languages after LT/EN is solid
- expose language choice in Patyrusiems and Advanced modes
- keep Minimal mode simple and opinionated
- avoid adding many languages if quality cannot be tested

Quality priority:

1. Lithuanian transcription quality.
2. Lithuanian punctuation/readability.
3. Lithuanian to English subtitle translation.
4. English transcription.
5. More languages.

## Product modes

### Minimal

Purpose:
Bare power tool.

User sees:
- file drop
- one clear action button
- simple status
- result button

Behavior:
- one file
- LT SRT by default
- automatic punctuation cleanup
- automatic dialogue cleanup
- no technical controls

### Paprasta

Purpose:
Easy user mode.

User controls:
- language
- output: LT / EN / LT + EN
- file selection
- basic progress

No:
- thread settings
- beam settings
- batch
- detailed logs by default

### Patyrusiems

Purpose:
Quality control mode.

User controls:
- output folder
- subtitle output mode
- max segment length
- punctuation cleanup
- dialogue cleanup
- split on word
- GPU / CPU
- thread count
- beam / best-of
- no-speech threshold

### Advanced

Purpose:
Production mode.

User controls:
- batch queue
- multiple files
- Mac specs panel
- safe / recommended / maximum performance
- parallel jobs
- logs
- diagnostics
- tool/model path selection

## Subtitle outputs

Required outputs:

- `video.srt` for simple LT-only mode.
- `video.lt.srt` when both LT and EN are generated.
- `video.en.srt` for English output.
- Future: `.vtt`, `.ass`, `.txt`, `.docx`, `.json`.

Important:
If the user chooses LT + EN:

1. Create Lithuanian SRT.
2. Create English SRT.
3. Keep matching timing style.
4. Show both result buttons.

## Burned-in subtitles

This is a major video-editor feature.

Goal:
User can choose:

- export SRT only
- export MP4 copy with subtitle track
- export video with subtitles burned in later
- export both

Current implementation direction:
- First working video export should create an MP4 copy with a selectable internal subtitle track using ffmpeg `mov_text`.
- This is fast because it can copy video/audio streams instead of rendering every frame.
- It is useful for review, delivery, and some editor/player workflows.

Burn-in direction:
- True burned-in subtitles require a video filter/render path.
- ffmpeg builds must include subtitle rendering support such as libass/subtitles filter, or the app needs another local render engine.
- Do not label subtitle-track export as burn-in in the UI.

Implementation direction:
- Use ffmpeg subtitles/ass filter.
- Convert SRT to ASS for better styling control.
- Offer style presets.

Possible presets:

- Clean documentary
- YouTube bold
- TikTok captions
- Interview lower-third
- Minimal white
- High contrast accessibility

Controls:
- font
- size
- position
- color
- outline
- background box
- max lines
- safe margins

Important:
Burned-in subtitles create a new video copy. Never overwrite original.

## Editor-ready workflow

The app should be useful with:

- Final Cut Pro
- DaVinci Resolve
- Adobe Premiere
- YouTube Studio
- TikTok / Instagram / Shorts

Useful features:

- reveal exported files
- export folder preset
- naming templates
- batch output folder
- preview generated SRT
- warnings for long lines
- warnings for too-fast subtitles

## SRT quality engine

Current direction:
- trim text
- normalize spacing
- add terminal punctuation
- dialogue dash cleanup

Next quality rules:

- max characters per line
- max two lines per subtitle block
- characters per second warning
- minimum subtitle duration
- maximum subtitle duration
- avoid subtitle overlaps
- avoid too-small gaps
- split long blocks
- merge too-short blocks
- keep sentences coherent
- dialogue line formatting

Possible future "Fix All" button:

- fix punctuation
- fix long lines
- fix dialogue dashes
- fix overlaps
- fix CPS warnings

## Speaker diarization

This can become a killer feature.

User scenario:
User records an interview. App outputs:

```text
Speaker 1: Question...
Speaker 2: Answer...
```

Subtitle scenario:

```text
- Question...
- Answer...
```

Technical reality:
True speaker diarization is harder than simple transcription. It needs extra models and alignment. It may be heavier than the base Whisper workflow.

Roadmap:

1. First: dialogue formatting heuristics.
2. Later: speaker labels for transcript export.
3. Later: true diarization with local model support if practical.

## Live captions and live translation

Long-term power feature.

Potential use cases:
- live interview transcription
- meeting captions
- live Lithuanian to English translation
- local live captions on powerful Macs

Technical reality:
This is a separate engine:
- microphone capture
- streaming chunks
- partial results
- low-latency model
- rolling context
- live correction

Likely stages:

1. Live transcript preview.
2. Save live transcript to text.
3. Save live transcript to SRT with approximate timestamps.
4. Live translation.
5. Better local diarization.

This should not block the current video-editor product.

## Model strategy

Current default:
- whisper.cpp large-v3

Why:
- strong quality
- works locally
- already installed
- good offline story

Potential future model options:

- small / medium for speed
- large-v3 for quality
- turbo / distilled models for faster runs if local quality is acceptable
- alignment/word timestamp engine for better SRT timing
- diarization model for speakers

Product rule:
Beginner modes should not ask users to understand models.
Advanced mode may expose model and performance details.

## First setup / DMG strategy

DMG should not be called Friend Pack in a product build.

Better names:
- `[ProductName].dmg`
- `[ProductName] Setup.dmg`
- `[ProductName] Installer.dmg`

DMG contents:
- app
- Applications shortcut
- Read Me First
- optional setup command

Ideal first launch:

1. App opens.
2. Shows setup wizard if not offline-ready.
3. User connects to internet.
4. App installs/checks tools.
5. App downloads model.
6. App runs tiny test.
7. App shows Offline Ready.

Important:
No Apple Developer account means:
- app can be shared
- macOS may show unidentified developer warning
- user may need right-click Open / Open Anyway
- no clean notarized installer experience

## Update system

Start simple.

Phase 1:
- show current app version
- "Check for updates" button
- app downloads a small version manifest
- if update exists, open a download page or DMG URL

Phase 2:
- download DMG inside app
- show release notes
- user manually installs

Phase 3:
- real auto-update later if signing/notarization situation improves

Do not start with risky self-replacement logic.

## Branding requirements

Need:
- final product name
- icon
- DMG name
- About screen
- footer: Made by Guoste Aleknaite / Guoste Aleknaite
- version
- update check

The current `SRT Forge` name is usable for development, but likely should be renamed before public/commercial sharing.

## Strong feature roadmap

### Stage 1: Solid local app

- four modes: Minimal, Paprasta, Patyrusiems, Advanced
- offline readiness
- setup wizard
- LT / EN / LT + EN
- SRT cleanup
- DMG setup

### Stage 2: Video editor features

- burned-in subtitles
- subtitle style presets
- export SRT + video copy
- SRT preview
- file naming templates

### Stage 3: Quality engine

- CPS warnings
- line length warnings
- block split/merge
- overlap/gap repair
- "Fix All"

### Stage 4: Interview workflow

- transcript export
- speaker labels
- dialogue view
- better diarization if local model is practical

### Stage 5: Live tools

- live microphone transcription
- live captions
- live translation
- local-only workflow for powerful Macs

## Immediate next decisions

Before more implementation:

1. Choose final product name.
2. Choose icon direction.
3. Decide whether DMG is:
   - small internet-setup DMG
   - huge offline DMG with model included
   - both
4. Decide first burned-in subtitle style presets.
5. Decide what the first update-check URL will be.
