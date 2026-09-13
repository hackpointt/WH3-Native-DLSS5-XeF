from pathlib import Path

path = Path('optiscaler-src/OptiScaler/wrapped/wrapped_swapchain.cpp')
text = path.read_text(encoding='utf-8')

anchor = '''static bool _dx11Device = false;\nstatic bool _dx12Device = false;\n'''
insert = r'''static bool _dx11Device = false;
static bool _dx12Device = false;

// WH3 V17 experiment: attach an explicit ReShade effect runtime to the final
// XeFG D3D12 swapchain. ReShade exposes a public library API specifically for
// creating a runtime for a swapchain it did not hook automatically. This keeps
// the validated V15 native-DLSS -> OptiFG -> XeFG path intact and composes the
// ReShade UI on the final presenter instead of trying to make the hidden DX11
// swapchain visible.
using PFN_ReShadeCreateEffectRuntime = bool (*)(int, void*, void*, void*, const char*, void**);
using PFN_ReShadeDestroyEffectRuntime = void (*)(void*);
using PFN_ReShadeUpdateAndPresentEffectRuntime = void (*)(void*);

static void* wh3PostFgReShadeRuntime = nullptr;
static IDXGISwapChain* wh3PostFgReShadeSwapchain = nullptr;
static PFN_ReShadeCreateEffectRuntime wh3ReShadeCreateRuntime = nullptr;
static PFN_ReShadeDestroyEffectRuntime wh3ReShadeDestroyRuntime = nullptr;
static PFN_ReShadeUpdateAndPresentEffectRuntime wh3ReShadeUpdateRuntime = nullptr;
static bool wh3PostFgReShadeArmed = false;
static bool wh3PostFgHomeWasDown = false;
static bool wh3PostFgExportFailureLogged = false;

static bool Wh3EnsurePostFgReShadeRuntime(IDXGISwapChain* swapchain, ID3D12CommandQueue* queue)
{
    if (swapchain == nullptr || queue == nullptr || State::Instance().currentD3D12Device == nullptr)
        return false;

    if (wh3PostFgReShadeRuntime != nullptr && wh3PostFgReShadeSwapchain == swapchain)
        return true;

    HMODULE reshade = GetModuleHandleW(L"ReShade64.dll");
    if (reshade == nullptr)
        return false;

    if (wh3ReShadeCreateRuntime == nullptr)
    {
        wh3ReShadeCreateRuntime = reinterpret_cast<PFN_ReShadeCreateEffectRuntime>(
            GetProcAddress(reshade, "ReShadeCreateEffectRuntime"));
        wh3ReShadeDestroyRuntime = reinterpret_cast<PFN_ReShadeDestroyEffectRuntime>(
            GetProcAddress(reshade, "ReShadeDestroyEffectRuntime"));
        wh3ReShadeUpdateRuntime = reinterpret_cast<PFN_ReShadeUpdateAndPresentEffectRuntime>(
            GetProcAddress(reshade, "ReShadeUpdateAndPresentEffectRuntime"));
    }

    if (wh3ReShadeCreateRuntime == nullptr || wh3ReShadeUpdateRuntime == nullptr)
    {
        if (!wh3PostFgExportFailureLogged)
        {
            LOG_ERROR("WH3 ReShade post-FG: required ReShade library API exports are unavailable");
            wh3PostFgExportFailureLogged = true;
        }
        return false;
    }

    if (wh3PostFgReShadeRuntime != nullptr)
    {
        if (wh3ReShadeDestroyRuntime != nullptr)
            wh3ReShadeDestroyRuntime(wh3PostFgReShadeRuntime);
        wh3PostFgReShadeRuntime = nullptr;
        wh3PostFgReShadeSwapchain = nullptr;
    }

    // Use a dedicated config so the post-FG runtime does not overwrite the
    // automatically created DX11 runtime's ReShade.ini while we experiment.
    const auto configPath = (Util::ExePath().parent_path() / "ReShade-XeFG.ini").string();
    void* runtime = nullptr;

    // ReShade api::device_api::d3d12 == 0xC000.
    const bool created = wh3ReShadeCreateRuntime(
        0xC000,
        State::Instance().currentD3D12Device,
        queue,
        swapchain,
        configPath.c_str(),
        &runtime);

    LOG_INFO("WH3 ReShade post-FG: create runtime result {}, runtime {:X}, swapchain {:X}, queue {:X}",
             created, (size_t) runtime, (size_t) swapchain, (size_t) queue);

    if (!created || runtime == nullptr)
        return false;

    wh3PostFgReShadeRuntime = runtime;
    wh3PostFgReShadeSwapchain = swapchain;
    return true;
}

static void Wh3RenderPostFgReShade(IDXGISwapChain* swapchain, ID3D12CommandQueue* queue)
{
    if (_stricmp(State::Instance().gameExe.c_str(), "Warhammer3.exe") != 0 ||
        State::Instance().activeFgOutput != FGOutput::XeFG ||
        State::Instance().swapchainInteropApi != SwapchainInteropApi::Dx11wDx12)
        return;

    // Arm lazily on the first Home press so normal V15 rendering remains
    // completely unchanged until the player actually asks for ReShade UI.
    const bool homeDown = (GetAsyncKeyState(VK_HOME) & 0x8000) != 0;
    if (homeDown && !wh3PostFgHomeWasDown && !wh3PostFgReShadeArmed)
    {
        wh3PostFgReShadeArmed = true;
        LOG_INFO("WH3 ReShade post-FG: armed by Home; creating runtime on final XeFG swapchain");
    }
    wh3PostFgHomeWasDown = homeDown;

    if (!wh3PostFgReShadeArmed)
        return;

    if (!Wh3EnsurePostFgReShadeRuntime(swapchain, queue))
        return;

    wh3ReShadeUpdateRuntime(wh3PostFgReShadeRuntime);
}
'''

if anchor not in text:
    raise SystemExit('V17 static anchor missing')
text = text.replace(anchor, insert, 1)

present_anchor = '''        // Draw overlay\n        MenuOverlayDx::Present(pSwapChain, SyncInterval, Flags, pPresentParameters, pDevice, hWnd, isUWP);\n'''
present_insert = '''        // Draw overlay\n        MenuOverlayDx::Present(pSwapChain, SyncInterval, Flags, pPresentParameters, pDevice, hWnd, isUWP);\n\n        // WH3 V17: render the explicit ReShade runtime on the final XeFG D3D12\n        // presenter. At this point LocalPresent owns the visible swapchain, so\n        // unlike V16 this must not switch away from or stop the XeFG presenter.\n        if (cq != nullptr)\n            Wh3RenderPostFgReShade(pSwapChain, cq);\n'''

if present_anchor not in text:
    raise SystemExit('V17 LocalPresent anchor missing')
text = text.replace(present_anchor, present_insert, 1)

path.write_text(text, encoding='utf-8')
