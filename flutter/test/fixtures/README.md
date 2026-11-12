# 合成互通样本

## 发票 PDF 回归样本（2.3.1）

`invoice-predictor-crop.pdf` 是人为构造的1页PDF，包含PNG predictor 15的RGB方格图、透明红色图块、16位RGB小图、细字开票人和有效裁剪区域外的页脚。MediaBox为A4，CropBox为非零起点且超出MediaBox，用于防止票面坐标和图片重编码问题回归。`invoice-rotations.pdf` 复用同一合成票面，依次为0/90/180/270°四页。图形和文字不来自用户发票，不含企业、金额、纳税人识别号或真实二维码数据。

验证命令：`flutter test test/invoice_pdf_engine_test.dart test/invoices_test.dart`。首次运行会由固定的 `pdfium_flutter 0.4.1` 依赖下载PDFium；运行时不需要Python。

以下为原有协议互通夹具说明。

这些样本由本仓库原生 OrbitCore 1.6.0 build10 和 AppKit 生成，全部是人为构造的示例，没有读取用户任务库。样本中的恢复密钥和 SP 码是公开的固定测试数据，**绝不能用于真实备份**。

| 文件 | 用途 |
|---|---|
| 01-json-v1.json | HTML/ORBIT V1，未完成显式null、无扩展字段 |
| 01b-json-v2.json | 自定义状态与顺序，不含项目 |
| 02-json-v3.json | 项目、停用状态、本地设置和工作空间 |
| 03-json-v4.json | 中文文本附件与PNG字节 |
| 04-json-v5.json | 独立开始日期与真实截止日期 |
| 05-json-v6.json | AppKit生成的真实flat RTFD，含格式、内嵌图、普通文本镜像 |
| 06-synthetic-sqlite.base64.txt | 含V6任务的独立合成SQLite快照，使用Base64文本存储 |
| 07-github-packet.base64.txt | SPACE-GITHUB-1加密包，Base64解码后为实际packet |
| 08-sp-envelope.json | 手动同步外层JSON，可直接作为.spacesync内容使用 |
| 09-github-portable.json | 原生portable实际编码字节，用于核对序列化和SHA256 |
| EXPECTED.json | 测试key、码、固定时钟、过期日、receipt、指纹和SQLite哈希 |

## 验证顺序

1. 在隔离目录导入JSON V1～V6；核对任务字段、状态顺序、项目、附件字节、格式和图像。
2. Base64解码06，检查SQLite user_version=3、quick_check=ok，再通过目标平台业务校验读取。
3. 使用EXPECTED里的测试key解密07，检查header/AAD/GCM与逻辑内容；修改key或任意密文一字节必须失败。
4. 对09文件的原始UTF-8字节计算SHA256，与EXPECTED.githubFingerprint比对；目标平台生成portable后先比字节再比哈希。
5. 用EXPECTED里的测试SP码解密08，**测试时钟必须固定在2026-11-02T00:00:00.000Z**；日期采用2001 epoch。解出的数据库哈希应与EXPECTED.sqliteSHA256一致。
6. 将SP测试时钟改到2026-11-09T00:00:00.000Z或之后，应拒绝过期；不能按当前运行日期测试后误以为解密算法错误。
7. 图文样本经目标平台编辑/导出后在Mac上用AppKit重读；仅仅保留Base64但无法编辑不算完整复刻。

生成器为 `tools/GenerateInteropFixtures.swift`，需要macOS与AppKit，和native/Sources/OrbitCore一起编译。生成器的密文nonce和SQLite修订号每次随机，因此重新生成后密文/数据库哈希可能不同，必须使用同批次EXPECTED。不要把这些测试key/码复制到用户设置。

手动示例（在本仓库根目录，用Python提取06到临时文件）：

```python
from pathlib import Path
import base64, hashlib, json
folder = Path('fixtures')
facts = json.loads((folder/'EXPECTED.json').read_text())
database = base64.b64decode((folder/'06-synthetic-sqlite.base64.txt').read_text())
assert hashlib.sha256(database).hexdigest() == facts['sqliteSHA256']
portable = (folder/'09-github-portable.json').read_bytes()
assert hashlib.sha256(portable).hexdigest() == facts['githubFingerprint']
```

本资料包已用原生代码解密并重读这些样本。其他平台执行结果仍需实际记录，不能直接继承该通过结论。
