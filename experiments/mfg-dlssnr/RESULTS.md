# WH3 DLSS5 Neural Rendering + DLSS-G 4× runtime test

Build: [`f51d29e`](https://github.com/hackpointt/WH3-Native-DLSS5-XeF/commit/f51d29e), [GitHub Actions run 36232738811](https://github.com/hackpointt/WH3-Native-DLSS5-XeF/actions/runs/36232738811). The resulting `OptiScaler.dll` SHA256 is `9FCFD8FC2B23886B352BAF357F226F6B5459340CD56A187AC27625B1842517FC`.

The first local 3D-scene run used the fork-aware DLSS-NR source and a deferred Streamline swapchain. In **the same game process**, the DLSS5 Feed log reported `neural forwarder loaded, neural model (feature 18) loaded` after evaluate 2. OptiScaler subsequently reported `EvaluateAfterUpscale returned; running true` through at least trace 1500, while its post-hidden-present Neural Rendering colour recapture succeeded through at least probe 1500.

Only after native DLSS and Neural Rendering had evaluated did the two-stage presenter load Streamline and recreate the swapchain. The Streamline DLSS-G plugin reported support for up to five generated frames, accepted interpolation count 3, and logged four transitions to `eOn, numFramesToGenerate=3` during the run. The last enabled interval lasted about 30 seconds before the user exited. No OptiScaler error lines or Feed evaluate crash appeared in the saved logs.

This establishes concurrent Neural Rendering and an active 4× DLSS-G request at runtime. It does **not** measure the actual display-output frame count or settle visual quality and frame pacing. User assessment of the 3D scene is pending.

Local evidence: `D:\DLSS5-Audit\2026-09-25-refresh\dlssnr-mfg-combined-run-20260926`. The predeployment stable DLSS5 + XeFG files are backed up at `D:\DLSS5-Audit\2026-09-25-refresh\dlssnr-mfg-predeploy-20260926`.
