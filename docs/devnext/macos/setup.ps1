#Requires -Version 7.0
param(
    [string]$Source = 'https://newbox.stevenmliss.com',

    # Where the sandbox task definitions are cloned. Same reasoning as the
    # Windows setup - configuration for devnext rather than part of it, so it
    # lives in a private repository of its own.
    #
    # ~/.local/share rather than a path invented for this: gluc.vim already
    # resolves its non-Windows directory to ~/.local/share/gluc, so the
    # convention exists in this repository and this follows it.
    [string]$SandboxKits = "$HOME/.local/share/devnext/kits"
)

$ErrorActionPreference = 'Stop'

# devnext on the Mac, and it stops at the sandbox.
#
# The Windows setup also registers file associations, installs MarkText and
# gvim, and says what a terminal is. None of that is here, because none of it
# is why this machine is in scope: the Mac is where sbx runs. What the desktop
# looks like there is a question for whenever the Mac becomes somewhere work
# actually happens, and answering it early would mean porting a set of choices
# to a machine that has not asked for them.
#
# So this is the sandbox block from the Windows setup and nothing else, kept
# recognisably the same shape so the two can be read side by side.

# Two hard requirements, checked rather than discovered.
#
# sbx runs Arm Linux microVMs on Apple's Virtualization Framework, so an Intel
# Mac cannot run it at all and no amount of retrying will change that. Failing
# here with the reason beats failing inside brew with a formula error, or worse
# installing cleanly and falling over on first run.
$arch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
if ($arch -ne 'Arm64') {
    throw "sbx needs Apple silicon; this is $arch"
}

$macos = (& sw_vers -productVersion).Trim()
if ([version]($macos -replace '^(\d+\.\d+).*', '$1') -lt [version]'14.0') {
    throw "sbx needs macOS 14 or later; this is $macos"
}

# Where its task definitions come from.
#
# Not from here. A definition says which machine reaches which service and how
# a credential for it is minted - configuration for devnext rather than part of
# it - so it lives in a private repository of its own and devnext keeps only
# the machinery.
#
# Set rather than cloned. Cloning needs credentials and a decision about where,
# and an installer that silently pulls a private repository onto a machine is
# doing something it was not asked to do.
#
# The one place this genuinely cannot mirror Windows. There
# [Environment]::SetEnvironmentVariable(..., 'User') writes a persistent user
# variable; on macOS that overload is a silent no-op, which is worse than not
# trying. So the session gets it now and the pwsh profile gets it for next
# time - pwsh rather than the shell profile, because everything in this stack
# that reads the variable is PowerShell.
$env:SANDBOX_KITS = $SandboxKits

$profilePath = $PROFILE.CurrentUserAllHosts
New-Item -ItemType Directory -Force -Path (Split-Path $profilePath -Parent) | Out-Null
$already = (Test-Path $profilePath) -and
           (Select-String -Path $profilePath -Pattern 'SANDBOX_KITS' -Quiet)
if (-not $already) {
    Add-Content -Path $profilePath -Value "`$env:SANDBOX_KITS = '$SandboxKits'"
    Write-Output "wrote SANDBOX_KITS to $profilePath"
}

if (Test-Path $SandboxKits) {
    Write-Output "sandbox kits: $SandboxKits"
} else {
    Write-Output "sandbox kits: $SandboxKits (not there yet)"
    Write-Output "  git clone https://github.com/stlis_microsoft/sandbox-kits.git $SandboxKits"
}

# The sandbox.
#
# A MINIMUM rather than a pin, and rather than whatever is newest. Same value
# and same reasoning as Windows: the credential proxy is part of the sandbox
# runtime, so keeping its baseline current is a compatibility decision rather
# than an unrelated upgrade. Below it, upgrade. At or above it, leave alone.
$SbxLeast = [version]'0.42.1'

# Simpler than the Windows path, and worth saying why so nobody adds the
# missing half back. There, the public winget catalog can lag Docker's
# releases, so the payload carries a hash-pinned local manifest. Here the tap
# is Docker's own - it cannot lag itself - so brew is the whole story.
$brew = (Get-Command brew -EA SilentlyContinue).Source
if ($brew) {
    # Ask sbx itself rather than brew. brew knows what it installed, which is
    # not the same as what is on PATH, and the version that matters is the one
    # that runs.
    $have = $null
    $sbx = (Get-Command sbx -EA SilentlyContinue).Source
    if ($sbx) {
        $said = & $sbx version 2>&1
        if ($said -match '(\d+\.\d+\.\d+)') { $have = [version]$Matches[1] }
    }

    if ($have -and $have -ge $SbxLeast) {
        Write-Output "already installed: sbx $have"
    } else {
        $what = if ($have) { "upgrading sbx $have -> at least $SbxLeast" } else { 'installing sbx' }
        Write-Output $what

        # docker/tap is not an official tap, so brew refuses to load it until
        # it is trusted. Without this the install fails on a formula brew can
        # see and will not run, which reads as a broken tap rather than a
        # policy it is waiting on.
        & $brew trust docker/tap
        if ($LASTEXITCODE) { throw "brew could not trust docker/tap (exit $LASTEXITCODE)" }

        if ($have) { & $brew upgrade docker/tap/sbx }
        else       { & $brew install docker/tap/sbx }
        if ($LASTEXITCODE) { throw "brew could not install sbx (exit $LASTEXITCODE)" }

        # Re-ask, the way the Windows setup does: an installer that exits zero
        # has said the package landed, not that the thing on PATH is current.
        $sbx = (Get-Command sbx -EA SilentlyContinue).Source
        $said = if ($sbx) { & $sbx version 2>&1 } else { '' }
        if ($said -notmatch '(\d+\.\d+\.\d+)' -or [version]$Matches[1] -lt $SbxLeast) {
            throw "sbx installation completed but sbx does not report at least $SbxLeast"
        }
        Write-Output "installed sbx $($Matches[1])"
    }

    # Git Credential Manager.
    #
    # Not a nicety on this platform. AZDO_TOKEN's renewer is kind
    # git-credential, and it is that kind because the tenant behind
    # MicrosoftHackathon-DAI refuses the Azure CLI application - az returns
    # AADSTS50020 for an account GCM authenticates silently. macOS ships
    # osxkeychain, which answers with whatever was stored; a PAT travels as
    # Basic and the kit sends this token as a bearer, so the keychain helper
    # cannot stand in for it.
    #
    # Its installer sets credential.helper globally with an empty entry first,
    # which resets the list rather than stacking on osxkeychain. Verified after
    # install rather than assumed - two helpers both answering is how a stale
    # credential wins silently.
    if (Get-Command git-credential-manager -EA SilentlyContinue) {
        Write-Output 'already installed: git-credential-manager'
    } else {
        Write-Output 'installing git-credential-manager'
        & $brew install --cask git-credential-manager
        if ($LASTEXITCODE) {
            Write-Warning 'could not install git-credential-manager - it needs an admin password, so run it in a terminal: brew install --cask git-credential-manager'
        }
    }

    # A container builder, for `image.ps1` and nothing else.
    #
    # devnext does not want a builder. Exactly one moment does - building the
    # task image - and image.ps1 probes for a running engine at that moment and
    # says what to do when there is not one. So this installs the TOOLING and
    # deliberately does not start anything: `brew install colima docker` lays
    # down two binaries and no virtual machine, and `colima start` is the part
    # that costs a VM and several gigabytes.
    #
    # Declared here rather than typed by hand when someone first needs it,
    # because hand-installed state survives exactly until something rebuilds
    # from source. Started nowhere, because paying for a VM against the chance
    # of someday building an image is the wrong shape.
    if (Get-Command colima -EA SilentlyContinue) {
        Write-Output 'already installed: colima'
    } else {
        Write-Output 'installing colima and the docker CLI (no VM is created)'
        & $brew install colima docker
        if ($LASTEXITCODE) { Write-Warning 'could not install colima - see sandbox/RUNBOOK.md' }
    }

    # The two steps no installer can do, per sandbox/RUNBOOK.md. Printed rather
    # than attempted: `sbx login` opens a browser for Docker OAuth and `sbx
    # setup` probes the host, and both want a human who is present.
    Write-Output ''
    Write-Output 'Two one-time steps need you, and neither is automatable:'
    Write-Output '  sbx login       sign in to Docker'
    Write-Output '  sbx setup       detect host configuration (experimental)'
    Write-Output '  sbx diagnose    checks both, and whether a newer sbx exists'
} else {
    Write-Warning 'brew not found - install Docker Sandboxes by hand, see sandbox/RUNBOOK.md'
}
