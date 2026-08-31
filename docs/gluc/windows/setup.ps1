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

function Get-Payload($name, $dest) {
    $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot $name } else { $null }
    if ($local -and (Test-Path $local)) { Copy-Item -LiteralPath $local -Destination $dest -Force }
    else { Invoke-WebRequest -Uri "$Source/gluc/windows/$name" -OutFile $dest -UseBasicParsing }
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
Get-Process Gluc.Host, AutoHotkey64 -EA SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

$dir = Join-Path $env:LOCALAPPDATA 'gluc'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# Daily.ahk is the hotkeys and gluc-watch.ahk is the focus watcher; they run as
# separate processes at different integrity levels. Both #Include the others, so
# a missing one stops AutoHotkey loading at all.
$scripts = 'Daily.ahk', 'gluc-watch.ahk', 'gluc-http.ahk', 'gluc-watch-core.ahk',
           'gluc-explorer.ahk', 'gluc-terminal.ahk'
foreach ($script in $scripts) {
    $to = Join-Path $dir $script
    Get-Payload $script $to
    Write-Output "wrote $to"
}
# Scripts that used to be part of the payload. Nothing includes them any more,
# so they are inert - but an inert copy of a file that once mattered is exactly
# what you find and believe on the day something is wrong.
$retired = 'gluc-pipe.ahk', 'gluc-core.ahk'
foreach ($script in $retired) {
    $old = Join-Path $dir $script
    if (Test-Path $old) {
        Remove-Item $old -Force
        Write-Output "removed $old"
    }
}

$dest = Join-Path $dir 'Daily.ahk'

$ico = Join-Path $dir 'gvim.ico'
Get-Payload 'gvim.ico' $ico
Write-Output "wrote $ico"

$saver = Join-Path $dir 'paste-image.ps1'
Get-Payload 'paste-image.ps1' $saver
Write-Output "wrote $saver"

$zip = Join-Path $env:TEMP 'gluc-host.zip'
Get-Payload 'gluc-host.zip' $zip
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Remove-Item $zip -Force
$host_exe = Join-Path $dir 'Gluc.Host.exe'
if (-not (Test-Path $host_exe)) { throw 'gluc-host.zip did not contain Gluc.Host.exe' }
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

$gvim = Get-ChildItem 'C:\Program Files*\Vim\vim*\gvim.exe' -EA SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $gvim) { throw 'gvim.exe not found - run newbox.ps1 first' }

$MarkdownProgId = 'gluc.markdown'
$MarkdownExtensions = @('.md', '.markdown')
$marktext = Join-Path $env:LOCALAPPDATA 'Programs\marktext\marktext.exe'

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

$blocked = @()
foreach ($ext in $Extensions) {
    $uc = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice"
    $held = (Get-ItemProperty -Path $uc -Name ProgId -EA SilentlyContinue).ProgId
    if ($held -and $held -ne $ProgId) {
        $exe = Get-DefaultAppExe $held
        if (-not ($exe -and $exe -ieq $gvim)) {
            $blocked += ('{0,-11} {1}' -f $ext, (Get-DefaultAppName $held))
        }
    }
}

Write-Output "associated $($Extensions.Count) extensions with gvim, and added it to their Open with menus"
if ($blocked) {
    Write-Host ''
    Write-Host 'These have a UserChoice entry, which overrides that:' -ForegroundColor Yellow
    $blocked | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host 'If you did not set those yourself, Windows did during setup.' -ForegroundColor Yellow
    Write-Host 'Change them in Settings > Apps > Default apps   ms-settings:defaultapps' -ForegroundColor Yellow
}
