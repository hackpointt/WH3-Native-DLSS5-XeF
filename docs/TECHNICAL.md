# Technical Architecture

## Problem

WH3 is a DX11 title without a native frame-generation path. The working DLSS5 setup reaches NVIDIA NGX through a ShortFuse-created D3D12 path. A naive OptiScaler DLSS interception caused the visual pipeline to freeze, while disabling DLSS interception preserved DLSS5 but left OptiFG without an upscaler input.

## RC1 architecture

```text
WH3 DX11
   |
   +--> ReShade / ShortFuse DLSS5
   |       |
   |       +--> native NVIDIA D3D12 NGX SuperSampling Create/Evaluate
   |                 |
   |                 +--> NVIDIA DLSS5 output (unchanged passthrough)
   |                 |
   |                 +--> private metadata-only shadow adapter
   |                           |
   |                           +--> Depth + Motion Vectors
   |                                      |
   |                                   OptiFG
   |                                      |
   +---------------- DX11 -> DX12 interop -+--> XeFG presenter
                                                   |
                                             generated frames
```

The private shadow is deliberately **not** assigned to `State::currentFeature`. Earlier experiments proved that publishing the metadata-only object as a normal upscaler could push unrelated Present/GPU-timing code down an invalid lifecycle path and freeze the frame.

## XeFG swapchain compatibility

Two relevant conditions were discovered during isolation:

1. WH3's converted interop swapchain included `DXGI_USAGE_UNORDERED_ACCESS`; XeFG's `CreateSwapChainForHwnd` rejected the resulting descriptor with `DXGI_ERROR_INVALID_CALL`. RC1 removes only the UAV usage for the WH3 XeFG path.
2. The windowed XeFG path omits the fullscreen descriptor when initializing the XeFG swapchain.

`DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING` remains preserved. Removing it caused a later mismatch when WH3 presented with `DXGI_PRESENT_ALLOW_TEARING`.

## Runtime observability

RC1 exposes four live states:

- `DLSS5 feeder: DETECTED`: `dlss5-feed.addon64` is loaded.
- `Native DLSS NGX: ACTIVE`: a real native D3D12 DLSS Evaluate succeeded within the recent activity window.
- `Depth + MV: READY`: both FG resources are currently tagged.
- `XeFG: ACTIVE`: the actual XeFG instance is active and not paused.

## Source scope

The consolidated patch modifies exactly the compatibility-related OptiScaler source areas used by the experiment and is based on commit:

`5c5e424dd137d69ef36c4231fd45b760b4c65cc8`
