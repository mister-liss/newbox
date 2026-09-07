# The shell plugin. Reports what this shell is looking at, and when it becomes
# the one you are typing in.
#
# Dot-source from $PROFILE:  . "$env:LOCALAPPDATA\gluc\gluc-shell.ps1"
#
# The hard part, and how it is solved: a focus event can only name the window,
# and one Windows Terminal process owns every window and every shell inside
# them. Nothing observable connects a shell to the window showing it - that
# mapping lives only inside the terminal's own memory.
#
# So the shell says so itself, in the window title, in characters that render
# as nothing. See the marker below. That is identity rather than inference,
# and it replaced a join made on TIME - the shell you last typed in taken to be
# the one in front - which was right most of the time and quietly wrong the
# rest.
#
# The report still carries the ancestor - the nearest process up the tree that
# owns a top-level window - because it is what matches when no marker is
# present: a shell that has not reached a prompt, or one whose title has been
# taken over by vim or an agent CLI. Those report themselves or they do not;
# this does not pretend to speak for them.

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

# The marker: this shell's pid, written into the window title in characters
# that render as nothing.
#
# It is the answer to the only question focus cannot answer. One
# WindowsTerminal.exe owns every window, so a focus event names the terminal
# and never the shell inside it, and nothing observable connects the two -
# that mapping lives in the terminal's own memory. Before this, gluc joined
# them on TIME: the shell you last typed in was taken to be the one in front.
# Usually right, quietly wrong whenever you clicked a window and read it
# without typing.
#
# The title is the one channel that carries from a shell to something the
# focus forwarder can read. Zero-width characters survive it intact - measured
# against GetWindowText, non-ASCII and all - so the marker costs nothing
# visible.
#
# Binary rather than digits, because there are only two invisible characters
# worth trusting. U+2060 delimits, U+200B is 0 and U+200C is 1, and the pid is
# 24 bits, which covers every Windows pid.
$global:GlucMark = $(
    $bits = [Convert]::ToString($PID, 2).PadLeft(24, '0')
    [char]0x2060 + -join ($bits.ToCharArray() | ForEach-Object {
        if ($_ -eq '1') { [char]0x200C } else { [char]0x200B }
    }) + [char]0x2060
)

# Stamped on every prompt, and that is the point rather than an inefficiency.
# The string is built once - a pid does not change - and the write is one
# concatenation onto a title something is setting anyway.
#
# It has to repeat because anything that takes over the terminal sets its own
# title: vim, a pager, an agent CLI. Those are not gluc's business - they
# report themselves, or they do not - but when one exits, the shell is plainly
# a shell again, and a marker written only at startup would have been gone for
# good. Re-stamping makes it self-repairing.
function Add-GlucMark {
    try {
        $title = $Host.UI.RawUI.WindowTitle
        if ($title -notlike "*$($global:GlucMark)*") {
            $Host.UI.RawUI.WindowTitle = $title + $global:GlucMark
        }
    } catch { }
}

# And wire it, rather than leaving it for the profile to remember. A cd is not
# a keystroke, so without this the only reports are the idle-to-active ones -
# change directory, alt-tab away and back, and gluc still believes the place
# you left.
#
# Chains whatever prompt was already defined instead of replacing it, and only
# once: this file is dot-sourced from more than one profile on some machines.
#
# The guard reads the prompt itself rather than a flag beside it. A flag can be
# wrong - cleared by hand, or by something restoring a session - and a wrapper
# that wraps itself captures itself as the inner prompt and recurses until the
# stack runs out. Asking the function whether it is already ours cannot drift
# from the truth, because it IS the truth.
#
# The inner prompt runs first because it is the one that sets the title; the
# mark goes on afterwards, onto whatever it wrote.
if ($function:prompt -notmatch 'gluc-wrapped-prompt') {
    $global:GlucInnerPrompt = $function:prompt
    function global:prompt {
        # gluc-wrapped-prompt - the guard above looks for this line.
        Update-GlucLocation
        $text = if ($global:GlucInnerPrompt) { & $global:GlucInnerPrompt } else { "PS $($PWD.Path)> " }
        Add-GlucMark
        $text
    }
}

# The keystroke handler is gone, and its absence is the whole point of the
# marker above.
#
# It existed to make the timing join work: report on the idle-to-active
# transition so that "the shell you last typed in" was current enough to stand
# in for "the shell in the focused window". That guess is not needed now - the
# title says which shell it is - and what it cost was a PSReadLine handler on
# every letter, digit and space in the language, each one re-implementing
# SelfInsert.
#
# What remains is the prompt: it reports where this shell is, and stamps the
# mark that says which shell it is.
