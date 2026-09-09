#Requires -Version 5.1
param([string]$Source = 'https://newbox.stevenmliss.com')

$ErrorActionPreference = 'Stop'
$TaskName = 'gluc'

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    Write-Host 'This must run elevated.' -ForegroundColor Red
    Write-Host 'It registers a scheduled task at highest privileges, which is what lets'
    Write-Host 'AutoHotkey send input while an elevated window has focus.'
    Write-Host ''
    Write-Host 'Start PowerShell as administrator, then run:'
    Write-Host ('  irm ' + $Source + '/gluc/windows/setup.ps1 | iex')
    exit 1
}

# The payload is not one folder any more. Most of it is the Windows half, but
# the vim reporter is neither Windows-specific nor a script this installs and
# runs - so it has its own area, and the fetch takes one rather than assuming.
#
# Both halves of this resolve the same way whether setup was downloaded from
# the feed or run out of the repo, because this script sits in gluc/windows in
# both, so its parent is gluc in both.
function Get-Payload($name, $dest, $area = 'windows') {
    $local = if ($PSScriptRoot) {
        Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) $area) $name
    } else { $null }
    if ($local -and (Test-Path $local)) { Copy-Item -LiteralPath $local -Destination $dest -Force }
    else { Invoke-WebRequest -Uri "$Source/gluc/$area/$name" -OutFile $dest -UseBasicParsing }
}

$winget = (Get-Command winget -EA SilentlyContinue).Source
if (-not $winget) { $winget = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" }
if (-not (Test-Path $winget)) { throw 'winget not found - install App Installer from the Store' }

foreach ($id in 'AutoHotkey.AutoHotkey', 'Microsoft.DotNet.DesktopRuntime.10') {
    & $winget list --id $id --exact --disable-interactivity 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Output "already installed: $id"
    } else {
        Write-Output "installing $id"
        & $winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    }
}

Stop-ScheduledTask -TaskName $TaskName -EA SilentlyContinue
Get-Process Gluc.Host, Gluc.FileForwarder, Gluc.Picker, AutoHotkey64 -EA SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

$dir = Join-Path $env:LOCALAPPDATA 'gluc'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# Daily.ahk is the hotkeys, elevated. The three forwarders are separate
# unelevated processes: focus reports every foreground change, the other two
# report for apps that cannot report for themselves. All of them #Include
# gluc-http.ahk, and a missing include stops AutoHotkey loading at all.
$scripts = 'Daily.ahk', 'gluc-http.ahk',
           'gluc-focus-forwarder.ahk', 'gluc-explorer-forwarder.ahk',
           'gluc-shell.ps1'
foreach ($script in $scripts) {
    $to = Join-Path $dir $script
    Get-Payload $script $to
    Write-Output "wrote $to"
}
# Files that used to be part of this payload. Nothing reads them any more, so
# they are inert - but an inert copy of a file that once mattered is exactly
# what you find and believe on the day something is wrong.
#
# gvim.ico is the newest of them, and it did not stop mattering: it moved to
# devnext with the associations that use it. A copy left here would be the
# harder kind of stale, since it is a file that still does something, just not
# from this folder.
$retired = 'gluc-pipe.ahk', 'gluc-core.ahk',
            'gluc-watch.ahk', 'gluc-watch-core.ahk',
            'gluc-explorer.ahk', 'gluc-terminal.ahk',
            'gvim.ico'
foreach ($script in $retired) {
    $old = Join-Path $dir $script
    if (Test-Path $old) {
        Remove-Item $old -Force
        Write-Output "removed $old"
    }
}

$dest = Join-Path $dir 'Daily.ahk'

# The shell plugin is dot-sourced from $PROFILE rather than run by the daemon -
# it has to live inside the shell to know when that shell is being typed in.
#
# One marked line, added only if absent, so re-running setup does not stack
# them and removing it is obvious.
# ONE profile, and only if no profile already has it.
#
# This used to add the line to CurrentUserAllHosts and CurrentUserCurrentHost
# both, which sources the plugin twice in every shell. Harmless while the
# plugin only defines functions - and not harmless on 2026-09-08, when it also
# wrapped the prompt: the second pass captured a prompt that had itself
# captured the first pass's wrapper, and the two chains formed a cycle that
# hung every new terminal. The wrapper is gone, but sourcing anything twice
# for no reason is how that became possible.
$profileLine = '. "$env:LOCALAPPDATA\gluc\gluc-shell.ps1"   # gluc'

$already = @($PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost) |
    Where-Object { $_ -and (Test-Path $_) } |
    Where-Object { (Get-Content $_ -Raw) -match [regex]::Escape('gluc-shell.ps1') }

if ($already) {
    Write-Output ("already in " + (($already | ForEach-Object { Split-Path $_ -Leaf }) -join ', '))
} else {
    $profilePath = $PROFILE.CurrentUserAllHosts
    $parent = Split-Path $profilePath -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Add-Content -Path $profilePath -Value $profileLine
    Write-Output "added gluc to $profilePath"
}

# The vim reporter, installed and hooked up the same way the shell plugin is:
# gluc puts its own file in place and adds one marked line to the file vim
# already reads. Neither half edits the other's - _vimrc is newbox's, and this
# only appends to it, which is also what lets gluc be installed on a machine
# newbox has never touched.
#
# Guarded on the file existing, because a `source` of a missing file is an
# error on every vim startup, and an editor that complains at launch is one
# that gets its configuration deleted.
$plugin = Join-Path $dir 'gluc.vim'
Get-Payload 'gluc.vim' $plugin -area 'vim'
Write-Output "wrote $plugin"

$vimrc = Join-Path $env:USERPROFILE '_vimrc'
$vimLine = 'if filereadable(expand(''$LOCALAPPDATA/gluc/gluc.vim'')) | source $LOCALAPPDATA/gluc/gluc.vim | endif   " gluc'
$existingVimrc = if (Test-Path $vimrc) { Get-Content $vimrc -Raw } else { '' }
if ($existingVimrc -notmatch 'gluc\.vim') {
    Add-Content -Path $vimrc -Value $vimLine
    Write-Output "added gluc to $vimrc"
} else {
    Write-Output "already in $vimrc"
}

# The commit this payload was published from. One file, so comparing what is
# installed against the repo is a diff rather than an investigation.
try {
    $stampFile = Join-Path $dir 'version.txt'
    Get-Payload 'version.txt' $stampFile
    Write-Output ("installed version " + (Get-Content $stampFile -Raw).Trim())
} catch {
    Write-Warning 'no version.txt in the feed - published before versions existed'
}

# Win+G belongs to the switcher, and the Game Bar overlay will not give it up.
#
# AutoHotkey does get the key - the switcher opens - but it cannot suppress it,
# so the overlay opens too. A keyboard hook does not help: the overlay's claim
# is handled outside the chain a hook can preempt. Neither does turning off
# GameDVR, AppCapture or the startup panel; those govern recording and tips,
# not the shortcut. Measured, all of them.
#
# So the package goes. Reversible - re-register it from its staged files, or
# reinstall Xbox Game Bar from the Store.
$overlay = Get-AppxPackage -Name 'Microsoft.XboxGamingOverlay' -EA SilentlyContinue
if ($overlay) {
    try {
        Remove-AppxPackage -Package $overlay.PackageFullName -EA Stop
        Write-Output 'removed the Game Bar overlay, so Win+G belongs to the switcher'
    } catch {
        Write-Warning "could not remove the Game Bar overlay - Win+G will open it as well as the switcher: $($_.Exception.Message)"
    }
}


$saver = Join-Path $dir 'paste-image.ps1'
Get-Payload 'paste-image.ps1' $saver
Write-Output "wrote $saver"

$zip = Join-Path $env:TEMP 'gluc-host.zip'
Get-Payload 'gluc-host.zip' $zip
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Remove-Item $zip -Force
$host_exe = Join-Path $dir 'Gluc.Host.exe'
if (-not (Test-Path $host_exe)) { throw 'gluc-host.zip did not contain Gluc.Host.exe' }
$forwarder_exe = Join-Path $dir 'Gluc.FileForwarder.exe'
if (-not (Test-Path $forwarder_exe)) { throw 'gluc-host.zip did not contain Gluc.FileForwarder.exe' }
$picker_exe = Join-Path $dir 'Gluc.Picker.exe'
if (-not (Test-Path $picker_exe)) { throw 'gluc-host.zip did not contain Gluc.Picker.exe' }
Write-Output "wrote $host_exe"

# The task starts the host, and the host starts AutoHotkey. A supervisor has to
# outlive what it supervises, so it cannot be the thing the task launches.
Unregister-ScheduledTask -TaskName 'RunAutohotkeyDailyScript' -Confirm:$false -EA SilentlyContinue

$me        = "$env:USERDOMAIN\$env:USERNAME"
$action    = New-ScheduledTaskAction -Execute $host_exe
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $me
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Output "registered scheduled task: $TaskName"

Stop-ScheduledTask -TaskName $TaskName -EA SilentlyContinue
Start-ScheduledTask -TaskName $TaskName
Write-Output "started $TaskName"
