#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/release"
APP_DIR="${ROOT_DIR}/dist/SRT Forge.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
APP_VERSION="${SRTFORGE_APP_VERSION:-0.1.0}"
APP_BUILD="${SRTFORGE_APP_BUILD:-1}"
UPDATE_MANIFEST_URL="${SRTFORGE_UPDATE_MANIFEST_URL:-}"

cd "${ROOT_DIR}"

echo "Kuriamas release build..."
swift build -c release

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BUILD_DIR}/SRTForge" "${MACOS_DIR}/SRT Forge"

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>SRT Forge</string>
  <key>CFBundleIdentifier</key>
  <string>local.srtforge.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>SRT Forge</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>__APP_VERSION__</string>
  <key>CFBundleVersion</key>
  <string>__APP_BUILD__</string>
  <key>SRTForgeUpdateManifestURL</key>
  <string>__UPDATE_MANIFEST_URL__</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/sed -i '' \
  -e "s#__APP_VERSION__#${APP_VERSION}#g" \
  -e "s#__APP_BUILD__#${APP_BUILD}#g" \
  -e "s#__UPDATE_MANIFEST_URL__#${UPDATE_MANIFEST_URL}#g" \
  "${CONTENTS_DIR}/Info.plist"

echo
echo "App sukurta:"
echo "${APP_DIR}"
echo
echo "Paleidimas:"
echo "open \"${APP_DIR}\""
