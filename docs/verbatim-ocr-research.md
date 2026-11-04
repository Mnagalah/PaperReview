# 原样保留英语错拼：OCR 专项研究

核实日期：2026-11-03。范围：官方模型、SDK、文档、问题讨论与可执行的训练路径。本轮只查资料；未下载新权重、未修改应用代码、未调用或重启正在运行的服务。

后续用户明确比赛模型固定：先修文档结构与覆盖，再用同一 MiniCPM-OCR 做多粒度、原色/增强读字与 Jev 核验；不引入其他模型。见 [综合决定](research/20261103-ocr-fidelity-synthesis.md)。下文外部 CTC 方案仅供方法参考，早期 Q4 印刷实验是历史证据，当前主 OCR 已固定为未量化 F16。

## 决定：先验证自动候选判别，不能用“请忠于原文”充当保证

产品目标是老师导入后得到保留学生错误的转写，再自动标注基础语言错误。默认增加人工核对不满足本次目标。

父代理报告的当前实测是：MiniCPM-OCR 1.0 Q4 对一份合成印刷测试图，在全页官方提示、强保真提示、单行裁切三种条件下，均把 `beautifull` 转成 `beautiful`；`goed`、`freind` 等错误得到保留。同一行的 Apple Vision 关闭语言纠正后给出 `beautifull`。这是本项目已出现的具体反例，不是本研究独立复现，也不是学生手写数据结论。

**推荐顺序：**

1. 立即做自动路径：保留独立候选，在同一词/行裁切上让 MiniCPM-OCR 与局部 Jev 判别竞争，验证能否恢复 `beautifull`；不让后续语法模型回写转写。
2. 若局部排序仍把规范词排在原字形之前，停止把提示词和重试次数当成修复方向，转为“含错拼原样标签”的 OCR 领域微调。
3. 后续已确认 Kraken small 与 PyLaia IAM 有可用公开手写 CTC 权重，首轮不必自训；先验证无外部 LM 旁路。它仍需隔离依赖与本机适配，不是现有 MiniCPM 的一个开关。

## 公开接口没有找到关闭语言先验的模式

核查了 [OCR 任务说明](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/minicpm_ocr_1dot0_en.md)、[默认提示](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/sdk/minicpmvocr/prompts.py)、[SDK 配置](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/sdk/minicpmvocr/config.py)、[请求构造](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/sdk/minicpmvocr/backends/dialects.py)，未发现以下公开能力：`disable_autocorrect`、字典开关、逐字符 OCR、CTC 解码、输出字形序列的独立任务头。

模型是视觉编码器加语言模型的条件生成架构，不是“识别后再运行一个可关闭的拼写纠正器”。官方 [config.json](https://huggingface.co/openbmb/MiniCPM-OCR-1.0/blob/main/config.json)声明 `MiniCPMOcrForConditionalGeneration`、`qwen3_5_text`；[generation_config.json](https://huggingface.co/openbmb/MiniCPM-OCR-1.0/blob/main/generation_config.json)只有 BOS/EOS、缓存等基础字段。官方正文任务是 `Text Recognition:`。

以下设置不能等同于关闭模型的语言先验：

| 设置或做法 | 实际改变 | 对本问题的判断 |
|---|---|---|
| greedy、低 temperature | 从模型现有分布取更确定的输出 | 可重复地输出被规范化的词，不保证保留错拼 |
| 改成逐字母/JSON 格式 | 输出格式或受限生成空间 | 同一模型仍可能漏一个字母；未找到官方逐字符保真结果 |
| grammar / JSON schema | 约束允许的输出结构 | 不提供图像中的字符真值 |
| logit bias | 改变指定 token 的倾向 | 针对已知 `beautifull` 强推答案不能泛化；也可能污染其他词 |
| 单行或单词裁切 | 改变视觉分辨率与上下文 | 是值得做的实验，不是已证实的纠正关闭模式 |

grammar、logit bias 等含义见 [llama.cpp b11960 服务文档](https://github.com/ggml-org/llama.cpp/blob/b11960/tools/server/README.md)。[tokenizer_config.json](https://huggingface.co/openbmb/MiniCPM-OCR-1.0/blob/main/tokenizer_config.json)已有 `clean_up_tokenization_spaces=false`；这个字段控制 token 解码空格清理，不能阻止模型生成 `beautiful`。

### 多候选采样有一个易踩的配置问题

官方 [config.py 的采样校验](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/sdk/minicpmvocr/config.py)明确指出：若只调 temperature，却继承 greedy 的 `top_k=1`、`top_p=0.001`，采样仍会得到同样的文本。做候选多样性实验时需显式设置整组采样参数，并记录有效值；同一个 greedy 结果重复三次不构成三份独立证据。[官方 TTS 实现](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/sdk/minicpmvocr/pipeline/_tts.py)也是先生成、去重，再交给 Jev 排序。

## 没找到 OCR 1.0 的同类官方反例或已合入修复

核查当前 OpenBMB/MiniCPM-OCR 的 GitHub issue 列表，并以 `spelling`、`correction`、`错别字`、`纠正` 等词补查 OpenBMB/MiniCPM-V；另检查 OCR 1.0 模型页当前的 12 项 Hugging Face 讨论标题。未找到把英语错拼自动规范化的同类报告，也未找到官方承诺已修复该问题。

可追溯的相关报告是老版本 MiniCPM-V 的 [issue #314](https://github.com/OpenBMB/MiniCPM-V/issues/314)：报告营业执照号码经常漏掉中间一位。它说明精确字符提取存在用户报告，但涉及旧模型、数字漏字，不是 OCR 1.0 英语错拼的实证。因此本项目 `beautifull` 反例仍是当前决策的直接依据。

检索入口：[OCR issue 列表](https://github.com/OpenBMB/MiniCPM-OCR/issues)、[OCR 模型讨论](https://huggingface.co/openbmb/MiniCPM-OCR-1.0/discussions)。未检索到不等于不存在，尤其该模型刚发布不久；不能用讨论缺席推翻本地实测。

## Jev 能判别候选，但不会创造缺失候选

官方 [Jev 使用说明](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/minicpm_ocr_jev_en.md)要求：同一裁切、同一内容边界上的候选才能直接比较。Jev 的输入包含原图、候选文本和该候选的渲染图；它只从已有候选里选优，不会把 `beautiful` 自动还原为 `beautifull`。

适用于此次局部实验的条件：

- 原图裁切完整包含目标词，不截掉末尾第二个 `l`，候选不能夹带裁切外的相邻词。
- 每次比较使用完全相同的原图；渲染字体、字号、留白、背景与画布策略固定。
- 候选至少包含 `beautiful` 与 `beautifull`，且各自渲染图必须和提交文本完全一致。
- 先测同词图的成对排序，再测单独阈值。不能把全页高分当成单字母正确的证据，也不能拿不同裁切上的绝对分直接比较。
- 保存两个分数、差值、最终选择及对应图像，而不是只保存最高分。

“固定画布、避免按候选分别强制拉伸到相同文字宽度”是本应用的实验建议：若不同长度候选被任意压缩，可能弱化一个字母带来的几何差异。它不是官方已验证的渲染最优策略。

官方 [Jev 微调文档](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/finetune_jev_en.md)把缺字、错字列为不一致标签，但标签作用于整个候选，不提供字符定位。官方发布的是块级评估，未给出单词图、重复字母最小差异或学生错拼专项结果。词级 crop 是新输入分布，应以本项目实验决定是否有效，不能预设 Jev 会重视最后一个 `l`。

## 立即能做：独立候选 + 局部证据的自动恢复

Apple [Vision 官方属性说明](https://developer.apple.com/documentation/vision/vnrecognizetextrequest/useslanguagecorrection)确认 `usesLanguageCorrection=false` 返回不应用语言纠正的原始识别结果。可把它作为候选来源而不是直接视为真值：MiniCPM-OCR 仍负责主体识别，Vision 只在两者逐字差异的局部提供替代假设，Jev 检查字形一致性。该组合是否满足要求取决于局部判别实验，不能靠“两个模型同意”替代测量。

关键验收不是普通正确词识别率，而是：

- **错拼保留率**：原图中的错误词是否逐字保留。
- **错误规范化率**：原图错误词被转成规范词的比例，单独报告。
- **正确词损伤率**：自动恢复路径是否把正确词改坏。
- **字符精确率/召回与 CER**：同时报告漏字、加字、替换，不让低整体 CER 掩盖错拼被消失。

测试必须同时含错误词与正确词、相同词的不同书写者，尤其 `ll/l`、重复词、漏字、`ie/ei`、非词、语法错误但拼写正确的词。当前印刷反例可作回归哨兵；真实手写样本决定产品验收。不把人工核对加到默认业务流中来抵消不通过的结果。

## 需要训练：保持 MiniCPM 主体的首选路径

官方已有 [MiniCPM-OCR 法语手写行 ms-swift 教程](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/swift_minicpm_ocr_french_en.md)与 [LlamaFactory 教程](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/llamafactory_minicpm_ocr_french_en.md)。它们以 10,138 训练行、1,138 验证行、778 测试行做全参数 SFT：训练视觉和语言模型，冻结 projector，4× 视觉压缩。参考训练使用 8 × A100 80GB；不能把此配置宣称为 24 GiB Mac 已有可运行训练方案。

官方结果：相同 778 条法语测试行，基模 CER 5.67%；LlamaFactory 微调后 2.98%，ms-swift 微调后 3.08%。这些结果支持手写行领域适配的可行性，但目标不是英语错拼保留，不能直接承诺本任务收益。

### 本项目训练标签必须保留错误

沿用官方的“图像 + `Text Recognition:` → 转写”监督格式，目标文本直接使用图像原字形，不用语法模型生成的标准答案。例如以下仅是本项目数据格式示意：

```json
{
  "messages": [
    {"role": "user", "content": "<image>Text Recognition:"},
    {"role": "assistant", "content": "It was a beautifull day."}
  ],
  "images": ["/dataset/lines/writer_017_line_003.png"]
}
```

数据应包含真实学生错拼及正确对照，按书写者/整篇作文划分训练、验证、测试，防止同一笔迹片段跨集合。合成印刷/手写风格数据可扩展重复字母、换位、漏字等覆盖面，但要保留独立真实手写测试集。当前 OCR 部署固定 F16，训练结果先按 F16 复测；若用户将来另行选择量化，再单独验证量化结果，不擅自切回 Q4。

若生成候选覆盖原词后，Jev 仍偏向规范词，再进行 Jev 域适配。官方训练格式为“原图、候选文本、候选渲染图、0/1标签”；本项目应专门加入 `beautifull` 原图配 `beautiful` 的困难负例，以及相同原图配原样词的正例。官方强调同时保留真实识别错误与合成负例，并按页面划分；训练标注是一次性模型建设工作，不是让老师每次使用时逐条核对。

## 字符级识别方法仅作参考，不接入比赛版本

如果目标是从机制上避免词典式解码，字符集合 + CTC greedy 是值得建立的独立模型基线。[PaddleOCR 官方 CTC 解码源码](https://github.com/PaddlePaddle/PaddleOCR/blob/main/ppocr/postprocess/rec_postprocess.py#L185)按每个时间步的字符 argmax 进行重复/blank 消除；该路径没有调用拼写词典或外部语言模型。[CTC head](https://github.com/PaddlePaddle/PaddleOCR/blob/main/ppocr/modeling/heads/rec_ctc_head.py)输出字符分布。这提供了可控制的解码路径，不等于识别器不会漏重复字母或从训练语料学到偏好。

用户已明确比赛版本固定三个指定模型，不接入Kraken/PyLaia或CTC旁路。这里借鉴字符级对齐、无词典解码和保错评测的方法，不形成模型替换或下载计划。当前优先修页/行/词结构和覆盖，用同一个MiniCPM-OCR做多视图、多粒度识别，再独立检查Jev的判别能力；完整决策见 [研究汇总](research/20261103-ocr-fidelity-synthesis.md)。
