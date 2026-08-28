#Requires -Version 5.1
param([string]$Source = 'https://mister-liss.github.io/newbox')

$ErrorActionPreference = 'Stop'
$TaskName = 'RunAutohotkeyDailyScript'

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    Write-Host 'This must run elevated.' -ForegroundColor Red
    Write-Host 'It registers a scheduled task at highest privileges, which is what lets'
    Write-Host 'AutoHotkey send input while an elevated window has focus.'
    Write-Host ''
    Write-Host 'Start PowerShell as administrator, then run:'
    Write-Host ('  iwr ' + $Source + '/gluc/windows/setup.ps1 -UseBasicParsing | iex')
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

& $winget list --id AutoHotkey.AutoHotkey --exact --disable-interactivity 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Output 'already installed: AutoHotkey.AutoHotkey'
} else {
    Write-Output 'installing AutoHotkey.AutoHotkey'
    & $winget install --id AutoHotkey.AutoHotkey --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
}

$dir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AutoHotkey'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$dest = Join-Path $dir 'Daily.ahk'
Get-Payload 'Daily.ahk' $dest
Write-Output "wrote $dest"

$exe = Get-ChildItem 'C:\Program Files*\AutoHotkey\v2\AutoHotkey64.exe' -EA SilentlyContinue |
       Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $exe) { throw 'AutoHotkey64.exe not found - open a new shell and re-run' }

$me        = "$env:USERDOMAIN\$env:USERNAME"
$action    = New-ScheduledTaskAction -Execute $exe -Argument ('"' + $dest + '"')
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $me
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType InteractiveToken -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Output "registered scheduled task: $TaskName"

Stop-ScheduledTask -TaskName $TaskName -EA SilentlyContinue
Start-ScheduledTask -TaskName $TaskName
Write-Output "started $TaskName"
