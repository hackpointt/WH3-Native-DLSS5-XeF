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
$path = 'optiscaler-src\OptiScaler\with_dx12\dx11_with_dx12_sc.cpp'
$text = [System.IO.File]::ReadAllText($path)

$globalOld = "static int scCount = 0;`n"
$globalNew = @'
static int scCount = 0;

// WH3 V16 experiment: when ReShade's Home key is pressed, temporarily present the
// original DX11 swapchain instead of the XeFG DX12 presenter. This lets the already
// loaded ReShade runtime compose its own overlay without creating a second runtime.
// The validated V15 XeFG path is untouched while this mode is off.
static bool wh3ReShadeTuningMode = false;
static bool wh3ReShadeRestoreFg = false;
static bool wh3ReShadeHomeWasDown = false;
static bool wh3ReShadeResumeAfterPresent = false;
'@
$globalNew = $globalNew -replace "`r`n", "`n"
if (-not $text.Contains($globalOld)) { throw 'V16 global insertion anchor missing' }
$text = $text.Replace($globalOld, $globalNew + "`n")

$presentOld = @'
    if ((Flags & DXGI_PRESENT_TEST) != 0)
        return _real->Present(SyncInterval, Flags);

    if (!_InitInteropObjects())
        return DXGI_ERROR_DEVICE_REMOVED;
'@
$presentOld = $presentOld -replace "`r`n", "`n"

$presentNew = @'
    if ((Flags & DXGI_PRESENT_TEST) != 0)
        return _real->Present(SyncInterval, Flags);

    // WH3 ReShade tuning mode.
    // ReShade is attached to the original DX11 swapchain. In the normal XeFG path
    // OptiScaler copies the DX11 backbuffer to the DX12 FG chain before the hidden
    // DX11 Present occurs, so ReShade's Present-time UI never reaches final output.
    //
    // Home toggles a conservative tuning mode: FG is temporarily disabled and only
    // the original DX11 swapchain is presented. ReShade therefore owns the visible
    // Present exactly as it did before XeFG. On the closing Home press we re-enable
    // FG before presenting the closing frame, so the next game frame can repopulate
    // Depth/MV and let the existing V15 warm-up path resume safely.
    const bool wh3ReShadeCompat =
        _stricmp(State::Instance().gameExe.c_str(), "Warhammer3.exe") == 0 &&
        GetModuleHandleW(L"ReShade64.dll") != nullptr;

    if (wh3ReShadeCompat)
    {
        const bool homeDown = (GetAsyncKeyState(VK_HOME) & 0x8000) != 0;
        if (homeDown && !wh3ReShadeHomeWasDown)
        {
            if (!wh3ReShadeTuningMode)
            {
                wh3ReShadeRestoreFg = Config::Instance()->FGEnabled.value_or_default();
                if (wh3ReShadeRestoreFg)
                {
                    Config::Instance()->FGEnabled.set_volatile_value(false);
                    State::Instance().fgChanged = true;
                }

                wh3ReShadeTuningMode = true;
                wh3ReShadeResumeAfterPresent = false;
                LOG_INFO("WH3 ReShade tuning mode: ON; original DX11 Present is visible, XeFG temporarily paused");
            }
            else
            {
                if (wh3ReShadeRestoreFg)
                {
                    Config::Instance()->FGEnabled.set_volatile_value(true);
                    State::Instance().fgChanged = true;
                }

                wh3ReShadeResumeAfterPresent = true;
                LOG_INFO("WH3 ReShade tuning mode: closing; FG restored for next frame");
            }
        }
        wh3ReShadeHomeWasDown = homeDown;
    }

    if (wh3ReShadeTuningMode)
    {
        auto tuningPresentResult = _real->Present(SyncInterval, Flags);

        if (wh3ReShadeResumeAfterPresent)
        {
            wh3ReShadeTuningMode = false;
            wh3ReShadeResumeAfterPresent = false;
            wh3ReShadeRestoreFg = false;
            LOG_INFO("WH3 ReShade tuning mode: OFF; returning to XeFG presenter");
        }

        return tuningPresentResult;
    }

    if (!_InitInteropObjects())
        return DXGI_ERROR_DEVICE_REMOVED;
'@
$presentNew = $presentNew -replace "`r`n", "`n"
if (-not $text.Contains($presentOld)) { throw 'V16 Present insertion anchor missing' }
$text = $text.Replace($presentOld, $presentNew)
[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))

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
