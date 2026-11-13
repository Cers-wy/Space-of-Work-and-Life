# Space 开发交接

更新：2026-11-13。当前开发版本 **2.3.2+19**，仍使用根目录唯一 `flutter/`。用户最新授权编译两端功能，并明确需要 Windows 便携包，Windows 实机性能测试由用户完成。本轮在 `codex/space-2.3.2-build` 保存构建快照，macOS 编译生产入口，Windows 通过现有 Actions 构建；不将编译或历史测试当作本轮性能验收。macOS 正式性能、资源测试和正式发布尚未安排，当前 2.3.1 正式分发继续保留。

### main 同步（2026-11-13，最新）

用户明确要求“提交 main”。已将构建分支截至 `12588c3a` 的三次提交快进合入本地 main，并同步到 origin/main；后续从根目录同一份 flutter 源码继续开发。本次只做分支同步及交接记录更新，应用代码与已构建的 2.3.2+19 相同，未重复测试、构建或发布安装包。未跟踪的 `.workbuddy/` 与 `flutter/.vscode/` 保持原样，不纳入提交。

### 本轮构建准备

- Windows 手动构建前恢复固定版本的四个 PP-OCRv6 模型并校验 SHA256；打包时检查 PDFium、ONNX Runtime、OCR 原生辅助库及模型完整性。两端源码、版本均为 2.3.2+19。
- macOS Release 首次编译发现本机 PDFium arm64 缓存误放通用二进制，已提取同文件的 arm64 切片恢复正确缓存；未修改 PDFium 版本或业务代码。
- 相关功能此前已通过 +19 自检，本轮不重复运行未改动且已通过的用例，也不扩展到全量回归。Windows 编译结果和本轮最终交付在下方追加，不得提前标为运行验收。

### 本轮构建结果（2026-11-13，最新）

- `codex/space-2.3.2-build@1fe87a8d` 两端同源 **2.3.2+19**：macOS 生产 Release 通用二进制编译成功，隔离启动及新增文件管理入口/筛选原生检查通过，PP-OCR small/medium 均实际识别合成中文发票。未进行正式性能测试，也未制作 macOS DMG/ZIP。
- Windows x64 Release 经现有 Actions 编译、打包成功，已取回 `downloads/Space-2.3.2-Windows-x64.zip`（约 156.1 MB）。包内程序、PDFium、ONNX Runtime、OCR 辅助库、VC 运行库和四个固定模型检查通过；用户回 Windows 系统自行运行与性能测试，不记为 Windows 验收通过。
- Windows CI 二进制来源仍为 `1fe87a8d`；后续记录提交仅补上上游许可证、最终校验和交接记录。本机 ZIP 替换第三方说明文件，二进制与 CI 一致。最终 SHA256 见同名 `.zip.sha256`。旧 2.3.1 正式包和下载入口保留。
- 已清理约 933 MB 的临时副本、测试数据、绘图缓存、重复 Artifact/便携包及经哈希确认的重复模型，保护 SDK/依赖缓存、业务数据、唯一源码及用户 IDE 配置。详情见 [本轮构建检查](flutter/verification/构建检查-2.3.2.md)。

## 测试范围约定（2026-11-13 更新）

- 后续单元测试、功能测试及性能/资源测试只覆盖本轮新增、改动或确受影响的功能/模块，按相关测试文件或用例定向运行，不默认执行全量回归。未改动且不受影响的模块全部跳过，不因缺少历史记录补测；共享组件改动仅验证确受影响的调用路径。具体以 AGENTS.md 为准。
- 本次仅更新执行规范与交接说明，未修改应用源码，未运行应用测试、构建或发布；下文已有测试结果保留为历史记录，不代表后续需要重复执行。

## 2.3.2 进行中

### 2026-11-13 标题栏纯图标与后台批量识别（+19，最新）

- 用户要求标题栏操作不显示文字，悬停或点击才显示提示；发票批量识别必须在后台进行，不影响前端操作。已实现并同步到 AGENTS.md 共用规范。
- 发票识别/删除以及文件管理添加文件/文件夹、重试失败、清除已完成均使用 `IconButtonS.toolbar`，不再按窗口宽度显示文字。共用 SpaceButton 的点击提示仅对 toolbar 启用，动作即时执行；锚定浮层关闭时清理残留提示。
- 批量识别独立 `batchRecognizing / batchNotice / batchError`，不再通过前台 `run/busy` 包裹。串行后台队列、单独底栏进度，切页、筛选、勾选、详情编辑、导入、导出及删除继续可用；仅阻止重复提交进行中的批次。
- 同一票据的主动识别复用在途任务；批次启动后尊重用户新查询与新勾选。识别写入按开始时票面字段快照逐项比对，期间已保存的手工字段不被覆盖。删除不等待 OCR，当前/排队项被跳过，迟到结果不恢复已删记录。列表异步刷新增加代次保护。
- 最终完整回归 **203 项通过**（refinement 14 项），包括等待识别时编辑保存、即时删除当前/排队项、界面继续筛选/导入/导出，以及纯图标悬停/点击提示。分析仅原有 3 条 Quill 警告，无新增问题。
- macOS **2.3.2+19** Debug 构建成功。调试中定位到钥匙串 SecItemCopyMatching 在 AppKit 主线程阻塞，导致旧窗口 AX/热重载超时；已将 macOS 凭据读写迁至工作线程，回主线程回复，保留既有存储、权限与 LAContext 规则。主界面先显示，网盘异步初始化且未配置时不读令牌，并发初始化复用同一 Future。原窗口未关闭；独立 Space-Background-Preview 演示实例已重新构建启动，VM Service 与热重载正常。原生视觉读取未复验，界面由 Widget 测试验证，待用户实际体验。
- VS Code 原有配置未改，用户 F5 仍使用 Space-Local-Preview；两者使用同一根目录 flutter 源码。Windows 只同步共用代码与版本，未构建/运行；未做正式性能资源测试或打包发布。最新记录见 Debug 自检顶部 +19 节与 refinement-2.3.2 最新日志。


### 2026-11-13 发票自动保存、批量操作与文件管理合页（+18）

用户已确认整体方案并明确授权本轮 macOS 编码和 Debug。以下为最新状态，后面的 +17 / 晚间记录保留作历史：

- 唯一源码仍为根目录 `flutter/`，在现有 main@5172bf16 未提交工作区上增量修改，保留 Workbuddy 既有改动及用户 IDE 配置。版本统一为 **2.3.2+18**。
- 主动识别通过串行共用队列直接落库有效票面字段与结构化数据；详情保持打开，无新增常驻成功提示条，标题仍为纯识别图标。个人备注/报销字段不随主动识别提交；合并自动识别期间更新的未编辑字段，避免误报 dirty。保存失败保留识别草稿并报错。报销项目沿用原生半列与圆形报销勾选。
- 发票列表新增选中项识别、批量删除。识别串行处理且逐项刷新，单张失败不中止整批；结束后仅保留失败项勾选，并在票名处提示未完成/悬停原因。批量删除明确确认原件与关联附件范围。
- 工具文件卡整卡点击/键盘直达文件管理，左下同款箭头，独立上传图标，整卡 DropTarget 接收文件/文件夹。上传队列仍在应用服务中，切页不重建。
- 文件管理与上传记录合为一页双标签，顶部使用统一 40 高标题栏。文件路径在标签右侧；上传状态“全部/上传中/失败/已完成”也移至标签右侧，窄窗口必要时另占一行。删除重复大标题、说明与独立拖拽条。
- 文件筛选直接复用任务 `_Filters` 的 Glass/16 内边距/4 滚动内边距/field/SpaceInput/SpaceMultiSelect，日期复用 DateField/DatePopover，单日匹配。名称、单日、十类多选按交集/类型并集；后缀忽略大小写，未知和无后缀归其他，`.app` 包夹可归应用程序。共用控件新增 `matchFieldWidth`，文件筛选的日期/多选弹层与条件等宽，任务筛选的多选也启用相同规则，其他表单默认尺寸保持原状。
- 仓库设置迁到全局“网盘设置”，关于 Space 始终最后。文件页齿轮通过稳定分类 ID 直达并返回原状态；兼容仓库链接和账号/仓库，沿用独立本机配置/令牌安全存储。换仓库清空列表/下载目标缓存并防止旧请求回填，不改业务备份。
- **完整 flutter test 198 项通过**；静态分析仅保留 3 条已有 Quill 实验 API 警告；最终 macOS Debug 构建成功，Info.plist 核对 2.3.2 / 18，已用 Space-Local-Preview + SPACE_DEMO=true 运行并热重启到最终源码。原生实际检查了卡片直达、文件双标签、日期/十类多选、设置直达及返回上传标签。真实仓库写入/上传未代替用户执行；识别落库、批量部分失败、删除原件、等宽弹层与竞态用隔离测试验证。
- Git 远端读取及 `git push --dry-run` 预检正常；未提交/推送本轮源码，未制作分发包。Windows 仅共用功能源码与版本，已核对既有宿主接口可复用，未构建/运行。正式功能/性能资源实测与发布仍待用户体验后另行明确安排。
- 最新记录：`flutter/verification/Debug自检-2.3.2.md` 顶部 +18 节及 `flutter/verification/refinement-2.3.2/`。有效历史性能基线与 2.3.1 正式包保留。视觉回归截图改写入 `verification/screenshots/2.3.2/`，不覆盖 2.3.1 历史截图。


### 2026-11-13 网盘首次连接 422 修复

- `core/drive.dart` 新分支初始化此前提交 `tree: []`；改为创建仅包含 `.space-drive/index.json`（内容 `{}`）的树，再创建独立根提交和 `space-drive` 引用，不复制或改动业务备份分支。并发创建导致引用已存在时重新确认远端分支。
- GitHub HTTP 错误现在标明失败操作，并保留服务端 `message/errors` 的简明内容；限制长度并遮蔽令牌，不再把所有 422 笼统归因于权限/网络。
- 相关检查 8 项通过（drive_test + file_drive_ui_test），含本机 HTTP 422 响应解析、初始化、已有分支只读连接和并发建分支；局部静态分析无问题。未读取用户令牌、未修改真实私有仓库。
- **本次 macOS Debug 已重新构建成功，产物已包含当前源码和本次修复**；晚间记录中的旧构建阻塞本次未复现，旧产物结论不再适用于当前 Debug。版本仍为 2.3.2+17。用户应重启 Debug 后按原仓库和分支重试连接。

- 已实现：发票八列含金额、票面标题、个人备注两行、详情识别/保存关闭；PDF 原生文字提取优先，macOS Vision / Windows OCR 本地接口兜底。Windows 代码尚未编译验证。
- 发票表升级到 user_version 8，新增 title、recognition；保留旧 purpose 文本作为个人备注，自动识别不写入个人备注和报销状态，保护已编辑字段；备份恢复复制新增列。
- Git 网盘独立配置和本机队列在数据目录 `file-drive/`，令牌在系统安全存储，均不混入业务备份恢复。工具首页进度、上传整页、远端文件列表、批量文件夹扫描、取消/重试/记录删除、下载校验、预览和远端删除已接入。
- Git 使用 blob/tree/commit/非强制 ref 更新，每批最多 8 文件；索引 `.space-drive/index.json` 与文件同提交，读取目录不逐文件查历史；列表按 HEAD 缓存。文件保留来源设备与首次上传时间。正常关闭经三选项检查，真实退出停止上传，重启后中断任务可重试。
- Debug 自检记录见 `flutter/verification/Debug自检-2.3.2.md`。Git 功能目前以模拟远端验证，真实私有仓库需要用户在独立连接界面配置后体验；未替用户写真实远端数据。
- 用户的出租车样照分辨率 482×1056，热敏点阵/印章导致系统 OCR 部分字段不稳定；当前按不完整结果待核对处理，不声称所有字段准确识别。原图、OCR 临时产物不进 Git。
- 最新源码改动尚未作为正式版发布；2.3.1 分发包作为当前已验证正式版本保留，2.3.2 通过后再替换。不要提前删除可用旧包或把 Debug 包当更新包。

### 2026-11-12 晚间增量修改标记（票面信息恢复两列）

- 依据用户截图反馈，把 `lib/ui/invoice_details.dart` 票面信息从 2.3.2 的单列四行改回**两列**：第一行「发票名称 | 发票号码」，第二行「销售方名称 | 开票日期」；「更多票面字段」折叠区内同样两列，奇数末尾字段宽窗口只占左半列、右列留空。统一复用 `_formPane` 的 `row()`，宽窗口两列、窄窗口（`maxWidth < 340`）自动逐行，保持既有玻璃样式与间距。
- 保留 GPT 本轮 2.3.2 的全部新增能力：发票名称字段、字段改名（销售方名称/备注）、更多字段折叠区、自动识别、保存后关闭详情；报销信息、金额区与附件区未改。后续迭代请勿再把票面信息改回单列，除非用户明确要求。
- 折叠区外补一层透明 `Material`，修复 Debug 下 `ListTile` 水波纹被带底色 `DecoratedBox` 遮挡的框架断言；同时补齐 `initState` 的花括号，消除该文件静态分析 info。
- 同步测试：`test/v231_visual_test.dart` 改为校验新的两列配对、折叠区默认收起/展开成对、备注两行输入，并在 fake async 中快进 2.3.2 OCR worker 的 25 秒空闲定时器；`test/desktop_ui_test.dart` 将「保存后详情内提示」改为「自动关闭详情 + 会话通知」，适配 2.3.2 保存行为。
- 自检：全量 `flutter test` 175 项通过；`dart analyze lib test` 仅剩既有 3 条 Quill 实验 API 警告与 `drive_test.dart` 1 条既有 info。**macOS Debug 原生重建被本机 Xcode 27.2 的 `sandbox-exec: sandbox_apply: Operation not permitted` 包解析错误阻塞**，现有 `Space.app` 为 18:39 旧产物、不含本次改动，须由用户从 VS Code F5 重建后体验；详见 `flutter/verification/Debug自检-2.3.2.md` 晚间增量节。仍属源码预览阶段：未打包、未做正式性能/资源实测、未上传 Git、未构建 Windows。

### 2026-11-12 20:50 增量修改标记（图标、重新识别、关闭交互、PDF/OCR 结构化、设置开关）

本轮按用户 6 条反馈实现，改动均在根目录 `flutter/`，未提交 Git：

1. **图标空方块修复** `lib/ui/controls.dart`：工具首页「上传记录」用到 `cloud`、文件网盘「刷新仓库」用到 `reload`，两个图标名未在 `_IconPainter` 登记，落到 `default` 只画空方块。补画云朵与双箭头循环字形（与既有 1.6px 线性风格一致），并在 `default` 处加注释说明仅为兜底；`test/invoice_structured_test.dart` 增加源码扫描，校验所有 `SpaceIcon`/`IconButtonS` 调用名都有字形，防止再出现同类漏登记。
2. **重新识别并自动回写** `lib/ui/invoice_details.dart`：标题栏入口改为「识别 / 重新识别」，可重复触发；识别结果按 `title/number/issued/seller/buyer/seller_tax/buyer_tax/cents/tax_cents/net_cents` 自动写入对应输入框，仅覆盖非空结果，命中差异才置 dirty；个人备注、消费日期、报销状态与用途不参与回写。结构化明细/合计/人员通过 `applyRecognition(structured:)` 单独落到该发票记录，提示「重新识别完成，已更新票面字段，请核对后保存」。
3. **点击左侧空白关闭** `lib/ui/invoice_details.dart`：详情面板左侧新增全高透明点击区（`invoice-details-dismiss-area`），点击走统一 `requestClose()`；无修改直接关闭，有修改弹出「保存修改？」三选（保存 / 不保存 / 取消），保存复用现有 `save()` 并在成功后关闭，Esc 与标题栏关闭共用同一路径。
4. **PDF 结构化解析** 新增 `lib/core/invoice_structured.dart`：移植 `output/invoice-parser/parser.js` 的词坐标方案——行内按 x 切栏、表头识别数值列、项目名称跨行合并、价税合计取大写与末位小写金额做一致性校验。`lib/core/invoice_pdf_engine.dart` 改用 PDFium 的**文本矩形**（`FPDFText_CountRects/GetRect/GetBoundedText`）取「一段文字 + 坐标」，不再逐字符猜字距；同时处理真实数电票的三类坑：名称标签被拆成单字/与取值分行（按相邻行 x 配对）、小数点与百分号独立成行或独立字框（按位置并回所在行并拼成完整数值）、金额列被拆散（取税率左侧最后一个数作金额）。识别链默认优先文本层，缺失或字段不全才 OCR。
5. **设置新增「发票识别」栏目** `lib/ui/settings_panel.dart`、`lib/store.dart`：第六个设置分类，含「优先使用 OCR」开关（`settings-prefer-ocr`，默认关闭，`SpaceStore.preferOcr` 持久化到 settings 表）及两段说明文字；概览页同步显示当前策略（优先 OCR / 优先 PDF 文本层）。开关传入 `InvoiceRecognizer.recognize(preferOcr:)`：开启时先渲染页面走 OCR，结果不完整再回退文本层。
6. **OCR 结果结构化** `lib/core/invoice_recognition.dart`：OCR 带坐标行经 `invoiceWordsFromOcr` + `invoiceLines` + `structuredLinesPayload(source: 'ocr')` 复用同一套结构化解析，票种、号码、日期、购销方及税号、金额、税额、未税金额写入发票字段，明细/合计/人员/校验作为 structured 保存；不写个人备注与报销状态，字段不全时提示核对原件。

- 同步测试：新增 `test/invoice_structured_test.dart`（词合并、行聚类、表头 6/8 列、明细跨行、价税合计校验、名称标签/小数点分行、PDF 无文本层安全返回、图标名登记）；`test/invoice_recognition_test.dart` 增加 preferOcr 分支与结构化落库断言；`test/settings_test.dart` 覆盖新栏目导航与开关默认关闭/持久化；`test/desktop_ui_test.dart` 覆盖点击左侧空白关闭、未保存三选、保存后关闭。
- 真实发票验证（2026-11-12 晚，用 `~/Desktop/发票测试`，不入库）：15 张数电票（成品油、旅客运输、增值税专票/普票，含 6 列与 8 列明细）全部解析出票种、号码、开票日期、购销方名称与税号、金额/税额/未税金额及明细，金额一致性校验全部通过；8 张行程单正确判为非发票并提示核对，未写入金额字段。此前同一批 PDF 只能取到票种/号码/日期。
- 自检：全量 `flutter test` **185 项通过**；`dart analyze lib test` 仅剩既有 3 条 Quill 实验 API 警告与 `drive_test.dart` 1 条既有 info。macOS Debug 原生重建仍被本机 Xcode 27.2 的 `sandbox-exec: sandbox_apply: Operation not permitted`（解析 FlutterGeneratedPluginSwiftPackage）阻塞，`Space.app` 仍是 18:39 旧产物、不含本轮改动，请用 VS Code F5 从源码重建体验。仍属源码预览阶段：未打包、未做正式性能/资源实测、未上传 Git、未构建 Windows。

以下为 **上个正式版本 2.3.1** 的有效交付和性能基线，保留供后续核查。

## 当前状态与唯一源码

- 后续只在本项目根目录下的 `flutter/` 迭代，当前检出分支为 `main`（2.3.2 开发改动在同一目录）。版本和提交以 `git status --short --branch`、`git log -1 --oneline` 为准。应用运行代码提交为 `43884e7b`，后续交付提交只增加探针、验收记录及文档，不改变两端包的应用代码。
- Git远端：`https://github.com/Cers-wy/Space-of-Work-and-Life.git`。本轮已将2.3.1快进合入main，删除已经合并的2.3.0、2.3.1开发分支；正常提交历史与历史标签保留，不强制推送或重写历史。
- 本地分发文件统一放 `downloads/`，仅保留最新macOS DMG、ZIP及Windows完整便携ZIP；校验见 [SHA256SUMS.txt](downloads/SHA256SUMS.txt)。安装包使用Release资产分发，不提交二进制到Git历史。
- macOS正式包采用 `lib/main.dart` 构建，无演示/性能探针入口；已做ZIP CRC、DMG校验、临时签名深度验证及挂载后隔离启动。签名为ad-hoc，未经Developer ID公证。
- [v2.3.1 Release](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/tag/v2.3.1) 已发布macOS DMG、ZIP和SHA256，服务端哈希与本地一致，三个匿名下载链接均返回200。旧2.2.0资产已替换，历史Release记录保留。标签指向 `d66bd91b`；其后main只追加发布核验和清理记录。
- Windows构建来源：GitHub Actions [43157693057](https://github.com/Cers-wy/Space-of-Work-and-Life/actions/runs/43157693057)，提交 `43884e7bb4b24f2c9359bfbd47a886f0ac3f92d2`，Release x64。完整ZIP的SHA256、CRC、x64 PE、PDFium及运行库结构已核验；用户Windows实机测试与手动发布待完成。

## 本轮实现及用户确认

- 发票合并：默认四边10mm，双张首票靠上、末票靠下，剩余高度分配到票间；本例间距约29.5mm。单张及末页单张仍靠上，沿用相同容量的票面尺寸。支持自动/指定票间距，裁剪虚线位于实际空隙中点，附件独立整页居中。
- `InvoiceLayout` 固定容量槽位等比适配，禁止拉伸二维码。无效设置保留上一次有效预览并禁用输出。
- 两端共用 `core/invoice_pdf_engine.dart`：PDFium检查、裁边、预览、Form对象级合并。规范化CropBox/MediaBox、非零起点和旋转，保留原二维码、印章、图像及透明蒙版；可打印批注在内存副本扁平化。原Quartz重编码及Windows栅格拼版已移除，macOS Swift仅保留系统打印面板。
- 固定 `pdfium_flutter/pdfium_dart 0.4.1`、PDFium 8125，Windows printing的PDFium同版本。开发最低Flutter3.47 / Dart3.13，运行最低macOS12保持不变。首次构建需联网下载原生库，日常运行无需Python或联网。
- 性能实测暴露旧1800px逐像素裁边对象分配过多，已改900px原生BGRA直接扫描，保留0.5mm外扩；导出仍保留PDF原对象。合并预览1600px、详情1200px，串行工作Isolate避免并发占用与阻塞UI。
- 发票详情：项目框40高而已报销控件32高导致中线偏上4px。仅在详情页提供40高居中区域，保留圆形勾选、32点击区及现有玻璃样式。浅深色、窄窗口断言通过。

## 正式验证结果

- 本轮完整自动化回归 **163项通过**；静态分析只有 `dialogs.dart:259–260` 的3条既有Quill实验API警告，无新增警告。
- [macOS性能与资源报告](flutter/verification/performance-2.3.1/README.md)：与同版本修改前 `9e08bcbe` 同探针对比，全程真实前台的有效样本。100票裁边393.6–402.2ms（基线556.6ms）；100票导出50页371.0–376.2ms（基线341.6ms）；合并空闲约0.9% CPU，关闭后约0.60%–0.67%。UI阶段p95未超过16.67ms。预览清晰度提高带来约65–76ms首次预览成本，详见报告，不隐藏取舍。
- 重复详情开关、滚动、双票首次预览、排版切换、100票处理、关闭后回收均实测。失焦样本保留标记并剔除；物理掉帧率、长期泄漏、实体打印扫码、Intel Mac未实测。
- 100票50页导出中6组原图像/蒙版解码哈希全部保留，见 [pdf-fidelity.json](flutter/verification/performance-2.3.1/pdf-fidelity.json)。私人原票、导出和测试数据库不上传Git。
- [基本自检](flutter/verification/发票合并基本自检-2.3.1.md) 记录真实Debug应用导入两张用户票据及导出。自动化夹具 `test/fixtures/invoice-*.pdf` 全为合成图形。
- 本次未影响的任务/Gantt/日历大量数据性能沿用 `verification/performance-2.0.10/` 与 `验收记录-2.0.10.md`，不写成本次实测。Windows结果待用户补充到交接和验收记录，再更新发布状态。

## 2.3.1其他既有功能

- 云同步快照 `SPACE-GITHUB-3`：AES-GCM加密完整SQLite任务/发票台账及独立附件信封 `SPACE-FILE-1`；附件按sha256增量传输、校验。手动触发，上传SHA防并发，恢复fingerprint防本地修改，兼容旧快照。无自动同步或自动冲突合并。
- `.spacepack` 本地备份：数据库+发票/附件，兼容旧裸SQLite；正式数据与恢复备份必须保护。数据库user_version7，invoice_files含sha256/bytes。
- 发票台账与详情：上传、下载、删除、编辑、筛选、导出Excel，关联附件、报销状态及共用项目；消费日期与报销月份联动。详情520宽、预览/表单独立滚动、附件左右/滚轮/键盘切换。
- 合并每页1–4张、横纵向、排序、一式两份、可选附件。圆形复选框、玻璃材质与既有主题保持一致。

## 下一位AI如何继续

1. 先读本文件和AGENTS，核对main、远端、工作区，保留用户未提交内容。`.workbuddy/` 与 `flutter/.vscode/` 是用户本地配置，未跟踪属正常状态。
2. 唯一源码是本目录 `flutter/`，不要另留正式/开发复制版。`work/flutter-sdk-bootstrap/` 是本机SDK与依赖缓存，供后续迭代使用，不是另一份Space源码；不上传Git。旧源码快照、旧安装包和失效测试产物已按本次授权清理。无法确认归属的旧数据备份迁到本地忽略的 `local-data-backups/`，不要上传或随意删除。
3. 本机SDK为 `work/flutter-sdk-bootstrap/flutter`，依赖缓存为同级 `pub-cache`。VS Code打开 `flutter/`，沿用本机「Space Dev (macOS, 演示数据)」配置；换机用下面命令。预览独立数据库，禁止拿正式库做测试。

```sh
space_sdk="$PWD/work/flutter-sdk-bootstrap"
cd flutter
PUB_CACHE="$space_sdk/pub-cache" "$space_sdk/flutter/bin/flutter" run -d macos \
  --dart-define="SPACE_DATA_DIRECTORY=$HOME/Library/Application Support/Space-Local-Preview" \
  --dart-define=SPACE_DEMO=true
```

运行测试时清除HTTP_PROXY/HTTPS_PROXY/ALL_PROXY及小写对应变量，避免flutter_tester WebSocket受代理干扰。性能探针用法见性能报告；探针包绝不能发给用户，测后重建生产入口。

Windows安装Flutter3.47.9与Visual Studio C++桌面开发工具，参考 `.github/workflows/windows-build.yml`；工作流仅构建并保存artifact，不自动发布Release。用户拿完整ZIP解压运行Space.exe，测试时选隔离数据，验证两张票据的预览、裁边、二维码/印章、单张靠上、双张间距、100票输出、系统打印及资源回收。Windows尚未验证是本轮用户明确安排，不是已通过事项。用户验收通过后，可将本地 `downloads/Space-2.3.1-Windows-x64.zip` 手动加到同一v2.3.1 Release；现有SHA256文件已包含其哈希，再补充Windows验收记录和下载入口。不要拿旧Windows包替代。

## 源码入口

|范围|入口|
|---|---|
|任务视图和共享控件|`lib/ui/workspace.dart`、`controls.dart`、`theme.dart`、`dialogs.dart`|
|发票台账、详情、合并|`lib/ui/invoice_workspace.dart`、`invoice_details.dart`、`invoice_merge.dart`|
|PDF布局、保真引擎、系统打印|`lib/core/invoice_pdf.dart`、`invoice_pdf_engine.dart`、`macos/Runner/InvoicePdf.swift`|
|数据库、附件、同步|`lib/core/repository.dart`、`invoices.dart`、`sync.dart`、`sync_service.dart`|
|验证与打包|`test/`、`tool/invoice_performance.dart`、`tool/package_macos.py`、`verification/performance-2.3.1/`|

历史细节可通过Git查看，无需恢复旧检出目录或旧分支。没有完成的Windows实测与发布必须保持待办，后续不能因本文件列有安装包而自动宣称双平台正式验证完成。
