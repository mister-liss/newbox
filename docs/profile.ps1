# The prompt.
#
# Everything a prompt usually says - where you are, what branch you are on -
# is state, not conversation. Printed inline it pushes the place you type
# further right on every directory you descend into, and says it again on
# every command, so history reads as a hundred copies of a thing that changed
# twice.
#
# So it goes on its own line, and the line below it is the part that is
# actually a prompt. The insertion point sits at column three whatever you
# have cd'd into, and the state is one line above it - which is where you are
# already looking. The tab title says the same thing for the times you are
# looking at the tab strip instead, which costs nothing to keep current.
#
# And it is transient: the moment you press Enter the line is redrawn without
# it, so it exists while you are typing and leaves nothing behind. Scrollback
# is the record of what you ran, and a copy of the same directory above every
# one of them is not a record of anything.
#
# The branch is read out of .git rather than by running git. A prompt that
# spawns a process is a prompt you wait for, and this one runs before every
# command you type.

function Get-Branch($path) {
    $dir = try { [System.IO.DirectoryInfo]::new($path) } catch { $null }
    while ($dir) {
        $git = Join-Path $dir.FullName '.git'
        if (Test-Path $git) {
            # A worktree or submodule keeps a file here pointing at the real
            # git directory.
            if (Test-Path $git -PathType Leaf) {
                $line = (Get-Content $git -TotalCount 1 -EA SilentlyContinue)
                if ($line -notmatch '^gitdir:\s*(.+)$') { return $null }
                $git = $Matches[1].Trim()
                if (-not [System.IO.Path]::IsPathRooted($git)) {
                    $git = Join-Path $dir.FullName $git
                }
            }
            $head = Join-Path $git 'HEAD'
            if (-not (Test-Path $head)) { return $null }
            $ref = (Get-Content $head -TotalCount 1 -EA SilentlyContinue)
            if ($ref -match '^ref:\s*refs/heads/(.+)$') { return $Matches[1] }
            # Detached: the sha is all there is to say.
            if ($ref) { return $ref.Substring(0, [Math]::Min(7, $ref.Length)) }
            return $null
        }
        $dir = $dir.Parent
    }
    return $null
}

function global:prompt {
    $cwd = $ExecutionContext.SessionState.Path.CurrentLocation.Path
    $short = if ($cwd.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase)) {
        '~' + $cwd.Substring($HOME.Length)
    } else { $cwd }

    $branch = Get-Branch $cwd
    $line = if ($branch) { "$short  ($branch)" } else { $short }
    $Host.UI.RawUI.WindowTitle = $line

    # On the way out, only the prompt itself.
    if ($global:PromptIsLeaving) { return '> ' }

    # Dim, because it is there to be glanced at rather than read, and it should
    # not compete with the output of whatever you just ran. [char]27 rather
    # than `e so this still parses under Windows PowerShell.
    $esc = [char]27
    "$esc[90m$line$esc[0m`n> "
}

# Redraw without the state line, then accept. InvokePrompt calls the function
# above again in place, so the two lines you were typing at collapse to the one
# that is worth keeping - and the command you ran scrolls away as `> thing`.
#
# ExtraPromptLineCount is what makes that land on the right row. PSReadLine
# remembers where the input starts, not where the prompt starts, and works back
# to the second by subtracting this. Left at its default of zero the redraw
# rewrites the input line and the state line above it survives - which is
# exactly the pollution this exists to stop.
Import-Module PSReadLine -ErrorAction SilentlyContinue
if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -ExtraPromptLineCount 1

    Set-PSReadLineKeyHandler -Chord Enter -ScriptBlock {
        # An unfinished command - an open brace, a trailing pipe - means Enter
        # continues the line rather than running it, and the prompt is not
        # going anywhere. Collapsing it there would take the state away while
        # you are still typing at it.
        $errors = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState(
            [ref]$null, [ref]$null, [ref]$errors, [ref]$null)

        if (-not $errors -or $errors.Count -eq 0) {
            $global:PromptIsLeaving = $true
            try { [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt($null, $null) }
            catch { }
            finally { $global:PromptIsLeaving = $false }
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
}

. "$env:LOCALAPPDATA\gluc\gluc-shell.ps1"   # gluc
