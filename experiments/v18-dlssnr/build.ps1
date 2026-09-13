$ErrorActionPreference = 'Stop'

$forkCommit = '973761621353b99bee3dc7d4bb27b117fef2644f'

Write-Host 'Cloning OptiScaler_DLSSNR fork...'
git clone --recursive https://github.com/Dagherbou/OptiScaler_DLSSNR.git optiscaler-src
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Set-Location optiscaler-src
git checkout $forkCommit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
git submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Set-Location ..

Write-Host 'Applying validated WH3 V15 patch with three-way merge...'
$patchText = [System.IO.File]::ReadAllText('source\WH3-native-DLSS5-XeFG.patch')
if ($patchText.Length -gt 0 -and [int]$patchText[0] -eq 0xFEFF) { $patchText = $patchText.Substring(1) }
[System.IO.File]::WriteAllText('wh3-v15.patch', $patchText, (New-Object System.Text.UTF8Encoding($false)))
Set-Location optiscaler-src
git apply --3way --recount ..\wh3-v15.patch
if ($LASTEXITCODE -ne 0) {
    Write-Host 'V15 patch did not merge cleanly into DLSSNR fork.'
    git status --short
    git diff --cc
    exit $LASTEXITCODE
}
Set-Location ..

Write-Host 'Applying validated V17 post-FG ReShade runtime experiment...'
python .\experiments\v17\apply_v17.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Enabling DLSS Neural Rendering in packaged default configuration...'
$iniPath = 'optiscaler-src\OptiScaler.ini'
$ini = [System.IO.File]::ReadAllText($iniPath)
if ($ini -notmatch '(?m)^\[DlssNr\]$') { throw '[DlssNr] section missing from fork OptiScaler.ini' }
$ini = [regex]::Replace($ini, '(?ms)(^\[DlssNr\]\s*.*?^Enabled=)auto\s*$', '${1}true', 1)
[System.IO.File]::WriteAllText($iniPath, $ini, (New-Object System.Text.UTF8Encoding($false)))

Set-Location optiscaler-src
Write-Host 'Checking merge invariants...'
$ngx = Get-Content 'OptiScaler\inputs\NVNGX_DLSS_Dx12.cpp' -Raw
if ($ngx -notmatch 'DlssNr::EvaluateAfterUpscale') { throw 'DLSSNR EvaluateAfterUpscale hook was lost' }
if ($ngx -notmatch 'WH3 native DLSS bridge: private shadow active') { throw 'WH3 private bridge was lost' }
if ($ngx -notmatch 'WH3 native DLSS passthrough:') { throw 'WH3 native passthrough was lost' }

# Critical invariant: the fork must still run Neural Rendering after a successful native NGX evaluate.
# A plain V15 port is not enough if it returns before this call.
$nativeBlock = [regex]::Match($ngx, '(?s)if \(handleId < DLSS_MOD_ID_OFFSET\).*?return result;')
if (-not $nativeBlock.Success) { throw 'Could not locate native DLSS evaluate block' }
if ($nativeBlock.Value -notmatch 'DlssNr::EvaluateAfterUpscale') {
    throw 'WH3 native passthrough currently bypasses DLSSNR; integration must preserve EvaluateAfterUpscale before return'
}

git diff --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
git diff --binary HEAD | Out-File -Encoding utf8 '..\WH3-v18-dlssnr-xefg.patch'

Write-Host 'Building Release x64...'
msbuild /m /p:Configuration=Release . /verbosity:minimal
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Set-Location ..

$dll = 'optiscaler-src\x64\Release\a\OptiScaler.dll'
if (-not (Test-Path $dll)) { throw 'Compiled OptiScaler.dll missing' }
$ascii = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($dll))
foreach ($marker in @(
    'WH3 native DLSS passthrough:',
    'WH3 native DLSS bridge: private shadow active',
    'WH3 XeFG compatibility:',
    'WH3 ReShade post-FG: armed by Home'
)) {
    if (-not $ascii.Contains($marker)) { throw "Missing marker: $marker" }
}

New-Item -ItemType Directory -Force -Path package | Out-Null
Copy-Item -Recurse -Force 'optiscaler-src\x64\Release\a\*' package\
Copy-Item -Force 'WH3-v18-dlssnr-xefg.patch' package\
Copy-Item -Force 'optiscaler-src\OptiScaler.ini' package\OptiScaler-DLSSNR-WH3.ini

@'
WH3 Native DLSS5 Neural Rendering -> XeFG V18 integration experiment

Source bases:
- Dagherbou/OptiScaler_DLSSNR: 973761621353b99bee3dc7d4bb27b117fef2644f (v0.2.0-dlssnr source)
- WH3 V15 native-DLSS/XeFG compatibility patch
- WH3 V17 post-FG ReShade UI runtime

Goals:
1. Keep ShortFuse/DLSS5-Feeder native D3D12 NGX calls alive.
2. Preserve Dagherbou fork's DlssNr::EvaluateAfterUpscale pass after the native DLSS result.
3. Feed Depth/MV privately into OptiFG without publishing the metadata shadow as currentFeature.
4. Keep XeFG active.
5. Keep the V17 ReShade UI visible on the final XeFG presenter.

Runtime prerequisites:
- nvngx_dlssnr.dll must be supplied by the user; it is not redistributed here.
- nvngx.dll_dlssnr.dll from the DLSSNR fork package/build must be present.
- [DlssNr] Enabled=true.
- RTSS and NVIDIA Smooth Motion should remain off during isolation testing.

Expected validation state:
- DLSS5 feeder: DETECTED
- Native DLSS NGX: ACTIVE
- Neural Rendering: ACTIVE / model running
- Depth + MV: READY
- XeFG: ACTIVE

Experimental branch only. main and v0.1.0-rc1 remain unchanged.
'@ | Set-Content -Encoding UTF8 package\README-V18-DLSSNR-TEST.txt
