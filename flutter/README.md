# Space · Flutter 桌面版

Space 2.0.3（4）使用 Flutter 3.47.9 / Dart 3.13.7，共用 macOS 与 Windows 界面及业务代码。macOS 安装包适用于 Apple Silicon（arm64）。本目录不包含个人任务、真实附件、Token 或恢复密钥。

## 界面与交互

- 看板、列表、甘特图、日历四视图；项目、分类、状态、优先级、日期与搜索共用筛选。
- 明亮主题为蓝白，暗色主题为黑灰与紫色环境光。保持现有主题色、毛玻璃和卡片流光；支持跟随系统及平滑主题过渡。
- 项目管理采用文件夹与项目条目线性图标，任务状态管理采用三个节点与列表线性图标；视图图标统一细线与圆角端点。
- 导航展开与收起入口在顶栏左上方；收起和展开均使用完整圆角矩形侧栏、平直顶栏边缘。导航和概览可独立收起，偏好写入本地设置。
- 甘特图内置状态使用蓝紫、紫晶与青绿实色填充，自定义状态稳定映射琥珀、玫瑰或青蓝色；文字与填充对比度至少4.5:1。默认排期也保留实色，并用虚线提示。
- 甘特图支持固定14天日期范围、项目分组、整条平移、两端改期与撤销；无日期默认排期仅用于显示，主动拖动后保存。未新增进度百分比字段。
- 图文说明支持加粗、下划线、光标位置粘图、附件上传、预览、另存；任务、项目与状态管理共用可撤销事务。

## 数据与同步

macOS 数据位于 `~/Library/Application Support/com.cers.space.flutter`；Windows 位于 `%APPDATA%\SpaceFlutter`。与原生版任务库独立，首次启动为空。设置仅提供 SQLite 导入、导出与上次快照恢复；内部业务协议读取 JSON V1至V6及SQLite 1至3版本。

GitHub提供“同步数据到云端”“恢复云端数据”，连接自动保存在SQLite；用户自行填写Token与恢复密钥。本地SQLite备份包含连接和凭据，云端仅包含加密业务数据。旧Base64密钥保持V1兼容，新恢复口令使用PBKDF2与AES-GCM V2包，旧客户端无法读取V2。

验收使用显式隔离目录，禁止将测试数据写入正式任务库。`SPACE_FLUTTER_DATA_DIRECTORY`环境变量用于独立运行数据目录。发布构建不设置演示参数。

## 构建与安装

安装同版本Flutter及目标平台编译工具，进入本目录：

```sh
flutter pub get
flutter test --reporter expanded
flutter build macos --release
python3 tool/package_macos.py
# Windows开发机：
flutter build windows --release
```

`pubspec.lock`锁定依赖。macOS打包脚本创建DMG、ZIP与SHA256校验文件；发布目录已存在时停止，不自动覆盖。安装步骤见[macOS安装说明](INSTALL-macOS.md)。本机临时签名未做Apple公证。

合成协议样本在`test/fixtures`，测试可直接从本目录运行，不依赖上级工作区文件。可在全新空目录生成5项合成窗口验收任务：

```sh
dart run tool/prepare_ui_review.dart /absolute/empty/review-directory
```

## 验证范围

76项自动回归通过，包括黑白两主题、四种窗口宽度、四视图、导航收展持久化、状态填色、拖动撤销、图文与数据同步协议。macOS独立窗口已验证黑白甘特图、导航点击收展，以及项目与任务状态管理入口。详情见[验收记录](verification/图标导航甘特验收-20261103.md)。

Windows共用源码已更新，本版没有重新构建或实测Windows包。真实GitHub双端同步、完整190项组合实机验收仍待执行；现有Windows性能数据不能视为本版性能结论。组件截图与实际窗口截图在记录中分别标明。

## 目录

`lib/core`为模型、图文、SQLite及加密同步；`lib/ui`为共用桌面界面；`macos`、`windows`为桌面桥接；`test`为核心、业务与交互回归；`tool`为打包、合成验收与性能工具。依赖许可证见`THIRD_PARTY_NOTICES.txt`。自有应用图标随源码提供，不分发Apple字体或SF Symbols字体。
