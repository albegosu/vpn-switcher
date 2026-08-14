#!/usr/bin/env bash
#
# VPN Switcher installer — builds from source and installs the app.
#
#   ./install.sh
#
# A local build is ad-hoc signed and carries no quarantine flag, so it runs
# without Gatekeeper prompts (unlike a downloaded binary). This script checks
# prerequisites, builds, installs to /Applications and launches the app.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { printf "${GREEN}==>${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}==>${NC} %s\n" "$1"; }
die()  { printf "${RED}error:${NC} %s\n" "$1" >&2; exit 1; }

cd "$(dirname "$0")"
APP_NAME="VPNSwitcher.app"

# 1. macOS only.
[ "$(uname)" = "Darwin" ] || die "VPN Switcher is macOS only."

# 2. Xcode (xcodebuild needs the full Xcode, not just the Command Line Tools).
xcodebuild -version >/dev/null 2>&1 || die \
  "Xcode is required. Install it from the App Store, then run: sudo xcodebuild -license accept"

# 3. XcodeGen (generates the .xcodeproj from project.yml).
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    info "Installing XcodeGen via Homebrew..."
    brew install xcodegen
  else
    die "XcodeGen is required. Install Homebrew (https://brew.sh), then run: brew install xcodegen"
  fi
fi

# 4. Build.
info "Building VPN Switcher (this may take a minute)..."
make build

APP_SRC="build/DerivedData/Build/Products/Debug/${APP_NAME}"
[ -d "$APP_SRC" ] || die "Build did not produce ${APP_NAME}."

# 5. Install. Prefer /Applications, fall back to ~/Applications if not writable.
DEST="/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
  warn "/Applications is not writable; installing to $DEST instead."
fi

info "Installing to $DEST/${APP_NAME}..."
pkill -x VPNSwitcher 2>/dev/null || true
rm -rf "${DEST:?}/${APP_NAME}"
cp -R "$APP_SRC" "$DEST/${APP_NAME}"

# 6. Launch.
open "$DEST/${APP_NAME}"

info "VPN Switcher is installed and running."
printf '\n'
printf 'Look for the shield icon in your menu bar (top-right).\n\n'
printf 'Next: click it and choose "Create example config" to write\n'
printf '  ~/.config/vpn-switcher/profiles.yaml\n'
printf 'then edit it with your own VPNs. See PROVIDERS.md for recipes.\n'
