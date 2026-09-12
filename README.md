# Total War: WARHAMMER III — Native DLSS5 → XeFG

[中文说明](README.zh-CN.md) · [Download RC1](https://github.com/hackpointt/WH3-Native-DLSS5-XeF/releases/tag/v0.1.0-rc1)

An experimental compatibility package that keeps **ShortFuse/native NVIDIA DLSS5** as the game's upscaling path while feeding its native D3D12 **Depth + Motion Vectors** into **OptiFG → Intel XeFG** for frame generation.

This is an **unofficial community experiment**. It is not affiliated with Creative Assembly, SEGA, NVIDIA, Intel, ReShade, ShortFuse, or OptiScaler.

## What has been validated

- Total War: WARHAMMER III running in DX11.
- Native NVIDIA D3D12 DLSS evaluation remains passthrough; the patch does **not** replace the ShortFuse DLSS evaluator.
- Native DLSS Depth/MV are bridged through a private metadata-only adapter into OptiFG.
- XeFG owns the final DX12 interop presenter and successfully dispatches generated frames.
- Stable full battles were tested at 2560×1440 and 3840×2160 on an RTX 4090.
- The OptiScaler menu exposes a four-stage live health check:

```text
DLSS5 feeder:     DETECTED
Native DLSS NGX:  ACTIVE
Depth + MV:       READY
XeFG:             ACTIVE
```


## Before installing

**ShortFuse/DLSS5 is not redistributed in this package.** Install and configure your existing ReShade + ShortFuse DLSS5 setup first. Before adding this RC1, launch WH3 and make sure your desired DLSS5 preset/model is already working.

Why configure it first? Once XeFG owns the final Present path, the ReShade overlay may no longer be visible even though the ShortFuse addon itself continues to run.

For the RC1 validation path, also disable:

- NVIDIA Smooth Motion / NVIDIA App AI frame generation for WH3.
- RTSS overlay/hooking for WH3.

## Quick install

The safest route is the included PowerShell installer:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Install-WH3-DLSS5-XeFG.ps1 -GameDir "D:\SteamLibrary\steamapps\common\Total War WARHAMMER III"
```

It validates the game directory and ShortFuse/ReShade prerequisites, backs up the current `dxgi.dll`, `OptiScaler.ini`, and `OptiScaler` directory, then installs the RC1 payload.

Manual installation is documented in `docs/INSTALL.md`.

## First launch

1. Start WH3 normally.
2. Enter a real 3D battle first. Do **not** enable frame generation from the main menu for the first test.
3. Open the OptiScaler menu.
4. Confirm `FG Input = OptiFG (Upscaler)` and `FG Output = XeFG`.
5. Enable **Frame Generation (XeFG) → Active**.
6. Wait for the four live status lines to become `DETECTED / ACTIVE / READY / ACTIVE`.
7. Close the menu and play for several minutes before changing any other settings.

The packaged `OptiScaler.ini` intentionally starts with frame generation disabled, while preselecting the tested input/output path.

## Uninstall / rollback

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Uninstall-WH3-DLSS5-XeFG.ps1 -GameDir "D:\SteamLibrary\steamapps\common\Total War WARHAMMER III"
```

The installer records its backup location and the uninstall script restores the previous files.

## Known limitations

- The ReShade UI may be invisible after XeFG takes over the final Present chain. This does **not** by itself mean DLSS5 is off; use the four live status lines instead.
- Only the RTX 4090 path has been validated so far. Other GPUs are experimental.
- Smooth Motion and RTSS were disabled during validation and should remain off for RC1 testing.
- HDR, unusual overlays, other swapchain injectors and alternate proxy DLL names are not part of the validated matrix.
- This is an RC1, not a production-supported mod. Keep the rollback backup.

## Technical source

The package includes `source/WH3-native-DLSS5-XeFG.patch`, based on OptiScaler commit:

`5c5e424dd137d69ef36c4231fd45b760b4c65cc8`

The patch is the reviewable source of the compatibility changes used by this binary.

See `docs/TECHNICAL.md` for the architecture and `docs/TROUBLESHOOTING.md` for failure-state interpretation.
