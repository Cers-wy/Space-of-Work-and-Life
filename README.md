# Space 个人工作台

当前发布：**Space Flutter 2.0.6（7）**，适用于Apple Silicon macOS与Windows 11 x64。

[下载最新免安装版](https://github.com/18390208101/Space-macOS-native/releases/latest) · [本版发布说明](https://github.com/18390208101/Space-macOS-native/releases/tag/v2.0.6) · [Flutter源码与构建说明](flutter/README.md)

## 免安装运行

| 平台 | 下载文件 | 运行方式 |
|---|---|---|
| macOS Apple Silicon（arm64） | `Space-Flutter-2.0.6-macOS-arm64.zip` | 完整解压后打开`Space Flutter.app`，也可移入“应用程序” |
| Windows 11 x64 | `Space-Flutter-2.0.6-Win11-x64-Portable.zip` | 完整解压后运行`Space.exe`，保留全部DLL和`data`目录 |

发布附件提供`SHA256SUMS.txt`用于下载校验。GitHub也会按发布标签提供源码ZIP和tar.gz。

macOS包为本机临时签名，未做Apple公证。首次打开若被系统拦截，请在“系统设置→隐私与安全性”确认来源后允许。详细步骤见[macOS使用说明](flutter/INSTALL-macOS.md)与[Windows使用说明](flutter/INSTALL-Windows.md)。

## 功能与本版改进

看板、列表、甘特图、日历共用项目、状态、分类、优先级、日期与搜索筛选；支持任务与项目管理、撤销、图文说明、附件，以及SQLite备份和GitHub加密同步。保持现有明暗主题、毛玻璃和卡片流光。

本版整合2.0.3以来的菜单及文件面板中文修复、按预览尺寸解码图片、关闭预览释放缓存和图文修改判断优化。macOS与Windows源码位于`flutter/`，当前版本与依赖锁定在`pubspec.yaml`和`pubspec.lock`。

数据保存在用户目录：macOS为`~/Library/Application Support/com.cers.space.flutter`，Windows为`%APPDATA%\SpaceFlutter`。替换程序文件不会清空现有数据；更新前建议先在设置中导出SQLite备份。SQLite备份可能含用户自行填写的Token和恢复密钥，请妥善保管。新恢复口令使用V2加密包，旧版2.0.0客户端无法读取V2。

## 构建与验证

需要Flutter 3.47.9 / Dart 3.13.7以及目标平台开发工具链。在`flutter/`目录运行：

```sh
flutter pub get
flutter test --reporter expanded
flutter build macos --release
# Windows开发机
flutter build windows --release
```

macOS与Windows均有79项回归通过记录；Windows最终ZIP的26个文件哈希与解压启动通过，独立SQLite校验为`ok`。本轮未完成真实GitHub双端联调、完整190项组合实机验收或Windows性能复测。详见[Windows交付验收](flutter/verification/Windows免安装包验收-20261103.md)、[macOS文件面板验收](flutter/verification/导入导出文件面板中文验收-20261103.md)与[图片性能验收](flutter/verification/图片性能优化验收-20261103.md)。

`native/`与根目录`docs/`、`fixtures/`、`tools/`保留早期SwiftUI/AppKit实现和复刻基线，当前Flutter行为以`flutter/README.md`为准。旧分发二进制从当前分支移除，历史提交仍可追溯。

仓库和发布包不包含个人任务、真实附件或预设云端凭据。
