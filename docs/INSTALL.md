# Installation

## Prerequisites

1. A working Total War: WARHAMMER III DX11 installation.
2. ReShade available as `ReShade64.dll` in the WH3 game directory (the tested OptiScaler loading arrangement).
3. ShortFuse `dlss5-feed.addon64` installed somewhere below the WH3 game directory and already validated in-game.
4. NVIDIA Smooth Motion off for WH3.
5. RTSS closed or WH3 excluded from RTSS hooking.

## Automated install

Run from an ordinary PowerShell window:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Install-WH3-DLSS5-XeFG.ps1 -GameDir "<WH3 folder>"
```

The installer is conservative: it refuses a folder without `Warhammer3.exe`, checks for ReShade and ShortFuse, and creates a timestamped backup before replacing OptiScaler-related files.

## Manual install

If you prefer full control:

1. Back up these items if they exist in the WH3 executable directory:
   - `dxgi.dll`
   - `OptiScaler.ini`
   - `OptiScaler\`
2. Copy `runtime\OptiScaler\` into the WH3 executable directory as `OptiScaler\`.
3. Copy `runtime\OptiScaler.dll` into the WH3 executable directory and rename the copy to `dxgi.dll`.
4. Copy `config\OptiScaler.ini` into the WH3 executable directory.
5. Keep your existing `ReShade64.dll` and ShortFuse addon installation in place.

The RC1 preset contains the tested values:

```ini
[FrameGen]
Enabled=false
FGInput=upscaler
FGOutput=xefg

[Inputs]
EnableDlssInputs=true

[Plugins]
LoadReshade=true
```

`Enabled=false` is intentional. Enable XeFG manually only after entering a 3D battle on the first run.
