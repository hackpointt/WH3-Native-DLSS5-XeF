# 《战锤 3》DLSS5 与多帧生成共存：排障记录

记录日期：2026-09-25 至 2026-09-26。本文描述一次 RTX 4090、WH3 DX11、RHI 管理 ReShade/视觉插件的本地实验。它记录成功与失败的证据，也记录最后的画质取舍；**目前游戏已回退到验证过的 DLSS5 + XeFG 基线，下面的 4× 版本不是推荐安装版。**

## 要解决的问题与验收口径

原有魔改把 ShortFuse/DLSS5 Feed 的原生 D3D12 DLSS 调用保留下来，并把 Depth/Motion Vectors 提供给 OptiFG → XeFG。插件更新后，这条链路曾出现启动或首次 Evaluate 失败；用户希望先恢复 DLSS5 + XeFG，再探索更高倍率的 MFG。用户负责进入“神器任务战斗”这一真实 3D 场景，代理负责备份、构建、部署及读日志。旧存档可能冻结，因此未作为可靠测试场景。

我们最终采用两个**必须在同一次游戏运行中成立**的判据：

1. `dlss5-feed.log` 明确报告 `neural forwarder loaded, neural model (feature 18) loaded`；OptiScaler 的 `EvaluateAfterUpscale` 报告 `running true`。仅看到 `Native DLSS NGX: ACTIVE`，只能证明原生 DLSS 调用活着，**不能证明 DLSS5 Neural Rendering 在运行**。
2. Streamline 报告 `DLSS-G interpolation state changed from disabled to enabled (mode=sl::DLSSGMode::eOn, numFramesToGenerate=3, ...)`。这里的 3 是每个渲染帧请求生成的额外帧数，即 4× 模式。菜单选择 4× 或插件报告最大能力，都不能代替运行时启用记录。

这两个判据确认运行链路，不直接测量显示器的实际输出帧数，也不能代替用户对残影、延迟与长期稳定性的评估。

## 排障历程

| 阶段 | 观察 | 结论与后续动作 |
| --- | --- | --- |
| 恢复基线 | DLSS5 Feed 检测到游戏，原生 NGX 与 Depth/MV 可用，XeFG 在 3D 场景中接管 Presenter 并运行。 | 保留独立备份及哈希，把它作为每次失败后的回退点。V18.3 中还修正了 Neural Rendering 输出在 hidden DX11 Present 后的可见性。 |
| 直接切换 DLSS-G | WH3 的 DX11→DX12 Presenter 创建返回 `0x887A0001`。 | 只在 WH3 的 DLSS-G 交换链描述中移除 `DXGI_USAGE_UNORDERED_ACCESS`，交换链随后能创建。 |
| 交换链创建后 | Feed 的原生 DLSS `CreateFeature` 所用命令列表 `Close()` 返回 `0x80070057`，首次 Evaluate 出现 `0xC0000005`。 | XeFG 对照组可连续 Evaluate；移除 MFG Unlock 或换用缓存的较旧 Streamline 仍复现问题，因此重点转向 Streamline/DLSS-G 的初始化时序。 |
| 只延后 DLSS-G feature 加载 | 已创建代理交换链后卸载、延后重载 DLSS-G feature，Feed 仍在重载前失败。 | 延后 feature 不够；必须让 Feed 初始化时使用普通 Presenter，之后释放并重建为 Streamline Presenter。参考 [NVIDIA Streamline 编程指南](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md)。 |
| 第一版两阶段 Presenter | 普通 DX12 Presenter 创建成功，但 Streamline 被 OptiScaler 的 D3D12 device hook 更早加载；Feed 仍崩溃。 | 把 **Streamline DLL 本身的加载**也推迟到第一次成功的原生 DLSS Evaluate 之后。 |
| 上游 OptiScaler 两阶段实验 | Feed 持续运行，Streamline 先后记录 2× 和 `numFramesToGenerate=3` 的 4× 启用区间。 | 这只解决了插帧时序。复查 Feed 日志发现 `neural forwarder NOT loaded, neural model (feature 18) NOT loaded`：当时的上游 OptiScaler 构建没有 DLSS-NR feature-18 hook，不能称为 DLSS5 + MFG。该误判已在[旧实验分支的结果](https://github.com/hackpointt/WH3-Native-DLSS5-XeF/blob/experiment/wh3-dlssg-mfg-20260926/experiments/mfg/RESULTS.md)中更正。 |
| 移植到 DLSS-NR fork | 以 `Dagherbou/OptiScaler_DLSSNR` 固定提交 `973761621353b99bee3dc7d4bb27b117fef2644f` 为底座，把 WH3 原生 DLSS 桥、V18.3 Neural Rendering 输出修正、两阶段 Presenter、延后 Streamline 加载组合进[独立补丁](../experiments/mfg-dlssnr/wh3-dlssnr-mfg.patch)。 | 保持调用顺序：原生 NVIDIA DLSS Evaluate 成功 → `DlssNr::EvaluateAfterUpscale` → Feed 神经输出可见性重捕获 → DLSS-G 消费最终画面。只有原生 Evaluate 成功后才允许加载 Streamline 与重建交换链。 |
| GitHub 构建 | [首轮](https://github.com/hackpointt/WH3-Native-DLSS5-XeF/actions/runs/36232607257)在 Windows PowerShell 中因 `.NET ReadAllText` 使用相对路径而失败；改用 `Resolve-Path` 后，[第二轮](https://github.com/hackpointt/WH3-Native-DLSS5-XeF/actions/runs/36232738811)构建及打包成功。 | 构建脚本还检查原生 DLSS、Neural Rendering 调用顺序、延后加载与菜单状态标记；产物 DLL SHA256 为 `9FCFD8FC2B23886B352BAF357F226F6B5459340CD56A187AC27625B1842517FC`。 |
| 同局 3D 实测 | Feed 在 evaluate 2 后报告 feature 18 神经模型已加载；Neural Rendering `running true` 至少到 trace 1500。Streamline 在同一进程中于 DLSS/NR 启动后创建代理 Presenter，接受 `InterpolationCount=3`，四次进入 4× 启用状态。 | **技术上的并行运行目标成立**；日志未见 Feed Evaluate 崩溃或 OptiScaler 错误。第一次反馈是画面与操作正常，但继续体验后用户认为该版本“尾音较重”，不如基线，因此决定回退。 |

上游 OptiScaler 4× 实验和 DLSS-NR fork 的 4× 实验属于**不同源码底座**。前者证明了 Streamline 的初始化顺序和 4× 请求路径，后者才在同一次运行中同时加载 feature 18 神经模型。不要把前者的截图或 `Native DLSS NGX: ACTIVE` 当作 Neural Rendering 证据。

## 最终实验的可核对证据

- [构建脚本](../experiments/mfg-dlssnr/build.ps1)、[GitHub Actions 工作流](../.github/workflows/build-wh3-dlssnr-mfg.yml)和[结果记录](../experiments/mfg-dlssnr/RESULTS.md)都在 `experiment/wh3-dlssnr-mfg-20260926` 分支。
- 本地完整日志位于 `D:\DLSS5-Audit\2026-09-25-refresh\dlssnr-mfg-combined-run-20260926`；其中 `deployment-manifest.json` 记录部署文件哈希、构建链接及备份位置。日志含用户本地路径和设备信息，因此没有直接上传 GitHub。
- 17:38:39，Feed 记录 `neural forwarder loaded, neural model (feature 18) loaded`；OptiScaler 记录 `Streamline presenter active after neural rendering`。
- 17:38:44 起，Streamline 记录 `eOn, numFramesToGenerate=3`；最后一次启用持续约 30 秒直到用户退出。Neural Rendering 的稀疏成功 trace 至少到 1500。
- 本次仅做了一局短时画面测试，没有外部工具独立测量实际输出帧数，也没有完成长时间稳定性或残影优化测试。用户后续报告“尾音较重”，这是回退的直接原因。

## 当前状态与回退

用户确认游戏已退出后，实验版的 `dxgi.dll`、`OptiScaler.ini`、`nvngx.dll_dlssnr.dll`、相关日志和 `OptiScaler/streamline` 被保存到 `D:\DLSS5-Audit\2026-09-25-refresh\dlssnr-mfg-rolled-back-20260926`。随后从 `D:\DLSS5-Audit\2026-09-25-refresh\dlssnr-mfg-predeploy-20260926` 恢复 DLSS5 + XeFG 基线；逐项 SHA256 核对通过：

```text
dxgi.dll                 B36FA955CE8B32417655967EF4824F62D50D4795702806D5A286F02B14DCCB96
OptiScaler.ini           E21420337B0CAD5C049B6E69637A2E2EDE00F345173D2F911BE4C7DC9BF75DE9
nvngx.dll_dlssnr.dll     7652E9A68DB069F035F78ABC5136FF967F9E48E5CB9CEC482C2B813F84D34016
```

实验用 Streamline 目录已从游戏中移出。用户自己的 `nvngx_dlssnr.dll`、DLSS5 Feed、RHI/ReShade 安装没有被回退操作替换。RHI 仍登记 OptiScaler 插件；以后在 RHI 中更新它可能覆盖本地定制 DLL，重新实验前应先核对哈希并再次备份。

如果继续研究 4×，应先量化并定位用户报告的“尾音较重”，再与相同场景的 XeFG 基线并排比较。此前的日志仅足以证明链路已运行，**不足以证明它优于基线**。
