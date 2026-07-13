#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="${HOME}/Library/Application Support/SRT Forge"
MODEL_DIR="${APP_SUPPORT}/Models"
MODEL_FILE="${MODEL_DIR}/ggml-large-v3.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"

mkdir -p "${MODEL_DIR}"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew nerastas."
  echo "Idiek Homebrew is https://brew.sh arba idiek ffmpeg ir whisper.cpp rankiniu budu."
  exit 1
fi

echo "Diegiamas ffmpeg-full su libass/subtitles palaikymu..."
brew list ffmpeg-full >/dev/null 2>&1 || brew install ffmpeg-full

FFMPEG_BIN=""
for candidate in \
  "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg" \
  "/usr/local/opt/ffmpeg-full/bin/ffmpeg" \
  "$(command -v ffmpeg || true)"; do
  if [[ -n "${candidate}" && -x "${candidate}" ]]; then
    FFMPEG_BIN="${candidate}"
    break
  fi
done
if [[ -z "${FFMPEG_BIN}" ]]; then
  echo "ffmpeg nerastas po diegimo."
  exit 1
fi
FFMPEG_FILTERS="$("${FFMPEG_BIN}" -hide_banner -filters 2>/dev/null || true)"
if ! grep -Eq '(^|[[:space:]])subtitles([[:space:]]|$)' <<<"${FFMPEG_FILTERS}"; then
  echo "ffmpeg neturi subtitles/libass filtro. Burned-in MP4 neveiks."
  exit 1
fi

echo "Diegiamas whisper.cpp..."
brew list whisper-cpp >/dev/null 2>&1 || brew install whisper-cpp

echo "Diegiamas Hugging Face downloaderis modeliams..."
python3 -m pip install --user --upgrade "huggingface_hub[hf_xet]"

if [[ -f "${MODEL_FILE}" ]]; then
  echo "Modelis jau yra: ${MODEL_FILE}"
else
  echo "Siunciamas Whisper large-v3 modelis."
  echo "Failas didelis, tai gali uztrukti."
  HF_CLI="${HOME}/Library/Python/3.9/bin/hf"
  if [[ -x "${HF_CLI}" ]]; then
    rm -f "${MODEL_FILE}.tmp" "${MODEL_FILE}.tmp.aria2"
    HF_XET_HIGH_PERFORMANCE=1 "${HF_CLI}" download ggerganov/whisper.cpp ggml-large-v3.bin --local-dir "${MODEL_DIR}" --max-workers 8
  else
    curl -L --fail --continue-at - --progress-bar "${MODEL_URL}" -o "${MODEL_FILE}.tmp"
    mv "${MODEL_FILE}.tmp" "${MODEL_FILE}"
  fi
fi

echo
echo "Paruosta."
echo "Modelis: ${MODEL_FILE}"
echo "ffmpeg: ${FFMPEG_BIN}"
echo "whisper.cpp: $(command -v whisper-cli || command -v whisper-cpp || true)"
