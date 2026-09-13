$ErrorActionPreference = 'Stop'

Write-Host 'Cloning OptiScaler base...'
git clone --recursive https://github.com/optiscaler/OptiScaler.git optiscaler-src
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Set-Location optiscaler-src
git checkout 5c5e424dd137d69ef36c4231fd45b760b4c65cc8
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
git submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Set-Location ..

Write-Host 'Applying validated V15 patch...'
$patchText = [System.IO.File]::ReadAllText('source\WH3-native-DLSS5-XeFG.patch')
if ($patchText.Length -gt 0 -and [int]$patchText[0] -eq 0xFEFF) { $patchText = $patchText.Substring(1) }
[System.IO.File]::WriteAllText('v15.patch', $patchText, (New-Object System.Text.UTF8Encoding($false)))
Set-Location optiscaler-src
git apply --recount ..\v15.patch
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Set-Location ..

Write-Host 'Applying V17 post-FG ReShade runtime experiment...'
python .\experiments\v17\apply_v17.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Location optiscaler-src
git diff --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
git diff --binary HEAD | Out-File -Encoding utf8 "..\WH3-v17-reshade-postfg.patch"

Write-Host 'Building Release x64...'
msbuild /m /p:Configuration=Release . /verbosity:minimal
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Set-Location ..

$dll = 'optiscaler-src\x64\Release\a\OptiScaler.dll'
if (-not (Test-Path $dll)) { throw 'Compiled DLL missing' }
$ascii = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($dll))
foreach ($marker in @(
    'WH3 native DLSS passthrough:',
    'WH3 native DLSS bridge: private shadow active',
    'WH3 XeFG compatibility:',
    'WH3 ReShade post-FG: armed by Home',
    'WH3 ReShade post-FG: create runtime result'
)) {
    if (-not $ascii.Contains($marker)) { throw "Missing marker: $marker" }
}

New-Item -ItemType Directory -Force -Path package | Out-Null
Copy-Item -Recurse -Force 'optiscaler-src\x64\Release\a\*' package\
Copy-Item -Force 'WH3-v17-reshade-postfg.patch' package\
@'
WH3 Native DLSS5 -> XeFG V17 ReShade post-FG runtime experiment

Base: validated V15 RC1 patch on OptiScaler 5c5e424d

What changed:
- V16 hidden-DX11-present switching has been abandoned.
- V17 keeps the final XeFG presenter alive at all times.
- On the first Home press, it uses ReShade's public library API to create an explicit D3D12 effect runtime on the final XeFG swapchain.
- The runtime is rendered from OptiScaler LocalPresent, i.e. on the visible D3D12 presenter path.
- A separate ReShade-XeFG.ini is used to avoid overwriting the normal ReShade.ini during this experiment.

Test:
1. Start a 3D battle and verify the usual four green states.
2. Press Home once.
3. Expected: no freeze. ReShade should create a post-FG runtime and its UI/add-on overlays should become visible.
4. If the UI appears, change one ShortFuse/DLSS5 parameter and verify native DLSS remains ACTIVE and XeFG remains ACTIVE.

If no UI appears, upload the OptiScaler log. Look for:
- WH3 ReShade post-FG: armed by Home
- WH3 ReShade post-FG: create runtime result true/false
- WH3 ReShade post-FG: required ReShade library API exports are unavailable

Experimental branch only; main/RC1 unchanged.
'@ | Set-Content -Encoding UTF8 package\README-V17-TEST.txt
