# clipboard-bridge

A tiny macOS daemon that fixes clipboard image pasting in [Claude Code](https://claude.ai/code).

## The problem

Copying an image from Chromium/Electron apps (Figma, Chrome, VS Code, Slack, etc.) and pasting into Claude Code shows **"No image found in clipboard"** — even though the image is there.

This happens because Chromium puts images on the clipboard as `public.png`, but Claude Code checks for `«class PNGf»` — a legacy AppleScript pasteboard type. Native macOS apps include both, Chromium doesn't.

## How it works

A background daemon (~7.5MB, 0% CPU) watches the clipboard. When it sees an image with `public.png` but no `«class PNGf»`, it adds the legacy type — preserving everything else. Transparent, instant, no manual steps.

## Install

Signed and notarized universal binary (Apple Silicon + Intel). No Xcode required.

```bash
curl -fsSL https://github.com/elomid/clipboard-bridge/releases/latest/download/install.sh | bash
```

Starts automatically on login.

## Uninstall

```bash
curl -fsSL https://github.com/elomid/clipboard-bridge/releases/latest/download/install.sh | bash -s -- --uninstall
```

## Build from source

```bash
git clone https://github.com/elomid/clipboard-bridge.git
cd clipboard-bridge
make install && make start
```

## Related

- [anthropics/claude-code#30936](https://github.com/anthropics/claude-code/issues/30936) — upstream bug report

## License

MIT
