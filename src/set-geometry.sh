#!/bin/sh
set -e

BAND_W_IN=8.3
BAND_H_IN=5.1

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

command -v xrandr >/dev/null 2>&1 || { echo "xrandr is required" >&2; exit 1; }
line=$(xrandr --current | grep ' connected primary ' | head -1)
[ -n "$line" ] || line=$(xrandr --current | grep ' connected ' | head -1)
[ -n "$line" ] || { echo "no connected display" >&2; exit 1; }

sw=$(echo "$line"  | sed -n 's/.* \([0-9]\{1,\}\)x\([0-9]\{1,\}\)+[0-9]\{1,\}.*/\1/p')
shh=$(echo "$line" | sed -n 's/.* \([0-9]\{1,\}\)x\([0-9]\{1,\}\)+[0-9]\{1,\}.*/\2/p')
mmw=$(echo "$line" | sed -n 's/.* \([0-9]\{1,\}\)mm x \([0-9]\{1,\}\)mm.*/\1/p')
mmh=$(echo "$line" | sed -n 's/.* \([0-9]\{1,\}\)mm x \([0-9]\{1,\}\)mm.*/\2/p')
[ -n "$sw" ] && [ -n "$shh" ] || { echo "could not read resolution from xrandr" >&2; exit 1; }

vals=$(mktemp)
awk -v sw="$sw" -v sh="$shh" -v mmw="${mmw:-0}" -v mmh="${mmh:-0}" \
    -v maxc="$maxc" -v maxl="$maxl" -v bw="$BAND_W_IN" -v bh="$BAND_H_IN" 'BEGIN {
    if (mmw > 0 && mmh > 0) {
        ppix = sw / (mmw / 25.4); ppiy = sh / (mmh / 25.4)
        tw = bw * ppix; th = bh * ppiy
        how = sprintf("EDID %dx%dmm, %dx%d ppi", mmw, mmh, ppix, ppiy)
    } else {
        tw = sw * 0.30; th = sh / 3
        how = "no physical size - fell back to 30% of screen"
    }
    cellw = sw / maxc; cellh = sh / maxl
    cols = int(tw / cellw); if (cols < 20) cols = 20
    lines = int(th / cellh); if (lines < 5) lines = 5
    printf "cols=%d\nlines=%d\nx=%d\ny=%d\ntw=%d\nth=%d\nhow=\"%s\"\n",
        cols, lines, int((sw - cols * cellw) / 2), int((sh - lines * cellh) / 2), tw, th, how
}' > "$vals"
. "$vals"
rm -f "$vals"

dir="$HOME/.vim"
mkdir -p "$dir"
printf 'set lines=%s\nset columns=%s\nwinpos %s %s\n' "$lines" "$cols" "$x" "$y" > "$dir/geometry.vim"

echo "screen ${sw}x${shh}, max cells ${maxc}x${maxl}, $how"
echo "target ${BAND_W_IN}x${BAND_H_IN} in = ${tw}x${th} px"
echo "wrote $dir/geometry.vim : ${cols}x${lines} cells at ${x},${y}"
