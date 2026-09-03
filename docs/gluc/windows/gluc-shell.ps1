# The shell plugin. Reports what this shell is looking at, and when it becomes
# the one you are typing in.
#
# Dot-source from $PROFILE:  . "$env:LOCALAPPDATA\gluc\gluc-shell.ps1"
#
# Why a keystroke matters here and nowhere else: a focus event can only name
# the window, and one Windows Terminal process owns every window and every
# shell inside them. Nothing observable connects a shell to the window showing
# it - that mapping lives only inside the terminal's own memory. So the join is
# made on time instead: only one window is focused, and if a shell reports
# activity while a terminal window is in front, that shell is the one in it.
#
# That is why the report carries the ancestor - the nearest process up the tree
# that owns a top-level window. A focus event names that process; this names it
# too, and says what is running inside it.
#
# The cost is a known gap: focus a terminal and never type, and gluc still
# believes the last shell you typed in. It corrects on the first keypress.
# If PSReadLine ever adopts virtual terminal input, the terminal itself will
# report focus (DECSET 1004) and this becomes unnecessary - see todo.md.

$script:GlucEndpoint = $null
$script:GlucLastReport = [datetime]::MinValue
$script:GlucLastPath = ''
$script:GlucAncestor = 0
$script:GlucHttp = $null

# How long a shell must be quiet before a keystroke counts as becoming active
# again. Typing is not news; going from idle to typing is.
$script:GlucIdleSeconds = 4

function Get-GlucAncestor {
    # The nearest ancestor owning a top-level window - what a focus event will
    # actually name. Walks rather than assuming the parent, because a shell can
    # sit several levels down.
    $seen = 0
    $current = $PID
    while ($current -and $seen -lt 8) {
        $seen++
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$current" -EA SilentlyContinue
        if (-not $p) { return 0 }
        if ($current -ne $PID) {
            $proc = Get-Process -Id $current -EA SilentlyContinue
            if ($proc -and $proc.MainWindowHandle -ne 0) { return $current }
        }
        $current = $p.ParentProcessId
    }
    return 0
}

function Get-GlucEndpoint {
    $file = Join-Path $env:LOCALAPPDATA 'gluc\endpoint'
    if (-not (Test-Path $file)) { return $null }
    $lines = Get-Content $file -TotalCount 3 -EA SilentlyContinue
    if ($lines.Count -lt 3) { return $null }
    return @{ Port = $lines[0]; Token = $lines[1]; Pid = [int]$lines[2] }
}

function Send-GlucEvent {
    param([string]$Kind)

    $e = $script:GlucEndpoint
    # The port moves whenever the daemon restarts, so a failure is usually a
    # stale endpoint rather than a dead one.
    if (-not $e -or -not (Get-Process -Id $e.Pid -EA SilentlyContinue)) {
        $script:GlucEndpoint = Get-GlucEndpoint
        $e = $script:GlucEndpoint
        if (-not $e) { return }
    }

    if ($script:GlucAncestor -eq 0) { $script:GlucAncestor = Get-GlucAncestor }

    $body = @{
        kind     = $Kind
        source   = 'shell'
        osObject = @{ pid = $PID; ancestor = $script:GlucAncestor }
        path     = $PWD.Path
    } | ConvertTo-Json -Compress -Depth 5

    try {
        if (-not $script:GlucHttp) {
            $script:GlucHttp = [System.Net.Http.HttpClient]::new()
            $script:GlucHttp.Timeout = [timespan]::FromSeconds(2)
        }
        $content = [System.Net.Http.StringContent]::new($body, [System.Text.Encoding]::UTF8, 'application/json')
        $request = [System.Net.Http.HttpRequestMessage]::new('POST', "http://127.0.0.1:$($e.Port)/event")
        $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $e.Token)
        $request.Content = $content
        # Fire and forget. Nothing here is worth making you wait to type.
        [void]$script:GlucHttp.SendAsync($request)
    } catch {
        $script:GlucEndpoint = $null
    }

    $script:GlucLastReport = Get-Date
    $script:GlucLastPath = $PWD.Path
}

# On the prompt: the directory may have changed, which is a real transition.
# Also keeps the PEB honest, so anything reading the process from outside sees
# where this shell actually is rather than where it started.
function Update-GlucLocation {
    try { [System.IO.Directory]::SetCurrentDirectory($PWD.Path) } catch { }
    if ($PWD.Path -ne $script:GlucLastPath) { Send-GlucEvent 'select' }
}

# On a keystroke: report only the idle-to-active transition, never the typing
# itself. Sending on every character would be a sample rather than a change,
# and would fill the log with one event per keypress.
function Test-GlucActive {
    if (((Get-Date) - $script:GlucLastReport).TotalSeconds -ge $script:GlucIdleSeconds) {
        Send-GlucEvent 'select'
    }
}

# PSReadLine is loaded by the host when it starts the prompt loop, which
# happens after $PROFILE runs - so testing whether it is already loaded is
# false in exactly the interactive case this exists for, and every handler was
# silently skipped. Import it, then check the command really is there.
Import-Module PSReadLine -ErrorAction SilentlyContinue
if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    $keys = @()
    foreach ($c in [char[]]'abcdefghijklmnopqrstuvwxyz0123456789') { $keys += "$c" }
    $keys += 'Spacebar'

    foreach ($k in $keys) {
        Set-PSReadLineKeyHandler -Chord $k -ScriptBlock {
            param($key, $arg)
            Test-GlucActive
            [Microsoft.PowerShell.PSConsoleReadLine]::SelfInsert($key, $arg)
        }
    }
}
