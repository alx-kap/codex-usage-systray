# ChatGPT Codex Usage Tray v1.0.8

## Highlights

- Refactored the app into focused `App`, `Models`, `Services`, `Views`, and `Support` source groups for a more maintainable native macOS structure
- Moved Settings onto a native SwiftUI `Settings` scene with `SettingsLink` on supported macOS versions and a legacy fallback for Ventura compatibility
- Tightened the Settings window into a compact utility layout and restored glass/material styling across the window body and top chrome

## UX Improvements

- Split the menu bar popup into smaller dedicated components for quota rows, status content, and actions
- Reworked the Settings screen into lighter glass cards with a cleaner bottom action area for reset behavior
- Preserved automatic preference for installed Codex auth while keeping manual fallback session storage available in Keychain

## Stability

- Extracted usage fetching, parsing, scheduling, and notifications into smaller service components with clearer ownership
- Removed duplicate notification timing paths so alerts are managed by a single controller
- Updated tests around scheduler behavior, settings persistence, and credential flow after the refactor

## Notes

- Release artifact: `ChatGPT-Codex-Usage-Tray-v1.0.8-macOS.zip`
- This build was verified with a successful macOS Release build in Xcode's command-line toolchain
