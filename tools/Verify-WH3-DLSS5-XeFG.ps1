param(
    [Parameter(Mandatory = $true)]
    [string]$GameDir
)

$ErrorActionPreference = 'Stop'
$GameDir = (Resolve-Path $GameDir).Path

$checks = @(
    @{ Name = 'Warhammer3.exe'; Path = (Join-Path $GameDir 'Warhammer3.exe') },
    @{ Name = 'dxgi.dll (RC1 proxy expected)'; Path = (Join-Path $GameDir 'dxgi.dll') },
    @{ Name = 'OptiScaler.ini'; Path = (Join-Path $GameDir 'OptiScaler.ini') },
    @{ Name = 'OptiScaler runtime dir'; Path = (Join-Path $GameDir 'OptiScaler') },
    @{ Name = 'ReShade64.dll'; Path = (Join-Path $GameDir 'ReShade64.dll') }
)

foreach ($c in $checks) {
    $ok = Test-Path $c.Path
    $status = if ($ok) { 'OK' } else { 'MISSING' }
    $color = if ($ok) { 'Green' } else { 'Red' }
    Write-Host ("{0,-34} {1}" -f $c.Name, $status) -ForegroundColor $color
}

$shortFuse = Get-ChildItem -Path $GameDir -Filter 'dlss5-feed.addon64' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($shortFuse) {
    Write-Host ("{0,-34} {1}" -f 'dlss5-feed.addon64', 'FOUND') -ForegroundColor Green
    Write-Host "  $($shortFuse.FullName)"
} else {
    Write-Host ("{0,-34} {1}" -f 'dlss5-feed.addon64', 'MISSING') -ForegroundColor Red
}

$ini = Join-Path $GameDir 'OptiScaler.ini'
if (Test-Path $ini) {
    $text = Get-Content $ini -Raw
    Write-Host ""
    foreach ($needle in @('FGInput=upscaler','FGOutput=xefg','EnableDlssInputs=true','LoadReshade=true')) {
        $ok = $text -match [regex]::Escape($needle)
        $color = if ($ok) { 'Green' } else { 'Yellow' }
        $state = if ($ok) { 'OK' } else { 'CHECK' }
        Write-Host ("{0,-34} {1}" -f $needle, $state) -ForegroundColor $color
    }
}

Write-Host ""
Write-Host "Runtime truth still comes from the in-game four-state panel:" -ForegroundColor Cyan
Write-Host "  DLSS5 feeder:     DETECTED"
Write-Host "  Native DLSS NGX:  ACTIVE"
Write-Host "  Depth + MV:       READY"
Write-Host "  XeFG:             ACTIVE"
