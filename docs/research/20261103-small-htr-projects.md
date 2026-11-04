# 小型英文手写识别：优先试独立 CTC，而不是再加一个通用生成模型

> 后续决定：用户明确本项目是比赛项目，只能保持 MiniCPM-OCR、Jev 与 MiniCPM5-2B。本文保留为外部项目调查，下面的 CTC 选型建议不执行；不下载或接入任何额外识别模型。当前执行顺序见 `20261103-ocr-fidelity-synthesis.md`。

核查日期：2026-11-03。范围为官方仓库、维护者文档、作者模型卡与论文；只读取公开文字、源码和文件元数据，未下载权重、调用模型、操作服务或读取用户作业。当前约束保持：Apple Silicon 24 GiB、MiniCPM-OCR 官方 F16、Jev Q4、MiniCPM5-2B Q4。

## 结论：首选 Kraken 7.1 + PP-OCRv6 small；PyLaia IAM 无 LM 作英文专门对照

**最值得增加的是一条独立的字符 CTC 行识别旁路，同时保留字符时间步和几何位置。** 首选 **Kraken 7.1 的 PP-OCRv6 small**：已经有包含现代英文手写训练数据的公开权重，只有 **13,065,380 bytes**；官方支持 macOS ARM、MPS，也有基线、多边形分行和字符位置输出。第二选择 **Teklia/PyLaia IAM，无外部语言模型**：英文现代手写用途更明确，checkpoint 为 **42,671,836 bytes**，可以直接做英语专门基线；代价是较旧的 Python/Lightning 依赖和未验证的 Mac 环境组合。[Kraken 7.1 发布](https://github.com/mittagessen/kraken/releases/tag/7.1)、[small 模型元数据](https://zenodo.org/api/records/21788405)、[PyLaia IAM 模型卡](https://huggingface.co/Teklia/pylaia-iam)

选择顺序是工程判断，不是准确率排行榜。两者的公开测试均**没有单独测量学生错拼和冗词保留率**。关闭外部语言模型能够去掉一层词法归正压力，但不能消除识别网络自己学到的文字先验。尤其 Kraken small 模型卡明确承认混合语料的转写规范不一致、可能展开缩写；不能把“CTC”当成“必定忠于原字”的保证。[small 模型卡](https://zenodo.org/records/21788405)、[PyLaia 解码机制](https://doc.teklia.com/pylaia/usage/prediction/)

父任务提供的反例包含两个不同缺口：`suny → sunny` 是字串替换；`I'm is a student` 丢掉 `is` 是删除。**任何新识别器都必须配合插入/删除对齐，不能只替换已有词。** 当前“原文里找不到 range 就跳过”的词级修补接口不能恢复漏词。这是父任务的代码检查结论，本报告未重新读取私有图片或复现反例。

## 候选筛选：支持 HTR 不等于已有英文现代手写权重

| 候选 | 实际可用的英文现代手写权重 | 解码与词典/LM | 几何/对齐能力 | Mac 路径与本轮取舍 |
|---|---|---|---|---|
| **Kraken 7.1 / PP-OCRv6 small** | **有**。维护者发布的多语种手写/印刷行模型，训练清单明确包含 IAM | 字符/codec 标签 CTC；默认 greedy，无外接词典或 LM | 行基线与边界多边形；识别后字符 cuts/置信度；可聚合词框、输出 ALTO/PageXML；另有强制对齐 | 官方 macOS ARM、`--device mps`；**首选旁路与几何工具** |
| **Teklia/PyLaia IAM** | **有**。模型卡明确是现代英文手写、IAM RWTH split | CNN–BLSTM–CTC；`decode.use_language_model=false`；可另启 KenLM/ARPA 与 lexicon | 输入必须已分行；`decode.segmentation=char/word` 给 CTC 估计框 | 官方 CPU 解码；本机安装/MPS未验证；**第二个识别对照** |
| **pero-ocr** | **本轮未核实到可直接取得的现代英文手写 OCR 权重**。README 公开默认 OCR 为欧洲印刷，偏捷克报纸；手写引擎需联系作者 | 有字符 CTC、`TYPE=GREEDY`；也有带 LM 的 beam 解码和跨行 LM 状态 | 段落/基线/行裁切、PageXML/ALTO、CTC 强制对齐 | 源码有 CPU 路径，未见针对 Apple Silicon/MPS 的官方验证；可借几何，不先引入全套 |
| **Microsoft TrOCR small handwritten** | **有**。IAM 微调的单行英文模型 | **自回归 wordpiece**，不是字符 CTC；`num_beams=1` 仍保留 UniLM 文本解码器 | 官方模型卡未提供字符/词框或 CTC 对齐 | 官方 PyTorch CPU 示例；Mac MPS 未专项验证；可作普通 HTR 对照，但不优先解决语言归正 |

表中依据：[Kraken README](https://github.com/mittagessen/kraken/blob/7.1/README.rst)、[Kraken 推理文档](https://kraken.re/main/user_guide/inference.html)、[Kraken 默认 CTC 配置](https://github.com/mittagessen/kraken/blob/7.1/kraken/configs/base.py)、[PyLaia IAM](https://huggingface.co/Teklia/pylaia-iam)、[PyLaia 解码文档](https://doc.teklia.com/pylaia/usage/prediction/)、[pero-ocr README](https://github.com/DCGM/pero-ocr/blob/master/README.md)、[pero decoder factory](https://github.com/DCGM/pero-ocr/blob/master/pero_ocr/decoding/decoding_itf.py)、[TrOCR 官方仓库](https://github.com/microsoft/unilm/tree/master/trocr)、[TrOCR 模型卡](https://huggingface.co/microsoft/trocr-small-handwritten)。

## 1. Kraken small：一个运行时同时补字符证据和歪斜行几何

### 已经核实的发布物

Kraken **7.1 正式发布**新增 PP-OCRv6 tiny/small/medium 及相应预训练权重；不是只能从训练实验分支拼装。small 模型卡要求 Kraken ≥7.1.0。它是轻量 CNN + 非循环 neck 的 CTC 行识别器，作者报告约 **3.24M 参数**，行高 **128 px**，宽度/CTC 标签预算不固定封顶。这里指 Kraken 维护者训练、适配的模型，不是 PaddleOCR 的同名通用模型包。[7.1 release](https://github.com/mittagessen/kraken/releases/tag/7.1)、[维护者模型卡](https://zenodo.org/records/21788405)

| 对象 | 经核实的元数据 |
|---|---|
| 发布者与记录 | Benjamin Kiessling / Inria ALMAnaCH；2026-08-04；DOI `10.5281/zenodo.21788405` |
| 识别权重 | `small.safetensors`，**13,065,380 bytes**；[官方文件地址](https://zenodo.org/api/records/21788405/files/small.safetensors/content) |
| 权重许可证 | 元数据 `apache2.0`；与代码 Apache-2.0 分别核实 |
| 自带分行模型 | 仓库 `kraken/blla.mlmodel`，Git 树标示 **5,047,641 bytes**；无需因扩展名而误认成原生 CoreML 推理方案 |

文件尺寸来自 [Zenodo JSON 元数据](https://zenodo.org/api/records/21788405)与 [Kraken 官方 Git 树](https://api.github.com/repos/mittagessen/kraken/git/trees/main?recursive=1)；代码许可来自 [7.1 项目配置](https://github.com/mittagessen/kraken/blob/7.1/pyproject.toml)。尺寸不等于进程峰值内存；本轮未测 Mac 延迟或与现有模型共驻的内存。

### 能借用什么，不能据此推断什么

- **几何可独立借用。** `segment -bl` 使用自带基线分行模型，输出基线和行边界多边形；不必先接受另一个 OCR 的文字。对歪斜/弯曲行，这是比把 Vision 碎片按单个矩形排序更合适的候选。官方称支持复杂版面与曲线行；本项目作文纸、双页、题号仍需单独验证，不据此替换现有已修好的行分组。[推理文档](https://kraken.re/main/user_guide/inference.html)、[SegmentationTaskModel 源码](https://github.com/mittagessen/kraken/blob/7.1/kraken/tasks/segmentation.py)
- **字符证据来自 CTC 时间步，而非 LLM 口头置信度。** 默认 `RecognitionInferenceConfig.decoder` 是 `greedy_decoder`；它逐时间步 argmax，再合并连续同标签并移除 blank，没有查词典/外部 LM。识别记录提供字符 cuts、置信度，基线型位置再经多边形映射回页图。词框是识别字符的聚合，不是每个词独立检测。[配置](https://github.com/mittagessen/kraken/blob/7.1/kraken/configs/base.py)、[greedy decoder](https://github.com/mittagessen/kraken/blob/7.1/kraken/lib/ctc_decoder.py)、[CTC 位置映射](https://github.com/mittagessen/kraken/blob/7.1/kraken/models/ctc.py)、[容器定义](https://github.com/mittagessen/kraken/blob/7.1/kraken/containers.py)
- **保错效果尚未知。** small 的公开英文混合测试为 **2,005 行，CER 8.18%、WER 28.45%**；不是独立 IAM 的固定分割，且作者按语言随机留出 5%（最多 100 页），未按文档隔离训练/测试。只能视为域内参考，不能与 PyLaia/TrOCR 表中数值横向排高低。训练含 IAM，但同时含历史手写、印刷和私有数据；NFD 与空白规范化、混合转写规范都会影响逐字契约。[small 元数据中的完整模型卡](https://zenodo.org/api/records/21788405)

### 本机运行路径：官方支持，尚未在本机执行

官方明确支持 macOS x64/ARM、Python 3.10–3.13，CLI 设备包含 `cpu` 与 `mps`。因此可先在隔离 Python 环境以独立子进程测试，不要求替换已有 llama.cpp 服务，也没有核实可直接嵌入纯 Swift/CoreML 的等价路径。[README](https://github.com/mittagessen/kraken/blob/7.1/README.rst)、[设备选项](https://kraken.re/main/user_guide/inference.html)

以下是**已具备依赖和本地权重后**的接口示例，本轮未执行：

```sh
# 只做行几何；不接受任何识别文字
kraken --device cpu -i /private/tmp/htr-probe/page.png /private/tmp/htr-probe/lines.json \
  -n segment -bl

# 完整旁路：页图 -> 分行 -> 识别 -> 带几何的 ALTO
kraken --device mps -i /private/tmp/htr-probe/page.png /private/tmp/htr-probe/ctc.xml \
  -a segment -bl ocr -m /absolute/model-directory/small.safetensors

# 单独测试已有行裁切，排除分行差异
kraken --device cpu -i /private/tmp/htr-probe/line.png /private/tmp/htr-probe/line.txt \
  ocr --no-segmentation -m /absolute/model-directory/small.safetensors
```

命令形态依据 [官方推理文档](https://kraken.re/main/user_guide/inference.html)。先用 CPU 固定数值基线，再比较 MPS；不要为了一个不支持的算子静默落回 CPU 而把它报告为 Metal 实测。

**两个实现细节会改变候选打分：**

1. `ForcedAlignmentTaskModel` 只是把**已提供的文字**贴到图上；字符集不匹配时可能忽略字符，失败时可能返回空 cuts。它不能证明漏掉的 `is` 本来不存在，也不能凭“能够对齐”判定 `sunny` 胜过 `suny`。先自由 CTC 解码生成独立候选，再做候选/原文差异对齐。[强制对齐源码](https://github.com/mittagessen/kraken/blob/main/kraken/tasks/align.py)
2. **7.1 的 `return_logits` 名称不能直接当数学契约。** `models/ctc.py` 先 softmax，存为 `self.outputs`，基线记录的 `logits` 再取自此对象。因此若后续做 CTC forward probability，应先核实张量到底是 logits、概率还是 log-probabilities，不能因字段名再次盲目 `log_softmax`；还要检查字符可编码、时间步可行、空/失败分支和长度偏置。这是源码发现，本轮未做数值复现。[7.1 源码 `_rec_predict` 与 `BaselineOCRRecord`](https://github.com/mittagessen/kraken/blob/7.1/kraken/models/ctc.py)

## 2. PyLaia IAM：更聚焦的英文无 LM 基线，但先解决旧依赖组合

[Teklia 官方 checkpoint](https://huggingface.co/Teklia/pylaia-iam)明确面向现代英文手写，IAM RWTH 分割为训练 **6,482**、验证 **976**、测试 **2,915 行**；保持长宽比缩放至 **128 px 行高**。无外部 LM 时 CER **8.44%**、WER **24.51%**；加 6-gram 字符 LM 后为 **7.50% / 20.98%**。普通 IAM 指标提高不能证明“保留学生错误”更好；本用途应固定无 LM，再把 LM 作为归正风险的可选负对照。

| 文件 | 官方元数据尺寸 |
|---|---:|
| `weights.ckpt` | **42,671,836 bytes** |
| `model`（架构 pickle） | **1,515 bytes** |
| `syms.txt` | **409 bytes** |
| `language_model.arpa.gz`（首轮不需要） | **5,355,981 bytes** |

核查 revision：`9c22c3e4ae7e8455a7fb7c6784a7c372c47270db`；[官方模型 API](https://huggingface.co/api/models/Teklia/pylaia-iam)、[固定 revision 文件清单](https://huggingface.co/api/models/Teklia/pylaia-iam/tree/9c22c3e4ae7e8455a7fb7c6784a7c372c47270db)。模型卡标 MIT；没有核实该 checkpoint 的参数量，不按文件大小推算。

可直接消费的配置要点：

```yaml
syms: /absolute/model-directory/pylaia-iam/syms.txt
img_list: /private/tmp/htr-probe/line_ids.txt
img_dirs:
  - /private/tmp/htr-probe/lines-128px/
common:
  experiment_dirname: /absolute/model-directory/pylaia-iam
  model_filename: /absolute/model-directory/pylaia-iam/model
  checkpoint: /absolute/model-directory/pylaia-iam/weights.ckpt
decode:
  use_language_model: false
  join_string: ""
  convert_spaces: true
  segmentation: char
trainer:
  gpus: 0
```

然后使用 `pylaia-htr-decode-ctc --config /private/tmp/htr-probe/decode.yaml`。这是按官方文档适配的待验证配置，不是本机已通过的启动脚本。[参数与 CPU 示例](https://doc.teklia.com/pylaia/usage/prediction/)

`segmentation: char` 或 `word` 输出 `(text, x1, y1, x2, y2)`，位置来自 CTC alignment，属于输入行裁切坐标；若先缩放/纠斜，必须带逆变换返回页图。为评分保留原始时间步分布时，可用其 `pylaia-htr-netout` 接口而不只保留最终字符串。[解码/对齐文档](https://doc.teklia.com/pylaia/usage/prediction/)、[网络输出文档入口](https://doc.teklia.com/pylaia/releases/)

**避免两个旧教程陷阱：**

- 原 GitHub README 已指向 Teklia GitLab 为维护源。当前官方 1.1.1 发布说明已**移除不维护的 nnutils 依赖**；不要沿用旧仓库的 `nnutils-pytorch` 安装补丁。该发布仍使用 PyTorch Lightning **1.4.2**，Mac 当前 Python/Torch 组合尚未验证，应隔离并固定依赖，而不是修改现有模型环境。[维护历史](https://doc.teklia.com/pylaia/)、[1.1.1 发布说明](https://doc.teklia.com/pylaia/releases/)
- Teklia HF demo 源码会在找到 `tokens.txt` 时启用 LM；IAM 仓库恰有该文件。不能直接复制 demo 的自动判断，必须显式固定 `use_language_model=false`，不加载 LM/lexicon。[维护者 demo 源码](https://huggingface.co/spaces/Teklia/PyLaia/blob/main/app.py)

官方有 CPU 解码证据；本轮没有获得 PyLaia 对 Apple Silicon/MPS 的专项支持声明或本机运行证据。**CPU 可测**与**Mac MPS 已支持**应分开记录。

## 3. 为什么暂不优先选 pero-ocr 或 TrOCR

### pero-ocr：可复用几何，但缺少已核实的英文手写发布物

它有完整的段落/行检测、归一化裁切和 PageXML/ALTO 管线，CTC `GreedyDecoder` 与 `force_align` 也适合提取字符证据；配置 `TYPE=GREEDY` 可跳过 `FAST-LOG-RAW` 的 LM beam 路径。然而其 README 公开下载的是**欧洲印刷 OCR，偏捷克报纸**，手写识别要求联系作者，不能把“布局支持印刷与手写”写成“已提供可直接用的现代英文 HTR 权重”。[README](https://github.com/DCGM/pero-ocr/blob/master/README.md)、[decoder factory](https://github.com/DCGM/pero-ocr/blob/master/pero_ocr/decoding/decoding_itf.py)、[CTC 强制对齐](https://github.com/DCGM/pero-ocr/blob/master/pero_ocr/core/force_alignment.py)

源码有 CPU TorchScript 加载分支，使用 `checkpoint + '.cpu'`；这说明需要正确 CPU 导出物，不能仅换设备字符串就承诺现成 GPU 权重可在 Mac 运行。没有核实官方 MPS 路径、现代英文手写权重尺寸及其授权，故不把它列入首轮识别实验。[引擎源码](https://github.com/DCGM/pero-ocr/blob/master/pero_ocr/ocr_engine/pytorch_ocr_engine.py)

### TrOCR：确有英文权重，但仍是强语言先验的自回归识别器

官方 Small 为 **62M 参数**，IAM cased CER **4.22%**；模型卡明确是单行输入，DeiT 图像编码器 + UniLM 文本解码器，自回归产生 token。`num_beams=1` 只是关闭 beam 搜索，不能关闭 UniLM 内部文本建模，也不会变成字符 CTC。官方没有给此 checkpoint 的学生错拼/冗词保留指标；低 IAM CER 不足以决定它适合本次缺口。[作者仓库与评测](https://github.com/microsoft/unilm/blob/master/trocr/README.md)、[模型卡](https://huggingface.co/microsoft/trocr-small-handwritten)

HF revision `b4648cfa171985a6745f37ddd637e98c0da958ac` 的 `pytorch_model.bin` 为 **245,933,041 bytes**，另有 tokenizer/processor 配置；[官方文件元数据](https://huggingface.co/api/models/microsoft/trocr-small-handwritten/tree/b4648cfa171985a6745f37ddd637e98c0da958ac)。标准 `TrOCRProcessor` + `VisionEncoderDecoderModel` 是可研究的本地 PyTorch 路径；不采用旧 fairseq 的 CUDA/apex 安装教程，也不把 HF 页面自动生成的通用 pipeline 示例当成已验证兼容性。源码/模型卡未提供字符坐标接口，仍需外部分行与对齐。

## 4. GFCN 上游补核：同题证据由文献报告承担，工程接入不优于已核实的两项

另一条文献线已研究 `vlm-ocr-research` 的英文作文 CTC 实验；本报告只核上游，不重复其结果。作者官方 [FactoDeepLearning/LinePytorchOCR](https://github.com/FactoDeepLearning/LinePytorchOCR)确实提供 IAM 预训练 GFCN，并链接作者 GitLab；README 报测试 CER **7.99%**，分割也是 6,482 / 976 / 2,915 行。入口参数为**单通道灰度、行高 64、可变宽、宽缩小率 4、CTC**，没有自回归解码器。[README](https://github.com/FactoDeepLearning/LinePytorchOCR/blob/master/README.md)、[main.py](https://github.com/FactoDeepLearning/LinePytorchOCR/blob/master/source/main.py)

本轮作者 GitLab 页面仅返回 CSR 壳，公开 API 对该项目路径返回 404；**未核实当前精确 checkpoint 路径、文件大小与单独权重许可**，不把 README 的链接当成已经完成下载可用性验证。代码许可是 **CeCILL-C**，不是 MIT。CPU 分支存在，但 `torch.load(checkpoint_path)` 未设置 `map_location`，Mac 加载 CUDA 保存物可能需要适配；没有官方 MPS 验证。[作者发布入口](https://git.litislab.fr/dcoquenet/linepytorchocr)、[LICENSE](https://github.com/FactoDeepLearning/LinePytorchOCR/blob/master/LICENSE.md)、[加载与 greedy CTC](https://github.com/FactoDeepLearning/LinePytorchOCR/blob/master/source/ocr.py)

**取舍：** GFCN 的同题实验机制值得借，但 PyLaia 的公开 checkpoint、解码/坐标接口和宽松模型卡更清楚；Kraken 则把维护、Metal 与几何合在一个运行时。除非文献线找到可稳定取得的作者 checkpoint 与明确权重授权，否则不把 GFCN 加为第三条并行工程路线。

## 5. 许可证：分别记录代码、权重和训练数据

| 对象 | 已核实许可与实际影响 |
|---|---|
| Kraken 代码 / PP-OCRv6 small 权重 | 代码 Apache-2.0；该权重 Zenodo 元数据也为 Apache-2.0。产品分发需保留相应许可证、版权/NOTICE 与修改说明；私有训练数据本身未随权重开放 |
| PyLaia 代码 / IAM checkpoint | 代码 MIT；Teklia 模型卡标 MIT。架构文件是 pickle，后续仅从已核实发布者取得、固定 revision，不加载任意来源模型 |
| pero-ocr | 代码 BSD-3-Clause；本轮没有核实适用的现代英文手写权重及其许可，不能沿用代码许可代替权重授权 |
| TrOCR | UniLM 仓库 MIT；所核 HF small handwritten 卡未声明独立 `license` 字段。模型用于随产品分发前仍需明确权重适用授权，不仅引用仓库代码许可 |
| GFCN 上游 | 代码 CeCILL-C，含分发时提供相应源代码及界面可访问权利说明等要求；权重单独授权本轮未确认 |
| **IAM 原始数据** | IAM 官方条款是**非商业研究**，注册与引用要求另列。Teklia 数据卡的 MIT 标签与原数据官方条款不能混为一份授权；模型卡 MIT/Apache 不自动赋予重新分发 IAM 图片或商业再训练的权利 |

许可原件：[Kraken LICENSE](https://github.com/mittagessen/kraken/blob/7.1/LICENSE)、[small 元数据](https://zenodo.org/api/records/21788405)、[PyLaia LICENSE](https://github.com/jpuigcerver/PyLaia/blob/master/LICENSE)、[Teklia checkpoint 卡](https://huggingface.co/Teklia/pylaia-iam)、[pero LICENSE](https://github.com/DCGM/pero-ocr/blob/master/LICENSE)、[UniLM LICENSE](https://github.com/microsoft/unilm/blob/master/LICENSE)、[TrOCR 卡原文](https://huggingface.co/microsoft/trocr-small-handwritten/raw/main/README.md)、[GFCN LICENSE](https://github.com/FactoDeepLearning/LinePytorchOCR/blob/master/LICENSE.md)、[IAM 原数据使用条款](https://fki.tic.heia-fr.ch/databases/download-the-iam-handwriting-database)、[Teklia IAM 数据卡](https://huggingface.co/datasets/Teklia/IAM-line)。权重卡许可与原数据限制应作为不同对象保留；商业训练/打包分发前由产品负责人向发布者澄清冲突，不在此报告推导不存在的豁免或禁令。

## 6. 最小对照测试：先验证“保错且不伤正确字”，再决定接入

以下是下一阶段待授权的小实验，不涉及老师逐篇核对。用专门制作、可共享的非私有测试材料一次建立金标，随后自动回归。

### 测试集与固定条件

- **12 条短行 × 3 位书写者 = 36 行**，保留原图，并生成轻度倾斜副本。包含成对条件：`suny/sunny`、`beautifull/beautiful`、`freind/friend`、`goed/went`；`I'm is a student/I'm a student`；重复词、重复字母、撇号、大小写、标点。用手写主集，不以合成印刷代替；固定金标中的错误、重复次数与位置。
- 第一轮所有模型使用**相同行裁切**，分别测现有 MiniCPM、Kraken small greedy、PyLaia IAM 无 LM；只在同图对比中判断识别增益。第二轮才比较现有 Vision 行分组与 Kraken 基线几何，防止把分行问题和识别问题混算。
- 不让 Jev 或语法审核改写测试输出；语法审核只能生成批注。Jev 可单独记录是否仍偏向正确词，不能用它过滤掉独立 CTC 证据后再统计“成功”。

### 必须输出的证据

| 指标 | 具体回答的问题 |
|---|---|
| 错拼精确保留 / 归正 / 删除 / 其他错误次数 | `suny` 是原样保留，还是被“修好”或丢掉？ |
| 冗词、重复词保留率与正确对照的新增词率 | 能否保留 `I'm is`，又不把正常 `I'm` 变成 `I'm is`？ |
| 正确对照 CER 与字符插入/删除/替换分项 | 提高保错是否损伤本来正确的内容？ |
| CTC 候选召回与最终合并准确率分开 | 是识别器没读到，还是合并/打分丢掉了候选？ |
| 字符 cuts/行多边形与逆变换 | 能否在正确行、正确位置定位多余或缺失文字？ |
| Mac CPU/MPS 各自的单行/整页耗时、峰值内存、失败样例 | 24 GiB 和现有服务共存是否实际可用？ |

若需要比较同一行的两个候选，用完整字符序列的插入/删除动态规划与 CTC emission 证据，而不只是找原文词 range。保留无 LM 自由解码结果，强制对齐只能作定位；候选 CTC 分数还要明确原始/长度归一口径、不可编码/不可对齐失败，不沿用别的项目固定阈值。正式自动替换规则应在独立留出材料上确定，而不是靠本次 36 行调到全对。

### 完成条件与未知

**下一步首选：只做 Kraken small 的同裁切、无外部 LM 旁路测试；再用 PyLaia IAM 验证失败究竟来自模型还是 CTC 路线本身。** 不先换主 OCR、不升级内容理解模型，也不要求老师成为默认质量门。

本轮已经确认了公开权重、解码机制、坐标来源和官方 Mac 支持层级；尚未确认的是：这些 checkpoint 在本项目手写错拼/冗词上的保留效果、Kraken MPS 本机速度与稳定性、PyLaia 旧依赖实际可安装组合，以及训练数据条款对将来商业分发/再训练的适用安排。决定是否集成的证据是上述自动对照结果，而不是模型规模、一般 CER 或一句“支持手写”。
