# Space macOS 原生版代码备份

基准：1.6.0 build10（SwiftUI + AppKit），备份日期：2026-11-02。

- `native/`：完整源码、测试、资源及构建脚本。
- `SOURCE-MANIFEST.json`：逐文件 SHA-256 校验清单。
- [`docs/00-阅读指南与复刻基线.md`](docs/00-阅读指南与复刻基线.md)：从此开始，8份详细文档涵盖完整功能、视觉布局、数据协议、两套同步、190条验收、开发交接、源码索引与历史取舍。
- `history/`：13份历史Markdown需求与验收记录，保留版本演进证据。
- `fixtures/`：原生代码生成的合成JSON V1～V6、图文RTFD、SQLite与加密互通样本，不含用户真实数据。
- `tools/`：合成样本生成器、验收文档生成器和资料校验工具。
- `BUNDLE-MANIFEST.json`：资料包逐文件校验清单，`BACKUP-RECEIPT.json`记录源码固定提交。

## 构建

在 macOS 14+、安装 Xcode/Swift 工具链后，从仓库根目录运行：

```sh
zsh native/scripts/test.sh
zsh native/scripts/build-app.sh
```

应用输出到 `output/Space.app`。首次运行为空工作台。

此备份不包含个人任务数据库、附件数据、Token、恢复密钥或设备同步配置。
内部 Bundle ID `com.cers.orbit` 为历史兼容标识，不应据此把产品误认为旧版 ORBIT。

## 验证与跨平台交接

2026-11-02在独立备份副本运行74项原生XCTest，0失败；合成互通样本用实际OrbitCore/AppKit生成并校验。190条验收用例是目标平台待执行要求，不能视为其他系统已通过。

```sh
python3 tools/verify_bundle.py
```

目标平台未指定，本仓库不强制UI框架。完整复刻必须分别验证业务、视觉、文件/剪贴板、安全存储、RTFD双向编辑与真实双设备同步。原macOS应用采用本机临时签名、未Apple公证；其他平台签名/打包状态须如实说明。

`native/README.md`保留原样，其中有旧版本历史章节及早期范围声明；当前需求以docs/和固定源码为准。
