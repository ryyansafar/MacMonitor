#!/bin/bash
# MacMonitor — post-install setup
# Run this once after dragging MacMonitor.app to /Applications

APP="/Applications/MacMonitor.app"
SUDOERS_FILE="/etc/sudoers.d/macmonitor"
MACTOP="/opt/homebrew/bin/mactop"
BREW="/opt/homebrew/bin/brew"

echo ""
echo "MacMonitor Setup"
echo "────────────────"

# ── 1. Verify app is installed ────────────────────────────────────────────────
if [ ! -d "$APP" ]; then
  echo ""
  echo "MacMonitor.app not found in /Applications."
  echo "Please drag MacMonitor.app to your Applications folder first, then run this script again."
  echo ""
  read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi

# ── 2. Remove quarantine flag ─────────────────────────────────────────────────
echo ""
echo "→ Removing macOS quarantine flag..."
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "  Done."

# ── 3. Install mactop if missing ──────────────────────────────────────────────
if [ ! -f "$MACTOP" ]; then
  echo ""
  echo "→ Installing mactop (needed for GPU, temperature, and power data)..."
  if [ -f "$BREW" ]; then
    "$BREW" install mactop
  else
    echo "  Homebrew not found at $BREW."
    echo "  Install Homebrew from https://brew.sh, then re-run this script."
    read -n 1 -s -r -p "Press any key to close..."
    exit 1
  fi
else
  echo "→ mactop already installed."
fi

# ── 4. Grant passwordless sudo for mactop ────────────────────────────────────
echo ""
echo "→ Granting MacMonitor permission to read GPU, temperature, and power data."
echo "  You may be prompted for your macOS password (one time only)."
echo ""
echo "%admin ALL=(ALL) NOPASSWD: $MACTOP" | sudo tee "$SUDOERS_FILE" > /dev/null
sudo chmod 440 "$SUDOERS_FILE"
echo "  Permission granted."

# ── 5. Launch app ─────────────────────────────────────────────────────────────
echo ""
echo "✓ Setup complete. Launching MacMonitor..."
echo ""
open "$APP"
