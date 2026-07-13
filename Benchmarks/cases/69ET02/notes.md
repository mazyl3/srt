# 69ET02

Local source:

```text
/Users/guoste/Downloads/69ET02.WAV
```

Production audio type:

- PolyWAV / multi-channel WAV.
- 4 channels detected by ffprobe.
- Metadata seen in earlier diagnostics:
  - Ch1: MixL BOOM
  - Ch2: MixR LAV
  - Ch3: BOOM 1
  - Ch4/metadata fallback: ELENA

Known issue:

Whisper large-v3 produced weak Lithuanian transcription on earlier tests. Channel choice matters; dedicated BOOM/LAV channels should be preferred over Mix channels when appropriate.

Reference:

Fill `reference.txt` with a human-verified transcript before treating WER/CER as meaningful.
