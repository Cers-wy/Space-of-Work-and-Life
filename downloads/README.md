# Space 下载

## 2.3.3（20）

- Windows x64：[Space-2.3.3-Windows-x64.zip](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/download/v2.3.3/Space-2.3.3-Windows-x64.zip)，完整解压后运行 `Space.exe`。源码 `094a2ac3`，由 [Windows CI 43406561773](https://github.com/Cers-wy/Space-of-Work-and-Life/actions/runs/43406561773) 完成 Release x64 编译与便携包完整性检查；已核对 `Space.exe`、`pdfium.dll`、ONNX Runtime、OCR 原生辅助库、四个固定 OCR 模型与 VC 运行库。**用户 Windows 实机功能与性能测试尚未完成**。校验见 `SHA256SUMS.txt`。
- **macOS 本轮无新包**。本机 Xcode 27.2 的包解析被系统拒绝（`sandbox-exec: sandbox_apply: Operation not permitted`），`flutter build macos` 与直接 `xcodebuild` 均失败，未构造 macOS 资产，也不能视为 macOS 已验证。当前 macOS 可用包仍为 2.3.2（19）。
- 本次变更：发票批量更新（月份/项目/备注，单事务校验）、窄窗口标题栏横向滚动、价税合计解析更严格、**修复任务看板点击筛选时整窗闪一下**。
- [发布说明](../flutter/verification/发布说明-2.3.3.md) · [本轮验证记录](../flutter/verification/release-2.3.3/verification.json) · [SHA256 校验](SHA256SUMS.txt)。

## 2.3.2（19，macOS 仍为当前可用包）

- macOS 通用包：[DMG](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/download/v2.3.2/Space-2.3.2-macOS-universal.dmg) · [ZIP](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/download/v2.3.2/Space-2.3.2-macOS-universal.zip)，包含 arm64 / x86_64。应用版本 2.3.2（19），本地 ad-hoc 签名，未公证；实测平台为 Apple Silicon。该轮按用户确认跳过正式性能与资源实测。
- [发布说明与新增功能介绍](../flutter/verification/发布说明-2.3.2.md) · 完整解压 ZIP 或挂载 DMG 后，将 Space.app 放入 Applications，升级前退出旧版。

本目录只保留当前交付包；历史有效基线与验证记录保留在 [历史性能报告](../flutter/verification/performance-2.3.1/README.md)，历史结果不作为本轮性能实测。

[macOS安装说明](../flutter/INSTALL-macOS.md) · [Windows使用说明](../flutter/INSTALL-Windows.md) · [开发交接](../DEVELOPMENT_HANDOFF.md)
