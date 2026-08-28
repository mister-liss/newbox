#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$CommitPrefix = 'publish from devnext'

$src = Join-Path $PSScriptRoot '..\devnext'
if (-not (Test-Path (Join-Path $src 'newbox'))) { throw "devnext not found at $src" }
$src = (Resolve-Path $src).Path
$docs = Join-Path $PSScriptRoot 'docs'

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

Copy-Item (Join-Path $src 'newbox\*') $docs -Recurse -Force
$glucDst = Join-Path $docs 'gluc\windows'
New-Item -ItemType Directory -Force -Path $glucDst | Out-Null
Copy-Item (Join-Path $src 'gluc\windows\*') $glucDst -Recurse -Force

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
$head = (& git -C $src rev-parse --short HEAD).Trim()
& git -C $PSScriptRoot commit -m "$CommitPrefix $head" | Out-Null
& git -C $PSScriptRoot push
Write-Output 'published'
