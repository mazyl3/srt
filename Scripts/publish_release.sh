#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

VERSION="$(/usr/bin/python3 - <<'PY'
import json
with open("version.json", "r", encoding="utf-8") as f:
    print(json.load(f)["version"])
PY
)"
BUILD="$(/usr/bin/python3 - <<'PY'
import json
with open("version.json", "r", encoding="utf-8") as f:
    print(json.load(f)["build"])
PY
)"
TAG="v${VERSION}-build${BUILD}"
DMG="dist/SRT-Forge-Setup.dmg"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI nerastas. Idiek: brew install gh"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI neprijungtas. Pirma paleisk: gh auth login"
  exit 1
fi

if [[ ! -f "${DMG}" ]]; then
  echo "DMG nerastas: ${DMG}"
  echo "Pirma paleisk: SRTFORGE_APP_VERSION=${VERSION} SRTFORGE_APP_BUILD=${BUILD} bash Scripts/build_friend_dmg.sh"
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Repo turi necommitintų pakeitimų. Pirma commitink arba sutvarkyk statusą."
  git status --short
  exit 1
fi

git push origin main

if git rev-parse "${TAG}" >/dev/null 2>&1; then
  git tag -f "${TAG}" HEAD
else
  git tag "${TAG}" HEAD
fi
git push origin "${TAG}" --force

if gh release view "${TAG}" >/dev/null 2>&1; then
  gh release upload "${TAG}" "${DMG}" --clobber
else
  gh release create "${TAG}" "${DMG}" \
    --title "SRT Forge ${VERSION} build ${BUILD}" \
    --notes-file version.json
fi

echo "Publikuota:"
echo "https://github.com/mazyl3/srt/releases/tag/${TAG}"
