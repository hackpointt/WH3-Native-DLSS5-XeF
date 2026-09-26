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
    if (-not $rx.IsMatch($text)) { throw "Missing INI key [$section] $key" }
    return $rx.Replace($text, { param($match) $match.Groups[1].Value + $value }, 1)
}

git clone --recursive https://github.com/Dagherbou/OptiScaler_DLSSNR.git optiscaler-src
Assert-NativeSuccess 'git clone'
Set-Location optiscaler-src
git checkout $forkCommit
Assert-NativeSuccess 'git checkout'
git submodule update --init --recursive
Assert-NativeSuccess 'git submodule update'
git apply --check '..\experiments\mfg-dlssnr\wh3-dlssnr-mfg.patch'
Assert-NativeSuccess 'git apply --check'
git apply '..\experiments\mfg-dlssnr\wh3-dlssnr-mfg.patch'
Assert-NativeSuccess 'git apply'
git diff --check
Assert-NativeSuccess 'git diff --check'

$ngx = Get-Content 'OptiScaler\inputs\NVNGX_DLSS_Dx12.cpp' -Raw
$nativeStart = $ngx.IndexOf('// Native DLSS passthrough', $ngx.IndexOf('NVSDK_NGX_D3D12_EvaluateFeature'))
$nativeEnd = $ngx.IndexOf('// DLSSG replacements passthrough', $nativeStart)
if ($nativeStart -lt 0 -or $nativeEnd -lt 0) { throw 'Native DLSS evaluate block missing' }
$nativeBlock = $ngx.Substring($nativeStart, $nativeEnd - $nativeStart)
if ($nativeBlock -notmatch 'DlssNr::EvaluateAfterUpscale') { throw 'Neural rendering hook missing from native DLSS path' }
if ($nativeBlock.IndexOf('D3D12_EvaluateFeature()(InCmdList') -gt $nativeBlock.IndexOf('DlssNr::EvaluateAfterUpscale')) { throw 'Neural rendering runs before native DLSS' }
if ($nativeBlock -notmatch 'wh3NativeDlssLastSuccessTick\.store') { throw 'Native DLSS success heartbeat missing' }
$sl = Get-Content 'OptiScaler\proxies\Streamline_Proxy.h' -Raw
if ($sl -notmatch 'Streamline load now permitted') { throw 'Deferred Streamline load missing' }
$interop = Get-Content 'OptiScaler\with_dx12\dx11_with_dx12_sc.cpp' -Raw
if ($interop -notmatch 'WH3 Feeder visibility probe #') { throw 'Post-Feeder neural render recapture missing' }
if ($interop -notmatch 'WH3 DLSSG two-stage') { throw 'Two-stage DLSSG transition missing' }
$menu = Get-Content 'OptiScaler\menu\menu_common.cpp' -Raw
if ($menu -notmatch 'Neural Rendering:') { throw 'Neural Rendering status missing' }

$iniPath = (Resolve-Path 'OptiScaler.ini').Path
$ini = [System.IO.File]::ReadAllText($iniPath)
$ini = Set-IniValue $ini 'DlssNr' 'Enabled' 'true'
$ini = Set-IniValue $ini 'FrameGen' 'Enabled' 'true'
$ini = Set-IniValue $ini 'FrameGen' 'FGInput' 'upscaler'
$ini = Set-IniValue $ini 'FrameGen' 'FGOutput' 'dlssg'
$ini = Set-IniValue $ini 'FrameGen' 'FGNvngxReplacement' 'none'
$ini = Set-IniValue $ini 'DLSSG' 'InterpolationCount' '3'
$ini = Set-IniValue $ini 'Inputs' 'EnableDlssInputs' 'true'
$ini = Set-IniValue $ini 'Plugins' 'LoadReshade' 'true'
$ini = Set-IniValue $ini 'Log' 'LogToFile' 'true'
$ini = Set-IniValue $ini 'Log' 'LogLevel' '2'
[System.IO.File]::WriteAllText($iniPath, $ini, (New-Object System.Text.UTF8Encoding($false)))

msbuild /m /p:Configuration=Release . /verbosity:minimal
Assert-NativeSuccess 'MSBuild'
Set-Location ..

$dll = 'optiscaler-src\x64\Release\a\OptiScaler.dll'
if (-not (Test-Path $dll)) { throw 'Compiled OptiScaler.dll missing' }
$ascii = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($dll))
foreach ($marker in @('WH3 native DLSS passthrough:', 'WH3 native DLSS5 NR -> XeFG bridge', 'Neural Rendering:', 'WH3 Feeder visibility probe #', 'WH3 DLSSG two-stage', 'Streamline load now permitted', 'backend forwarder, feature18 result')) {
    if (-not $ascii.Contains($marker)) { throw "Missing compiled marker: $marker" }
}

New-Item -ItemType Directory -Force -Path package | Out-Null
Copy-Item -Recurse -Force 'optiscaler-src\x64\Release\a\*' package\
Copy-Item -Force 'optiscaler-src\OptiScaler.ini' package\OptiScaler-DLSSNR-WH3.ini
Copy-Item -Force 'experiments\mfg-dlssnr\wh3-dlssnr-mfg.patch' package\
$forwarder = Get-ChildItem -Path 'optiscaler-src' -Filter 'nvngx.dll_dlssnr.dll' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $forwarder) { throw 'DLSSNR forwarder missing' }
Copy-Item -Force $forwarder.FullName package\nvngx.dll_dlssnr.dll
@'
Experimental WH3 native DLSS5 Neural Rendering plus 4x DLSS-G/MFG.
Source: Dagherbou/OptiScaler_DLSSNR commit 973761621353b99bee3dc7d4bb27b117fef2644f.
Neural Rendering is not proven by Native DLSS NGX ACTIVE. Verify DLSS5-Feed log explicitly reports both neural forwarder loaded and neural model (feature 18) loaded, then check Streamline numFramesToGenerate=3 in the same continuous run.
This build is experimental. Keep the stable DLSS5+XeFG backup.
'@ | Set-Content -Encoding UTF8 package\README-TEST.txt
