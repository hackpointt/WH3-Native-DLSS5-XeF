from pathlib import Path

path = Path('optiscaler-src/OptiScaler/with_dx12/dx11_with_dx12_sc.cpp')
text = path.read_text(encoding='utf-8')

old_global = 'static int scCount = 0;\n'
new_global = '''static int scCount = 0;

// WH3 V16 experiment: when ReShade's Home key is pressed, temporarily present the
// original DX11 swapchain instead of the XeFG DX12 presenter. This lets the already
// loaded ReShade runtime compose its own overlay without creating a second runtime.
// The validated V15 XeFG path is untouched while this mode is off.
static bool wh3ReShadeTuningMode = false;
static bool wh3ReShadeRestoreFg = false;
static bool wh3ReShadeHomeWasDown = false;
static bool wh3ReShadeResumeAfterPresent = false;
'''
if text.count(old_global) != 1:
    raise SystemExit(f'V16 global insertion anchor count={text.count(old_global)}')
text = text.replace(old_global, new_global, 1)

old_present = '''    if ((Flags & DXGI_PRESENT_TEST) != 0)
        return _real->Present(SyncInterval, Flags);

    if (!_InitInteropObjects())
        return DXGI_ERROR_DEVICE_REMOVED;
'''
new_present = '''    if ((Flags & DXGI_PRESENT_TEST) != 0)
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
'''
if text.count(old_present) != 1:
    raise SystemExit(f'V16 Present insertion anchor count={text.count(old_present)}')
text = text.replace(old_present, new_present, 1)

path.write_text(text, encoding='utf-8', newline='\n')
print('V16 ReShade tuning transform applied')
