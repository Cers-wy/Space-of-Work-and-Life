# Space macOS 原生版 DMG 验证

- 应用版本：1.6.0 build10。
- 架构及系统：arm64，macOS 14.0 或更新。
- 安装包：Space-1.6.0-build10-macOS-arm64.dmg。
- hdiutil verify 完整性校验通过。
- 只读挂载成功，全部应用文件与 output/Space.app 的 SHA-256 一致。
- 挂载包内代码签名严格校验通过（本机临时签名，未公证）。
- Applications 符号链接指向 /Applications，包含中文安装说明。
- 未包含任务数据库或同步凭据，未替换已安装应用。
