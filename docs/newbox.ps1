#Requires -Version 5.1
param([string]$Source = 'https://newbox.stevenmliss.com')

$ErrorActionPreference = 'Stop'

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    Write-Host 'This must run elevated.' -ForegroundColor Red
    Write-Host 'It registers a scheduled task at highest privileges, which is what lets'
    Write-Host 'AutoHotkey send input while an elevated window has focus.'
    Write-Host ''
    Write-Host 'Start PowerShell as administrator, then run:'
    Write-Host ('  irm ' + $Source + '/newbox.ps1 | iex')
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

# The PowerShell profile, which is the _vimrc of the shell.
#
# CurrentUserAllHosts rather than the host-specific one, so it applies wherever
# pwsh runs. It is also the first of the four to load, which is what lets the
# prompt it defines be wrapped rather than replaced: gluc's shell plugin, dot-
# sourced at the end of it, chains whatever is there.
$profileDir = Split-Path $PROFILE.CurrentUserAllHosts -Parent
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
if (Test-Path $PROFILE.CurrentUserAllHosts) {
    Copy-Item $PROFILE.CurrentUserAllHosts "$($PROFILE.CurrentUserAllHosts).bak" -Force
}
Get-Payload 'profile.ps1' $PROFILE.CurrentUserAllHosts
Write-Output "wrote $($PROFILE.CurrentUserAllHosts)"

# A host-specific profile loads after that one and would win. Nothing here
# writes it, so its contents are the machine's own business - but a prompt
# defined there is a prompt that quietly undoes the one above, so say so
# rather than leaving it to be discovered.
if (Test-Path $PROFILE.CurrentUserCurrentHost) {
    $host_ = Get-Content $PROFILE.CurrentUserCurrentHost -Raw -EA SilentlyContinue
    if ($host_ -match '(?m)^\s*function\s+(global:)?prompt|posh-git') {
        Write-Warning "$($PROFILE.CurrentUserCurrentHost) defines a prompt of its own, which loads after this one and wins."
    }
}

# Excludes that belong to the machine rather than to any repo. git reads this
# path on its own - it is the documented default - so nothing has to be
# configured for it to take effect, and an existing core.excludesFile is left
# alone rather than overwritten.
$ignore = Join-Path $env:USERPROFILE '.config\git\ignore'
New-Item -ItemType Directory -Force -Path (Split-Path $ignore -Parent) | Out-Null
Get-Payload 'gitignore' $ignore
Write-Output "wrote $ignore"

$excludes = (& git config --global --get core.excludesFile 2>$null)
if ($LASTEXITCODE -eq 0 -and $excludes) {
    Write-Warning "core.excludesFile is set to $excludes, so git reads that instead of $ignore"
}

# git's diff tool.
#
# gvimdiff, because vim is already the editor and the diff configuration is vim
# configuration - the two-cell band, the near-monochrome scheme inside a diff,
# and marking that changes the glyphs rather than putting a block behind them.
# A block gives one line two grounds and then the line stops reading as a line,
# which is what every tool tried before this got wrong.
#
# By path rather than by name. There is usually more than one vim on a Windows
# box and PATH tends to prefer the older.
#
# merge.tool is NOT set here, deliberately. A three-way merge is four windows,
# and two cells cannot hold four panes any better than one cell could hold two.
# Until that has an answer, whatever was already configured keeps the job.
$vim = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Vim\gvim.exe')
    'C:\Program Files\Vim\vim*\gvim.exe'
    'C:\Program Files (x86)\Vim\vim*\gvim.exe'
) | ForEach-Object { Get-ChildItem $_ -EA SilentlyContinue } |
    Sort-Object { try { [version]$_.VersionInfo.FileVersion } catch { [version]'0.0' } } -Descending |
    Select-Object -First 1 -ExpandProperty FullName

if ($vim) {
    & git config --global diff.tool gvimdiff
    & git config --global difftool.gvimdiff.path $vim
    & git config --global difftool.prompt false
    Write-Output "git difftool: $vim"
} else {
    Write-Warning 'no gvim found - leaving git diff.tool alone'
}

# A contrast theme rather than an ordinary dark one. Dark mode is a suggestion
# apps may ignore; a contrast theme makes them defer to this palette, which is
# what guarantees legibility and visible window edges.
#
# Only written, not applied. Windows has no API for applying a theme - the
# shell verb opens the personalisation page and waits for a click, by design.
$themes = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes'
New-Item -ItemType Directory -Force -Path $themes | Out-Null
$theme = Join-Path $themes 'TactileDark.theme'
Get-Payload 'TactileDark.theme' $theme
Write-Output "wrote $theme  (apply it from Settings > Accessibility > Contrast themes)"

$geom = Join-Path ([System.IO.Path]::GetTempPath()) 'set-geometry.ps1'
Get-Payload 'set-geometry.ps1' $geom
& $geom
Remove-Item $geom -Force

Write-Output ''
Write-Output 'Done. Open gvim.'

# newbox prepares a box. What it prepares it for is devnext, which brings gluc
# with it - so the handoff is to devnext rather than to gluc directly. A box
# without either is still a box worth having, which is why this is the last
# thing rather than the whole point.
$devnext = $null
if ($PSScriptRoot) {
    $devnext = @(
        (Join-Path $PSScriptRoot 'devnext\windows\setup.ps1'),
        (Join-Path $PSScriptRoot '..\devnext\windows\setup.ps1')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if ($devnext) {
    & $devnext -Source $Source
} else {
    # A feed does not have to carry devnext. This one is published by newbox,
    # which builds fine without it - so a missing setup here is a feed that
    # offers the box and not the stack, and saying so is the right answer
    # rather than failing on the last step of a run that worked.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'devnext-setup.ps1'
    try {
        Invoke-WebRequest -Uri "$Source/devnext/windows/setup.ps1" -OutFile $tmp -UseBasicParsing
    } catch {
        Write-Output ''
        Write-Output "This feed carries newbox only - no devnext at $Source/devnext."
        Write-Output 'The box is ready; nothing else to install.'
        return
    }
    & $tmp -Source $Source
    Remove-Item $tmp -Force -EA SilentlyContinue
}
