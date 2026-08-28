#Requires -Version 5.1
param([string]$Source = 'https://newbox.stevenmliss.com')

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

& $winget list --id AutoHotkey.AutoHotkey --exact --disable-interactivity 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Output 'already installed: AutoHotkey.AutoHotkey'
} else {
    Write-Output 'installing AutoHotkey.AutoHotkey'
    & $winget install --id AutoHotkey.AutoHotkey --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
}

$dir = Join-Path $env:LOCALAPPDATA 'gluc'
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
    '.txt','.log','.md','.markdown','.ini','.cfg','.conf','.yml','.yaml','.toml',
    '.json','.xml','.csv','.tsv','.sql','.vim','.lua',
    '.sh','.bash','.ps1','.psm1','.py','.js','.ts','.css',
    '.c','.h','.cpp','.hpp','.cs','.java','.go','.rs','.rb'
)

$gvim = Get-ChildItem 'C:\Program Files*\Vim\vim*\gvim.exe' -EA SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $gvim) { throw 'gvim.exe not found - run newbox.ps1 first' }

$classes = 'HKCU:\Software\Classes'
New-Item -Path "$classes\$ProgId\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$classes\$ProgId" -Name '(default)' -Value 'Text file'
New-Item -Path "$classes\$ProgId\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$classes\$ProgId\DefaultIcon" -Name '(default)' -Value "$gvim,0"
Set-ItemProperty -Path "$classes\$ProgId\shell\open\command" -Name '(default)' -Value ('"' + $gvim + '" "%1"')

foreach ($ext in $Extensions) {
    New-Item -Path "$classes\$ext\OpenWithProgIds" -Force | Out-Null
    Set-ItemProperty -Path "$classes\$ext\OpenWithProgIds" -Name $ProgId -Value ([byte[]]@()) -Type None
    Set-ItemProperty -Path "$classes\$ext" -Name '(default)' -Value $ProgId
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
