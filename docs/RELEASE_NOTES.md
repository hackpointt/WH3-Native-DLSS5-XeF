# RC1 Release Notes

**Release:** WH3 Native DLSS5 → XeFG RC1  
**Implementation:** V15 convergence build  
**Date:** 2026-09-13  
**Base OptiScaler commit:** `5c5e424dd137d69ef36c4231fd45b760b4c65cc8`

## Included

- V15 OptiScaler compatibility binary.
- Tested WH3 RC1 configuration preset.
- Consolidated source patch.
- Conservative install / rollback scripts.
- Four-state runtime health panel.
- Bilingual release documentation.

## Validation matrix

| Item | Result |
|---|---|
| WH3 DX11 | Passed |
| RTX 4090 | Passed |
| 2560×1440 battle | Passed |
| 3840×2160 battle | Passed |
| Native DLSS passthrough | Passed |
| Depth + MV bridge | Passed |
| XeFG activation / dispatch | Passed |
| Full battle stability | Passed |
| ReShade overlay visibility after XeFG | Known limitation |
| Smooth Motion coexistence | Not supported in RC1 validation |
| RTSS coexistence | Not supported in RC1 validation |
