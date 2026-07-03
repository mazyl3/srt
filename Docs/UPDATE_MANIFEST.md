# SRT Forge Update Manifest

The app uses a simple update manifest for the first OTA update flow.

Build with:

```bash
SRTFORGE_UPDATE_MANIFEST_URL="https://example.com/srt-forge/version.json" \
SRTFORGE_APP_VERSION="0.1.0" \
SRTFORGE_APP_BUILD="1" \
bash Scripts/build_app.sh
```

Manifest format:

```json
{
  "version": "0.1.1",
  "build": "2",
  "downloadURL": "https://example.com/downloads/SRT-Forge-0.1.1.dmg",
  "releaseNotes": "Improved video subtitle export and setup flow.",
  "minimumSystemVersion": "13.0"
}
```

Phase 1 behavior:

- The app downloads this JSON file.
- If `version` is newer than the installed app version, it shows an update.
- The user clicks Download and the app opens the DMG/download URL.
- The app does not replace itself while running.

This keeps updates simple and avoids fragile self-update behavior before signing/notarization is solved.
