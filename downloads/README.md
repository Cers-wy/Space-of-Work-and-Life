# Space 下载

## 2.3.2（19）功能构建，供用户实测

- Windows x64：本目录 `Space-2.3.2-Windows-x64.zip`，完整解压后运行 `Space.exe`。两端功能共用源码 `1fe87a8d`；已在 Windows Server 2022 CI 完成 Release 编译及便携包完整性检查，用户 Windows 实机功能及性能测试尚未完成。校验见 `Space-2.3.2-Windows-x64.zip.sha256`。
- macOS：当前源码的 Release 应用在 `../flutter/build/macos/Build/Products/Release/Space.app`，支持 arm64 / x86_64；已作隔离启动及新增功能基本检查，未进行本轮正式性能测试，未制作新 DMG/ZIP。
- [Windows CI](https://github.com/Cers-wy/Space-of-Work-and-Life/actions/runs/43383147368) · [本轮记录](../flutter/verification/构建检查-2.3.2.md)。本机便携包补入了 ONNX Runtime 上游许可证及依赖说明；程序、模型和原生库二进制与 CI 一致。

## 2.3.1（16）现有正式版

macOS本轮功能、性能与资源验证已完成。Windows x64完整便携包已构建并校验，待用户实机测试及手动发布；未完成Windows性能验收。

|平台|最新文件|交付状态|
|---|---|---|
|macOS Apple Silicon|[DMG](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/download/v2.3.1/Space-2.3.1-macOS-arm64.dmg) · [ZIP](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/download/v2.3.1/Space-2.3.1-macOS-arm64.zip)|安装包已验证；ad-hoc签名，未公证|
|Windows x64|`Space-2.3.1-Windows-x64.zip`|项目本地本目录提供，完整解压后运行Space.exe；用户测试、手动发布|

三包均在本机本目录保留，校验见 [SHA256SUMS.txt](SHA256SUMS.txt)。Windows文件当前不作为已验证的公共Release资产发布。应用代码来源 `43884e7b`，最终main增加验收工具与交接文档，应用运行代码一致。

[macOS安装说明](../flutter/INSTALL-macOS.md) · [Windows使用说明](../flutter/INSTALL-Windows.md) · [性能报告](../flutter/verification/performance-2.3.1/README.md) · [开发交接](../DEVELOPMENT_HANDOFF.md)
