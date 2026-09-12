# Troubleshooting

Use the WH3-specific live status block in the OptiScaler menu as the primary diagnostic.

## `DLSS5 feeder: not detected`

The `dlss5-feed.addon64` module is not loaded. Confirm ShortFuse is installed and that ReShade is being loaded through `ReShade64.dll`. Configure and validate DLSS5 before troubleshooting XeFG.

## `Native DLSS NGX: inactive`

The real native D3D12 NVIDIA DLSS Evaluate call has not succeeded recently. This usually means the ShortFuse/native DLSS path is not actually running yet. Enter a 3D scene and verify your ShortFuse installation.

## `Depth + MV: not ready`

The bridge has not tagged both Depth and Motion Vector inputs. Make sure you are in a 3D battle, `FG Input = OptiFG (Upscaler)`, and frame generation has been enabled.

## `XeFG: inactive`

Check `FG Output = XeFG` and enable `Frame Generation (XeFG) → Active`. XeFG needs a short warm-up after activation.

## Main menu or battle freezes

For RC1, first restore the validated environment:

- Smooth Motion off.
- RTSS off / excluded.
- Use the supplied `dxgi.dll` (copy of the RC1 `OptiScaler.dll`).
- Use the supplied RC1 `OptiScaler.ini`.
- Do not mix older experimental V2–V14 DLLs with the V15 runtime directory.

If the problem persists, roll back with the uninstall script and verify that vanilla WH3 + your standalone ShortFuse/DLSS5 setup is stable.

## ReShade menu does not appear

This is a known limitation. XeFG owns the final DX12 interop presenter, and the ReShade overlay path may not be composed into the final output. The ShortFuse addon can still be active. Use the four live OptiScaler status lines to verify DLSS5 and XeFG.

For now, choose your ShortFuse/DLSS5 preset **before installing/enabling RC1**.

## Need a debug log

Only for troubleshooting, edit `OptiScaler.ini` and enable file logging / a verbose log level. Restore normal logging afterward; full trace logs can become very large.
