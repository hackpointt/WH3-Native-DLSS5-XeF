param(
    [Parameter(Mandatory = $true)]
    [string]$GameDir
)

$ErrorActionPreference = 'Stop'
$GameDir = (Resolve-Path $GameDir).Path
$PackageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RuntimeDir = Join-Path $PackageRoot 'runtime'
$ConfigPath = Join-Path $PackageRoot 'config\OptiScaler.ini'

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path (Join-Path $GameDir 'Warhammer3.exe'))) {
    Fail "Warhammer3.exe was not found in: $GameDir"
}
if (-not (Test-Path (Join-Path $RuntimeDir 'OptiScaler.dll'))) {
    Fail "Package runtime is incomplete: runtime\OptiScaler.dll is missing."
}
if (-not (Test-Path $ConfigPath)) {
    Fail "Package config is incomplete: config\OptiScaler.ini is missing."
}

$reshade = Join-Path $GameDir 'ReShade64.dll'
if (-not (Test-Path $reshade)) {
    Fail "ReShade64.dll was not found in the WH3 game directory. Install/configure ReShade + ShortFuse first."
}

$shortFuse = Get-ChildItem -Path $GameDir -Filter 'dlss5-feed.addon64' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $shortFuse) {
    Fail "dlss5-feed.addon64 was not found under the WH3 game directory. Install/configure ShortFuse first."
}

Write-Host "WH3 directory: $GameDir"
Write-Host "ReShade:       $reshade"
Write-Host "ShortFuse:     $($shortFuse.FullName)"
Write-Host ""
Write-Host "IMPORTANT: NVIDIA Smooth Motion and RTSS should be disabled for RC1 validation." -ForegroundColor Yellow
Write-Host ""

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $GameDir "_WH3-DLSS5-XeFG-RC1-backup\$stamp"
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$targets = @(
    @{ Rel = 'dxgi.dll'; Kind = 'File' },
    @{ Rel = 'OptiScaler.ini'; Kind = 'File' },
    @{ Rel = 'OptiScaler'; Kind = 'Directory' }
)

$records = @()
foreach ($target in $targets) {
    $dst = Join-Path $GameDir $target.Rel
    $exists = Test-Path $dst
    $records += [pscustomobject]@{ path = $target.Rel; existed = $exists }
    if ($exists) {
        $backupDst = Join-Path $backupRoot $target.Rel
        if ($target.Kind -eq 'Directory') {
            New-Item -ItemType Directory -Force -Path (Split-Path $backupDst -Parent) | Out-Null
            Copy-Item -Path $dst -Destination $backupDst -Recurse -Force
        }
        else {
            New-Item -ItemType Directory -Force -Path (Split-Path $backupDst -Parent) | Out-Null
            Copy-Item -Path $dst -Destination $backupDst -Force
        }
    }
}

# Install dependency directory first.
$dstOpti = Join-Path $GameDir 'OptiScaler'
if (Test-Path $dstOpti) { Remove-Item $dstOpti -Recurse -Force }
Copy-Item -Path (Join-Path $RuntimeDir 'OptiScaler') -Destination $dstOpti -Recurse -Force

# OptiScaler is used as the DXGI proxy in the validated WH3 path.
Copy-Item -Path (Join-Path $RuntimeDir 'OptiScaler.dll') -Destination (Join-Path $GameDir 'dxgi.dll') -Force
Copy-Item -Path $ConfigPath -Destination (Join-Path $GameDir 'OptiScaler.ini') -Force

$installRecord = [pscustomobject]@{
    package = 'WH3 Native DLSS5 -> XeFG RC1'
    implementation = 'V15'
    installed_at = (Get-Date).ToString('o')
    backup_dir = $backupRoot
    targets = $records
}
$recordPath = Join-Path $GameDir '.wh3-dlss5-xefg-rc1-install.json'
$installRecord | ConvertTo-Json -Depth 5 | Set-Content -Path $recordPath -Encoding UTF8

Write-Host ""
Write-Host "Installed WH3 Native DLSS5 -> XeFG RC1." -ForegroundColor Green
Write-Host "Backup: $backupRoot"
Write-Host ""
Write-Host "First run:" -ForegroundColor Cyan
Write-Host "  1. Enter a 3D battle before enabling FG."
Write-Host "  2. Open OptiScaler."
Write-Host "  3. Enable Frame Generation (XeFG) -> Active."
Write-Host "  4. Verify DETECTED / ACTIVE / READY / ACTIVE."
