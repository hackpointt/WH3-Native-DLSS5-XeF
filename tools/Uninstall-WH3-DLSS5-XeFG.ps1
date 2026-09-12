param(
    [Parameter(Mandatory = $true)]
    [string]$GameDir
)

$ErrorActionPreference = 'Stop'
$GameDir = (Resolve-Path $GameDir).Path
$recordPath = Join-Path $GameDir '.wh3-dlss5-xefg-rc1-install.json'

if (-not (Test-Path $recordPath)) {
    Write-Host "No RC1 install record was found at $recordPath" -ForegroundColor Yellow
    Write-Host "Nothing was changed. For a manual install, restore your own backups manually."
    exit 1
}

$record = Get-Content $recordPath -Raw | ConvertFrom-Json
$backupRoot = $record.backup_dir
if (-not (Test-Path $backupRoot)) {
    Write-Host "Backup directory is missing: $backupRoot" -ForegroundColor Red
    exit 1
}

foreach ($target in $record.targets) {
    $dst = Join-Path $GameDir $target.path
    if (Test-Path $dst) {
        Remove-Item $dst -Recurse -Force
    }

    if ($target.existed) {
        $backupSrc = Join-Path $backupRoot $target.path
        if (-not (Test-Path $backupSrc)) {
            Write-Host "Missing backup item: $backupSrc" -ForegroundColor Red
            exit 1
        }
        Copy-Item -Path $backupSrc -Destination $dst -Recurse -Force
    }
}

Remove-Item $recordPath -Force
Write-Host "RC1 removed and previous OptiScaler/DXGI files restored." -ForegroundColor Green
Write-Host "Backup retained at: $backupRoot"
