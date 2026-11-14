# Space 下载

## macOS 2.3.4（21，当前版本）

- [DMG 安装包](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/download/v2.3.4/Space-2.3.4-macOS-universal.dmg) · [ZIP 分发包](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/download/v2.3.4/Space-2.3.4-macOS-universal.zip) · [SHA256 校验](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/download/v2.3.4/SHA256SUMS.txt)。公开下载与远端摘要已核验。
- 两种包均包含 arm64 / x86_64；从合并后的生产源码构建，完成包完整性、深层签名、四个 OCR 模型及独立数据目录实际启动检查。实测为 Apple Silicon，未做 Intel 实机验证或 Apple 公证，使用 ad-hoc 签名。
- 新增发票每页 50 张的数据库分页查询，以及报销月份/项目/备注批量更新。保留识别后自动保存、后台批量识别、文件与上传记录双标签、网盘设置直达；修正任务筛选浅色闪烁。千张库存滚动构建 p95 从约 107 ms 降至 3.3 ms；个别其他场景仍有低频帧耗时尖峰。
- [新增功能与使用介绍](../flutter/verification/发布说明-2.3.4.md) · [本轮测试、性能及限制](../flutter/verification/macos-2026-11-14/README.md) · [GitHub Release](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/tag/v2.3.4)。

## Windows

两端最新共用源码版本为 2.3.4+21，已合并 `2026-11-13-win优化` 的备份句柄修复、自定义安装路径及用户数据保护逻辑，并同步新增分页。本轮仅同步源码，未构建或实机测试新的 Windows 包；昨晚验证记录见 [Windows 基线](../flutter/verification/windows-2026-11-13/README.md)，不能代替本轮分页验收。

现有 [2.3.3 Windows x64 便携包](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/download/v2.3.3/Space-2.3.3-Windows-x64.zip) 来自 `094a2ac3` / CI 43406561773，仍作为历史可用包保留，不包含本次 2.3.4 分页代码，也不是昨夜优化分支的新安装器。完整解压后运行 `Space.exe`。已有 Windows Release 资产未改动。

本地只保留最新已验证 macOS 2.3.4 DMG/ZIP、现有 Windows 2.3.3 便携包及校验；旧 macOS 包已在新版上传核验后清理。历史有效基线及必要记录保留。

[macOS 安装说明](../flutter/INSTALL-macOS.md) · [Windows 使用说明](../flutter/INSTALL-Windows.md) · [开发交接](../DEVELOPMENT_HANDOFF.md)
