# Space 开发交接

更新：2026-11-12。当前应用 **2.3.1+16**。本轮用户已确认源码体验，授权完成macOS性能与资源测试、打包、目录清理、源码合入main和无效分支清理。**Windows只构建便携包，实机功能、性能、资源测试及发布由用户自行完成。** 不得把Windows编译成功写成双平台验收完成。执行规范见 [AGENTS.md](AGENTS.md)，本次明确授权优先于默认双平台发布流程。

## 当前状态与唯一源码

- 后续只在本项目根目录下的 `flutter/` 迭代，最终分支为 `main`。版本和提交以 `git status --short --branch`、`git log -1 --oneline` 为准。应用运行代码提交为 `43884e7b`，后续交付提交只增加探针、验收记录及文档，不改变两端包的应用代码。
- Git远端：`https://github.com/Cers-wy/Space-of-Work-and-Life.git`。本轮将2.3.1快进合入main，删除已经合并的2.3.0、2.3.1开发分支；正常提交历史与历史标签保留，不强制推送或重写历史。
- 本地分发文件统一放 `downloads/`，仅保留最新macOS DMG、ZIP及Windows完整便携ZIP；校验见 [SHA256SUMS.txt](downloads/SHA256SUMS.txt)。安装包使用Release资产分发，不提交二进制到Git历史。
- macOS正式包采用 `lib/main.dart` 构建，无演示/性能探针入口；已做ZIP CRC、DMG校验、临时签名深度验证及挂载后隔离启动。签名为ad-hoc，未经Developer ID公证。
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

Windows安装Flutter3.47.9与Visual Studio C++桌面开发工具，参考 `.github/workflows/windows-build.yml`；工作流仅构建并保存artifact，不自动发布Release。用户拿完整ZIP解压运行Space.exe，测试时选隔离数据，验证两张票据的预览、裁边、二维码/印章、单张靠上、双张间距、100票输出、系统打印及资源回收。Windows尚未验证是本轮用户明确安排，不是已通过事项。

## 源码入口

|范围|入口|
|---|---|
|任务视图和共享控件|`lib/ui/workspace.dart`、`controls.dart`、`theme.dart`、`dialogs.dart`|
|发票台账、详情、合并|`lib/ui/invoice_workspace.dart`、`invoice_details.dart`、`invoice_merge.dart`|
|PDF布局、保真引擎、系统打印|`lib/core/invoice_pdf.dart`、`invoice_pdf_engine.dart`、`macos/Runner/InvoicePdf.swift`|
|数据库、附件、同步|`lib/core/repository.dart`、`invoices.dart`、`sync.dart`、`sync_service.dart`|
|验证与打包|`test/`、`tool/invoice_performance.dart`、`tool/package_macos.py`、`verification/performance-2.3.1/`|

历史细节可通过Git查看，无需恢复旧检出目录或旧分支。没有完成的Windows实测与发布必须保持待办，后续不能因本文件列有安装包而自动宣称双平台正式验证完成。
