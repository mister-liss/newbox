#!/bin/sh
set -e

SOURCE="${SOURCE:-https://newbox.stevenmliss.com}"
FONT_RELEASE="https://github.com/intel/intel-one-mono/releases/download/V1.4.0/ttf.zip"
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")

payload() {
    if [ -n "$HERE" ] && [ -f "$HERE/$1" ]; then
        cp "$HERE/$1" "$2"
    else
        curl -fsSL "$SOURCE/$1" -o "$2"
    fi
}

if command -v gvim >/dev/null 2>&1; then
    echo "already installed: gvim"
elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y vim-gtk3
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y vim-X11
elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm gvim
elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y gvim
else
    echo "no known package manager - install gvim yourself" >&2
    exit 1
fi

command -v unzip >/dev/null 2>&1 || { echo "unzip is required" >&2; exit 1; }
tmp=$(mktemp -d)
curl -fsSL "$FONT_RELEASE" -o "$tmp/ttf.zip"
unzip -q -j "$tmp/ttf.zip" 'ttf/*.ttf' -d "$tmp/ttf"
dst="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
mkdir -p "$dst"
cp "$tmp/ttf"/*.ttf "$dst"/
fc-cache -f "$dst" >/dev/null 2>&1 || true
echo "installed $(ls "$tmp/ttf" | wc -l) font files to $dst"
rm -rf "$tmp"

[ -f "$HOME/.vimrc" ] && cp "$HOME/.vimrc" "$HOME/.vimrc.bak"
payload '_vimrc' "$HOME/.vimrc"
echo "wrote $HOME/.vimrc"

geom=$(mktemp)
payload 'set-geometry.sh' "$geom"
sh "$geom"
rm -f "$geom"

echo
echo "Done. Open gvim."
