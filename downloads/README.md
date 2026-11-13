# Space 下载

## 2.3.2（19）

- Windows x64：本目录 `Space-2.3.2-Windows-x64.zip`，完整解压后运行 `Space.exe`。两端功能共用源码 `1fe87a8d`；已在 Windows Server 2022 CI 完成 Release 编译及便携包完整性检查，用户 Windows 实机功能及性能测试尚未完成。校验见 `Space-2.3.2-Windows-x64.zip.sha256`。
- macOS 通用包：[DMG](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/download/v2.3.2/Space-2.3.2-macOS-universal.dmg) · [ZIP](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/download/v2.3.2/Space-2.3.2-macOS-universal.zip)，包含 arm64 / x86_64。应用版本 2.3.2（19），本地 ad-hoc 签名，未公证；实测平台为 Apple Silicon。本轮按用户确认跳过正式性能与资源实测。
- [发布说明与新增功能介绍](../flutter/verification/发布说明-2.3.2.md) · [SHA256 校验](SHA256SUMS.txt)。完整解压 ZIP 或挂载 DMG 后，将 Space.app 放入 Applications，升级前退出旧版。
- [Windows CI](https://github.com/Cers-wy/Space-of-Work-and-Life/actions/runs/43383147368) · [本轮记录](../flutter/verification/构建检查-2.3.2.md)。本机便携包补入了 ONNX Runtime 上游许可证及依赖说明；程序、模型和原生库二进制与 CI 一致。

本目录只保留当前交付包；历史 2.3.1 的有效验证及基线记录保留在 [历史性能报告](../flutter/verification/performance-2.3.1/README.md)。历史结果不作为 2.3.2 性能实测。

[macOS安装说明](../flutter/INSTALL-macOS.md) · [Windows使用说明](../flutter/INSTALL-Windows.md) · [开发交接](../DEVELOPMENT_HANDOFF.md)
