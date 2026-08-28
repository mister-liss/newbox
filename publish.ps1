#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot '..\devnext'
if (-not (Test-Path (Join-Path $src 'newbox'))) { throw "devnext not found at $src" }
$src = (Resolve-Path $src).Path
$docs = Join-Path $PSScriptRoot 'docs'

if (Test-Path $docs) { Remove-Item $docs -Recurse -Force }
New-Item -ItemType Directory -Force -Path $docs | Out-Null

Copy-Item (Join-Path $src 'newbox\*') $docs -Recurse -Force

$glucDst = Join-Path $docs 'gluc\windows'
New-Item -ItemType Directory -Force -Path $glucDst | Out-Null
Copy-Item (Join-Path $src 'gluc\windows\*') $glucDst -Recurse -Force

New-Item -ItemType File -Path (Join-Path $docs '.nojekyll') -Force | Out-Null

& git -C $PSScriptRoot add -A
$changed = & git -C $PSScriptRoot status --porcelain
if (-not $changed) {
    Write-Output 'nothing to publish'
    return
}

& git -C $PSScriptRoot status --short
$head = (& git -C $src rev-parse --short HEAD).Trim()
& git -C $PSScriptRoot commit -m "publish from devnext $head" | Out-Null
& git -C $PSScriptRoot push
Write-Output 'published'
