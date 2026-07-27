# AerialWall

Turn Apple's aerial screen savers into live desktop wallpapers on macOS.

macOS already downloads gorgeous 4K aerial videos (the ones you see on the lock
screen and in System Settings → Wallpaper). AerialWall finds the ones you've
downloaded and plays them as your actual desktop wallpaper — behind your icons,
on every Space and display.

- **Native and light** — AVFoundation with hardware video decode, no browser engine
- **Nice picker** — a menu-bar gallery of your downloaded aerials with thumbnails
- **Battery-aware** — pauses on battery, resumes on the power cable (toggleable)
- **Auto-updates** — via Sparkle
- **No bundled videos** — it only plays the aerials Apple already put on your Mac

## Install

### Homebrew

```bash
brew tap leifsternyc/tap
brew install --cask aerialwall
```

### Direct download

1. Download `AerialWall.zip` from the [latest release](https://github.com/LeifsterNYC/AerialWall/releases/latest) and unzip.
2. Move `AerialWall.app` to `/Applications`.
3. First launch (the app isn't notarized): right-click the app → **Open**. If
   macOS still blocks it, go to **System Settings → Privacy & Security** and
   click **Open Anyway**, or clear the quarantine flag:

   ```bash
   xattr -d com.apple.quarantine /Applications/AerialWall.app
   ```

## Use

1. Download at least one aerial first: **System Settings → Wallpaper**, pick an
   aerial (Landscape / Cityscape / Underwater / Earth) and wait for it to finish
   downloading.
2. Click the ⛰ icon in the menu bar and pick a wallpaper from the gallery.
3. Optional: toggle **Only play on power cable** (on by default) and
   **Launch at login**.

## Requirements

macOS 14 Sonoma or later (Apple Silicon and Intel).

## Build from source

```bash
git clone https://github.com/LeifsterNYC/AerialWall
cd AerialWall
SPARKLE_PUBLIC_KEY=dev ./scripts/make-app.sh   # builds dist/AerialWall.app
```

## How it works

Aerial videos live in `~/Library/Application Support/com.apple.wallpaper/aerials/`
(macOS Tahoe) or `/Library/Application Support/com.apple.idleassetsd/Customer/`
(earlier versions), named by UUID. AerialWall maps the UUIDs to readable names
using Apple's own `entries.json` manifest, then plays your pick with
`AVPlayerLooper` in a borderless window at desktop level. An IOKit power-source
observer pauses playback when you unplug.
