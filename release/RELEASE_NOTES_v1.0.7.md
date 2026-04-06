# ChatGPT Codex Usage Tray v1.0.7

## Highlights

- Restored the native liquid glass appearance for the main menu bar popup
- Removed the custom menu window introspection and manual hiding logic that was interfering with `MenuBarExtra`
- Kept the refined borderless Settings window while giving it its own stable glass configuration

## Stability

- Reduced coupling between the Settings presenter and the system-managed tray popup lifecycle
- Preserved the single-window Settings behavior and existing settings layout improvements from the prior release
- Updated the app bundle version metadata so the shipped app and release notes stay aligned

## Notes

- Release artifact: `ChatGPT-Codex-Usage-Tray-v1.0.7-macOS.zip`
- This build was verified with a successful macOS Release build in Xcode's command-line toolchain
