# Space 分发文件

最新本地版本为 **2.3.0（15）**，安装包保存在项目 `output/Space-2.3.0/`，未上传到 GitHub Release。最近一次公开发布仍是 [v2.1.0](https://github.com/Cers-wy/Space-of-Work-and-Life/releases/tag/v2.1.0)，提供 macOS 与 Windows 安装包。

| 平台 | 2.3.0 分发包 | 状态 |
| --- | --- | --- |
| macOS Apple Silicon | `output/Space-2.3.0/Space-2.3.0-macOS-arm64.dmg` · `Space-2.3.0-macOS-arm64.zip` | 已产出并校验 |
| Windows 11 x64 | `Space-2.3.0-Windows-x64-Portable.zip` | 本次未产出 |

Windows 包缺失原因：构建环境无法访问 UTM 中的 Windows 虚拟机（`utmctl` 与 UTM 数据目录均被系统权限拒绝），本轮未能执行 Windows 构建。补齐方式见项目 [开发交接](../DEVELOPMENT_HANDOFF.md)。

[SHA256 校验文件](SHA256SUMS.txt)。macOS 包采用本地临时签名（ad-hoc），未进行 Developer ID 公证；首次打开如被系统拦截，右键选择「打开」。
