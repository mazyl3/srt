#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT_DIR}/TestRuns"
MODEL_DIR="${HOME}/Library/Application Support/SRT Forge/Models/Test"
MODEL_FILE="${MODEL_DIR}/ggml-tiny.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"

mkdir -p "${TEST_DIR}" "${MODEL_DIR}"

if [[ ! -f "${MODEL_FILE}" ]]; then
  echo "Downloading tiny test model..."
  curl -L --fail --continue-at - --progress-bar "${MODEL_URL}" -o "${MODEL_FILE}"
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found."
  exit 1
fi

if ! command -v whisper-cli >/dev/null 2>&1; then
  echo "whisper-cli not found."
  exit 1
fi

SOURCE_AUDIO="/System/Library/AssetsV2/com_apple_MobileAsset_TTSAXResourceModelAssets/08f4b5d5e2b7f3d74b63ada8188909e0441b4a1f.asset/AssetData/Contents/com.apple.voice.enhanced.en-US.Samantha.caf"

if [[ ! -f "${SOURCE_AUDIO}" ]]; then
  echo "Test voice sample not found:"
  echo "${SOURCE_AUDIO}"
  exit 1
fi

ffmpeg -y \
  -i "${SOURCE_AUDIO}" \
  -map 0:a:0 \
  -vn \
  -ar 16000 \
  -ac 1 \
  -c:a pcm_s16le \
  -bitexact \
  -f wav \
  "${TEST_DIR}/sample.wav" >/tmp/srtforge-smoke-ffmpeg.log 2>&1

if [[ ! -s "${TEST_DIR}/sample.wav" ]] || [[ "$(stat -f%z "${TEST_DIR}/sample.wav")" -lt 1000 ]]; then
  echo "Prepared WAV is empty or invalid."
  exit 1
fi

whisper-cli \
  -m "${MODEL_FILE}" \
  -f "${TEST_DIR}/sample.wav" \
  -osrt \
  -pp \
  -of "${TEST_DIR}/sample" \
  -t 4 \
  -l en \
  -ml 42 \
  -bo 5 \
  -bs 5 \
  -nth 0.60 \
  -sow \
  -sns \
  -ng >/tmp/srtforge-smoke-whisper.log 2>&1

test -s "${TEST_DIR}/sample.srt"

ffmpeg -y \
  -f lavfi \
  -i color=c=0x102030:s=1280x720:d=3 \
  -i "${TEST_DIR}/sample.wav" \
  -shortest \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -c:a aac \
  "${TEST_DIR}/sample-video.mp4" >/tmp/srtforge-smoke-video-source.log 2>&1

ffmpeg -y \
  -i "${TEST_DIR}/sample-video.mp4" \
  -i "${TEST_DIR}/sample.srt" \
  -map 0:v:0 \
  -map '0:a?' \
  -map 1:0 \
  -c:v copy \
  -c:a copy \
  -c:s mov_text \
  -metadata:s:s:0 language=eng \
  -movflags +faststart \
  "${TEST_DIR}/sample-subtitled.mp4" >/tmp/srtforge-smoke-video-subtitles.log 2>&1

test -s "${TEST_DIR}/sample-subtitled.mp4"

echo "Smoke test passed:"
echo "${TEST_DIR}/sample.srt"
echo "${TEST_DIR}/sample-subtitled.mp4"
