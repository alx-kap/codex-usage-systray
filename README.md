# ChatGPT Codex Usage Tray

A lightweight macOS menu bar app that shows your ChatGPT Codex usage at a glance without keeping the dashboard open in a browser.

Adapted from [adntgv/claude-usage-systray](https://github.com/adntgv/claude-usage-systray), with the macOS menu bar shell reworked for ChatGPT Codex usage.

![ChatGPT Codex Usage Tray](codex-usage-systray/Resources/Assets.xcassets/Image.imageset/Image.png)

## What it does

- Prefers the installed Codex desktop auth on your Mac when available
- Polls `https://chatgpt.com/backend-api/wham/usage` for installed-Codex auth
- Falls back to `https://chatgpt.com/codex/settings/usage` with a pasted browser cookie only when needed
- Stores the optional fallback browser cookie string securely in macOS Keychain
- Shows normalized primary and secondary quota metrics in the menu bar
- Opens the full ChatGPT Codex dashboard on demand
- Sends threshold notifications based on the primary quota metric

## Requirements

- macOS 13+
- Either:
  - the Codex desktop app installed and signed in on this Mac
  - or a browser session that can open the ChatGPT Codex usage page successfully

## Authentication

This app now prefers the local Codex desktop sign-in automatically.

### Recommended: installed Codex auth

1. Install the Codex desktop app and sign in there.
2. Launch this menu bar app.
3. It will automatically read the local Codex auth and use it for usage refreshes.

### Fallback: manual browser session

1. Open `https://chatgpt.com/codex/settings/usage` in your browser.
2. Open Developer Tools and inspect the request headers for that page.
3. Copy the full `Cookie` header value.
4. Paste it into the app's Settings screen.

The app validates the pasted fallback value immediately before storing it in your Keychain.

## Notes on reliability

- The installed-Codex path uses `https://chatgpt.com/backend-api/wham/usage`, which appears to be what the Codex desktop app itself calls. It is not a public API and may change without notice.
- The manual fallback path still depends on the web dashboard and Cloudflare. In practice, the cookie string may need to include Cloudflare cookies such as `cf_clearance`.
- The app understands both the backend JSON payload and the dashboard HTML/embedded JSON fallback.

## Build from source

```bash
cd codex-usage-systray
xcodebuild -project CodexUsageSystray.xcodeproj \
  -scheme CodexUsageSystray \
  -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/CodexUsageSystray-*/Build/Products/Release/CodexUsageSystray.app
```

## Run tests

```bash
xcodebuild test -project codex-usage-systray/CodexUsageSystray.xcodeproj \
  -scheme CodexUsageSystray \
  -destination 'platform=macOS'
```

## License

MIT

## Credits

- Original project: [adntgv/claude-usage-systray](https://github.com/adntgv/claude-usage-systray)
- This repository adapts that menu bar app for ChatGPT Codex usage on macOS
