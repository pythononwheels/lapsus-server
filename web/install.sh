#!/bin/sh
# LAPSUS installer.
#
#   curl -fsSL https://lapsus.pyrates.io/install.sh | bash
#
# Downloads the right build for your machine *via curl* — which, unlike a browser
# download, does NOT set the macOS quarantine flag — so the app launches without
# any Gatekeeper "unidentified developer" prompt. No xattr, no System Settings.
#
# Prefer to read before running? Grab it first:
#   curl -fsSL https://lapsus.pyrates.io/install.sh -o install.sh && less install.sh && sh install.sh
set -eu

REPO="pythononwheels/lapsus-app"
BASE="https://github.com/$REPO/releases/latest/download"

os="$(uname -s)"
arch="$(uname -m)"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

case "$os" in
  Darwin)
    [ "$arch" = "arm64" ] || die "Only Apple Silicon (arm64) is built right now. Intel is on the way."
    asset="LAPSUS-macos-arm64.zip"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    say "Downloading LAPSUS for macOS (Apple Silicon)…"
    curl -fsSL "$BASE/$asset" -o "$tmp/lapsus.zip"
    ditto -x -k "$tmp/lapsus.zip" "$tmp/out"
    app="$(find "$tmp/out" -maxdepth 3 -name 'LAPSUS.app' -type d | head -1)"
    [ -n "$app" ] || die "LAPSUS.app not found in the downloaded archive."
    # Prefer the system Applications folder (admin users can write it without sudo);
    # fall back to the per-user one otherwise.
    dest="/Applications"
    [ -w "$dest" ] || dest="$HOME/Applications"
    mkdir -p "$dest"
    rm -rf "$dest/LAPSUS.app"
    cp -R "$app" "$dest/LAPSUS.app"
    say "Installed → $dest/LAPSUS.app"
    open "$dest/LAPSUS.app" && say "Launching LAPSUS — it opens its UI in your browser."
    ;;
  Linux)
    case "$arch" in
      x86_64|amd64) asset="LAPSUS-linux-x64.tar.gz" ;;
      *) die "Only linux x86_64 is built right now (got $arch)." ;;
    esac
    dest="$HOME/.lapsus"
    mkdir -p "$dest"
    say "Downloading LAPSUS for Linux (x64)…"
    curl -fsSL "$BASE/$asset" | tar xz -C "$dest"
    say "Installed → $dest/lapsus"
    say "Start it with:"
    printf '    %s/lapsus/run-lapsus.sh\n' "$dest"
    ;;
  *)
    die "Unsupported OS: $os"
    ;;
esac
