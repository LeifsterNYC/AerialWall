# AerialWall

Turn Apple's aerial screen savers into live desktop wallpapers on macOS.

macOS already downloads gorgeous 4K aerial videos (the ones you see on the lock
screen and in System Settings → Wallpaper). AerialWall finds the ones you've
downloaded and plays them as your actual desktop wallpaper — behind your icons,
on every Space and display.

- **Native and light** — AVFoundation with hardware video decode, no browser engine; pauses under fullscreen apps and on the lock screen
- **Browse Apple's whole catalog** — all ~156 aerials with previews, searchable and filterable by category; click to download, hover-✕ to delete
- **Live previews** — hover any downloaded tile to see it in motion
- **Shuffle** — rotate wallpapers every 15 minutes/hour/day, or jump with ⌃⌥⌘N
- **Day/night aware** — optionally match light/dark mode with day/night variants
- **Per-display** — a different wallpaper on each monitor
- **Your own videos** — import any `.mov`/`.mp4` as a live wallpaper
- **Battery-aware** — pauses on battery, resumes on the power cable (toggleable)
- **Auto-updates** — via Sparkle, silent
- **No bundled videos** — aerials download straight from Apple's own CDN

## Install

### Homebrew

```bash
brew tap leifsternyc/tap
brew trust leifsternyc/tap
brew install --cask aerialwall
```

### Direct download

1. Download `AerialWall.zip` from the [latest release](https://github.com/LeifsterNYC/AerialWall/releases/latest) and unzip.
2. Move `AerialWall.app` to `/Applications`.

### First launch (either method)

The app isn't notarized, so macOS may block the first open:

1. Open the app; when macOS says it can't verify it, click **Done** (not Move to Trash).
2. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.
3. Click **Open Anyway** again on the confirmation popup.

Or skip all of that from Terminal:

```bash
xattr -d com.apple.quarantine /Applications/AerialWall.app
```

## Use

> **AerialWall is a menu bar app** — nothing opens when you launch it. Look for
> the ⛰ mountain icon near the top-right of your screen (on a MacBook it can
> hide behind the notch if your menu bar is crowded).

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
