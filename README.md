# Space macOS 原生版代码备份

基准：1.6.0 build10（SwiftUI + AppKit），备份日期：2026-11-02。

- `native/`：完整源码、测试、资源及构建脚本。
- `SOURCE-MANIFEST.json`：逐文件 SHA-256 校验清单。
- 后续 `docs/` 将提供基于历史记录与实际代码的完整跨平台复刻需求。

## 构建

在 macOS 14+、安装 Xcode/Swift 工具链后，从仓库根目录运行：

```sh
zsh native/scripts/test.sh
zsh native/scripts/build-app.sh
```

应用输出到 `output/Space.app`。首次运行为空工作台。

此备份不包含个人任务数据库、附件数据、Token、恢复密钥或设备同步配置。
内部 Bundle ID `com.cers.orbit` 为历史兼容标识，不应据此把产品误认为旧版 ORBIT。
