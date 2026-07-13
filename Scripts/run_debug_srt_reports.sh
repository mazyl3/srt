#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUG_DIR="${1:-/Users/guoste/Downloads/SRTForgeDebug}"

if [[ ! -d "${DEBUG_DIR}" ]]; then
  echo "Debug folder not found: ${DEBUG_DIR}" >&2
  exit 2
fi

find "${DEBUG_DIR}" -type f -name "*.srt" -print0 \
  | sort -z \
  | while IFS= read -r -d '' file; do
      echo
      "${ROOT_DIR}/Scripts/asr_quality_report.py" "${file}"
    done
