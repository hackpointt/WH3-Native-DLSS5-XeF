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

Write-Host 'Applying V16 ReShade tuning experiment...'
python .\experiments\v16\apply_v16.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Location optiscaler-src
git diff --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
git diff --binary HEAD | Out-File -Encoding utf8 "..\WH3-v16-reshade-tuning.patch"

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
    'WH3 ReShade tuning mode: ON',
    'WH3 ReShade tuning mode: OFF'
)) {
    if (-not $ascii.Contains($marker)) { throw "Missing marker: $marker" }
}

New-Item -ItemType Directory -Force -Path package | Out-Null
Copy-Item -Recurse -Force 'optiscaler-src\x64\Release\a\*' package\
Copy-Item -Force 'WH3-v16-reshade-tuning.patch' package\
@'
WH3 Native DLSS5 -> XeFG V16 ReShade tuning experiment

Base: validated V15 RC1 patch on OptiScaler 5c5e424d

Test goal:
- With XeFG active and the game in a 3D battle, press Home once.
- Expected: XeFG pauses and the original DX11/ReShade presentation becomes visible.
- ReShade/ShortFuse overlay should open normally.
- Adjust DLSS5 parameters.
- Press Home again.
- Expected: ReShade closes, FG is restored, then V15 Depth/MV warm-up resumes XeFG.

This is an experimental branch build. RC1/main remains unchanged.
'@ | Set-Content -Encoding UTF8 package\README-V16-TEST.txt
