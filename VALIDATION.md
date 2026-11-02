# 本次备份与资料验证记录

日期：2026-11-02（Asia/Shanghai）。原生基准：Space 1.6.0 build10。

## 已完成

- 私有源码仓库：18390208101/Space-macOS-native。
- 源码固定提交：1b07c70dbfdddbb8fb3393937badce91ed6413aa。
- 45个native文件逐文件SHA256与工作台当前源码完全一致；未修改基线源码。
- 在独立备份副本运行native/scripts/test.sh：74项XCTest通过、0失败（2026-11-02）。
- 8份详细Markdown文档与190条连续编号的验收用例；本地文档相对链接检查通过。
- 13份历史Markdown材料复制保留；需求明确标记旧规则替代与当前实现差异。
- 真实原生OrbitCore + AppKit生成合成JSON V1～V6、RTFD图文、SQLite、GitHub加密包、SP信封；加密解回与AppKit图文重读通过。
- 合成SQLite user_version=3、quick_check=ok；含1条任务、2附件及富文本，数据库哈希与portable指纹匹配EXPECTED。
- 仅选择源码、需求、历史说明、工具和合成样本；常见GitHub令牌/私钥模式扫描无命中。

## 结论边界

本次没有开发新的其他平台客户端。190条验收是后续目标平台需要执行的要求，不是本次全部执行通过；没有对正式任务库、真实附件、同步凭据或现有云端任务备份进行恢复/覆盖。本次加密样本仅用于协议互通，固定测试key和SP码不能用于真实备份。

历史真实GitHub单机上传/下载记录见history/space-github-sync-validation.md；真实第二设备恢复、目标系统UI、字体/材质等价及RTFD双向编辑仍需在移植阶段验证。代码扫描只能报告指定模式检查结果，不代表通用安全审计。

## 本地复核

运行python3 tools/verify_bundle.py，校验SOURCE-MANIFEST、BUNDLE-MANIFEST、相对链接、验收编号和合成样本结构。该脚本不依赖第三方Python包。
