# Space

Flutter/Dart 桌面工作台，macOS与Windows共用业务、界面与版本，当前版本 **2.0.7（8）**。

源码与使用说明：[flutter](flutter/README.md)。

下载最新文件：[macOS DMG](downloads/Space-Flutter-2.0.7-macOS-arm64.dmg) · [macOS ZIP](downloads/Space-Flutter-2.0.7-macOS-arm64.zip) · [Windows 11 x64免安装ZIP](downloads/Space-Flutter-2.0.7-Win11-x64-Portable.zip) · [SHA256](downloads/SHA256SUMS.txt)。

Mac完全退出旧版后替换应用；Windows完整解压后打开`Space.exe`。更新沿用现有Flutter数据库，包内不含正式数据或凭据。macOS包使用临时签名，未做Apple公证。

功能包括任务、项目、自定义状态、看板、列表、甘特图、日历、图文附件、SQLite备份和GitHub加密同步。看板列支持独立四档调宽及记忆；全部滚动区域使用细滚动条，可在设置中全局隐藏。

仓库当前文件只保留Flutter工程及最新分发文件，macOS平台目录是Flutter runner所需桥接代码。旧SwiftUI、WPF、Avalonia工程和旧分发文件已从当前目录移除，Git历史保持可追溯。
