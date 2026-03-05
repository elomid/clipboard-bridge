#!/bin/bash
set -euo pipefail

# clipboard-bridge installer
# Usage:
#   curl -fsSL https://github.com/elomid/clipboard-bridge/releases/latest/download/install.sh | bash
#   curl -fsSL ... | bash -s -- --uninstall

REPO="elomid/clipboard-bridge"
LABEL="com.elomid.clipboard-bridge"
BINDIR="$HOME/.local/bin"
LOGDIR="$HOME/.local/log"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
BIN_PATH="$BINDIR/clipboard-bridge"

RED='\033[0;31m'
GREEN='\033[0;32m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${BOLD}%s${RESET}\n" "$1"; }
ok()    { printf "${GREEN}✓${RESET} %s\n" "$1"; }
dim()   { printf "${DIM}%s${RESET}\n" "$1"; }
err()   { printf "${RED}error:${RESET} %s\n" "$1" >&2; exit 1; }

uninstall() {
    info "Uninstalling clipboard-bridge..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$BIN_PATH"
    rm -f "$PLIST_PATH"
    ok "Removed binary and LaunchAgent"
    dim "Log kept at $LOGDIR/clipboard-bridge.log (delete manually if desired)"
}

if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall
    exit 0
fi

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    err "clipboard-bridge only works on macOS"
fi

info "Installing clipboard-bridge..."
echo ""

# Detect architecture
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
    err "Unsupported architecture: $ARCH"
fi

# Download binary
mkdir -p "$BINDIR" "$LOGDIR" "$PLIST_DIR"

DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/clipboard-bridge"
dim "Downloading from $DOWNLOAD_URL"
if ! curl -fsSL -o "$BIN_PATH" "$DOWNLOAD_URL"; then
    err "Download failed. Check https://github.com/$REPO/releases for available releases."
fi
chmod +x "$BIN_PATH"
ok "Binary installed to $BIN_PATH"

# Remove quarantine attribute (binary is notarized but quarantine can still prompt)
xattr -d com.apple.quarantine "$BIN_PATH" 2>/dev/null || true

# Stop existing instance if running
launchctl unload "$PLIST_PATH" 2>/dev/null || true

# Install LaunchAgent
cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>$LOGDIR/clipboard-bridge.log</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLIST
ok "LaunchAgent installed"

# Start
launchctl load "$PLIST_PATH"
ok "Started clipboard-bridge"

echo ""
info "Done! clipboard-bridge is running and will start automatically on login."
echo ""
dim "Copy an image from Figma/Chrome and paste into Claude Code with Ctrl+V."
echo ""
dim "Commands:"
dim "  Status:    launchctl list | grep clipboard-bridge"
dim "  Log:       tail -f ~/.local/log/clipboard-bridge.log"
dim "  Stop:      launchctl unload ~/Library/LaunchAgents/$LABEL.plist"
dim "  Start:     launchctl load ~/Library/LaunchAgents/$LABEL.plist"
dim "  Uninstall: curl -fsSL https://github.com/$REPO/releases/latest/download/install.sh | bash -s -- --uninstall"
