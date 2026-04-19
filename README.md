<div align="center">
  <img src="optiontab/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="OptionTab icon" />

  # OptionTab

  A native macOS window switcher. Press `Option+Tab` to see all windows of the frontmost app and raise the one you want — without ever leaving the keyboard.
</div>

## Features

- `Option+Tab` global hotkey — no Dock interaction, no app switch
- Lists all windows from all Spaces, including minimized ones
- Minimized windows are marked and automatically unminimized on selection
- Liquid Glass UI — native macOS 26 visual style
- Menu bar utility — no Dock icon
- Launch at Login via `SMAppService`

## Requirements & Installation

macOS 26 or later. No prebuilt release — build from source with Xcode 26+.

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

OptionTab requires **Accessibility** access to read window titles and attributes, raise and unminimize windows, and listen for global key events. Screen Recording is not required.

## Roadmap

- **v0.2** — Preferences window, configurable hotkey, theme options
- **v0.3** — Window thumbnails (optional)
- **v0.4** — Prebuilt signed release

## Contributing

Open issues and pull requests are welcome. Please target the `develop` branch.

## License

MIT — see [LICENSE](LICENSE).
