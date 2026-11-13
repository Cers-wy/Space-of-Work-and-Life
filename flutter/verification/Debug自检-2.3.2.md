# Space 2.3.2+19 macOS Debug 基本自检

## 2026-11-13 标题栏与后台识别（2.3.2+19，最新）

- 标题栏操作均为纯图标，宽窗口也不显示操作文字；悬停与点击显示 Tooltip，点击同时立即执行动作；浮层关闭时清理提示，不持续残留。
- 批量识别不占用前台全局 busy，拥有独立后台状态、进度、失败汇总；识别期间的筛选、勾选、编辑、导入、导出、删除与切页可继续。期间新保存的字段优先于较早识别快照，用户调整的查询/选择不被批次结束覆盖；当前与待识别票据可立即删除，迟到结果跳过。
- **最终完整 `flutter test` 203 项通过**，其中 refinement 14 项。新增 4 项明确验证：后台时保存手工字段/保留新选择、删除无需等待及跳过当前/待处理项、图标悬停/点击即时提示、识别进行时前台筛选与导入/导出按钮仍可用。
- 静态分析仅有原先 3 条 Quill 实验 API 警告，无新增错误/警告/info；`git diff --check` 通过。
- Debug 构建成功，Info.plist 核对 **2.3.2 / 19**。最终 `flutter run` 再次编译当前源码、同步成功并建立 VM Service。为保护现有窗口及数据，本轮新启动实例使用 **Space-Background-Preview** 独立演示目录；原有 VS Code F5 配置仍为 Space-Local-Preview，未修改用户 IDE 配置。
- 调试初期原生 AX 和热重载超时，经对本轮新建进程作 1 秒线程栈诊断，定位主线程阻塞于 SecItemCopyMatching（仅用于定位故障，不是性能测量）。已修复 macOS 凭据读写线程、界面先显示与网盘异步初始化，未配置时不读令牌；没有改凭据服务名/ACL或削弱认证。重新构建启动后热重载完成（工具日志：Reloaded 0 libraries in 68ms），响应恢复。旧窗口未关闭，原生视觉读取未复验、不计为通过；最终体验仍由用户确认。
- Windows 只同步共用源码与版本，未构建或运行。本轮未做正式性能资源实测、打包或 Git 发布。下方 +18 与更早节为历史记录；通用日志链接指向当前最新 +19 结果。

当前启动方式（在 flutter 目录）：

```sh
PUB_CACHE="$PWD/../work/flutter-sdk-bootstrap/pub-cache" \
  ../work/flutter-sdk-bootstrap/flutter/bin/flutter run -d macos --debug --no-pub \
  --dart-define="SPACE_DATA_DIRECTORY=$HOME/Library/Application Support/Space-Background-Preview" \
  --dart-define=SPACE_DEMO=true
```

新增初始化检查也验证未配置不读钥匙串、配置存在时并发初始化仅发起一次读取。

最新 [测试日志](refinement-2.3.2/tests.txt)、[分析日志](refinement-2.3.2/analyze.txt)、[构建与启动摘要](refinement-2.3.2/build.txt)。

## 2026-11-13 本轮改进（2.3.2+18，最新）

本轮完成用户已确认的发票自动保存/批量操作、网盘设置迁入与文件管理合页，并纳入最后四条浏览器批注。以下记录为当前 Debug 结果；后面的 +17 与 11 月 12 日记录是历史，不代表本次未执行的验证。

| 检查 | 结果 |
|---|---|
| 全量 `flutter test --reporter expanded` | **198 项通过**，最终包含 9 项 refinement 测试；原有识别、网盘、设置、桌面、任务与视觉用例均通过 |
| `dart analyze lib test` | 无新增错误或 warning/info；仅原有 Quill clipboardConfig / QuillClipboardConfig / onClipboardPaste 3 条实验 API 警告 |
| `flutter build macos --debug --no-pub` | 成功，产物 `build/macos/Build/Products/Debug/Space.app`；Info.plist 为 2.3.2 / 18 |
| 实际 Debug 启动 | 成功，Metal/Impeller，VM Service 可用；隔离 `Space-Local-Preview`，`SPACE_DEMO=true`；最后一次热重启成功，包含最终源码 |
| 原生交互检查 | 工具卡直达文件管理；双标签；创建日期单日日历与十类多选；齿轮直达网盘设置、关于最后；返回保持上传记录标签 |
| 等宽与外观 | DatePopover / 多选 PopupSurface 与条件字段 340 宽比较通过；跟随系统浅深色、620/1100 宽、状态/标签可达无布局异常；原有浅深色卡片及详情 520 宽、两列与半列项目验证通过 |
| 数据与失败处理 | 隔离数据库验证票面立即保存、保护未保存备注、自动回写与手工状态合并、串行批量与单张失败、指定删除、切仓库旧请求拒绝回填 |
| Git | 现有 origin HEAD 可读；`git push --dry-run origin HEAD:refs/heads/main` 返回 Everything up-to-date；仅预检，没有实际提交/推送 |
| Windows | 共用源码及 2.3.2+18 版本同步，宿主 openFiles/openFolder/readSecret/writeSecret 接口已核对；未构建、未运行、未验收 |

环境：macOS 本机，Xcode 27.2 (27B52)，Flutter 3.47.9 / Dart 3.13.7。测试使用合成 PNG、模拟识别与远端接口及临时数据库，未对真实私有仓库发起上传/删除，也未修改正式业务数据库。真实票据识别准确率、真实仓库新配置与传输由用户接下来体验；不以模拟结果声明真实端到端验收。

本轮未进行正式 Release/Profile 性能资源实测、实体 Windows 验证或发布。没有将 Debug、单元测试、原生导航操作当作性能证明。保留当前正式 2.3.1 安装包与有效历史性能基线。

复核日志见 [最终测试日志](refinement-2.3.2/tests.txt)、[静态分析](refinement-2.3.2/analyze.txt)、[Debug 构建](refinement-2.3.2/build.txt)。视觉回归截图在 `screenshots/2.3.2/`；2.3.1 截图保留。

VS Code 继续打开同一份根目录 `flutter/`，选择 **Space Dev (macOS, 演示数据)** 按 F5。若已有其他调试会话，先关闭旧 Debug 窗口再 F5，避免体验旧进程。

## 2026-11-13 网盘连接 422 修复

新分支初始化改为先创建 `.space-drive/index.json`（空对象），再建立独立提交与分支；不发送空树，不修改备份分支。并发建分支时重新读取已创建引用。GitHub 错误增加失败操作、服务端简明原因，并遮蔽令牌。

`drive_test.dart` + `file_drive_ui_test.dart` 共 8 项通过。包含首次创建、已有分支无写入、并发建分支、实际本机 HTTP 422 响应解码与令牌遮蔽，以及原有队列/列表/删除语义和进度卡片/退出选择回归。使用本机模拟接口，没有读取用户令牌或写真实 GitHub 仓库。

本次 macOS Debug 构建成功，仍为 2.3.2+17，产物已包含当前源码及本次修复；此前晚间记录的 Xcode sandbox 阻塞本次未复现。正式性能、资源及发布阶段仍待用户安排。

日期：2026-11-12。源码基线 main@5172bf16 上的当前开发改动，唯一工作目录为项目根目录下 flutter。当前为源码体验阶段，尚未进行正式性能、资源或发布验收。

## 已完成

- macOS Debug 构建成功，Info.plist 为 2.3.2 / 17；显式使用 Space-Local-Preview 隔离演示数据，SPACE_DEMO=true。
- 19 项相关基本回归通过：`invoice_recognition_test.dart`、`drive_test.dart`、`invoices_test.dart`、`invoice_pdf_engine_test.dart`、`file_drive_ui_test.dart`。
- 覆盖票面标题/前导零/日期/金额、出租车结构化文本、无效值留空、个人备注保护、用户编辑与后台识别并发保存、数据库 v8 和备份恢复；PDF 裁边、旋转、图像、对象合并原有基本路径。
- Git 通过模拟远端验证后台完成、跨服务实例读取列表、时间及设备保留、本机记录清理与远端删除区别、HEAD 更新缓存，以及并发 ref 冲突后重新合并索引、不强推、不丢其他设备记录。测试不上传真实文件。
- 首页进度卡片浅深色、208 高度、完成数、退出三选项和继续上传返回路径的 Widget 检查通过。
- Dart 静态分析无新增问题，仅保留现有 Quill 三条实验 API 警告（dialogs.dart）；Flutter analyze 在本机出现 LSP 协议截断，使用 Dart analyze --format machine lib 成功完成同一源码静态检查。
- 实际启动隔离 Debug 应用，通过原生 UI 核对工具首页上传/网盘入口、上传记录整页、独立网盘列表字段、发票八列和金额、详情识别图标、备注、附件与原件操作。已有预览 PDF 在后台提取到电子发票标题、日期、金额，列表已更新；未修改正式数据库。
- Git 远端 HEAD 可读取，push --dry-run 成功（Everything up-to-date），仅检查上传能力，没有上传本轮源码或改动远端。

## 需要用户体验及后续验证

- 首次网盘体验：工具 → 文件管理右上上传图标 → 网盘连接设置，独立填写私有仓库、分支、来源设备及 Contents 读写令牌。令牌存系统安全存储，不放入业务备份。
- 当前真实 Git 私有仓库的传输、下载和删除尚未实测；需要用户配置后体验，不将模拟服务测试写成真实远端验收。
- 用户出租车照片为 482×1056，点阵、红章和热敏打印使系统 OCR 部分字段不稳定。已验证本机离线 OCR 能读到部分文字；当前允许不完整结果并提示核对，不声称该照片全部字段正确。号码分行合并等由共享解析器处理；不推测税额，不写入个人备注。
- OCR 目前使用系统原生引擎：macOS Vision；Windows Windows.Media.Ocr，后者需要系统具备中文 OCR 语言组件。本轮没有 Windows 构建或运行测试。
- 新增/受影响功能的正式 macOS 性能、资源实测等待用户确认体验并明确安排；当前不将 Debug 或单元测试结果当作性能证明。
- 等用户后续安排才制作 macOS DMG/ZIP、上传源码及资产、替换旧分发；2.3.1 作为最新已验证正式版本保留。

## 预览

VS Code 打开本项目 `flutter`，使用已有的 **Space Dev (macOS, 演示数据)** 配置按 F5。配置使用独立数据目录，未改动用户 .vscode 配置。

亦可在 flutter 目录运行：

```sh
PUB_CACHE="$PWD/../work/flutter-sdk-bootstrap/pub-cache" \
  ../work/flutter-sdk-bootstrap/flutter/bin/flutter run -d macos --no-pub \
  --dart-define="SPACE_DATA_DIRECTORY=$HOME/Library/Application Support/Space-Local-Preview" \
  --dart-define=SPACE_DEMO=true
```

Debug 应用：`flutter/build/macos/Build/Products/Debug/Space.app`。当前不是正式更新包。

## 本轮清理与保留

清理本轮已失效的 OCR 探索脚本、卡住的旧构建/测试进程；测试临时数据库由用例清理。保留唯一源码、当前 Debug、SDK/依赖缓存、有效测试与夹具、需求和设计参考、当前正式分发包、历史有效性能基线、用户 IDE 配置和恢复备份。不会在新版尚未确认时删除唯一可用正式包。

收尾发现未跟踪的 `flutter/packages/space_ocr/`，不属于本轮这组实现创建的文件，且未被当前 pubspec 引用。为保护其他未提交工作，原样保留，不将其计入本次 Debug 功能或清理范围。

构建期间固定 PDFium 8125 下载等待，复用了本机已验证 2.3.1 应用内相同版本原生库作为构建缓存，未改原生依赖版本或应用源码下载逻辑。

## 2026-11-12 晚间增量：发票详情票面信息恢复两列（本次修改标记）

- 依据用户截图，把 `lib/ui/invoice_details.dart` 的票面信息从 2.3.2 单列四行改回**两列**：第一行「发票名称 | 发票号码」，第二行「销售方名称 | 开票日期」；「更多票面字段」折叠区内同样两列，末尾奇数字段在宽窗口只占左半列、右列留空。复用 `_formPane` 的 `row()`：宽窗口两列、`maxWidth < 340` 时逐行，沿用既有玻璃样式与 12 间距。保留 2.3.2 全部新增字段、识别、折叠区与保存后关闭详情；报销信息、金额区、附件区未改。
- 折叠区外补一层透明 `Material`，修复 Debug 下 `ListTile` 水波纹被带底色 `DecoratedBox` 遮挡的框架断言；补齐 `initState` 花括号，消除该文件原有静态分析 info。
- 同步测试：`test/v231_visual_test.dart` 改为校验新的两列配对、折叠区默认收起与展开成对、备注两行输入，并在 fake async 中快进 2.3.2 OCR worker 的 25 秒空闲定时器；`test/desktop_ui_test.dart` 将「保存后详情内提示」改为「自动关闭详情 + 会话通知」，适配 2.3.2 保存行为。
- 自检结果：全量 `flutter test --no-pub` **175 项通过**（含视觉测试 4 项：浅色/深色/窄窗口两列几何、折叠区展开成对、报销信息）；`dart analyze lib test` 仅剩既有 3 条 Quill 实验 API 警告与 `test/drive_test.dart:72` 1 条既有 info，`invoice_details.dart` 原有 info 已修。截图由当前源码重新生成到 `verification/screenshots/2.3.1/`（该目录沿用历史命名、被 .gitignore 忽略）。
- **macOS Debug 原生重建未完成（环境阻塞，非代码问题）**：`flutter build macos --debug` 在本会话调用 xcodebuild 时固定报 `xcodebuild: error: Could not resolve package dependencies: sandbox-exec: sandbox_apply: Operation not permitted`（Xcode 27.2 解析 `FlutterGeneratedPluginSwiftPackage`）。已在非受限执行环境重试、临时关闭 SwiftPM 并恢复全局配置、直接执行 `xcodebuild -list -disableAutomaticPackageResolution` 复核，均为同一错误，属于本机 Xcode/会话执行环境限制。`build/macos/Build/Products/Debug/Space.app` 仍是 18:39 的旧产物，**不含本次两列改动，不要直接打开它验收**；Dart 层已由 175 项测试的编译与运行验证。
- 交付：请用 VS Code 打开本项目 `flutter`，以 **Space Dev (macOS, 演示数据)** 配置 F5 从当前源码重建并体验；若 F5 也出现上述 xcodebuild 错误，请提供构建日志。仍属源码预览阶段：未做正式性能/资源实测，未打包 DMG/ZIP，未上传 Git，未构建 Windows。

## 2026-11-12 20:50 增量：图标、重新识别、关闭交互、PDF/OCR 结构化与设置开关（本次修改标记）

本轮按用户 6 条反馈实现，改动均在根目录 `flutter/`：

- **图标空方块** `lib/ui/controls.dart`：`cloud`（工具首页「上传记录」）与 `reload`（文件网盘刷新）两个名称未登记字形，落到 `default` 画成空方块。已补画云朵与双箭头循环图标，`default` 加兜底注释；`test/invoice_structured_test.dart` 增加源码扫描，校验所有 `SpaceIcon`/`IconButtonS` 名称都有字形。
- **重新识别** `lib/ui/invoice_details.dart`：标题栏入口为「识别 / 重新识别」，可重复触发；结果按票面字段自动回写输入框（仅非空、有差异才置 dirty），个人备注、消费日期、报销状态、用途不回写；结构化明细/合计/人员经 `applyRecognition(structured:)` 存入发票记录。
- **点击左侧空白关闭**：详情左侧全高透明点击区（`invoice-details-dismiss-area`）统一走 `requestClose()`；无修改直接关闭，有修改弹「保存修改？」三选（保存 / 不保存 / 取消），Esc 与标题栏共用同一路径。
- **PDF 结构化解析**：新增 `lib/core/invoice_structured.dart`，移植 `output/invoice-parser/parser.js` 的行/栏/明细规则；`lib/core/invoice_pdf_engine.dart` 改用 PDFium 文本矩形（`FPDFText_CountRects/GetRect/GetBoundedText`）取「文字 + 坐标」，并处理名称标签拆字/分行、小数点与百分号独立成行、金额列被拆散三类真实版式问题。默认文本层优先，缺失或字段不全才 OCR。
- **真实发票验证**：用 `~/Desktop/发票测试` 的 15 张数电票（成品油、旅客运输、专票/普票，6/8 列明细）跑通，票种、号码、日期、购销方及税号、金额/税额/未税、明细与金额校验全部正确；8 张行程单正确判为非发票。验证脚本为临时用例，验证后已删除，不进入仓库。
- **设置「发票识别」栏目** `lib/ui/settings_panel.dart` + `lib/store.dart`：新增第六分类，含「优先使用 OCR」开关（默认关闭、持久化 `preferOcr`）与说明文字；概览同步显示当前策略。开关已接入 `InvoiceRecognizer.recognize(preferOcr:)`。
- **OCR 结构化** `lib/core/invoice_recognition.dart`：OCR 带坐标行复用同一套结构化解析（`source: 'ocr'`），票种/号码/日期/购销方及税号/金额/税额/未税写入字段，明细/合计/人员/校验存 structured；不写个人备注与报销状态。
- 自检结果：全量 `flutter test --no-pub` **185 项通过**；`dart analyze lib test` 仅剩既有 3 条 Quill 警告与 `drive_test.dart:72` 1 条既有 info（均为原有问题）。
- **macOS Debug 原生重建仍未完成（环境阻塞，非代码问题）**：本轮再次执行 `flutter build macos --debug`，退出码 1，报 `Could not resolve package dependencies: sandbox-exec: sandbox_apply: Operation not permitted`（Xcode 27.2 解析 `FlutterGeneratedPluginSwiftPackage`）。`build/macos/Build/Products/Debug/Space.app` 仍是 18:39 旧产物，**不含本轮六项改动，不要直接打开验收**。
- 交付：VS Code 打开 `flutter`，以 **Space Dev (macOS, 演示数据)** F5 重建体验。重点验证：工具首页「上传记录」与网盘刷新图标、详情「识别 / 重新识别」回写、点左侧空白关闭与三选提示、设置 → 发票识别开关、PDF 电子发票解析结果。仍属源码预览阶段：未打包、未做正式性能/资源实测、未上传 Git、未构建 Windows。
