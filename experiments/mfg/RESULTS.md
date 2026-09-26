# WH3 DLSS-G / MFG experiment status (2026-09-26)

**Not working; do not install this branch as a replacement for the validated DLSS5 + XeFG setup.**

The original OptiScaler DLSS-G path failed to create WH3's DX11-to-DX12 presenter swapchain with `0x887A0001`. Removing `DXGI_USAGE_UNORDERED_ACCESS` from the WH3-only DLSS-G descriptor allows Streamline to create the swapchain and report its interpolation capacity.

After that creation, DLSS5 Feed 1.17.0-beta.3 on its private D3D12 device consistently fails to close the command list used during native DLSS `CreateFeature` (`0x80070057`). Its first `Evaluate` then raises `0xC0000005`. OptiScaler reports native DLSS inactive, Depth/MV unavailable, and DLSS-G off. The same failure occurs with MFG Unlock removed and with both locally available Streamline versions (2.14.1 and the older RHI cached 2.14.0 package).

The identical OptiScaler DLL switched to XeFG instead of DLSS-G succeeds: DLSS5 Feed continues evaluating for thousands of frames, the WH3 bridge reports native NGX active and Depth/MV ready, and XeFG dispatches. This localizes the regression to initialization of the Streamline/DLSS-G presenter, rather than the WH3 native-DLSS input bridge or MFG Unlock alone.

An attempted delay unloaded `sl::kFeatureDLSS_G` **after** constructing its swapchain and requested reload after the first successful native DLSS evaluation. The unload returned `eOk`, but the Feed still failed during `CreateFeature` before that success point. This delayed-load patch is a failed diagnostic experiment, not a fix. NVIDIA's [Streamline programming guide](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md) specifies that switching between a native and DLSS-G proxy swapchain requires releasing and recreating the swapchain with the feature in the corresponding loaded state.

The game installation was restored to the pre-experiment DLL and INI hashes after each failed test. Local logs and snapshots are under `D:\DLSS5-Audit\2026-09-25-refresh`.
