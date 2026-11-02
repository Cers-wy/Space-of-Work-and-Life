# Space 1.2.0 build6 验收记录

日期：2026-10-29。交付：`output/Space.app`，macOS 14+ / Apple Silicon。

## 完成改动

- 自定义下拉菜单测量触发控件实际宽度，项目菜单与字段左右边缘一致；继续支持方向键、回车、Esc。
- 新建、详情和数据与设置共用32pt标题栏，从原64pt减半；保留当前主题与苹方字体。
- 说明支持⌘V贴PNG/TIFF截图及文件，也支持多选上传。正文独立保存，图片和附件显示在正文下方，提供缩略图、Quick Look预览、另存与移除。
- 附件原始字节随任务存入SQLite，无原文件路径依赖；取消表单不提交。备份、恢复、撤销与手动加密同步均包含附件。
- 单个附件≤10MB，每项任务≤20个、合计≤20MB；正文上限仍为5,000个UTF-16单位。
- 含附件JSON为Space V4，旧V1/V2/V3仍可读；JSON整体上限64MB。SQLite导入64MB及同步数据库32MB上限继续保留。旧应用不能读取含附件的新备份。

## 验证结果

- 40项自动测试全部通过：旧任务兼容、PNG原字节、TIFF转PNG、普通文本回退、文件字节独立性、附件校验、V4防降级、大JSON往返、SQLite重开/快照/恢复及本地加密同步与合并。
- Release构建、应用临时签名严格校验、Info.plist校验通过。
- 独立QA实际核对项目菜单等宽，以及新建/详情/设置紧凑标题栏。
- 实际输入中文任务和说明，通过文件面板上传TXT；Quick Look正确显示中文及换行。
- 保存后重新打开任务详情，正文和文件仍在；在说明中⌘V粘贴图片，出现图片附件条目。
- 保存后独立SQLite读取确认PNG与TXT均存在，TXT字节与来源一致，完整性检查ok。
- PNG/TIFF处理另有AppKit自动测试，自动测试不改写系统剪贴板。

测试日志：`work/space-attachments-tests.log`。构建日志：`work/space-attachments-build.log`。

## 数据隔离及使用

独立测试应用为`work/Space Attachments QA.app`，bundle为`com.cers.orbit.qa.attachments`，数据位于`work/native-qa/attachments`。未向正式空间添加验收任务。真实远程服务和跨设备网络联调仍待配置同步位置，本轮同步测试使用独立本地目录。

旧应用和源码保留于`work/backups/space-before-attachments/`。测试版验收后退出；正式应用当前工作状态不强制关闭。退出正在运行的旧进程后，重新打开`output/Space.app`使用更新。
