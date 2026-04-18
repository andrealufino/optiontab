# OptionTab

A native macOS window switcher. Press `Option+Tab` to get a vertical list of all windows of the currently active app and raise the one you want.

<!-- TODO: screenshot -->

## Features

- `Option+Tab` global hotkey — no Dock interaction, no app switch
- Lists **all windows** from all Spaces, including minimized ones
- Minimized windows are marked and automatically unminimized on selection
- Liquid Glass UI — native macOS visual style
- Menu bar utility — no Dock icon
- Launch at Login support via `SMAppService`

## Requirements

macOS 26 or later.

## Installation

Build from source with Xcode 26 or later. No prebuilt release for v0.1.

1. Clone the repo
2. Open `optiontab.xcodeproj`
3. Build and run (`⌘R`)

## Usage

1. Launch OptionTab — it lives in the menu bar
2. Press `Option+Tab` while any app is frontmost
3. Cycle through windows with `Tab` / `Shift+Tab` or `↓` / `↑`
4. Release `Option` to raise the selected window
5. Press `Esc` or click outside to cancel

## Permissions

OptionTab requires **Accessibility** access to:

- Read window titles and attributes via the Accessibility API
- Raise and unminimize windows
- Listen for global key events (`Option+Tab`, modifier release)

Screen Recording is **not** required — OptionTab never captures window contents.

## Roadmap

- **v0.2** — Preferences window, configurable hotkey, theme options
- **v0.3** — Window thumbnails (optional toggle in preferences)
- **v0.4** — Prebuilt signed release

## Contributing

Open issues and pull requests are welcome. Please target the `develop` branch.

## License

MIT — see [LICENSE](LICENSE).
