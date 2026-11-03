Space Flutter **2.0.6（7）**，提供macOS和Windows免安装版。

## 下载与使用

- **macOS Apple Silicon（arm64）**：下载`Space-Flutter-2.0.6-macOS-arm64.zip`，完整解压后打开`Space Flutter.app`。可移入“应用程序”。
- **Windows 11 x64**：下载`Space-Flutter-2.0.6-Win11-x64-Portable.zip`，完整解压后运行`Space.exe`。保留所有DLL和`data`目录，运行库已随包提供。
- `SHA256SUMS.txt`提供两个ZIP的SHA256。下方Source code按本版标签生成，完整共用源码位于`flutter/`。

## 更新内容

- macOS原生菜单、数据库导入导出面板及覆盖警告统一中文。
- 图片按预览区域与屏幕像素密度解码，保留原图；关闭详情释放预览缓存，减少图文修改判断的重复序列化。
- 包含新版项目管理、精简设置、跟随系统主题，以及图标、导航和甘特状态填色改进。
- Windows同步到2.0.6，保留现有明暗主题、毛玻璃及流光效果。

## 数据与验证

默认数据目录保持不变，更新前请完全退出旧版，并建议先导出SQLite备份。SQLite备份可能包含自行填写的连接凭据，请妥善保管。新恢复口令使用V2加密包，旧2.0.0客户端无法读取V2，请同步更新其他设备。

macOS包已验证临时签名，尚未Apple公证。首次启动若被系统拦截，请在“系统设置→隐私与安全性”确认来源后允许。

macOS与Windows均有79项回归通过记录；Windows最终ZIP逐一验证26个文件并完成独立空首页启动，SQLite完整性检查为`ok`。完整190项组合实机验收、真实GitHub双端联调及本轮Windows性能复测仍未完成。
