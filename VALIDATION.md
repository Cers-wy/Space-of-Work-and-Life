# 资料与验收说明

## 自动化检查

- native目录45个源码、资源及说明文件以SOURCE-MANIFEST校验。
- docs目录8份说明提供完整功能、UI与特效、数据、同步、验收、开发和源码索引。
- 190条验收编号连续；Markdown相对链接可以定位。
- fixtures包含JSON V1～V6、真实RTFD、合成SQLite、GitHub加密包与SP信封。
- 原生74项自动化测试已通过；合成样本已通过原生编码/解密和AppKit图文重读。

运行`python3 tools/verify_bundle.py`检查文件哈希、链接、验收编号、SQLite完整性及样本指纹。加密与RTFD生成器为tools/GenerateInteropFixtures.swift。

## 执行范围

验收用例是各实现平台需要独立执行的检查。原生测试不替代目标系统的真实界面、剪贴板、文件、双设备同步与图文往返测试。测试使用隔离目录、专用仓库和合成数据；不读取或恢复正式任务库。公开固定测试密钥和SP码只能用于fixtures，不能用于实际备份。
