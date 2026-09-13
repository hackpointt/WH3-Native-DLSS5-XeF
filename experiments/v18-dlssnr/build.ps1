$ErrorActionPreference = 'Stop'

$forkCommit = '973761621353b99bee3dc7d4bb27b117fef2644f'

function Assert-NativeSuccess([string] $step) {
    if ($LASTEXITCODE -ne 0) { throw "$step failed with exit code $LASTEXITCODE" }
}

Write-Host 'Cloning OptiScaler_DLSSNR fork...'
git clone --recursive https://github.com/Dagherbou/OptiScaler_DLSSNR.git optiscaler-src
Assert-NativeSuccess 'git clone'
Set-Location optiscaler-src
git checkout $forkCommit
Assert-NativeSuccess 'git checkout'
git submodule update --init --recursive
Assert-NativeSuccess 'git submodule update'
Set-Location ..

Write-Host 'Applying fork-aware WH3 native-DLSS + XeFG integration...'
python .\experiments\v18-dlssnr\apply_v18_dlssnr.py
Assert-NativeSuccess 'V18 DLSSNR transform'

Write-Host 'Applying validated V17 post-FG ReShade runtime experiment...'
python .\experiments\v17\apply_v17.py
Assert-NativeSuccess 'V17 ReShade transform'

Write-Host 'Enabling DLSS Neural Rendering in packaged default configuration...'
$iniPath = 'optiscaler-src\OptiScaler.ini'
$ini = [System.IO.File]::ReadAllText($iniPath)
if ($ini -notmatch '(?m)^\[DlssNr\]$') { throw '[DlssNr] section missing from fork OptiScaler.ini' }
$ini2 = [regex]::Replace($ini, '(?ms)(^\[DlssNr\]\s*.*?^Enabled=)auto\s*$', '${1}true', 1)
if ($ini2 -eq $ini) { throw 'Failed to switch [DlssNr] Enabled=auto to true' }
[System.IO.File]::WriteAllText($iniPath, $ini2, (New-Object System.Text.UTF8Encoding($false)))

Set-Location optiscaler-src
Write-Host 'Checking integration invariants...'
$ngx = Get-Content 'OptiScaler\inputs\NVNGX_DLSS_Dx12.cpp' -Raw
if ($ngx -notmatch 'DlssNr::EvaluateAfterUpscale') { throw 'DLSSNR EvaluateAfterUpscale hook was lost' }
if ($ngx -notmatch 'WH3 native DLSS bridge: private shadow active') { throw 'WH3 private bridge was lost' }
if ($ngx -notmatch 'WH3 native DLSS passthrough:') { throw 'WH3 native passthrough was lost' }
if ($ngx -notmatch 'wh3NativeDlssLastSuccessTick\.store') { throw 'Native DLSS heartbeat was lost' }

# Critical invariant: the native handle path must call Neural Rendering before returning.
$nativeStart = $ngx.IndexOf('// Native DLSS passthrough', $ngx.IndexOf('NVSDK_NGX_D3D12_EvaluateFeature'))
$nativeEnd = $ngx.IndexOf('// DLSSG replacements passthrough', $nativeStart)
if ($nativeStart -lt 0 -or $nativeEnd -lt 0) { throw 'Could not isolate native Evaluate block' }
$nativeBlock = $ngx.Substring($nativeStart, $nativeEnd - $nativeStart)
if ($nativeBlock -notmatch 'DlssNr::EvaluateAfterUpscale') {
    throw 'Native WH3 passthrough bypasses DLSSNR; EvaluateAfterUpscale must run before return'
}
if ($nativeBlock.IndexOf('D3D12_EvaluateFeature()(InCmdList') -gt $nativeBlock.IndexOf('DlssNr::EvaluateAfterUpscale')) {
    throw 'DLSSNR ordering invalid: Neural Rendering appears before native NVIDIA DLSS evaluate'
}

$menu = Get-Content 'OptiScaler\menu\menu_common.cpp' -Raw
if ($menu -notmatch 'WH3 native DLSS5 NR -> XeFG bridge') { throw 'Five-state WH3 status panel missing' }
if ($menu -notmatch 'DlssNr::IsRunning') { throw 'Neural Rendering live status missing' }

$xefg = Get-Content 'OptiScaler\framegen\xefg\XeFG_Dx12.cpp' -Raw
if ($xefg -notmatch 'WH3 XeFG compatibility: removed DXGI_USAGE_UNORDERED_ACCESS') { throw 'WH3 XeFG UAV fix missing' }
if ($xefg -notmatch 'xefgFullscreenDesc') { throw 'WH3 XeFG windowed fullscreen-desc fix missing' }

git diff --check
Assert-NativeSuccess 'git diff --check'
git diff --binary HEAD | Out-File -Encoding utf8 '..\WH3-v18-dlssnr-xefg.patch'

Write-Host 'Building Release x64...'
msbuild /m /p:Configuration=Release . /verbosity:minimal
Assert-NativeSuccess 'MSBuild'
Set-Location ..

$dll = 'optiscaler-src\x64\Release\a\OptiScaler.dll'
if (-not (Test-Path $dll)) { throw 'Compiled OptiScaler.dll missing' }
$ascii = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($dll))
foreach ($marker in @(
    'WH3 native DLSS passthrough:',
    'WH3 native DLSS bridge: private shadow active',
    'WH3 XeFG compatibility:',
    'WH3 ReShade post-FG: armed by Home',
    'WH3 native DLSS5 NR -> XeFG bridge',
    'Neural Rendering:'
)) {
    if (-not $ascii.Contains($marker)) { throw "Missing compiled marker: $marker" }
}

New-Item -ItemType Directory -Force -Path package | Out-Null
Copy-Item -Recurse -Force 'optiscaler-src\x64\Release\a\*' package\
Copy-Item -Force 'WH3-v18-dlssnr-xefg.patch' package\
Copy-Item -Force 'optiscaler-src\OptiScaler.ini' package\OptiScaler-DLSSNR-WH3.ini

# The forwarder is redistributable source/output from the fork and should accompany the build.
$forwarder = Get-ChildItem -Path 'optiscaler-src' -Filter 'nvngx.dll_dlssnr.dll' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $forwarder) {
    Copy-Item -Force $forwarder.FullName package\nvngx.dll_dlssnr.dll
    Write-Host "Packaged DLSSNR forwarder from $($forwarder.FullName)"
} else {
    Write-Warning 'nvngx.dll_dlssnr.dll was not found in source build output; runtime test will need the forwarder from Dagherbou v0.2.0 package.'
}

@'
WH3 Native DLSS5 Neural Rendering -> XeFG V18 integration experiment

Source bases:
- Dagherbou/OptiScaler_DLSSNR: 973761621353b99bee3dc7d4bb27b117fef2644f (v0.2.0-dlssnr source)
- Fork-aware port of the validated WH3 V15 native-DLSS/XeFG compatibility logic
- WH3 V17 post-FG ReShade UI runtime

Render order under test:
DLSS5-Feeder -> native NVIDIA D3D12 DLSS -> DLSS Neural Rendering -> private Depth/MV bridge -> XeFG -> post-FG ReShade UI

Safety invariants:
- ShortFuse/DLSS5-Feeder keeps the real native NGX handle and result.
- No second upscaler is created for the WH3 Feeder feature.
- The metadata shadow is never published as State::currentFeature.
- DlssNr::EvaluateAfterUpscale executes only after a successful native NVIDIA DLSS Evaluate.
- V17 UI remains lazy: the explicit final-presenter ReShade runtime is created only after Home is pressed.

Runtime prerequisites:
- nvngx_dlssnr.dll must be supplied by the user; it is NVIDIA software and is NOT redistributed here.
- nvngx.dll_dlssnr.dll from the DLSSNR fork must be present.
- [DlssNr] Enabled=true (the included OptiScaler-DLSSNR-WH3.ini has this enabled).
- RTSS and NVIDIA Smooth Motion OFF during isolation testing.

Expected five-state validation:
- DLSS5 feeder: DETECTED
- Native DLSS NGX: ACTIVE
- Neural Rendering: ACTIVE
- Depth + MV: READY
- XeFG: ACTIVE

Experimental branch only. main and v0.1.0-rc1 remain unchanged.
'@ | Set-Content -Encoding UTF8 package\README-V18-DLSSNR-TEST.txt
