# ChatGPT Codex Usage Tray v1.0.6

## Highlights

- Reworked Settings into a borderless, key-capable floating window so it behaves like a true glass surface
- Removed titlebar/titlebar-safe-area behavior from Settings, eliminating extra top inset and traffic-light controls
- Matched Settings translucency to the menu popup by mirroring the active menu glass profile at open time
- Ensured opening Settings hides menu presentation windows first to avoid stacked dark overlays
- Kept a single Settings window instance and refocused it on repeated open actions

## Native Layout Refresh

- Tightened spacing cadence in Settings for a more macOS-native rhythm
- Reduced heavy card-on-card treatment with lighter grouped section chrome
- Refined header/close control placement while preserving existing settings behavior and state logic

## Verification

- `xcodebuild test` passes on macOS (`19/19` tests)
