# Space 2.3.1（16）· Windows

适用于 Windows 11 x64。下载 `Space-2.3.1-Windows-x64.zip`，完整解压至可写目录后运行 `Space.exe`。这是本次源码的 Release 构建；用户将在 Windows 上自行完成性能、资源及功能验收后手动发布。

请保留同目录的全部 DLL、data 和资源目录。便携包包含 Visual C++ 运行库；无需单独安装 Flutter 或 Python。升级前退出旧版，再完整解压新版。保留本地业务备份；安装包不含数据库、令牌或恢复密钥。

继续沿用 `%APPDATA%\SpaceFlutter` 数据目录。发票合并改用 PDFium 保留原始 PDF 对象，修复二维码与印章，并支持自动票间距和单张靠上。云端同步支持加密数据库和发票附件，新增 `.spacepack` 备份包；云端恢复前仍应先备份本机。

运行前核对同批次 `SHA256SUMS.txt`。Windows 首次使用建议依次验证原票导入、单张/双张预览、指定间距、保存、系统打印、附件及 `.spacepack` 备份恢复。Windows 尚未实机验收的状态不能当作正式测试通过。
