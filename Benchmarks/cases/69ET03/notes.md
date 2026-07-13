# 69ET03

Local source:

```text
/Users/guoste/Downloads/69ET03.WAV
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

Earlier Whisper tests showed prompt leakage and repeated hallucinated phrases on some channels. This case should remain a hard regression test for ASR Quality Report and ASR artifact cleanup.

Reference:

Fill `reference.txt` with a human-verified transcript before treating WER/CER as meaningful.
