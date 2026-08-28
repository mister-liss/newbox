#Requires -Version 5.1
param([string]$Source = 'https://mister-liss.github.io/newbox')

$ErrorActionPreference = 'Stop'

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    Write-Host 'This must run elevated.' -ForegroundColor Red
    Write-Host 'It registers a scheduled task at highest privileges, which is what lets'
    Write-Host 'AutoHotkey send input while an elevated window has focus.'
    Write-Host ''
    Write-Host 'Start PowerShell as administrator, then run:'
    Write-Host ('  curl.exe -fsSL ' + $Source + '/newbox.ps1 | iex')
    exit 1
}
$FontRelease = 'https://github.com/intel/intel-one-mono/releases/download/V1.4.0/ttf.zip'

function Get-Payload($rel, $dest) {
    $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot $rel } else { $null }
    if ($local -and (Test-Path $local)) { Copy-Item -LiteralPath $local -Destination $dest -Force }
    else { Invoke-WebRequest -Uri "$Source/$rel" -OutFile $dest -UseBasicParsing }
}

$winget = (Get-Command winget -EA SilentlyContinue).Source
if (-not $winget) { $winget = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" }
if (-not (Test-Path $winget)) { throw 'winget not found - install App Installer from the Store' }

& $winget list --id vim.vim --exact --disable-interactivity 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Output 'already installed: vim.vim'
} else {
    Write-Output 'installing vim.vim'
    & $winget install --id vim.vim --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('iom-' + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Invoke-WebRequest -Uri $FontRelease -OutFile "$tmp\ttf.zip" -UseBasicParsing
Expand-Archive -Path "$tmp\ttf.zip" -DestinationPath $tmp -Force

Add-Type -AssemblyName System.Drawing
Add-Type -Name Gdi -Namespace Win32 -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResourceW(string path);
'@
$key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$n = 0
foreach ($f in Get-ChildItem $tmp -Filter *.ttf -Recurse) {
    $target = Join-Path $dir $f.Name
    if (-not (Test-Path $target) -or (Get-Item $target).Length -ne $f.Length) {
        try { Copy-Item -LiteralPath $f.FullName -Destination $target -Force }
        catch { Write-Warning "in use, left as-is: $($f.Name)" }
    }
    $pfc = New-Object System.Drawing.Text.PrivateFontCollection
    $pfc.AddFontFile($f.FullName)
    $family = $pfc.Families[0].Name
    $pfc.Dispose()
    $style = if ($f.BaseName -match '-(.+)$') { $Matches[1] } else { 'Regular' }
    Set-ItemProperty -Path $key -Name "$family $style (TrueType)" -Value $target
    [void][Win32.Gdi]::AddFontResourceW($target)
    $n++
}
Remove-Item $tmp -Recurse -Force
Write-Output "installed $n font files"

$vimrc = Join-Path $env:USERPROFILE '_vimrc'
if (Test-Path $vimrc) { Copy-Item $vimrc "$vimrc.bak" -Force }
Get-Payload '_vimrc' $vimrc
Write-Output "wrote $vimrc"

$geom = Join-Path ([System.IO.Path]::GetTempPath()) 'set-geometry.ps1'
Get-Payload 'set-geometry.ps1' $geom
& $geom
Remove-Item $geom -Force

Write-Output ''
Write-Output 'Done. Open gvim.'

$gluc = $null
if ($PSScriptRoot) {
    $gluc = @(
        (Join-Path $PSScriptRoot 'gluc\windows\setup.ps1'),
        (Join-Path $PSScriptRoot '..\gluc\windows\setup.ps1')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if ($gluc) {
    & $gluc -Source $Source
} else {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'gluc-setup.ps1'
    Invoke-WebRequest -Uri "$Source/gluc/windows/setup.ps1" -OutFile $tmp -UseBasicParsing
    & $tmp -Source $Source
    Remove-Item $tmp -Force
}
