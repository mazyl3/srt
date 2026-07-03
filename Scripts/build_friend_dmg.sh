#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/SRT Forge.app"
DMG_ROOT="${DIST_DIR}/SRT Forge Setup"
DMG_FILE="${DIST_DIR}/SRT-Forge-Setup.dmg"

cd "${ROOT_DIR}"

bash "${ROOT_DIR}/Scripts/build_app.sh"

rm -rf "${DMG_ROOT}" "${DMG_FILE}"
mkdir -p "${DMG_ROOT}"

cp -R "${APP_DIR}" "${DMG_ROOT}/SRT Forge.app"

cat > "${DMG_ROOT}/README - PERSKAITYK.txt" <<'README'
SRT Forge - Setup

Kas tai yra:
- Mac appas video/audio failams paversti i SRT subtitrus.
- Gali sukurti MP4 kopija su vidiniu subtitle track.
- Pirmam paruosimui reikia interneto.
- Po paruosimo transkripcija, LT/EN SRT ir vertimas veikia lokaliai be interneto.

Pirmas paleidimas:
1. Nutempk "SRT Forge.app" i Applications arba paleisk tiesiai is sio aplanko.
2. Jeigu macOS raso, kad appas is unidentified developer:
   - Right click ant appo -> Open.
   - Arba System Settings -> Privacy & Security -> Open Anyway.
3. Atsidarius appui, jeigu rodo "Offline dar ne", prisijunk prie interneto.
4. Spausk app'e "Internetinis paruosimas".
5. Palauk kol atsisius/irasys ffmpeg, whisper.cpp ir large-v3 modeli.
6. Kai appas rodo "Offline paruosta", gali dirbti be interneto.

Jeigu app'e paruosimas sustoja ties Homebrew:
- Atidaryk "Pirmas paruosimas.command" is sio DMG/folderio.
- Jis patikrins Homebrew, ffmpeg, whisper.cpp ir modeli.
- Jei Homebrew nera, scriptas parodys ka daryti.

Svarbu:
- large-v3 modelis yra apie 3 GB, todel pirmas paruosimas gali uztrukti.
- Appas nera Apple notarized, nes nenaudojamas Apple Developer account.
- Tai reiskia, kad pirma karta macOS gali rodyti saugumo ispejima.

Failai:
- SRT Forge.app - pati programa.
- Pirmas paruosimas.command - pagalbinis setup scriptas.
- README - sis failas.
README

cat > "${DMG_ROOT}/Pirmas paruosimas.command" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="${HOME}/Library/Application Support/SRT Forge"
MODEL_DIR="${APP_SUPPORT}/Models"
MODEL_FILE="${MODEL_DIR}/ggml-large-v3.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"

echo "SRT Forge pirmas paruosimas"
echo "================================"
echo
echo "Tam reikia interneto. Po sito setupo appas gales dirbti offline."
echo

mkdir -p "${MODEL_DIR}"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew nerastas."
  echo
  echo "Atidaryk https://brew.sh ir idiek Homebrew."
  echo "Tada paleisk sita faila dar karta."
  echo
  echo "Pastaba: Homebrew diegimas gali prasyti Mac password ir Xcode Command Line Tools."
  read -r -p "Spausk Enter uzdaryti..."
  exit 1
fi

echo "Tikrinamas ffmpeg..."
brew list ffmpeg >/dev/null 2>&1 || brew install ffmpeg

echo "Tikrinamas whisper.cpp..."
brew list whisper-cpp >/dev/null 2>&1 || brew install whisper-cpp

echo "Tikrinamas Hugging Face downloaderis..."
/usr/bin/python3 -m pip install --user --upgrade "huggingface_hub[hf_xet]"

if [[ -f "${MODEL_FILE}" ]] && [[ "$(stat -f%z "${MODEL_FILE}")" -ge 3000000000 ]]; then
  echo "large-v3 modelis jau yra:"
  echo "${MODEL_FILE}"
else
  echo "Siunciamas Whisper large-v3 modelis. Failas apie 3 GB."
  HF_CLI=""
  for candidate in \
    "${HOME}/Library/Python/3.12/bin/hf" \
    "${HOME}/Library/Python/3.11/bin/hf" \
    "${HOME}/Library/Python/3.10/bin/hf" \
    "${HOME}/Library/Python/3.9/bin/hf"; do
    if [[ -x "${candidate}" ]]; then
      HF_CLI="${candidate}"
      break
    fi
  done

  if [[ -n "${HF_CLI}" ]]; then
    HF_XET_HIGH_PERFORMANCE=1 "${HF_CLI}" download ggerganov/whisper.cpp ggml-large-v3.bin --local-dir "${MODEL_DIR}" --max-workers 8
  else
    curl -L --fail --continue-at - --progress-bar "${MODEL_URL}" -o "${MODEL_FILE}.tmp"
    mv "${MODEL_FILE}.tmp" "${MODEL_FILE}"
  fi
fi

echo
echo "Paruosta."
echo "ffmpeg: $(command -v ffmpeg || true)"
echo "whisper: $(command -v whisper-cli || command -v whisper-cpp || true)"
echo "modelis: ${MODEL_FILE}"
echo
echo "Dabar atidaryk SRT Forge.app. Turi rodyti Offline paruosta."
read -r -p "Spausk Enter uzdaryti..."
SCRIPT

chmod +x "${DMG_ROOT}/Pirmas paruosimas.command"

ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create \
  -volname "SRT Forge Setup" \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_FILE}"

echo
echo "DMG sukurtas:"
echo "${DMG_FILE}"
