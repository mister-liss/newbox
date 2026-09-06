# The prompt.
#
# Everything a prompt usually says - where you are, what branch you are on -
# is state, not conversation. Printed inline it pushes the place you type
# further right on every directory you descend into, and says it again on
# every command, so history reads as a hundred copies of a thing that changed
# twice.
#
# So it goes in the window title, which Windows Terminal shows on the tab: one
# copy, always current, and never in the way. What is left on the line is the
# part that is actually a prompt.
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
    $Host.UI.RawUI.WindowTitle = if ($branch) { "$short  ($branch)" } else { $short }

    '> '
}

. "$env:LOCALAPPDATA\gluc\gluc-shell.ps1"   # gluc
