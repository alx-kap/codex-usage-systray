# ChatGPT Codex Usage Tray

A lightweight macOS menu bar app that shows your ChatGPT Codex usage at a glance without keeping the dashboard open in a browser.

Adapted from [adntgv/claude-usage-systray](https://github.com/adntgv/claude-usage-systray), with the macOS menu bar shell reworked for ChatGPT Codex usage.

![ChatGPT Codex Usage Tray](codex-usage-systray/Resources/Assets.xcassets/Image.imageset/Image.png)

## What it does

- Prefers the installed Codex desktop auth on your Mac when available
- Polls `https://chatgpt.com/backend-api/wham/usage` for installed-Codex auth
- Falls back to `https://chatgpt.com/codex/settings/usage` with a pasted browser cookie only when needed
- Stores the optional fallback browser cookie string securely in macOS Keychain
- Shows normalized `5 Hour` and `Weekly` remaining quota in the menu bar
- Presents usage, additional limits, and actions in a custom floating macOS panel under the menu bar icon
- Opens the full ChatGPT Codex dashboard on demand
- Sends threshold notifications based on the primary quota metric

## Requirements

- macOS 13+
- Either:
  - the Codex desktop app installed and signed in on this Mac
  - or a browser session that can open the ChatGPT Codex usage page successfully

## Running the app

### From Xcode

1. Open `codex-usage-systray/CodexUsageSystray.xcodeproj`
2. Select the `CodexUsageSystray` scheme
3. Choose `My Mac` as the run destination
4. Press `Run`
5. Look for the app in the macOS menu bar instead of a normal app window

### From the command line

```bash
xcodebuild -project codex-usage-systray/CodexUsageSystray.xcodeproj \
  -scheme CodexUsageSystray \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-usage-derived \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM='' \
  build

open /tmp/codex-usage-derived/Build/Products/Debug/CodexUsageSystray.app
```

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
xcodebuild -project codex-usage-systray/CodexUsageSystray.xcodeproj \
  -scheme CodexUsageSystray \
  -configuration Release \
  -derivedDataPath /tmp/codex-release-build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM='' \
  build
```

The release app will be available at:

```bash
/tmp/codex-release-build/Build/Products/Release/CodexUsageSystray.app
```

## Package a release zip

```bash
ditto -c -k --sequesterRsrc --keepParent \
  /tmp/codex-release-build/Build/Products/Release/CodexUsageSystray.app \
  CodexUsageSystray-macOS.zip
```

## Run tests

```bash
xcodebuild test -project codex-usage-systray/CodexUsageSystray.xcodeproj \
  -scheme CodexUsageSystray \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-usage-derived \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM=''
```

## GitHub releases

The easiest way to distribute the app is:

1. Build the Release app
2. Zip `CodexUsageSystray.app`
3. Upload the zip to a GitHub Release

Unsigned builds will usually trigger a macOS warning on first launch. For wider distribution, sign and notarize the app with an Apple Developer account.

## Current UI changes

- Compact menu bar text now shows `5 Hour` first and `Weekly` second
- The dropdown uses a custom floating panel instead of `NSPopover`, which avoids the menu bar clipping issues
- The dropdown shows `CODEX LIMITS` and `ADDITIONAL LIMITS` sections
- The app displays remaining quota to match the Codex UI rather than consumed quota
- The menu uses installed Codex auth first, with manual browser-cookie fallback only when needed

## Development notes

- The app is a menu bar utility, so launching it will not open a standard app window
- Local Xcode workspace state in `xcuserdata` is intentionally not part of normal source changes
- The usage endpoint used for installed Codex auth is not a documented public API and may change

## Credits

- Original project: [adntgv/claude-usage-systray](https://github.com/adntgv/claude-usage-systray)
- This repository adapts that menu bar app for ChatGPT Codex usage on macOS

## License

MIT
