#Requires -Version 5.1
param([Parameter(Mandatory = $true)][string]$Directory)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$data = [System.Windows.Forms.Clipboard]::GetDataObject()
if (-not $data) { exit 1 }

function Read-Bytes($v) {
    if ($v -is [byte[]]) { return $v }
    if ($v -is [System.IO.Stream]) {
        $ms = New-Object System.IO.MemoryStream
        $v.Position = 0
        $v.CopyTo($ms)
        return $ms.ToArray()
    }
    return $null
}

$name = $null
if ($data.GetDataPresent('HTML Format')) {
    $html = [string]$data.GetData('HTML Format')
    if ($html -match 'alt\s*=\s*"([^"]+)"')      { $name = $Matches[1] }
    elseif ($html -match "alt\s*=\s*'([^']+)'")  { $name = $Matches[1] }
    if (-not $name -and $html -match 'src\s*=\s*"([^"]+)"') {
        try {
            $leaf = [System.IO.Path]::GetFileNameWithoutExtension(([uri]$Matches[1]).AbsolutePath)
            if ($leaf) { $name = $leaf }
        } catch { }
    }
}
if ($name) {
    $name = [System.Net.WebUtility]::HtmlDecode($name)
    $name = ($name -replace '[^\w\-. ]', ' ').Trim()
    $name = ($name -replace '\s+', '-').ToLower().Trim('-.')
    if ($name.Length -gt 60) { $name = $name.Substring(0, 60).TrimEnd('-', '.') }
}
if (-not $name) { $name = 'pasted-' + (Get-Date -Format 'yyyyMMdd-HHmmss') }

$bytes = $null
$ext = $null
foreach ($f in @(@('PNG', '.png'), @('JFIF', '.jpg'), @('image/png', '.png'))) {
    if ($data.GetDataPresent($f[0])) {
        $bytes = Read-Bytes $data.GetData($f[0])
        if ($bytes) { $ext = $f[1]; break }
    }
}
if (-not $bytes) {
    $img = [System.Windows.Forms.Clipboard]::GetImage()
    if (-not $img) { exit 2 }
    $ms = New-Object System.IO.MemoryStream
    $img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $ext = '.png'
}

$path = Join-Path $Directory ($name + $ext)
$n = 2
while (Test-Path -LiteralPath $path) {
    $path = Join-Path $Directory ("$name-$n$ext")
    $n++
}
[System.IO.File]::WriteAllBytes($path, $bytes)
Write-Output $path
