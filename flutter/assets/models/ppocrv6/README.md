# PP-OCRv6 bundled models

Run from `flutter/` before a fresh checkout's first build:

```sh
dart run tool/fetch_ocr_models.dart
```

The script downloads the pinned RapidAI v3.10.0 ONNX exports of PaddlePaddle
PP-OCRv6 small and medium detector/recognizer models and verifies SHA256.
Weights are bundled into the application; invoice recognition is fully local
and never downloads models during normal use. Binary model assets are ignored
by source Git; the fetch script, fixed release and hash manifest are tracked.

Default: small. Enhancement: medium only for incomplete/low-confidence results.
The CTC dictionary is read from each model's `character` metadata to prevent
dictionary/model mismatches. Images and model sessions run in a worker isolate.

Sources:
- https://github.com/PaddlePaddle/PaddleOCR
- https://github.com/RapidAI/RapidOCR/blob/main/python/rapidocr/default_models.yaml
- https://www.modelscope.cn/models/RapidAI/RapidOCR

PaddleOCR and RapidOCR model exports are subject to their original licenses
and attribution requirements. ONNX Runtime is distributed under the MIT
license, version 1.18.1, using Microsoft's official release binaries.

This implementation does not claim the upstream model benchmark as an
application result: its image preprocessing, connected-component boxes and
field parsing require separate validation on actual invoices.
