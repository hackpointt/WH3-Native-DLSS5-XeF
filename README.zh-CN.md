# Total War: WARHAMMER III — Native DLSS5 → XeFG

[English](README.md) · [下载 RC1](https://github.com/hackpointt/WH3-Native-DLSS5-XeF/releases/tag/v0.1.0-rc1)

这是一个实验性兼容包：**保留 ShortFuse / NVIDIA 原生 DLSS5 作为超分辨率链路**，同时从 native D3D12 DLSS 调用中取得 **Depth + Motion Vectors**，桥接给 **OptiFG → Intel XeFG** 做帧生成。

这不是 Creative Assembly、SEGA、NVIDIA、Intel、ReShade、ShortFuse 或 OptiScaler 的官方版本。

## 已验证

- WH3 DX11。
- NVIDIA native D3D12 DLSS Create/Evaluate 保持原生 passthrough。
- Depth / MV 通过 private shadow adapter 喂给 OptiFG，不把 shadow 冒充为正常 upscaler。
- XeFG 成功接管 DX11→DX12 interop 最终 Presenter 并持续 Dispatch。
- RTX 4090 下 2560×1440 与 3840×2160 均完成整局战斗稳定性测试。
- OptiScaler 菜单中的成功判据：

```text
DLSS5 feeder:     DETECTED
Native DLSS NGX:  ACTIVE
Depth + MV:       READY
XeFG:             ACTIVE
```


## 安装前必须做

本包**不重新分发 ShortFuse / DLSS5**。请先安装好你自己的 ReShade + ShortFuse DLSS5，并在安装本 RC1 前启动一次 WH3，确认 DLSS5 已工作且你已经选好想用的 preset/model。

原因：XeFG 接管最终 Present 后，ReShade 面板可能无法显示，但 ShortFuse addon 本身仍可继续正常运行。

RC1 验证环境还要求先关闭：

- NVIDIA App 的 Smooth Motion / AI 插帧。
- RTSS 对 WH3 的 overlay / hook。

## 快速安装

推荐用包内 PowerShell 安装器：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Install-WH3-DLSS5-XeFG.ps1 -GameDir "D:\SteamLibrary\steamapps\common\Total War WARHAMMER III"
```

安装器会检查 `Warhammer3.exe`、ReShade / ShortFuse，备份当前 `dxgi.dll`、`OptiScaler.ini` 和 `OptiScaler` 目录，再安装 RC1。

手动安装见 `docs/INSTALL.md`。

## 第一次启动

1. 正常启动 WH3。
2. 先进入真正的 3D 战斗；第一次测试不要在主菜单开启 FG。
3. 打开 OptiScaler。
4. 确认 `FG Input = OptiFG (Upscaler)`、`FG Output = XeFG`。
5. 勾选 `Frame Generation (XeFG) → Active`。
6. 等待四行状态变成 `DETECTED / ACTIVE / READY / ACTIVE`。
7. 关闭面板，正常打一段时间，再考虑改其他选项。

随包配置故意让 FG 默认保持关闭，但已经预选测试通过的 Input/Output。

## 回滚

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Uninstall-WH3-DLSS5-XeFG.ps1 -GameDir "D:\SteamLibrary\steamapps\common\Total War WARHAMMER III"
```

它会读取安装记录并恢复安装前文件。

## 已知限制

- XeFG 接管最终 Present 后，ReShade UI 可能不可见；这不代表 DLSS5 关闭，请看“四绿”。
- 当前只正式验证 RTX 4090，其他 GPU 仍属于实验范围。
- 验证时 Smooth Motion 与 RTSS 均关闭。
- HDR、其他 overlay / swapchain injector、其他 proxy DLL 名称未纳入当前验证矩阵。
- RC1 仍属于社区实验版本，务必保留回滚备份。

## 源码

`source/WH3-native-DLSS5-XeFG.patch` 是基于以下 OptiScaler commit 的单一 consolidated patch：

`5c5e424dd137d69ef36c4231fd45b760b4c65cc8`
