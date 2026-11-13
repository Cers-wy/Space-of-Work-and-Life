# Space 2.3.2（19）· macOS

适用于 macOS 12 或更新版本。通用包包含 Apple Silicon 与 Intel 架构，本次实测平台为 Apple Silicon。打开 DMG，将 Space 拖到 Applications；也可完整解压同批 ZIP 中的 `Space.app`。升级前退出旧版。核对同批 `SHA256SUMS.txt`，应用版本应为 2.3.2（19）。

本包使用本地临时签名（ad-hoc），未做 Developer ID 公证。首次打开请按 macOS 显示的提示操作。

新版继续沿用 `~/Library/Application Support/com.cers.space.flutter` 的业务数据；分发包不包含演示数据、正式数据库、令牌或恢复密钥。请保留业务恢复备份。

本版支持发票识别后自动保存票面信息、后台批量识别和批量删除。工具 → 文件管理提供文件列表与上传记录双标签，支持名称、单日创建日期、文件类型多选筛选；仓库连接统一在设置 → 网盘设置维护。文件识别使用内置本地 OCR，结果仍需核对；网盘上传仅在用户配置并添加文件后执行。恢复数据前先导出本机备份。

性能、功能及平台验收状态以项目最新开发交接和同版本验证记录为准。Windows 由用户另行测试并手动发布。
