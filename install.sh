#!/usr/bin/env bash
# Builds Strategy Lab and installs it for this user, so it starts from the application menu:
#   bundle        → ~/.local/share/strategy-lab/
#   desktop entry → ~/.local/share/applications/strategy-lab.desktop
#   icon          → ~/.local/share/icons/hicolor/scalable/apps/strategy-lab.svg
# Nothing is installed system-wide. Re-run after pulling changes; ./install.sh --uninstall removes it.
set -euo pipefail
cd "$(dirname "$0")"

data="${XDG_DATA_HOME:-$HOME/.local/share}"
dest="$data/strategy-lab"
desktop="$data/applications/strategy-lab.desktop"
icon="$data/icons/hicolor/scalable/apps/strategy-lab.svg"

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$dest" "$desktop" "$icon"
  update-desktop-database "$data/applications" 2>/dev/null || true
  echo "Strategy Lab removed."
  exit 0
fi

flutter build linux --release

# Replace the previous install as a whole, so no stale libraries are left behind.
rm -rf "$dest.new"
mkdir -p "$dest.new"
cp -r build/linux/x64/release/bundle/. "$dest.new/"
rm -rf "$dest"
mv "$dest.new" "$dest"

install -Dm644 linux/packaging/strategy-lab.svg "$icon"
mkdir -p "$(dirname "$desktop")"
sed "s|@BIN@|$dest/strategy_lab|" linux/packaging/strategy-lab.desktop > "$desktop"
chmod 644 "$desktop"
update-desktop-database "$data/applications" 2>/dev/null || true
gtk-update-icon-cache -q "$data/icons/hicolor" 2>/dev/null || true

echo "Installed Strategy Lab to $dest"
echo "Start it from the application menu (Strategy Lab), or: gtk-launch strategy-lab"
