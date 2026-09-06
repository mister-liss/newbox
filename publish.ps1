#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$CommitPrefix = 'publish'

# newbox publishes itself, and carries devnext if devnext is here.
#
# newbox is its own product: a script that prepares a machine the way I want it,
# with vim, a font, a contrast theme, a window geometry and a set of git
# excludes. It offers to install devnext at the end because I want that too -
# but a box without devnext is still a box worth having, and this publishes
# fine without it.
#
# So devnext is consumed, never obeyed. It exposes one entry point that builds
# and lays out what it offers; what that contains, how many layers it has and
# how it is built are its business. Adding an area over there does not edit
# anything here, which is exactly what used to happen.

$src  = Join-Path $PSScriptRoot 'src'
$docs = Join-Path $PSScriptRoot 'docs'
if (-not (Test-Path $src)) { throw "newbox's own source is missing at $src" }

& git -C $PSScriptRoot fetch -q origin
$incoming = @(& git -C $PSScriptRoot log --format='%h %an %s' HEAD..origin/main)
if ($incoming) {
    $foreign = @($incoming | Where-Object { $_ -notmatch [regex]::Escape($CommitPrefix) })
    if ($foreign) {
        Write-Host ''
        Write-Host 'Commits on origin that publish did not make:' -ForegroundColor Yellow
        $foreign | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        Write-Host 'GitHub writes CNAME here when the custom domain changes. CNAME is preserved;' -ForegroundColor Yellow
        Write-Host 'anything else it added under docs/ will be wiped by this publish.' -ForegroundColor Yellow
        Write-Host ''
    }
    & git -C $PSScriptRoot pull --ff-only -q
}

$cnamePath = Join-Path $docs 'CNAME'
$cname = if (Test-Path $cnamePath) { [System.IO.File]::ReadAllBytes($cnamePath) } else { $null }

if (Test-Path $docs) { Remove-Item $docs -Recurse -Force }
New-Item -ItemType Directory -Force -Path $docs | Out-Null

# newbox's own files sit at the root of the site, because the address people
# are given is the bare one.
Copy-Item (Join-Path $src '*') $docs -Recurse -Force
Write-Output 'published newbox'

# devnext, if it is beside us. Its payload lands under its own layer names,
# which are its to choose.
$pack = Join-Path $PSScriptRoot '..\devnext\tools\pack.ps1'
if (Test-Path $pack) {
    $staged = Join-Path ([System.IO.Path]::GetTempPath()) ('devnext-payload-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        & $pack -Out $staged
        Copy-Item (Join-Path $staged '*') $docs -Recurse -Force
    } finally {
        if (Test-Path $staged) { Remove-Item $staged -Recurse -Force -EA SilentlyContinue }
    }
} else {
    Write-Warning "devnext not found at $pack - publishing newbox alone"
}

if ($cname) { [System.IO.File]::WriteAllBytes($cnamePath, $cname) }

if ($cname) {
    $domain = [System.Text.Encoding]::UTF8.GetString($cname).Trim()
    if ($domain -notmatch '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$') {
        throw @"
docs/CNAME does not contain a single hostname. Got:

$domain

That file is written by GitHub when you set a custom domain, and publish reads
it to know the site's address. Either its format has changed, or something else
wrote to it. Fix docs/CNAME, or remove the custom domain in Settings > Pages and
delete the file, and publish will use the github.io address instead.
"@
    }
    $url = "https://$domain"
} else {
    $remote = (& git -C $PSScriptRoot remote get-url origin).Trim()
    if ($remote -notmatch '[:/]([^/:]+)/([^/]+?)(\.git)?$') { throw "cannot parse remote: $remote" }
    $owner = $Matches[1]
    $repo  = $Matches[2]
    $url = if ($repo -ieq "$owner.github.io") { "https://$owner.github.io" } else { "https://$owner.github.io/$repo" }
}

# The site's address is newbox's to know, so rendering happens here rather than
# wherever a template came from - including devnext's, which needs the feed URL
# to tell anyone where to fetch the next piece from.
$hit = 0
Get-ChildItem $docs -Recurse -File -Filter '*.tmplt.*' | ForEach-Object {
    $t = [System.IO.File]::ReadAllText($_.FullName)
    if (-not $t.Contains('@@URL@@')) {
        throw "$($_.Name) is named as a template but contains no @@URL@@"
    }
    $dest = Join-Path $_.DirectoryName ($_.Name -replace '\.tmplt\.', '.')
    [System.IO.File]::WriteAllText($dest, $t.Replace('@@URL@@', $url))
    Remove-Item $_.FullName -Force
    $hit++
}
Write-Output "site url $url  ($hit templates rendered)"

New-Item -ItemType File -Path (Join-Path $docs '.nojekyll') -Force | Out-Null

& git -C $PSScriptRoot add -A
$changed = & git -C $PSScriptRoot status --porcelain
if (-not $changed) {
    Write-Output 'nothing to publish'
    return
}

& git -C $PSScriptRoot status --short

# What went out, read back from the payload rather than asked of devnext's
# git. The version files are the record either way, and this keeps newbox from
# needing to know devnext is a repository at all.
$carried = Get-ChildItem $docs -Recurse -File -Filter 'version.txt' |
    ForEach-Object { "$($_.Directory.Parent.Name) $((Get-Content $_.FullName -Raw).Trim())" } |
    Sort-Object -Unique
$message = if ($carried) { "$CommitPrefix with $($carried -join ', ')" } else { "$CommitPrefix" }

& git -C $PSScriptRoot commit -m $message | Out-Null
& git -C $PSScriptRoot push
Write-Output 'published'
