# Space · Flutter 桌面版

Space 2.0.6（7）使用 Flutter 3.47.9 / Dart 3.13.7，共用 macOS 与 Windows 界面及业务代码。macOS 安装包适用于 Apple Silicon（arm64）。本目录不包含个人任务、真实附件、Token 或恢复密钥。

## 界面与交互

- 看板、列表、甘特图、日历四视图；项目、分类、状态、优先级、日期与搜索共用筛选。
- 明亮主题为蓝白，暗色主题为黑灰与紫色环境光。保持现有主题色、毛玻璃和卡片流光；支持跟随系统及平滑主题过渡。
- 项目管理采用文件夹与项目条目线性图标，任务状态管理采用三个节点与列表线性图标；视图图标统一细线与圆角端点。
- 导航展开与收起入口在顶栏左上方；收起和展开均使用完整圆角矩形侧栏、平直顶栏边缘。导航和概览可独立收起，偏好写入本地设置。
- 甘特图内置状态使用蓝紫、紫晶与青绿实色填充，自定义状态稳定映射琥珀、玫瑰或青蓝色；文字与填充对比度至少4.5:1。默认排期也保留实色，并用虚线提示。
- 甘特图支持固定14天日期范围、项目分组、整条平移、两端改期与撤销；无日期默认排期仅用于显示，主动拖动后保存。未新增进度百分比字段。
- 图文说明支持加粗、下划线、光标位置粘图、附件上传、预览、另存；任务、项目与状态管理共用可撤销事务。
- macOS原生菜单及查找、拼写和语法、替换、转换、语音子菜单使用简体中文；应用包声明中文语言，系统追加的自动填充、听写和表情菜单使用相同语言。
- 应用启动时在AppKit初始化前设置本应用的简体中文语言，数据库导入、导出及附件文件面板的系统标签、取消按钮和同名替换警告保持中文。数据库面板使用独立的导入/导出标题与SQLite类型限制，附件另存使用通用面板。
- 图文预览按显示区域与屏幕像素密度解码，编辑过程中复用图片数据，关闭预览时释放对应缓存；原图仍完整保存。图文修改判断采用结构比较，避免光标移动时反复序列化整份说明。常驻流光保留原有刷新与绘制隔离逻辑。

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

Windows 2.0.6（7）免安装包：`output/flutter/Space-Flutter-2.0.6-Win11-x64-Portable.zip`。完整解压后运行`Space.exe`，同目录包含C++运行库、Flutter资源及SQLite，无需另装运行环境。使用与数据位置见[Windows使用说明](INSTALL-Windows.md)。

`pubspec.lock`锁定依赖。macOS打包脚本创建DMG、ZIP与SHA256校验文件；发布目录已存在时停止，不自动覆盖。安装步骤见[macOS安装说明](INSTALL-macOS.md)。本机临时签名未做Apple公证。

合成协议样本在`test/fixtures`，测试可直接从本目录运行，不依赖上级工作区文件。可在全新空目录生成5项合成窗口验收任务：

```sh
dart run tool/prepare_ui_review.dart /absolute/empty/review-directory
```

## 验证范围

原生中文菜单在2.0.4的隔离macOS实际应用中验证，包括系统追加菜单及子项；菜单连接与快捷键保持一致。详情见[原生菜单中文验收](verification/原生菜单中文验收-20261103.md)。

79项自动回归覆盖黑白两主题、四种窗口宽度、四视图、导航收展持久化、状态填色、拖动撤销、图文与数据同步协议、大图缓存，以及数据库面板参数和取消不改库。原生文件面板已实际验证中文导出字段、导入侧栏和同名替换警告。详情见[文件面板中文验收](verification/导入导出文件面板中文验收-20261103.md)。此前的独立窗口验收见[验收记录](verification/图标导航甘特验收-20261103.md)。

两张合成4K图的解码缓存约67.64→3.12 MiB，关闭详情后为0；这是图片缓存口径，最终CPU及总内存的前台对比无有效样本。性能证据及适用范围见[图片性能优化验收](verification/图片性能优化验收-20261103.md)。

Windows 2.0.6（7）已在UTM Win11 x64重新构建Release，79项Windows回归全部通过，免安装ZIP已做解压启动检查，见[Windows免安装包验收](verification/Windows免安装包验收-20261103.md)。真实GitHub双端同步、完整190项组合实机验收仍待执行；本轮未复测Windows性能。组件截图与实际窗口截图在记录中分别标明。

## 目录

`lib/core`为模型、图文、SQLite及加密同步；`lib/ui`为共用桌面界面；`macos`、`windows`为桌面桥接；`test`为核心、业务与交互回归；`tool`为打包、合成验收与性能工具。依赖许可证见`THIRD_PARTY_NOTICES.txt`。自有应用图标随源码提供，不分发Apple字体或SF Symbols字体。
