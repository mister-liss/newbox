#Requires -Version 5.1
param(
    [string]$Source = 'https://newbox.stevenmliss.com',

    # Where the sandbox task definitions are cloned. They are configuration for
    # devnext rather than part of it, so they live in their own private
    # repository - see the block near the sandbox install below.
    [string]$SandboxKits = "$env:LOCALAPPDATA\devnext\kits"
)

$ErrorActionPreference = 'Stop'

# devnext: the choices, not the software.
#
# gluc is a mechanism. It asks the registry to edit or open a file and the
# registry answers; it does not know or care which program that is - the one
# place it named gvim is gone. What is left over is a set of opinions about
# what a good post-IDE desktop looks like, and those are devnext's:
#
#   MarkText is the markdown viewer, so `open` on a .md means reading it
#   rendered while `edit` still means vim. Without that choice both verbs
#   resolve to the same program and the split says nothing.
#
#   gvim is the editor, registered for the thirty extensions worth registering.
#   Without it every Enter in the switcher reaches the shell's Open with
#   dialog - which works, and is the honest answer, but is not a stack anyone
#   would call good.
#
# Nothing here is required for gluc to run, which is the test that put it in
# this file rather than that one. Install gluc alone and it works; install this
# too and it is worth using.
#
# Sandbox will land here eventually. It is the reason this exists now, while
# the contents are small enough that their shape is not an argument.

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    Write-Host 'This must run elevated.' -ForegroundColor Red
    Write-Host 'It installs gluc, which registers a scheduled task at highest privileges.'
    Write-Host ''
    Write-Host 'Start PowerShell as administrator, then run:'
    Write-Host ('  irm ' + $Source + '/devnext/windows/setup.ps1 | iex')
    exit 1
}

function Get-Payload($name, $dest, $area = 'windows') {
    $local = if ($PSScriptRoot) {
        Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) $area) $name
    } else { $null }
    if ($local -and (Test-Path $local)) { Copy-Item -LiteralPath $local -Destination $dest -Force }
    else { Invoke-WebRequest -Uri "$Source/devnext/$area/$name" -OutFile $dest -UseBasicParsing }
}

# The sandbox.
#
# Docker Sandboxes rather than Docker Desktop, and they are genuinely separate
# products: sbx installs to %LOCALAPPDATA%\DockerSandboxes with its own daemon,
# its own named pipe and its own storage. Verified on 2026-09-06 - `sbx ls`,
# `sbx secret ls` and `sbx policy log` all answer with Desktop's engine stopped
# and unreachable, and `sbx diagnose` names no Desktop component at all.
#
# So no Desktop, which was the question worth settling before committing to it.
#
# devnext's rather than gluc's by the usual test: gluc does not stop working
# without it. Sandboxed agents are a choice about how to develop, which is what
# this layer is for.
# A MINIMUM rather than a pin, and rather than whatever is newest.
#
# 0.39.0 is where `sbx secret set-custom` grew --command and --refresh, so a
# credential can name how it is minted instead of being handed a value that was
# already dying. Everything the sandbox does with credentials is built on that,
# so a 0.38 box is not a slightly older box - it is one where the design does
# not hold.
#
# Below it, upgrade. At or above it, leave alone: dragging a working sandbox
# forward on every install is not this script's decision to make.
# Where its task definitions come from.
#
# Not from here. A definition says which machine reaches which service and how
# a credential for it is minted - configuration for devnext rather than part of
# it - so it lives in a private repository of its own and devnext keeps only
# the machinery. That is also what keeps this layer publishable: nothing in a
# definition is secret, but internal hostnames and a tenant id have no business
# on a public feed.
#
# Set rather than cloned. Cloning needs credentials and a decision about where,
# and an installer that silently pulls a private repository onto a machine is
# doing something it was not asked to do.
[Environment]::SetEnvironmentVariable('SANDBOX_KITS', $SandboxKits, 'User')
$env:SANDBOX_KITS = $SandboxKits
if (Test-Path $SandboxKits) {
    Write-Output "sandbox kits: $SandboxKits"
} else {
    Write-Output "sandbox kits: $SandboxKits (not there yet)"
    Write-Output "  git clone https://github.com/stlis_microsoft/sandbox-kits.git $SandboxKits"
}

$SbxLeast = [version]'0.39.0'

$winget = (Get-Command winget -EA SilentlyContinue).Source
if (-not $winget) { $winget = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" }
if (Test-Path $winget) {
    # Ask sbx itself rather than winget. winget knows what it installed, which
    # is not the same as what is on PATH, and the version that matters is the
    # one that runs.
    $have = $null
    $sbx = (Get-Command sbx -EA SilentlyContinue).Source
    if ($sbx) {
        $said = & $sbx version 2>&1
        if ($said -match '(\d+\.\d+\.\d+)') { $have = [version]$Matches[1] }
    }

    if ($have -and $have -ge $SbxLeast) {
        Write-Output "already installed: Docker.sbx $have"
    } else {
        $what = if ($have) { "upgrading Docker.sbx $have -> at least $SbxLeast" } else { 'installing Docker.sbx' }
        Write-Output $what
        & $winget install --id Docker.sbx --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    }
} else {
    Write-Warning 'winget not found - install Docker Sandboxes by hand, see sandbox/RUNBOOK.md'
}

# The software first, then the choices about what it hands files to. devnext
# depends on gluc and not the other way round: these associations point at
# ProgIds gluc's switcher asks for by verb, and MarkText exists to give `open`
# something to mean.
$gluc = @(
    (Join-Path $PSScriptRoot '..\..\gluc\windows\setup.ps1'),
    (Join-Path $PSScriptRoot '..\..\..\gluc\windows\setup.ps1')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if ($gluc) {
    & $gluc -Source $Source
} else {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'gluc-setup.ps1'
    Invoke-WebRequest -Uri "$Source/gluc/windows/setup.ps1" -OutFile $tmp -UseBasicParsing
    & $tmp -Source $Source
    Remove-Item $tmp -Force -EA SilentlyContinue
}

# Its own folder, not gluc's. A file in gluc's directory is gluc's to delete.
$dir = Join-Path $env:LOCALAPPDATA 'devnext'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# Settings are about to be written over its own copy, and it rewrites them on
# exit.
Get-Process marktext -EA SilentlyContinue | Stop-Process -Force

# MarkText is not in winget, so it follows the same shape newbox uses for the
# font: a pinned URL and a direct download. Pinned rather than "latest" so a
# bump is a deliberate edit here instead of whatever shipped this morning.
#
# It is what `open` on a markdown file resolves to. Without it that verb falls
# back to gvim further down, which works but leaves open and edit doing the
# same thing - the exact conflation the verbs exist to undo.
$MarkTextVersion = '0.19.1'
$MarkTextUrl = "https://github.com/marktext/marktext/releases/download/v$MarkTextVersion/marktext-win-x64-$MarkTextVersion-setup.exe"
$marktext = Join-Path $env:LOCALAPPDATA 'Programs\marktext\marktext.exe'

if (Test-Path $marktext) {
    Write-Output 'already installed: marktext'
} else {
    Write-Output "installing marktext $MarkTextVersion"
    $installer = Join-Path $env:TEMP "marktext-$MarkTextVersion-setup.exe"
    try {
        Invoke-WebRequest -Uri $MarkTextUrl -OutFile $installer -UseBasicParsing
        # electron-builder NSIS. /S is silent, and it installs per-user, which
        # is why this does not need the elevation the rest of setup has.
        Start-Process $installer -ArgumentList '/S' -Wait
        Remove-Item $installer -Force -EA SilentlyContinue
        if (Test-Path $marktext) { Write-Output "wrote $marktext" }
        else { Write-Warning 'marktext installer ran but the exe is not where it was expected' }
    } catch {
        Write-Warning "marktext install failed ($($_.Exception.Message)) - markdown will open in gvim"
    }
}

$ico = Join-Path $dir 'gvim.ico'
Get-Payload 'gvim.ico' $ico
Write-Output "wrote $ico"

# MarkText settings travel with the install, the way the vimrc does. The file
# holds no paths and no state - just preferences - so it is safe to carry
# between machines whole.
#
# Merged rather than overwritten, so a MarkText version that adds a key keeps
# its own default for it instead of losing the key entirely. The trade is that
# re-running setup puts our value back over anything changed by hand since,
# which is what "settings come with the install" means.
$prefsPath = Join-Path $env:APPDATA 'marktext\preferences.json'
$prefsTemp = Join-Path $env:TEMP 'marktext-preferences.json'
try {
    Get-Payload 'marktext-preferences.json' $prefsTemp
    $ours = Get-Content $prefsTemp -Raw | ConvertFrom-Json
    $merged = [ordered]@{}
    if (Test-Path $prefsPath) {
        $existing = Get-Content $prefsPath -Raw | ConvertFrom-Json
        foreach ($k in $existing.PSObject.Properties.Name) { $merged[$k] = $existing.$k }
    }
    foreach ($k in $ours.PSObject.Properties.Name) { $merged[$k] = $ours.$k }

    New-Item -ItemType Directory -Force -Path (Split-Path $prefsPath -Parent) | Out-Null
    # Not Set-Content -Encoding UTF8: on PowerShell 5.1 that writes a BOM, and
    # JSON.parse in Electron rejects one, which would leave MarkText unable to
    # read its own preferences.
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($prefsPath, ($merged | ConvertTo-Json -Depth 10), $utf8)
    Remove-Item $prefsTemp -Force -EA SilentlyContinue
    Write-Output "wrote $prefsPath ($($merged.Count) keys)"
} catch {
    Write-Warning "marktext preferences not applied: $($_.Exception.Message)"
}

Add-Type -Name Ind -Namespace Win32 -MemberDefinition @'
[DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
public static extern int SHLoadIndirectString(string src, System.Text.StringBuilder buf, int cch, IntPtr r);
'@

function Get-DefaultAppExe($id) {
    foreach ($root in 'HKCU:\Software\Classes', 'HKLM:\SOFTWARE\Classes') {
        $c = (Get-ItemProperty -Path (Join-Path $root "$id\shell\open\command") -EA SilentlyContinue).'(default)'
        if ($c) {
            if ($c -match '^"([^"]+)"') { return $Matches[1] }
            return ($c -split ' ')[0]
        }
    }
    return $null
}

function Get-DefaultAppName($id) {
    foreach ($root in 'HKCU:\Software\Classes', 'HKLM:\SOFTWARE\Classes') {
        $a = Get-ItemProperty -Path (Join-Path $root "$id\Application") -EA SilentlyContinue
        if ($a -and $a.ApplicationName) {
            $n = $a.ApplicationName
            if ($n -like '@*') {
                $sb = New-Object System.Text.StringBuilder 1024
                if ([Win32.Ind]::SHLoadIndirectString($n, $sb, $sb.Capacity, [IntPtr]::Zero) -eq 0) { return $sb.ToString() }
            } else { return $n }
        }
        $c = (Get-ItemProperty -Path (Join-Path $root "$id\shell\open\command") -EA SilentlyContinue).'(default)'
        if ($c) {
            $exe = if ($c -match '^"([^"]+)"') { $Matches[1] } else { ($c -split ' ')[0] }
            $d = (Get-Item $exe -EA SilentlyContinue).VersionInfo.FileDescription
            if ($d) { return $d }
            if ($exe) { return (Split-Path $exe -Leaf) }
        }
    }
    return $id
}

$ProgId = 'gluc.gvim' 
$Extensions = @(
    '.txt','.log','.ini','.cfg','.conf','.yml','.yaml','.toml',
    '.json','.xml','.csv','.tsv','.sql','.vim','.lua',
    '.sh','.bash','.ps1','.psm1','.py','.js','.ts','.css',
    '.c','.h','.cpp','.hpp','.cs','.java','.go','.rs','.rb'
)

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
if (-not $gvim) { throw 'gvim.exe not found - run newbox.ps1 first' }

$MarkdownProgId = 'gluc.markdown'
$MarkdownExtensions = @('.md', '.markdown')

$classes = 'HKCU:\Software\Classes'

# Windows has room for more than one verb per type, and collapsing them into
# `open` is what forces every consumer to invent its own way of saying "no, the
# other kind of opening". `%2` is where a position goes - gvim gets +42 from
# the switcher through it - and a command with no slot for one simply opens the
# file at the top.
function Set-Verb($progId, $verb, $command) {
    $key = "$classes\$progId\shell\$verb\command"
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -Path $key -Name '(default)' -Value $command
}
New-Item -Path "$classes\$ProgId\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$classes\$ProgId" -Name '(default)' -Value 'Text file'
New-Item -Path "$classes\$ProgId\Application" -Force | Out-Null
Set-ItemProperty -Path "$classes\$ProgId\Application" -Name 'ApplicationName' -Value 'gvim'
New-Item -Path "$classes\$ProgId\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$classes\$ProgId\DefaultIcon" -Name '(default)' -Value "$gvim,0"
Set-Verb $ProgId 'open' ('"' + $gvim + '" %2 "%1"')
Set-Verb $ProgId 'edit' ('"' + $gvim + '" %2 "%1"')

# Markdown is the case that makes the point: opening it means reading it
# rendered, editing it means vim. One ProgId cannot say both, so it gets its
# own. Falls back to gvim for both verbs when MarkText is not installed.
New-Item -Path "$classes\$MarkdownProgId" -Force | Out-Null
Set-ItemProperty -Path "$classes\$MarkdownProgId" -Name '(default)' -Value 'Markdown document'
Set-Verb $MarkdownProgId 'edit' ('"' + $gvim + '" %2 "%1"')
if (Test-Path $marktext) {
    Set-Verb $MarkdownProgId 'open' ('"' + $marktext + '" "%1"')
    Write-Output "markdown opens in marktext, edits in gvim"
} else {
    Set-Verb $MarkdownProgId 'open' ('"' + $gvim + '" %2 "%1"')
    Write-Output 'marktext not installed - markdown opens in gvim'
}

foreach ($pair in @{ 'gvim.exe' = 'gvim'; 'vim.exe' = 'vim' }.GetEnumerator()) {
    $app = "$classes\Applications\$($pair.Key)"
    $target = Join-Path (Split-Path $gvim -Parent) $pair.Key
    if (Test-Path $target) {
        New-Item -Path "$app\shell\open\command" -Force | Out-Null
        Set-ItemProperty -Path "$app\shell\open\command" -Name '(default)' -Value ('"' + $target + '" "%1"')
        Set-ItemProperty -Path $app -Name 'FriendlyAppName' -Value $pair.Value
    }
}

$iconKey = "$classes\Applications\gvim.exe\DefaultIcon"
New-Item -Path $iconKey -Force | Out-Null
Set-ItemProperty -Path $iconKey -Name '(default)' -Value $ico

foreach ($pair in @($Extensions | ForEach-Object { @{ Ext = $_; Id = $ProgId } }) +
                  @($MarkdownExtensions | ForEach-Object { @{ Ext = $_; Id = $MarkdownProgId } })) {
    New-Item -Path "$classes\$($pair.Ext)\OpenWithProgIds" -Force | Out-Null
    Set-ItemProperty -Path "$classes\$($pair.Ext)\OpenWithProgIds" -Name $pair.Id -Value ([byte[]]@()) -Type None
    Set-ItemProperty -Path "$classes\$($pair.Ext)" -Name '(default)' -Value $pair.Id
}

Add-Type -Name Shell -Namespace Win32 -MemberDefinition @'
[DllImport("shell32.dll")]
public static extern void SHChangeNotify(int e, uint f, IntPtr a, IntPtr b);
'@
[Win32.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

# UserChoice outranks everything written above, and Windows will not let a
# script change it - the key carries a deny ACE, added specifically to stop
# programs hijacking associations. Taking ownership to strip that ACE is the
# attack the protection exists to block, so this only reports.
#
# Checked per extension against the id that extension is meant to have. An
# earlier run of this script put .md under the gvim ProgId, so comparing
# everything against a single id would call that correct and say nothing.
$blocked = @()
$intended = @{}
foreach ($ext in $Extensions) { $intended[$ext] = $ProgId }
foreach ($ext in $MarkdownExtensions) { $intended[$ext] = $MarkdownProgId }

foreach ($ext in $intended.Keys) {
    $uc = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice"
    $held = (Get-ItemProperty -Path $uc -Name ProgId -EA SilentlyContinue).ProgId
    if (-not $held -or $held -eq $intended[$ext]) { continue }

    # A different id pointing at the right program is not a problem.
    $exe = Get-DefaultAppExe $held
    if ($intended[$ext] -eq $ProgId -and $exe -and $exe -ieq $gvim) { continue }
    if ($intended[$ext] -eq $MarkdownProgId -and $exe -and $exe -ieq $marktext) { continue }

    $want = if ($intended[$ext] -eq $MarkdownProgId) { 'marktext' } else { 'gvim' }
    $blocked += ('{0,-11} opens with {1,-24} should be {2}' -f $ext, (Get-DefaultAppName $held), $want)
}

if ($blocked) {
    Write-Host 'These have a UserChoice entry, which overrides that:' -ForegroundColor Yellow
    $blocked | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host 'If you did not set those yourself, Windows did during setup.' -ForegroundColor Yellow
    Write-Host 'Change them in Settings > Apps > Default apps   ms-settings:defaultapps' -ForegroundColor Yellow
}
