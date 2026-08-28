#!/bin/sh
set -e

gvim=$(command -v gvim || true)
[ -n "$gvim" ] || { echo "gvim not found" >&2; exit 1; }

probe=$(mktemp)
script=$(mktemp)
printf 'set lines=999 columns=999\ncall writefile([&lines,&columns],"%s")\nqa!\n' "$probe" > "$script"
"$gvim" -f -S "$script"
maxl=$(sed -n 1p "$probe")
maxc=$(sed -n 2p "$probe")
rm -f "$probe" "$script"
[ -n "$maxl" ] && [ -n "$maxc" ] || { echo "gvim probe produced no output" >&2; exit 1; }

dims=
if command -v xrandr >/dev/null 2>&1; then
    dims=$(xrandr --current | sed -n 's/.*current \([0-9]*\) x \([0-9]*\).*/\1 \2/p' | head -1)
fi
if [ -z "$dims" ] && command -v xdpyinfo >/dev/null 2>&1; then
    dims=$(xdpyinfo | sed -n 's/^ *dimensions: *\([0-9]*\)x\([0-9]*\).*/\1 \2/p' | head -1)
fi
[ -n "$dims" ] || { echo "could not determine screen size" >&2; exit 1; }
sw=${dims% *}
sht=${dims#* }

dir="$HOME/.vim"
mkdir -p "$dir"
printf 'set lines=%s\nset columns=%s\nwinpos %s %s\n' \
    "$((maxl / 3))" "$((maxc / 3))" "$((sw / 3))" "$((sht / 3))" > "$dir/geometry.vim"
echo "screen ${sw}x${sht}, max cells ${maxc}x${maxl}"
echo "wrote $dir/geometry.vim : $((maxc / 3))x$((maxl / 3)) cells at $((sw / 3)),$((sht / 3))"
