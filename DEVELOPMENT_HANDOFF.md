# Space 开发交接

更新日期：2026-11-12。当前版本 **2.3.1（16）**。发票合并的均衡排版方案已获用户确认，已接入开发源码并完成 macOS 基本自检，等待用户在 VS Code 亲自体验；未进入正式性能验证、双平台打包或发布。项目约束见 [AGENTS.md](AGENTS.md)。

## 本轮续接：发票合并保真与均衡排版

- 用户已确认：双张首票靠上、末票靠下，中间分配余量；四边默认 10 mm；单张与末页单张靠上，尺寸不因少票而跳变。票间距新增“自动分配 / 指定间距”，自动最小间距 10 mm，界面显示当前页实际距离；指定模式严格按输入值排列。
- `InvoiceLayout` 逐票按固定容量槽位等比适配；混合尺寸同行顶部对齐；裁剪虚线在实际间隙中点。附件继续独立整页居中。无效设置保留最近有效预览并禁用输出。
- 新增 `core/invoice_pdf_engine.dart`，macOS、Windows 共用 PDFium 的检查、可见区域裁边、预览、对象级导入及输出；删除原 Windows 栅格拼版实现，macOS `InvoicePdf.swift` 仅保留系统打印面板。PDF 原页先规范化原始 CropBox/MediaBox、起点及旋转，再用独立 Form BBox 裁剪，不重绘二维码或印章图片；可打印批注只在内存副本中扁平化。
- 新增固定依赖 `pdfium_flutter 0.4.1` / `pdfium_dart 0.4.1`（PDFium 8125），Windows printing 的 PDFium 同步锁定 8125，避免载入不同版本 DLL。最低开发环境 Flutter 3.47 / Dart 3.13，macOS 最低 12.0 保持不变。首次源码构建需要联网下载固定原生库，之后运行不依赖网络或 Python。
- 发票详情补充修复：项目选择框高40而紧凑已报销控件高32，原先顶对齐造成中线偏上4。现仅在详情页为勾选控件提供40高居中区域，保留32点击区及圆形样式；浅深色/窄窗中线断言通过。
- 基本自检：macOS Debug 构建通过；相关 14 项测试通过；7 个修改 Dart 文件静态检查无问题。全项目检查只剩 `dialogs.dart:259–260` 的 3 条既有 Quill 实验 API 警告。减少动态效果设置下发现的 `AnimatedSize(Duration.zero)` 布局断言已修复为直接显示静态子树。
- 用户提供的发票1、发票2已在真实 Debug 应用中导入、预览并保存成功（1 页 A4）。实际应用导出中两票的二维码、红章、16 位小图标及透明蒙版解码数据均与对应原件一致；本例实际票间距约 29.5 mm，上下各 10 mm。私人原票及结果只留本机，没有纳入 Git。
- 验证记录：[发票合并基本自检](flutter/verification/发票合并基本自检-2.3.1.md)。`test/fixtures/invoice-*.pdf` 全为新造的公开测试图形，不含用户业务票据。
- Windows 能力检查：UTM 显示 Windows 运行中，但直接客机命令返回空输出，未能核验构建工具、编译或实机行为；不得将共享 Dart 测试或 macOS 输出当作 Windows 通过。
- 本轮仍未做：用户对实际源码的体验确认、正式功能/性能验证、实体打印扫码、Windows 编译和实机验证、同版本双端打包、发布到 main。新增 PDFium 会影响启动/空闲内存、发票详情 PDF 预览、裁边与大量合并导出，正式阶段须实测这些受影响场景；不能沿用旧发票引擎的性能结果直接视为通过。

以下“2.3.1 已完成的功能改进 / 完成状态”保留本轮之前的交接历史；其中 PDF 垂直居中和旧引擎描述已由本节替代。

## 当前源码与分支

| 项目 | 值 |
| --- | --- |
| 当前开发分支 | `codex/space-2.3.1`，已提交并推送到 `origin` |
| Flutter 应用版本 | `2.3.1+16`，定义在 [pubspec.yaml](flutter/pubspec.yaml) |
| 基线提交 | `8f35145f` = 2.3.0+15，远端 `origin/codex/space-2.3.0-ui-refinement` |
| 正式版 | 远端 `main` = 2.2.0+14（`541151ff`）；本地不再保留正式版分支 |

本机只保留 `codex/space-2.3.1` 这一个开发分支和一个检出目录。本地 `main`、`codex/space-2.2.0-dev`、`codex/space-2.3.0-ui-refinement` 及本地 `v2.3.0` tag 均已删除。2.3.1 源码已推送到 `origin/codex/space-2.3.1`；远端旧开发分支 `origin/codex/space-2.3.0-ui-refinement` 因 GitHub 连接间歇性中断尚未清理，正好作为 2.3.0 正式版源码的拉取来源。需要正式版时从 Git 拉取：

```sh
git fetch origin
git checkout -b main origin/main                                 # 2.2.0 正式版
git checkout -b space230 origin/codex/space-2.3.0-ui-refinement  # 2.3.0 源码
```

`origin/main` 与旧 2.3.0 分支保留在远端，可随时恢复。开始前用 `git status --short --branch` 和 `git log -1 --oneline --decorate` 核对当前状态。

## 2.3.1 已完成的功能改进

### 云端同步与备份包

- 同步内容从「任务状态 JSON」升级为「加密后的完整 SQLite 数据库（任务 + 发票台账）」＋「发票原件与附件」：快照格式 `SPACE-GITHUB-3`、附件独立信封 `SPACE-FILE-1`，沿用 AES-256-GCM（口令 PBKDF2-HMAC-SHA256），旧版快照仍可读取。
- 增量同步：上传按云端 `<sha256>.space` 清单差量补传附件；恢复按本地摘要只下载缺失或变更的文件，逐个 sha256 校验后落盘，进度显示「正在上传/恢复附件 x/y」。
- 仍为手动触发（设置中「同步到云端」「备份并恢复」），无自动同步、无自动冲突合并：上传用 GitHub `sha` 作前置条件防并发，恢复期间用 fingerprint 检测本地数据变化即中止；错误密钥或被篡改的包会被拒绝。恢复保留本机外观与连接设置，云端台账整体替换本地台账，磁盘上已有附件保留。
- 新增 `.spacepack` 备份包（zip：`space.sqlite` + `invoices/files/`）：导出、解包、恢复、清理；兼容旧版裸 `.sqlite`。设置面板导出改为「导出备份包」，恢复流程先解包再依次应用数据库、台账与附件。
- 涉及 `core/sync.dart`、`core/sync_service.dart`、`ui/sync_settings.dart`、`core/repository.dart`、`core/invoices.dart`、`ui/dialogs.dart`、`ui/settings_panel.dart`。

### 数据层

- SQLite `user_version` 上限 6 → 7，`invoice_files` 新增 `sha256`、`bytes` 两列；新增 `importInvoiceLedger()` 用快照整体替换台账并刷新 revision。
- 新增 `InvoiceSyncFile`、`InvoiceSnapshotFile`、`InvoiceSnapshot` 模型，以及 `syncManifest()`（Isolate 内流式计算摘要）、`localFileDigests()`、`writeSyncedFile()`、`readSnapshot()`。
- 涉及 `core/repository.dart`、`core/invoices.dart`。

### PDF 排版、合并与平台实现

- 合并排版新增票间距（默认 10 mm），默认边距 0 → 5 mm；末页发票不足时沿用同尺寸，同页按最小比例统一缩放并整体垂直居中；裁剪虚线改落在票间空白中线。
- 合并界面把「每页发票数」下拉换成 1~4 张/页可视化网格按钮，新增「排序设置」（添加顺序/开票日期/文件名）、「一式两份」（每张连续排两次、固定每页 2 张并禁用排版按钮）与汇总文案。
- macOS `InvoicePdf.swift` 与 Windows `invoice_pdf_windows.dart` 的票面裁剪改为逐行/列投影 + 命中阈值，暗像素阈值 246 → 242、外扩 4 → 2 px，避免噪点与页脚小字把大片空白算进票面。
- macOS `FilePanels.swift` 改用 `UTType(filenameExtension:)`，保证 `.spacepack` 在打开面板中可见。
- 涉及 `core/invoice_pdf.dart`、`ui/invoice_merge.dart`、`core/invoice_pdf_windows.dart`、`macos/Runner/InvoicePdf.swift`、`macos/Runner/FilePanels.swift`。

### 发票详情与台账

- 详情面板定宽 520，上预览、下表单独立滚动；「发票与附件」合并为单入口，左右箭头、滚轮（160 ms 节流）、键盘方向键切换，标题显示「共 N 个」，点击预览调用系统预览。
- 字段标签统一在控件上方，宽屏两列、窄窗单列；票面信息成对排列。
- 报销信息重排（已审核通过）：报销月份 + 消费日期各半宽并移到报销项目上方；报销项目半宽，右侧「是否报销」只用与输入框等高（32 逻辑像素）的圆形复选框 +「已报销」文字，不带输入框式底色与描边；用途独占整行且为最后一行。
- 详情内「消费时间」统一改为「消费日期」（字段键、保存、校验、报销月份联动）；台账列表列头与导出列名仍为「消费时间」。
- `SpaceCheckbox` 新增 `dense` 参数（默认 `false`，其他页面行为不变）；台账选中/悬停底色改为整行铺满；看板列宽提示线贴合列标题右边界；标题栏分类快捷标签不再显示选中态。
- 涉及 `ui/invoice_details.dart`、`ui/invoice_workspace.dart`、`ui/controls.dart`、`ui/workspace.dart`。

### 测试代码

- 新增 `test/sync_files_test.dart`（4 项）：附件加密包解封、错误密钥/篡改/空文件拒绝、双机内存 GitHub 模拟增量同步与恢复、`.spacepack` 导出还原、旧版 SQLite 备份兼容。
- 新增 `test/v231_visual_test.dart`（4 项）：默认模块与分类标签、看板提示线、发票列表整行选中、详情 520 定宽与附件单入口、报销信息布局断言、窄窗口不溢出、合并可视化排版与「一式两份」；输出浅色/深色截图到 `verification/screenshots/2.3.1/`。
- 更新 `invoices_test.dart`（DB v7、票间距、一式两份）、`settings_test.dart`（`.spacepack` 参数）、`workspace_test.dart`。

### 双平台代码

- 本次 macOS 原生改动 2 个文件（`InvoicePdf.swift`、`FilePanels.swift`）；Windows 侧改动在 Dart 的 `invoice_pdf_windows.dart`，`flutter/windows/` 目录本次无源码改动。
- 仓库内 `flutter/macos/` 与 `flutter/windows/` 平台工程文件随 2.3.1 分支一并同步，两端共用同一套 Dart 源码与版本号。

## 2.3.1 完成状态

### 已完成

- 上述全部功能改进的代码实现，包含 macOS 与 Windows 两端平台相关代码；版本号 `2.3.1+16`。
- 发票详情「报销信息」布局经用户审核通过；浅色/深色与窄窗口截图验收通过（截图在 `flutter/verification/screenshots/2.3.1/`，该目录被 `.gitignore` 忽略，不随 Git 同步）。
- 代码同步：全部源码改动已提交到 `codex/space-2.3.1`（`8bc9facf`）并成功推送到 GitHub；本地只保留该开发分支，正式版本地引用已删除（可从 Git 拉取）。
- 同步前的基本自检（上一轮预览阶段）：`dart analyze lib test` 无新增问题，相关 12 项 `flutter test` 通过。本机代理变量会干扰 `flutter_tester` 的 WebSocket，运行测试需临时清除 `HTTP_PROXY` 等变量。

### 未做（本轮按用户要求跳过）

- 未编译 Debug/Release 应用，未执行本轮编译验证；未做正式功能验证与性能验证，未做同版本双平台打包。
- 未产出 2.3.1 的 macOS DMG/ZIP 与 Windows 免安装 ZIP；`downloads/` 与 `output/` 中的分发包仍是 2.3.0 及更早版本，SHA256 校验文件与下载入口未更新。2.3.0 的 Windows 免安装包仍未补齐（构建环境无法访问 UTM 虚拟机）。
- 未把 2.3.1 合并或发布到 `main`；`main` 仍是 2.2.0 正式版，2.3.1 仍是开发分支。
- 功能上仍未实现：自动/定时同步、冲突自动合并、Windows 原生（C++）代码改动；台账列头「消费时间」未全局改为「消费日期」。
- 本地未跟踪的 `flutter/.vscode/`（IDE 调试配置）与 `.workbuddy/`（会话数据）未纳入 Git 同步；`output/Space-2.2.0/`、`output/Space-2.3.0/` 安装包是本地副本（未上传 GitHub Release），未删除。
- 远端整理待补做：GitHub 连接间歇性中断（TLS 握手被关闭），`v2.3.0` tag 未推送、远端旧开发分支 `origin/codex/space-2.3.0-ui-refinement` 未删除、`git fetch --prune` 未执行。源码分支本身已推送成功；网络恢复后补做即可，不影响代码同步。

## 本地调试

本轮使用 Flutter `3.47.9` 和 Dart `3.13.7`。本机可用 VS Code 打开 [flutter](flutter/) 目录，选中本地配置「Space Dev (macOS, 演示数据)」并按 F5。该配置使用独立演示数据目录，位于未同步的 `flutter/.vscode/`，换机后需按下列命令或自行配置。修改 Dart 界面后可按 `r` 热重载。

当前 Mac 的 Flutter SDK 位于项目下的 `work/flutter-sdk-bootstrap/flutter`（该目录被 `.gitignore` 忽略，不随 Git 同步）。从项目根目录执行以下命令，可复用本机已有的依赖缓存。

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

## 历史版本记录（2.3.0 及以前）

### 2.3.0 界面与交互优化

- 任务编辑器重排：标题、任务属性、任务说明、附件自上而下分区，纵向间距统一为 4 的倍数。属性改为两列三行栅格，所有输入控件同为 40 逻辑像素高；弹窗高度由 680 调到 720，说明区固定 200。
- 任务详情底部把创建、更新、完成时间合成一行紧凑说明；看板列宽改为连续比例（50%–100%），支持拖动、双击恢复与方向键微调。
- 按钮体系新增 `SpaceTextButton` 与淡色选中态；甘特图与日历的「收起 / 展开」合并为单按钮；日 / 周 / 月共用分段控件 `SpaceSegmented`。
- 发票详情改为宽屏两栏、报销月份随消费时间自动推导；发票台账支持导入 PDF/图片、编辑台账信息、管理附件、搜索筛选、批量勾选与按字段导出 Excel。
- 发票合并支持 A4 横纵向、每页 1 至 4 张、毫米边距和裁剪虚线；macOS 使用原生 PDF 实现，Windows 使用随应用分发的 PDFium 渲染票面。
- 发票报销项目与任务共用项目表；SQLite v4 旧报销项目迁移到 v5 时按归一化名称合并同名项目。发票元数据在 `space.sqlite`，原件及附件在同目录 `invoices/files`。
- 任务四种视图始终可切换，标题栏统一 40 逻辑像素；主导航选中项仅图标着色；新建任务、发票编辑、设置、项目/状态/分类管理统一表单样式，复选框统一为圆形。
- 工具首页移除重复标题，工具入口在主区域打开「工具 › 发票合并」；发票详情、任务详情与各类维护表单按钮统一 40 逻辑像素高。
- 玻璃材质、模糊、透明度、配色、线性图标与既有动效未改动，`theme.dart` 本轮无修改。

### 历史验证记录

- 2.2.0 / 2.3.0 阶段：macOS 全量自动化回归 148 项通过；`dart analyze lib` 仅保留 flutter_quill 实验成员等既有提示；界面复核覆盖 1380×860 与 1020×640 的浅色和深色截图。
- macOS 2.3.0 安装包取自同一份源码，DMG 与 ZIP 通过完整性校验，本地临时签名通过 `codesign --verify --deep --strict`。
- macOS 和 Windows 覆盖 110 项功能用例，两端发票相关用例复测通过；Windows 11 ARM64 虚拟机运行 x64 构建，验证 PDF 预览、裁边、A4 横纵向导出、附件独立分页与系统打印对话框。
- 未完成的历史项：Windows 2.3.0 免安装包（UTM 虚拟机权限受限）；性能验证按规范沿用既有结果。
- 复查台账和桌面界面时，可在 `flutter` 目录运行 `flutter test test/invoices_test.dart test/desktop_ui_test.dart`。主题和设置的回归测试位于 [settings_test.dart](flutter/test/settings_test.dart)。

## 源码入口

| 范围 | 文件 |
| --- | --- |
| 导航、任务界面和标题栏 | [workspace.dart](flutter/lib/ui/workspace.dart) |
| 按钮、下拉、复选框和主题 | [controls.dart](flutter/lib/ui/controls.dart)、[theme.dart](flutter/lib/ui/theme.dart) |
| 任务编辑、项目和状态分类管理 | [dialogs.dart](flutter/lib/ui/dialogs.dart) |
| 发票台账、详情和合并 | [invoice_workspace.dart](flutter/lib/ui/invoice_workspace.dart)、[invoice_details.dart](flutter/lib/ui/invoice_details.dart)、[invoice_merge.dart](flutter/lib/ui/invoice_merge.dart) |
| 共用项目、数据库迁移和发票存储 | [repository.dart](flutter/lib/core/repository.dart)、[invoices.dart](flutter/lib/core/invoices.dart) |
| 云端同步与备份包 | [sync.dart](flutter/lib/core/sync.dart)、[sync_service.dart](flutter/lib/core/sync_service.dart)、[sync_settings.dart](flutter/lib/ui/sync_settings.dart) |
| PDF 桥接及平台实现 | [invoice_pdf.dart](flutter/lib/core/invoice_pdf.dart)、[InvoicePdf.swift](flutter/macos/Runner/InvoicePdf.swift)、[invoice_pdf_windows.dart](flutter/lib/core/invoice_pdf_windows.dart) |
| 自动化回归 | [sync_files_test.dart](flutter/test/sync_files_test.dart)、[v231_visual_test.dart](flutter/test/v231_visual_test.dart)、[invoices_test.dart](flutter/test/invoices_test.dart)、[desktop_ui_test.dart](flutter/test/desktop_ui_test.dart) |
