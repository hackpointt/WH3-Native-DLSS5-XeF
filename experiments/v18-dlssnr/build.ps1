$ErrorActionPreference = 'Stop'

$forkCommit = '973761621353b99bee3dc7d4bb27b117fef2644f'

function Assert-NativeSuccess([string] $step) {
    if ($LASTEXITCODE -ne 0) { throw "$step failed with exit code $LASTEXITCODE" }
}

function Set-IniValue([string] $text, [string] $section, [string] $key, [string] $value) {
    $sec = [regex]::Escape($section)
    $k = [regex]::Escape($key)
    $pattern = "(?ms)(^\[$sec\]\r?\n.*?^$k=)[^\r\n]*"
    $rx = [regex]::new($pattern)
    $m = $rx.Match($text)
    if (-not $m.Success) { throw "Missing INI key [$section] $key" }
    return $rx.Replace($text, { param($match) $match.Groups[1].Value + $value }, 1)
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

Write-Host 'Preparing WH3 V18 configuration...'
$iniPath = 'optiscaler-src\OptiScaler.ini'
$ini = [System.IO.File]::ReadAllText($iniPath)
$ini = Set-IniValue $ini 'DlssNr' 'Enabled' 'true'
$ini = Set-IniValue $ini 'FrameGen' 'Enabled' 'false'
$ini = Set-IniValue $ini 'FrameGen' 'FGInput' 'upscaler'
$ini = Set-IniValue $ini 'FrameGen' 'FGOutput' 'xefg'
$ini = Set-IniValue $ini 'Inputs' 'EnableDlssInputs' 'true'
$ini = Set-IniValue $ini 'Plugins' 'LoadReshade' 'true'
$ini = Set-IniValue $ini 'Log' 'LogToFile' 'true'
$ini = Set-IniValue $ini 'Log' 'LogLevel' '2'
[System.IO.File]::WriteAllText($iniPath, $ini, (New-Object System.Text.UTF8Encoding($false)))

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
if ($nativeBlock -notmatch 'WH3 NR trace #') { throw 'Sparse native-to-NR ordering trace missing' }

$nr = Get-Content 'OptiScaler\shaders\dlssnr\DlssNr_Dx12.cpp' -Raw
if ($nr -notmatch 'backend forwarder, feature18 result') { throw 'Forwarder feature-18 result trace missing' }
if ($nr -notmatch 'backend proxy, feature18 result') { throw 'Proxy feature-18 result trace missing' }

$menu = Get-Content 'OptiScaler\menu\menu_common.cpp' -Raw
if ($menu -notmatch 'WH3 native DLSS5 NR -> XeFG bridge') { throw 'Five-state WH3 status panel missing' }
if ($menu -notmatch 'DlssNr::IsRunning') { throw 'Neural Rendering live status missing' }

$xefg = Get-Content 'OptiScaler\framegen\xefg\XeFG_Dx12.cpp' -Raw
if ($xefg -notmatch 'WH3 XeFG compatibility: removed DXGI_USAGE_UNORDERED_ACCESS') { throw 'WH3 XeFG UAV fix missing' }
if ($xefg -notmatch 'xefgFullscreenDesc') { throw 'WH3 XeFG windowed fullscreen-desc fix missing' }
if ($xefg -notmatch 'WH3 XeFG trace #') { throw 'Sparse XeFG success trace missing' }

$configText = Get-Content 'OptiScaler.ini' -Raw
foreach ($required in @('Enabled=true', 'FGInput=upscaler', 'FGOutput=xefg', 'EnableDlssInputs=true', 'LoadReshade=true', 'LogToFile=true', 'LogLevel=2')) {
    if ($configText -notmatch [regex]::Escape($required)) { throw "WH3 packaged config missing $required" }
}

git diff --check
Assert-NativeSuccess 'git diff --check'
git diff --binary HEAD | Out-File -Encoding utf8 '..\WH3-v18.1-dlssnr-diagnostic.patch'

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
    'Neural Rendering:',
    'WH3 NR trace #',
    'backend forwarder, feature18 result',
    'WH3 XeFG trace #'
)) {
    if (-not $ascii.Contains($marker)) { throw "Missing compiled marker: $marker" }
}

New-Item -ItemType Directory -Force -Path package | Out-Null
Copy-Item -Recurse -Force 'optiscaler-src\x64\Release\a\*' package\
Copy-Item -Force 'WH3-v18.1-dlssnr-diagnostic.patch' package\
Copy-Item -Force 'optiscaler-src\OptiScaler.ini' package\OptiScaler-DLSSNR-WH3.ini

# The forwarder is built from the open-source fork and accompanies this experiment.
$forwarder = Get-ChildItem -Path 'optiscaler-src' -Filter 'nvngx.dll_dlssnr.dll' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $forwarder) {
    Copy-Item -Force $forwarder.FullName package\nvngx.dll_dlssnr.dll
    Write-Host "Packaged DLSSNR forwarder from $($forwarder.FullName)"
} else {
    throw 'nvngx.dll_dlssnr.dll was not produced by the DLSSNR fork build'
}

@'
WH3 Native DLSS5 Neural Rendering -> XeFG V18.1 diagnostic experiment

Source bases:
- Dagherbou/OptiScaler_DLSSNR: 973761621353b99bee3dc7d4bb27b117fef2644f (v0.2.0-dlssnr source)
- Fork-aware port of the validated WH3 V15 native-DLSS/XeFG compatibility logic
- WH3 V17 post-FG ReShade UI runtime

Render order under test:
DLSS5-Feeder -> native NVIDIA D3D12 DLSS -> DLSS Neural Rendering -> XeFG -> post-FG ReShade UI
The private WH3 shadow only supplies Depth/MV metadata/resources to OptiFG; it never evaluates an upscaler.

Safety invariants:
- ShortFuse/DLSS5-Feeder keeps the real native NGX handle and result.
- No second upscaler is created for the WH3 Feeder feature.
- The metadata shadow is never published as State::currentFeature.
- DlssNr::EvaluateAfterUpscale executes only after a successful native NVIDIA DLSS Evaluate.
- V17 UI remains lazy: the explicit final-presenter ReShade runtime is created only after Home is pressed.

Packaged OptiScaler.ini is WH3-ready:
- [DlssNr] Enabled=true
- [FrameGen] Enabled=false (start safe; turn Active on in OptiScaler after entering a 3D scene)
- FGInput=upscaler
- FGOutput=xefg
- [Inputs] EnableDlssInputs=true
- [Plugins] LoadReshade=true
- [Log] LogToFile=true, LogLevel=2 (sparse INFO diagnostics; no per-frame DEBUG flood)

V18.1 diagnostic markers (first 10, then every 300; all NR failures remain visible):
- WH3 NR trace: native DLSS success -> EvaluateAfterUpscale enter/return
- WH3 NR evaluate: selected backend + real feature-18 result
- WH3 XeFG trace: Dispatch Ok

Runtime prerequisites:
- nvngx_dlssnr.dll must be supplied by the user; it is NVIDIA software and is NOT redistributed here.
- nvngx.dll_dlssnr.dll is included from this source build.
- RTSS and NVIDIA Smooth Motion OFF during isolation testing.

Expected five-state validation after enabling FG:
- DLSS5 feeder: DETECTED
- Native DLSS NGX: ACTIVE
- Neural Rendering: ACTIVE
- Depth + MV: READY
- XeFG: ACTIVE

Instrumentation-only experiment. Rendering behavior is unchanged from V18.
Experimental branch only. main and v0.1.0-rc1 remain unchanged.
'@ | Set-Content -Encoding UTF8 package\README-V18-DLSSNR-TEST.txt
