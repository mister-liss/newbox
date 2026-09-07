#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$BandWidthInches  = 8.3
$BandHeightInches = 5.1

# The newest gvim, not the first on PATH.
#
# Two installs is the normal state here: winget puts 9.2 under LOCALAPPDATA and
# an older MSI left 9.0 in Program Files (x86), and PATH prefers the stale one.
# Searching only Program Files finds the old one and never the new. The visible
# symptom was diff options the 9.0 build rejects; the quiet one is every file
# association pointing at an editor two years older than the one installed.
$gvim = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Vim\gvim.exe')
    'C:\Program Files\Vim\vim*\gvim.exe'
    'C:\Program Files (x86)\Vim\vim*\gvim.exe'
) | ForEach-Object { Get-ChildItem $_ -EA SilentlyContinue } |
    Sort-Object { try { [version]$_.VersionInfo.FileVersion } catch { [version]'0.0' } } -Descending |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $gvim) { $gvim = (Get-Command gvim -EA SilentlyContinue).Source }
if (-not $gvim) { throw 'gvim not found' }

$probe  = [System.IO.Path]::GetTempFileName()
$script = [System.IO.Path]::GetTempFileName() + '.vim'
@(
    'set lines=999 columns=999'
    "call writefile([&lines,&columns],'$($probe.Replace('\','/'))')"
    'qa!'
) | Set-Content -Path $script -Encoding ASCII

Start-Process -FilePath $gvim -ArgumentList '-f','-S',$script -Wait
$max = @(Get-Content $probe)
Remove-Item $probe, $script -Force
if ($max.Count -lt 2) { throw 'gvim probe produced no output' }
$maxLines = [int]$max[0]
$maxCols  = [int]$max[1]

Add-Type -Name Dpi -Namespace Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
[DllImport("gdi32.dll")]  public static extern int GetDeviceCaps(IntPtr h, int i);
'@
$dc    = [Win32.Dpi]::GetDC([IntPtr]::Zero)
$physW = [Win32.Dpi]::GetDeviceCaps($dc, 118)
$physH = [Win32.Dpi]::GetDeviceCaps($dc, 117)
$scale = $physW / [Win32.Dpi]::GetDeviceCaps($dc, 8)

$v = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$waX = [math]::Round($v.X * $scale);     $waY = [math]::Round($v.Y * $scale)
$waW = [math]::Round($v.Width * $scale); $waH = [math]::Round($v.Height * $scale)

$edid = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -EA SilentlyContinue |
        Where-Object { $_.MaxHorizontalImageSize -gt 0 } | Select-Object -First 1
if ($edid) {
    $ppiX = $physW / ($edid.MaxHorizontalImageSize / 2.54)
    $ppiY = $physH / ($edid.MaxVerticalImageSize / 2.54)
    $targetW = $BandWidthInches * $ppiX
    $targetH = $BandHeightInches * $ppiY
    $how = "EDID $($edid.MaxHorizontalImageSize)x$($edid.MaxVerticalImageSize)cm, $([math]::Round($ppiX))x$([math]::Round($ppiY)) ppi"
} else {
    $targetW = $waW * 0.30
    $targetH = $waH / 3
    $how = 'no EDID - fell back to 30% of screen'
}

$cellW = $waW / $maxCols
$cellH = $waH / $maxLines
$cols  = [math]::Max(20, [math]::Floor($targetW / $cellW))
$lines = [math]::Max(5,  [math]::Floor($targetH / $cellH))
$x = $waX + [math]::Floor(($waW - $cols * $cellW) / 2)
$y = $waY + [math]::Floor(($waH - $lines * $cellH) / 2)

# The same band, in multiples. One cell is a window you read; a diff wants two
# side by side and there is no width to spare inside one, which is the whole
# reason every diff tool tried so far failed the same way. Emitted rather than
# computed in vim, because the cell size comes from the display's physical
# dimensions and vim cannot see those.
$bands = [ordered]@{}
foreach ($w in 1, 2, 3) {
    foreach ($h in 1, 2) {
        $bc = [math]::Max(20, [math]::Floor($w * $targetW / $cellW))
        $bl = [math]::Max(5,  [math]::Floor($h * $targetH / $cellH))
        if ($bc -gt $maxCols)  { $bc = $maxCols }
        if ($bl -gt $maxLines) { $bl = $maxLines }
        $bx = $waX + [math]::Floor(($waW - $bc * $cellW) / 2)
        $by = $waY + [math]::Floor(($waH - $bl * $cellH) / 2)
        $bands["${w}x${h}"] = "'${w}x${h}': {'cols': $bc, 'lines': $bl, 'x': $bx, 'y': $by}"
    }
}

$dir = Join-Path $env:USERPROFILE 'vimfiles'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir 'geometry.vim'
@(
    "let g:gluc_bands = {" + ($bands.Values -join ', ') + "}"
    ""
    "function! GlucBand(size) abort"
    "    let b = get(g:gluc_bands, a:size, g:gluc_bands['1x1'])"
    "    execute 'set lines=' . b.lines"
    "    execute 'set columns=' . b.cols"
    "    execute 'winpos ' . b.x . ' ' . b.y"
    "endfunction"
    ""
    "call GlucBand('1x1')"
) | Set-Content -Path $out -Encoding ASCII

Write-Output "work area ${waW}x${waH} physical, max cells ${maxCols}x${maxLines}, $how"
Write-Output "target ${BandWidthInches}x${BandHeightInches} in = $([math]::Round($targetW))x$([math]::Round($targetH)) px"
Write-Output "wrote $out : ${cols}x${lines} cells at $x,$y"
