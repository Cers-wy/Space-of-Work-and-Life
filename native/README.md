# Space macOS 原生应用

Space 是个人任务工作台，提供看板、列表、甘特图和日历。任务、项目、状态、排期、图文说明及附件保存在用户本地 SQLite，支持备份恢复和加密同步。

## 界面与功能

- 蓝色奶白与黑灰亮紫双主题；全局分层毛玻璃、背景柔光、任务卡内部光效及四周流光。
- 左侧导航和顶部概览可独立收起；顶部分类快筛、全库统计、四视图图标及统一筛选浮层。
- 任务增改删、完成/重开、项目创建复用、自定义状态启停/迁移删除/拖动排序、单步撤销。
- 图文说明支持加粗、下划线、光标粘图；附件支持上传、预览、另存与移除。
- 甘特图按项目分组，显示所选日起14天，支持平移与两端改期；日历提供日/周/月及当日清单。
- SQLite/JSON导入导出、上一份快照恢复；GitHub私有仓库加密同步和其他位置SP验证码手动同步。

详细页面与特效见 [界面与特效说明](../docs/02-界面与特效说明.md)，全部业务规则见 [当前功能说明](../docs/01-当前功能说明.md)。

## 系统与构建

Apple Silicon，macOS 14或更新，SwiftUI + AppKit。安装Xcode或带macOS SDK的Swift工具链，在仓库根目录执行：

```sh
zsh native/scripts/test.sh
zsh native/scripts/build-app.sh
open output/Space.app
```

应用输出至output/Space.app。应用采用本机临时代码签名，未做Developer ID分发签名或Apple公证。

## 数据位置

`~/Library/Application Support/com.cers.orbit/`，主库space.sqlite，上一份space.previous.sqlite。GitHub连接及基线为github-sync.json；访问凭据与恢复密钥由系统钥匙串保存。

## 源码目录

- Sources/OrbitCore：模型、查询、排期、SQLite、备份及同步协议。
- Sources/OrbitApp：主界面、任务表单、图文编辑器、设置与系统集成。
- Sources/CSQLite：系统SQLite桥接。
- Tests：领域、持久化、富文本、附件、拖动及同步测试。
- Resources：应用信息与S图标；scripts：测试、构建和图标生成。
