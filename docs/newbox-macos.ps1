#Requires -Version 7.0
param([string]$Source = 'https://newbox.stevenmliss.com')

$ErrorActionPreference = 'Stop'

# newbox on the Mac, and it is deliberately a fraction of what it is on Windows.
#
# The Windows box is where I live: it gets the font, the contrast theme, the
# window geometry and the prompt, because those are what make a machine
# readable to me. The Mac is not that machine - it travels, it runs Teams and
# Scout, and it hosts sandboxed agents. Porting the workstation layer to it
# would be building for a way of working I have already said I cannot use
# there.
#
# So this installs what is true of any machine I touch - the git excludes - and
# then hands off to devnext, which is the layer the Mac is actually for. If the
# font and the editor are ever wanted here too, they are added deliberately
# rather than by symmetry.

# pwsh is a prerequisite rather than something this installs, which is the one
# asymmetry with Windows worth explaining. Windows ships PowerShell, so the
# entry command can be PowerShell; macOS does not, so something has to install
# it before a .ps1 can run at all. The choices were a bash line that installs
# pwsh and re-enters, or saying so on the page - and the page is where a
# prerequisite belongs. It is the same shape as "run this elevated" on Windows:
# stated, not hidden inside a script that cannot run until it is true.
#
# So by the time this executes, pwsh exists. What it cannot assume is brew,
# which is what everything below would need if it grew a dependency.

function Get-Payload($rel, $dest) {
    $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot $rel } else { $null }
    if ($local -and (Test-Path $local)) { Copy-Item -LiteralPath $local -Destination $dest -Force }
    else { Invoke-WebRequest -Uri "$Source/$rel" -OutFile $dest -UseBasicParsing }
}

if (-not (Get-Command git -EA SilentlyContinue)) {
    # macOS ships a git shim that is not git: running it when the Command Line
    # Tools are absent pops a GUI installer and returns non-zero, so a check
    # for the command alone would pass and the first real call would fail.
    throw 'git not found - run "xcode-select --install" first'
}

# Excludes that belong to the machine rather than to any repo. git reads this
# path on its own - it is the documented default - so nothing has to be
# configured for it to take effect, and an existing core.excludesFile is left
# alone rather than overwritten.
#
# $HOME rather than $env:USERPROFILE, and Join-Path in parts rather than one
# string with separators in it: the Windows script can write '.config\git\ignore'
# because it only ever runs on Windows, and this one has no reason to hardcode
# the other slash.
$ignore = Join-Path $HOME '.config' 'git' 'ignore'
New-Item -ItemType Directory -Force -Path (Split-Path $ignore -Parent) | Out-Null
Get-Payload 'gitignore' $ignore
Write-Output "wrote $ignore"

$excludes = (& git config --global --get core.excludesFile 2>$null)
if ($LASTEXITCODE -eq 0 -and $excludes) {
    Write-Warning "core.excludesFile is set to $excludes, so git reads that instead of $ignore"
}

Write-Output ''

# The handoff, same as the Windows script makes and for the same reason: newbox
# prepares a box, and what it prepares it for is devnext. A feed does not have
# to carry devnext, and on this platform it does not carry it yet - so a
# missing setup here is the honest answer rather than a failure on the last
# step of a run that worked.
$devnext = $null
if ($PSScriptRoot) {
    $devnext = @(
        (Join-Path $PSScriptRoot 'devnext' 'macos' 'setup.ps1'),
        (Join-Path $PSScriptRoot '..' 'devnext' 'macos' 'setup.ps1')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if ($devnext) {
    & $devnext -Source $Source
} else {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'devnext-setup.ps1'
    try {
        Invoke-WebRequest -Uri "$Source/devnext/macos/setup.ps1" -OutFile $tmp -UseBasicParsing
    } catch {
        Write-Output "This feed carries newbox only - no devnext at $Source/devnext/macos."
        Write-Output 'The box is ready; nothing else to install.'
        return
    }
    & $tmp -Source $Source
    Remove-Item $tmp -Force -EA SilentlyContinue
}
