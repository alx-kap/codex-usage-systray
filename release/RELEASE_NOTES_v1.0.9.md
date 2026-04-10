# ChatGPT Codex Usage Tray v1.0.9

## Highlights

- Fixed the native SwiftUI Settings scene so it opens on the desktop you are actively viewing
- Restored reliable reactivation for the existing Settings window when you click Settings again from the tray
- Kept the app on the system-supported `SettingsLink` path instead of falling back to a custom Settings presenter

## UX Improvements

- Removed the flicker caused by retry-based Settings refocusing and replaced it with a direct frontmost reveal for the existing Settings window
- Preserved the native Settings scene behavior while making repeated tray opens feel more like a polished macOS utility

## Notes

- Release artifact: `ChatGPT-Codex-Usage-Tray-v1.0.9-macOS.zip`
- This build was verified with a successful macOS Release build in Xcode's command-line toolchain
