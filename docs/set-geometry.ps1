#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$BandWidthInches  = 8.3
$BandHeightInches = 5.1

$gvim = (Get-Command gvim -EA SilentlyContinue).Source
if (-not $gvim) {
    $gvim = Get-ChildItem 'C:\Program Files*\Vim\vim*\gvim.exe' -EA SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
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

$dir = Join-Path $env:USERPROFILE 'vimfiles'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir 'geometry.vim'
@("set lines=$lines", "set columns=$cols", "winpos $x $y") | Set-Content -Path $out -Encoding ASCII

Write-Output "work area ${waW}x${waH} physical, max cells ${maxCols}x${maxLines}, $how"
Write-Output "target ${BandWidthInches}x${BandHeightInches} in = $([math]::Round($targetW))x$([math]::Round($targetH)) px"
Write-Output "wrote $out : ${cols}x${lines} cells at $x,$y"
