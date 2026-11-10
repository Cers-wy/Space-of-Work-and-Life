# Space 开发交接

更新日期为 2026-11-10。2.2.0（14）的安装包采用本地分发。后续开发从正式源码继续。

## 当前源码

| 项目 | 值 |
| --- | --- |
| 开发分支 | `codex/space-2.2.0-dev` |
| 开发检查点 | `v2.2.0-dev.1` |
| 检查点提交 | `bca892adb8f56e552dbb514169eb4e3f4dc3b4a8` |
| Flutter 应用版本 | `2.2.0+14`，定义在 [pubspec.yaml](flutter/pubspec.yaml) |
| 上一公开版本 | `v2.1.0` 对应提交 `a0125c87` |

开始前用 `git status --short --branch` 和 `git log -1 --oneline --decorate` 核对当前状态。项目约束见 [AGENTS.md](AGENTS.md)。

## 已完成

- macOS 和 Windows 主导航均提供工具和发票入口。工具页提供 PDF 发票合并。发票台账支持导入 PDF 和图片、查看和编辑台账信息、管理附件、搜索筛选、批量勾选及按字段导出 Excel。
- 发票合并支持 A4 横纵向、每页 1 至 4 张、毫米边距和裁剪虚线。台账可把选中的发票送入合并，并可将附件单独分页加入。macOS 使用原生 PDF 实现。Windows 使用随应用分发的 PDFium 渲染票面，合并 PDF 以图像嵌入票面和附件，打印调用系统对话框。
- 发票报销项目与任务共用项目表及管理窗口。SQLite v4 的旧报销项目迁移到 v5 时，按归一化后的名称合并同名项目，并保留其他旧项目及发票归属。删除共用项目会解除归属，保留发票记录。发票元数据在 `space.sqlite`，原件及附件存放在同一数据目录下的 `invoices/files`。
- 任务四种视图始终可切换，概览收起时入口仍可见，窄窗单独占一行。标题栏统一为 40 个逻辑像素，工具栏按钮独立排列。展开和收起导航的图标为 18 个逻辑像素，点击区域为 32 × 32。
- 主导航选中项仅图标着色。浅色主题的选中按钮使用导航蓝 `#356BFA` 配白色文字或图标。标题栏主题按钮只显示目标主题图标，浅色显示月亮，深色显示太阳。
- 新建任务、发票编辑、设置、项目管理、任务状态与分类管理统一了表单样式。单选、多选、日期和月份共用下拉入口样式。复选框统一为圆形，表头支持部分选中。任务完成按钮单独表达完成状态。
- 导航悬停与选中只显示一层底色。macOS Debug 使用绿色图标与独立 Bundle ID，正式构建使用蓝色图标。
- 看板「筛选与排序 → 看板列」支持多选并保存显示状态，至少保留一列。恢复全部后新增状态列会自动显示。任务详情、状态、分类和项目管理使用紧凑的线性图标和轻描边按钮。
- 工具首页移除重复标题。工具入口在主区域打开「工具 › 发票合并」，点击路径中的「工具」返回。发票台账的「合并打印」继续使用弹窗。侧栏和模块标题统一显示「发票」。
- 发票详情移除原件文件名标题，附件区可用左右箭头或文件选择器切换。发票详情、任务详情和项目、状态、分类维护的表单按钮统一为 40 逻辑像素高。

## 本地调试

本轮使用 Flutter `3.47.9` 和 Dart `3.13.7`。本机可用 VS Code 打开 [flutter](flutter/) 目录，选中本地配置「Space Dev (macOS, 演示数据)」并按 F5。该配置使用独立演示数据目录。通过命令行调试时，修改 Dart 界面后可按 `r` 热重载。若旧调试会话仍在运行，先停止后重新启动以加载绿色图标。

当前 Mac 的 Flutter SDK 位于项目下的 `work/flutter-sdk-bootstrap/flutter`。从项目根目录执行以下命令，可复用本机已有的依赖缓存。

```sh
space_sdk="$PWD/work/flutter-sdk-bootstrap"
cd flutter
PUB_CACHE="$space_sdk/pub-cache" "$space_sdk/flutter/bin/flutter" \
  --no-version-check run -d macos --no-pub \
  --dart-define="SPACE_DATA_DIRECTORY=$HOME/Library/Application Support/Space-Local-Preview" \
  --dart-define=SPACE_DEMO=true
```

换电脑时，在目标系统安装对应的 Flutter SDK。在 `flutter` 目录先执行 `flutter pub get`，再用该系统的 Flutter 命令启动。Windows 需要 Visual Studio 的「使用 C++ 的桌面开发」工作负载。环境配置见 [Flutter Windows 开发说明](https://docs.flutter.dev/platform-integration/windows/setup)。

```powershell
flutter doctor -v
flutter pub get
flutter run -d windows --dart-define="SPACE_DATA_DIRECTORY=$env:LOCALAPPDATA\Space-DevPreview" --dart-define=SPACE_DEMO=true
```

Windows 构建通过 CMake 获取固定版本的 PDFium。便携包须保留全部运行库、资源目录及 PDFium 许可文件。

## 已验证与待办

- 开发过程中，macOS Debug 构建和隔离数据启动通过。合并报销项目时，144 项自动化测试通过，覆盖旧库迁移、项目改名和删除、发票编辑选择任务项目、保存后重新读取，以及 A4 排版。
- 最后一轮标题栏图标与浅色选中配色调整后，79 项相关测试通过，并检查了浅色和深色截图。这两组数字来自不同阶段。随后保存检查点并更新应用版本号。
- 上一轮看板和导航调整的 macOS 全量自动化回归 148 项通过。Debug 构建使用 `AppIconDev`，启动后从独立目录载入 9 条演示任务，SQLite 完整性检查通过。
- 2.2.0 本轮按用户指令执行双平台功能验证，跳过性能测试。新安装包仅保存在本地，GitHub 同步源码。
- macOS 和 Windows 覆盖 110 项功能用例。图片预览修复后，两端发票相关用例复测通过。Windows 11 ARM64 虚拟机运行 x64 构建，使用合成票据验证 PDF 预览、裁边、A4 横纵向导出、附件独立分页、原件路径保护及系统 A4 打印对话框。macOS DMG 和 Windows ZIP 解压或挂载后均在隔离数据目录启动。

复查台账和桌面界面时，可在 `flutter` 目录运行 `flutter test test/invoices_test.dart test/desktop_ui_test.dart`。主题和设置的回归测试位于 [settings_test.dart](flutter/test/settings_test.dart)。

## 源码入口

| 范围 | 文件 |
| --- | --- |
| 导航、任务界面和标题栏 | [workspace.dart](flutter/lib/ui/workspace.dart) |
| 按钮、下拉、复选框和主题 | [controls.dart](flutter/lib/ui/controls.dart)、[theme.dart](flutter/lib/ui/theme.dart) |
| 任务编辑、项目和状态分类管理 | [dialogs.dart](flutter/lib/ui/dialogs.dart) |
| 发票台账、详情和合并 | [invoice_workspace.dart](flutter/lib/ui/invoice_workspace.dart)、[invoice_details.dart](flutter/lib/ui/invoice_details.dart)、[invoice_merge.dart](flutter/lib/ui/invoice_merge.dart) |
| 共用项目、数据库迁移和发票存储 | [repository.dart](flutter/lib/core/repository.dart)、[invoices.dart](flutter/lib/core/invoices.dart) |
| PDF 桥接及平台实现 | [invoice_pdf.dart](flutter/lib/core/invoice_pdf.dart)、[InvoicePdf.swift](flutter/macos/Runner/InvoicePdf.swift)、[invoice_pdf_windows.dart](flutter/lib/core/invoice_pdf_windows.dart) |
| 自动化回归 | [desktop_ui_test.dart](flutter/test/desktop_ui_test.dart)、[invoices_test.dart](flutter/test/invoices_test.dart) |
