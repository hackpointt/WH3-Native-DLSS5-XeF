from pathlib import Path

ROOT = Path('optiscaler-src')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'{label}: expected exactly one anchor, found {n}')
    return text.replace(old, new, 1)


# -----------------------------------------------------------------------------
# State: live native-DLSS heartbeat used by the WH3 status panel.
# -----------------------------------------------------------------------------
p = ROOT / 'OptiScaler/State.h'
s = p.read_text(encoding='utf-8-sig')
if '#include <atomic>' not in s:
    s = replace_once(s, '#include <mutex>\n', '#include <mutex>\n#include <atomic>\n', 'State atomic include')

state_anchor = '''    // FG\n    uint64_t fgLastFrame = 0;\n'''
state_insert = '''    // FG\n    uint64_t fgLastFrame = 0;\n\n    // WH3 native-DLSS -> OptiFG compatibility status. Updated only after a\n    // successful native NVIDIA D3D12 DLSS EvaluateFeature call.\n    std::atomic<uint64_t> wh3NativeDlssLastSuccessTick { 0 };\n'''
if 'wh3NativeDlssLastSuccessTick' not in s:
    s = replace_once(s, state_anchor, state_insert, 'State heartbeat')
p.write_text(s, encoding='utf-8')


# -----------------------------------------------------------------------------
# XeFG: preserve the two WH3-only swapchain fixes validated by V15.
# -----------------------------------------------------------------------------
p = ROOT / 'OptiScaler/framegen/xefg/XeFG_Dx12.cpp'
s = p.read_text(encoding='utf-8-sig')

xefg_desc_anchor = '''    scDesc.Stereo = false; // No info\n    scDesc.SwapEffect = desc->SwapEffect;\n    scDesc.Width = desc->BufferDesc.Width;\n\n    DXGI_SWAP_CHAIN_FULLSCREEN_DESC fsDesc {};\n'''
xefg_desc_insert = '''    scDesc.Stereo = false; // No info\n    scDesc.SwapEffect = desc->SwapEffect;\n    scDesc.Width = desc->BufferDesc.Width;\n\n    // WH3's DX11 chain carries UNORDERED_ACCESS. Intel XeFG rejects that usage\n    // when OptiScaler creates the final D3D12 FG presenter, so sanitize WH3 only.\n    const bool wh3XeFgCompat = _stricmp(State::Instance().gameExe.c_str(), "Warhammer3.exe") == 0;\n    if (wh3XeFgCompat)\n    {\n        LOG_INFO("WH3 XeFG compatibility: Width {}, Height {}, Format {}, Count {}, Usage {:X}, Flags {:X}, Scaling {}, SwapEffect {}, SampleCount {}, SampleQuality {}, AlphaMode {}",\n                 scDesc.Width, scDesc.Height, (UINT) scDesc.Format, scDesc.BufferCount, (UINT) scDesc.BufferUsage,\n                 (UINT) scDesc.Flags, (UINT) scDesc.Scaling, (UINT) scDesc.SwapEffect,\n                 scDesc.SampleDesc.Count, scDesc.SampleDesc.Quality, (UINT) scDesc.AlphaMode);\n\n        if ((scDesc.BufferUsage & DXGI_USAGE_UNORDERED_ACCESS) != 0)\n        {\n            scDesc.BufferUsage &= ~DXGI_USAGE_UNORDERED_ACCESS;\n            LOG_INFO("WH3 XeFG compatibility: removed DXGI_USAGE_UNORDERED_ACCESS; Usage now {:X}",\n                     (UINT) scDesc.BufferUsage);\n        }\n    }\n\n    DXGI_SWAP_CHAIN_FULLSCREEN_DESC fsDesc {};\n'''
if 'WH3 XeFG compatibility:' not in s:
    s = replace_once(s, xefg_desc_anchor, xefg_desc_insert, 'XeFG descriptor compatibility')

xefg_call_anchor = '''    xefg_swapchain_result_t result;\n    result = XeFGProxy::D3D12InitFromSwapChainDesc()(_swapChainContext, hwnd, &scDesc, &fsDesc, realQueue, factory12,\n                                                     &params);\n'''
xefg_call_insert = '''    xefg_swapchain_result_t result;\n\n    // Intel's windowed XeFG path expects no fullscreen descriptor. Keep this\n    // compatibility workaround scoped to WH3.\n    DXGI_SWAP_CHAIN_FULLSCREEN_DESC* xefgFullscreenDesc =\n        (wh3XeFgCompat && desc->Windowed) ? nullptr : &fsDesc;\n    if (wh3XeFgCompat && desc->Windowed)\n        LOG_INFO("WH3 XeFG compatibility: omitting fullscreen descriptor for windowed swapchain");\n\n    result = XeFGProxy::D3D12InitFromSwapChainDesc()(_swapChainContext, hwnd, &scDesc, xefgFullscreenDesc,\n                                                     realQueue, factory12, &params);\n'''
if 'xefgFullscreenDesc' not in s:
    s = replace_once(s, xefg_call_anchor, xefg_call_insert, 'XeFG fullscreen descriptor compatibility')
p.write_text(s, encoding='utf-8')


# -----------------------------------------------------------------------------
# Native DLSS + private OptiFG bridge + DLSS Neural Rendering.
# The important ordering is:
#   capture FG metadata -> native NVIDIA DLSS -> DLSSNR post-pass -> advance shadow.
# This preserves the fork's own EvaluateAfterUpscale call instead of returning early.
# -----------------------------------------------------------------------------
p = ROOT / 'OptiScaler/inputs/NVNGX_DLSS_Dx12.cpp'
s = p.read_text(encoding='utf-8-sig')

shadow_anchor = '''static bool shutdown = false;\nstatic bool _skipInit = false;\nstatic wchar_t const** paths;\n\nclass ScopedInitDx12\n'''
shadow_insert = '''static bool shutdown = false;\nstatic bool _skipInit = false;\nstatic wchar_t const** paths;\n\n// WH3 metadata-only shadow feature. It never creates or evaluates a second\n// upscaler. It exists only to describe the native Feeder-created D3D12 DLSS\n// contract to OptiFG's resource-capture path. Never publish it as currentFeature.\nclass WH3NativeDlssInputFeature final : public IFeature_Dx12\n{\n  public:\n    WH3NativeDlssInputFeature(unsigned int handleId, NVSDK_NGX_Parameter* params)\n        : IFeature(handleId, params), IFeature_Dx12(handleId, params)\n    {\n        _initParameters = SetInitParameters(params);\n        SetInit(_initParameters);\n        LOG_INFO("WH3 native DLSS bridge: shadow init: {}, IsInitParameters {}, Render {}x{}, Display {}x{}, Flags 0x{:X}, LowResMV {}, DepthInverted {}, JitteredMV {}",\n                 IsInited(), IsInitParameters(), RenderWidth(), RenderHeight(), DisplayWidth(), DisplayHeight(),\n                 GetFeatureFlags(), LowResMV(), DepthInverted(), JitteredMV());\n    }\n\n    bool InitInternal(ID3D12GraphicsCommandList*, NVSDK_NGX_Parameter*) override { return true; }\n    bool EvaluateInternal(ID3D12GraphicsCommandList*, NVSDK_NGX_Parameter*) override { return true; }\n    feature_version Version() override { return feature_version { 0, 0, 0 }; }\n    Upscaler GetUpscalerType() const final { return Upscaler::DLSS; }\n    bool IsWithDx12() override { return false; }\n    void AdvanceFrame() { _frameCount++; }\n};\n\nstatic std::unordered_map<unsigned int, std::unique_ptr<WH3NativeDlssInputFeature>> wh3NativeInputFeatures;\n\nclass ScopedInitDx12\n'''
if 'class WH3NativeDlssInputFeature' not in s:
    s = replace_once(s, shadow_anchor, shadow_insert, 'WH3 shadow feature')

create_anchor = '''    // OptiScaler internal handling (SuperSampling or RayReconstruction)\n    auto tryResult = TryCreateOptiFeature(InCmdList, InFeatureID, InParameters, OutHandle);\n'''
create_insert = '''    // WH3 + DLSS5-Feeder: its helper SuperSampling/RR feature is a real D3D12\n    // NVIDIA NGX feature. Keep that handle/result native; replacing it with an\n    // OptiScaler upscaler freezes WH3. Neural Rendering is intentionally NOT run\n    // here: the DLSSNR fork attaches its post-pass after the native Evaluate below.\n    const auto exeName = Util::ExePath().filename().wstring();\n    const bool wh3Dlss5Compat = _wcsicmp(exeName.c_str(), L"Warhammer3.exe") == 0;\n    const bool d3d12DlssAuxFeature =\n        InFeatureID == NVSDK_NGX_Feature_SuperSampling ||\n        InFeatureID == NVSDK_NGX_Feature_RayReconstruction;\n\n    if (wh3Dlss5Compat && d3d12DlssAuxFeature)\n    {\n        if (NVNGXProxy::NVNGXModule() == nullptr)\n            NVNGXProxy::InitNVNGX();\n\n        auto nativeCreate = NVNGXProxy::D3D12_CreateFeature();\n        LOG_INFO("WH3 native DLSS passthrough: D3D12 feature {}, native CreateFeature available: {}",\n                 (int) InFeatureID, nativeCreate != nullptr);\n\n        if (cfg.DLSSEnabled.value_or_default() && nativeCreate != nullptr)\n        {\n            NVSDK_NGX_Result res = nativeCreate(InCmdList, InFeatureID, InParameters, OutHandle);\n            LOG_INFO("WH3 native DLSS passthrough: native D3D12 CreateFeature result: 0x{:X}", (uint32_t) res);\n\n            if (*OutHandle)\n                HandleToFeature[(*OutHandle)->Id] = InFeatureID;\n\n            return res;\n        }\n\n        LOG_ERROR("WH3 native DLSS passthrough: native D3D12 NGX unavailable; refusing OptiScaler interception");\n        return NVSDK_NGX_Result_FAIL_FeatureNotSupported;\n    }\n\n    // OptiScaler internal handling (SuperSampling or RayReconstruction)\n    auto tryResult = TryCreateOptiFeature(InCmdList, InFeatureID, InParameters, OutHandle);\n'''
if 'WH3 native DLSS passthrough: D3D12 feature' not in s:
    s = replace_once(s, create_anchor, create_insert, 'WH3 native CreateFeature passthrough')

release_anchor = '''    auto handleId = InHandle->Id;\n\n    // Clean up framegen\n'''
release_insert = '''    auto handleId = InHandle->Id;\n\n    if (auto bridgeIt = wh3NativeInputFeatures.find(handleId); bridgeIt != wh3NativeInputFeatures.end())\n    {\n        wh3NativeInputFeatures.erase(bridgeIt);\n        LOG_INFO("WH3 native DLSS bridge: released for native handle {}", handleId);\n    }\n\n    // Clean up framegen\n'''
if 'WH3 native DLSS bridge: released for native handle' not in s:
    s = replace_once(s, release_anchor, release_insert, 'WH3 bridge release')

native_eval_anchor = '''    // Native DLSS passthrough\n    if (handleId < DLSS_MOD_ID_OFFSET)\n    {\n        if (cfg.DLSSEnabled.value_or_default() && NVNGXProxy::D3D12_EvaluateFeature() != nullptr)\n        {\n            LOG_DEBUG("Passthrough to native DLSS EvaluateFeature for handle {}", handleId);\n\n            NVSDK_NGX_Result result =\n                NVNGXProxy::D3D12_EvaluateFeature()(InCmdList, InFeatureHandle, InParameters, InCallback);\n            LOG_DEBUG("Native DLSS EvaluateFeature result: 0x{:X}", (uint32_t) result);\n\n            // Neural Rendering runs over what the upscaler just wrote, on the same list, so frame\n            // generation interpolates from enhanced frames and the model still costs one run per\n            // rendered frame. The feature check is the point: frame generation is handed depth and\n            // motion vectors too, and its handle can reach here because the branch above does not\n            // return, so filtering on the parameter block alone would run the model twice a frame.\n            if (result == NVSDK_NGX_Result_Success && feature != NVSDK_NGX_Feature_FrameGeneration)\n                DlssNr::EvaluateAfterUpscale(InCmdList, InParameters);\n\n            return result;\n        }\n'''
native_eval_insert = '''    // Native DLSS passthrough\n    if (handleId < DLSS_MOD_ID_OFFSET)\n    {\n        if (cfg.DLSSEnabled.value_or_default() && NVNGXProxy::D3D12_EvaluateFeature() != nullptr)\n        {\n            WH3NativeDlssInputFeature* bridgeFeature = nullptr;\n            bool wh3BridgeRunning = false;\n            const bool wh3NativeBridge =\n                _wcsicmp(Util::ExePath().filename().wstring().c_str(), L"Warhammer3.exe") == 0 &&\n                feature == NVSDK_NGX_Feature_SuperSampling && InParameters != nullptr &&\n                State::Instance().activeFgInput == FGInput::Upscaler;\n\n            if (wh3NativeBridge)\n            {\n                auto it = wh3NativeInputFeatures.find(handleId);\n                if (it == wh3NativeInputFeatures.end())\n                {\n                    auto shadow = std::make_unique<WH3NativeDlssInputFeature>(handleId, InParameters);\n                    bridgeFeature = shadow.get();\n                    wh3NativeInputFeatures.emplace(handleId, std::move(shadow));\n                    LOG_INFO("WH3 native DLSS bridge: created for native handle {}", handleId);\n                }\n                else\n                {\n                    bridgeFeature = it->second.get();\n                }\n\n                if (bridgeFeature != nullptr && bridgeFeature->IsInitParameters())\n                {\n                    const bool fgEnabled = Config::Instance()->FGEnabled.value_or_default();\n                    if (fgEnabled)\n                    {\n                        // Keep this metadata-only shadow private. LocalPresent must never\n                        // mistake it for a fully initialized upscaler.\n                        wh3BridgeRunning = true;\n                        static bool wh3PrivateLogged = false;\n                        if (!wh3PrivateLogged)\n                        {\n                            LOG_INFO("WH3 native DLSS bridge: private shadow active; currentFeature untouched");\n                            wh3PrivateLogged = true;\n                        }\n\n                        UpscalerInputsDx12::UpscaleStart(InCmdList, InParameters, bridgeFeature);\n                        UpscalerInputsDx12::UpscaleEnd(InCmdList, InParameters, bridgeFeature);\n\n                        static uint64_t wh3BridgeCounter = 0;\n                        wh3BridgeCounter++;\n                        if (wh3BridgeCounter <= 12 || (wh3BridgeCounter % 300) == 0)\n                        {\n                            auto fg = State::Instance().currentFG;\n                            LOG_INFO("WH3 native DLSS bridge: tick #{}: FGEnabled {}, fg {}, active {}, paused {}, depth {}, velocity {}, frame {}",\n                                     wh3BridgeCounter, fgEnabled, fg != nullptr,\n                                     fg != nullptr ? fg->IsActive() : false,\n                                     fg != nullptr ? fg->IsPaused() : false,\n                                     fg != nullptr ? fg->HasResource(FG_ResourceType::Depth) : false,\n                                     fg != nullptr ? fg->HasResource(FG_ResourceType::Velocity) : false,\n                                     fg != nullptr ? fg->FrameCount() : 0);\n                        }\n                    }\n                    else\n                    {\n                        static uint64_t wh3DormantCounter = 0;\n                        wh3DormantCounter++;\n                        if (wh3DormantCounter <= 3 || (wh3DormantCounter % 300) == 0)\n                            LOG_INFO("WH3 native DLSS bridge: dormant: FG disabled; currentFeature untouched");\n                    }\n                }\n                else\n                {\n                    LOG_ERROR("WH3 native DLSS bridge: blocked: shadow feature missing init parameters");\n                }\n            }\n\n            LOG_DEBUG("Passthrough to native DLSS EvaluateFeature for handle {}", handleId);\n\n            NVSDK_NGX_Result result =\n                NVNGXProxy::D3D12_EvaluateFeature()(InCmdList, InFeatureHandle, InParameters, InCallback);\n            LOG_DEBUG("Native DLSS EvaluateFeature result: 0x{:X}", (uint32_t) result);\n\n            if (wh3NativeBridge && result == NVSDK_NGX_Result_Success)\n                State::Instance().wh3NativeDlssLastSuccessTick.store(GetTickCount64(), std::memory_order_relaxed);\n\n            // Keep the DLSSNR fork's essential ordering: the neural model runs AFTER\n            // NVIDIA DLSS wrote Output and BEFORE XeFG consumes the finished frame.\n            if (result == NVSDK_NGX_Result_Success && feature != NVSDK_NGX_Feature_FrameGeneration)\n                DlssNr::EvaluateAfterUpscale(InCmdList, InParameters);\n\n            if (wh3BridgeRunning && bridgeFeature != nullptr)\n                bridgeFeature->AdvanceFrame();\n\n            return result;\n        }\n'''
if 'wh3NativeDlssLastSuccessTick.store' not in s:
    s = replace_once(s, native_eval_anchor, native_eval_insert, 'WH3 native Evaluate + DLSSNR ordering')

p.write_text(s, encoding='utf-8')


# -----------------------------------------------------------------------------
# V18.1 sparse diagnostics: prove the native-DLSS -> NR call boundary without
# changing when either operation runs.
# -----------------------------------------------------------------------------
p = ROOT / 'OptiScaler/inputs/NVNGX_DLSS_Dx12.cpp'
s = p.read_text(encoding='utf-8-sig')

nr_call_anchor = '''            // Keep the DLSSNR fork's essential ordering: the neural model runs AFTER
            // NVIDIA DLSS wrote Output and BEFORE XeFG consumes the finished frame.
            if (result == NVSDK_NGX_Result_Success && feature != NVSDK_NGX_Feature_FrameGeneration)
                DlssNr::EvaluateAfterUpscale(InCmdList, InParameters);
'''
nr_call_insert = '''            // Keep the DLSSNR fork's essential ordering: the neural model runs AFTER
            // NVIDIA DLSS wrote Output and BEFORE XeFG consumes the finished frame.
            if (result == NVSDK_NGX_Result_Success && feature != NVSDK_NGX_Feature_FrameGeneration)
            {
                static std::atomic_uint64_t wh3NrTraceCounter { 0 };
                const uint64_t traceId = wh3NativeBridge
                    ? wh3NrTraceCounter.fetch_add(1, std::memory_order_relaxed) + 1
                    : 0;
                const bool trace = wh3NativeBridge && (traceId <= 10 || (traceId % 300) == 0);

                if (trace)
                    LOG_INFO("WH3 NR trace #{}: native DLSS result 0x{:X} -> EvaluateAfterUpscale enter; handle {}, feature {}",
                             traceId, (uint32_t) result, handleId, (int) feature);

                DlssNr::EvaluateAfterUpscale(InCmdList, InParameters);

                if (trace)
                    LOG_INFO("WH3 NR trace #{}: EvaluateAfterUpscale returned; running {}, failure '{}'",
                             traceId, DlssNr::IsRunning(), DlssNr::FailureReason());
            }
'''
if 'WH3 NR trace #' not in s:
    s = replace_once(s, nr_call_anchor, nr_call_insert, 'V18.1 native-to-NR trace')

p.write_text(s, encoding='utf-8')


# -----------------------------------------------------------------------------
# Neural Rendering: sparse, result-bearing diagnostics at the real feature-18
# evaluate call. Only this seam can prove which backend ran and NVIDIA's result.
# -----------------------------------------------------------------------------
p = ROOT / 'OptiScaler/shaders/dlssnr/DlssNr_Dx12.cpp'
s = p.read_text(encoding='utf-8-sig')

nr_diag_anchor = '''    SetExtras(cfg, nullptr, nullptr, 0, 0, 0, 0);

    // The proxy path, when asked for. Same inputs, same model -- the difference is who calls it.
'''
nr_diag_insert = '''    SetExtras(cfg, nullptr, nullptr, 0, 0, 0, 0);

    // V18.1 instrumentation only. Keep enough INFO-level evidence to prove the
    // actual feature-18 backend/result without restoring per-frame debug spam.
    const bool wh3NrDiagnostic =
        _stricmp(State::Instance().gameExe.c_str(), "Warhammer3.exe") == 0;
    static uint64_t wh3NrEvaluateCounter = 0;
    const uint64_t wh3NrEvaluateId = wh3NrDiagnostic ? ++wh3NrEvaluateCounter : 0;
    const bool wh3NrSample = wh3NrDiagnostic &&
        (wh3NrEvaluateId <= 10 || (wh3NrEvaluateId % 300) == 0);

    // The proxy path, when asked for. Same inputs, same model -- the difference is who calls it.
'''
if 'V18.1 instrumentation only' not in s:
    s = replace_once(s, nr_diag_anchor, nr_diag_insert, 'V18.1 NR diagnostic state')

proxy_anchor = '''    if (cfg.DlssNrUseProxy.value_or_default())
    {
        const unsigned int proxyResult = DlssNr::Proxy::Run(
'''
proxy_insert = '''    if (cfg.DlssNrUseProxy.value_or_default())
    {
        if (wh3NrSample)
            LOG_INFO("WH3 NR evaluate #{}: backend proxy, feature18 dispatch begin; work {}x{}, guides {}x{}, reset {}",
                     wh3NrEvaluateId, workWidth, workHeight, guideWidth, guideHeight, g_nr.reset);

        const unsigned int proxyResult = DlssNr::Proxy::Run(
'''
if 'backend proxy, feature18 dispatch begin' not in s:
    s = replace_once(s, proxy_anchor, proxy_insert, 'V18.1 proxy begin trace')

proxy_result_anchor = '''        g_nr.reset = false;

        if (proxyResult != 1)
'''
proxy_result_insert = '''        g_nr.reset = false;

        if (wh3NrSample || proxyResult != NVSDK_NGX_Result_Success)
            LOG_INFO("WH3 NR evaluate #{}: backend proxy, feature18 result 0x{:X} ({})",
                     wh3NrEvaluateId, proxyResult, NgxResultName(proxyResult));

        if (proxyResult != 1)
'''
if 'backend proxy, feature18 result' not in s:
    s = replace_once(s, proxy_result_anchor, proxy_result_insert, 'V18.1 proxy result trace')

forwarder_anchor = '''    // Multi-pass was removed: re-feeding the model its own output re-opened the same-command-list
    // feature-creation hang, and the colour core is not settled enough to build on. One evaluate.
    const int result = g_nr.evaluate(
'''
forwarder_insert = '''    // Multi-pass was removed: re-feeding the model its own output re-opened the same-command-list
    // feature-creation hang, and the colour core is not settled enough to build on. One evaluate.
    if (wh3NrSample)
        LOG_INFO("WH3 NR evaluate #{}: backend forwarder, feature18 dispatch begin; loaded {}, work {}x{}, guides {}x{}, reset {}",
                 wh3NrEvaluateId, g_nr.feature != nullptr, workWidth, workHeight, guideWidth, guideHeight,
                 g_nr.reset);

    const int result = g_nr.evaluate(
'''
if 'backend forwarder, feature18 dispatch begin' not in s:
    s = replace_once(s, forwarder_anchor, forwarder_insert, 'V18.1 forwarder begin trace')

forwarder_result_anchor = '''    if (g_ngxTime != nullptr)
        g_ngxTime->End(cmdList);

    g_nr.reset = false;
'''
forwarder_result_insert = '''    if (g_ngxTime != nullptr)
        g_ngxTime->End(cmdList);

    if (wh3NrSample || result != NVSDK_NGX_Result_Success)
        LOG_INFO("WH3 NR evaluate #{}: backend forwarder, feature18 result 0x{:X} ({})",
                 wh3NrEvaluateId, (uint32_t) result, NgxResultName((unsigned int) result));

    g_nr.reset = false;
'''
if 'backend forwarder, feature18 result' not in s:
    s = replace_once(s, forwarder_result_anchor, forwarder_result_insert, 'V18.1 forwarder result trace')

p.write_text(s, encoding='utf-8')


# -----------------------------------------------------------------------------
# XeFG: sparse INFO success marker. Existing errors stay unthrottled.
# -----------------------------------------------------------------------------
p = ROOT / 'OptiScaler/framegen/xefg/XeFG_Dx12.cpp'
s = p.read_text(encoding='utf-8-sig')

xefg_trace_anchor = '''    LOG_DEBUG("Result: Ok");

    return true;
'''
xefg_trace_insert = '''    LOG_DEBUG("Result: Ok");

    if (_stricmp(state.gameExe.c_str(), "Warhammer3.exe") == 0)
    {
        static uint64_t wh3XeFgSuccessCounter = 0;
        const uint64_t traceId = ++wh3XeFgSuccessCounter;
        if (traceId <= 10 || (traceId % 300) == 0)
            LOG_INFO("WH3 XeFG trace #{}: Dispatch Ok; frameId {}, depth ready, velocity ready",
                     traceId, frameId);
    }

    return true;
'''
if 'WH3 XeFG trace #' not in s:
    s = replace_once(s, xefg_trace_anchor, xefg_trace_insert, 'V18.1 XeFG success trace')

p.write_text(s, encoding='utf-8')


# -----------------------------------------------------------------------------
# Menu: extend V14's observability to a five-state DLSSNR build.
# -----------------------------------------------------------------------------
p = ROOT / 'OptiScaler/menu/menu_common.cpp'
s = p.read_text(encoding='utf-8-sig')
menu_anchor = '''        else if (currentFeature == nullptr || currentFeature->IsFrozen())\n        {\n            ImGui::Text("Upscaler is not active"); // Probably never will be visible\n        }\n'''
menu_insert = '''        else if (currentFeature == nullptr || currentFeature->IsFrozen())\n        {\n            if (_stricmp(State::Instance().gameExe.c_str(), "Warhammer3.exe") == 0)\n            {\n                const bool feederDetected = GetModuleHandleW(L"dlss5-feed.addon64") != nullptr;\n                const uint64_t now = GetTickCount64();\n                const uint64_t lastDlssSuccess =\n                    State::Instance().wh3NativeDlssLastSuccessTick.load(std::memory_order_relaxed);\n                const bool nativeDlssActive = lastDlssSuccess != 0 && now >= lastDlssSuccess &&\n                                              (now - lastDlssSuccess) < 2000;\n                const bool neuralActive = DlssNr::IsRunning();\n\n                auto fg = State::Instance().currentFG;\n                const bool depthReady = fg != nullptr && fg->HasResource(FG_ResourceType::Depth);\n                const bool velocityReady = fg != nullptr && fg->HasResource(FG_ResourceType::Velocity);\n                const bool xefgActive = State::Instance().activeFgOutput == FGOutput::XeFG && fg != nullptr &&\n                                        fg->IsActive() && !fg->IsPaused();\n\n                ImGui::Text("WH3 native DLSS5 NR -> XeFG bridge");\n                ImGui::Text("DLSS5 feeder:      %s", feederDetected ? "DETECTED" : "not detected");\n                ImGui::Text("Native DLSS NGX:   %s", nativeDlssActive ? "ACTIVE" : "inactive");\n                ImGui::Text("Neural Rendering:  %s", neuralActive ? "ACTIVE" : "inactive");\n                ImGui::Text("Depth + MV:        %s", (depthReady && velocityReady) ? "READY" : "not ready");\n                ImGui::Text("XeFG:              %s", xefgActive ? "ACTIVE" : "inactive");\n\n                if (!neuralActive)\n                {\n                    const char* nrReason = DlssNr::FailureReason();\n                    if (nrReason != nullptr && nrReason[0] != '\\0')\n                        ImGui::TextWrapped("NR: %s", nrReason);\n                }\n            }\n            else\n            {\n                ImGui::Text("Upscaler is not active"); // Probably never will be visible\n            }\n        }\n'''
if 'WH3 native DLSS5 NR -> XeFG bridge' not in s:
    s = replace_once(s, menu_anchor, menu_insert, 'WH3 five-state menu')
p.write_text(s, encoding='utf-8')

print('V18 DLSSNR fork-aware transform applied successfully')
