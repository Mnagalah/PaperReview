# 本机语义审核实证：两阶段定位有帮助，2B Q4 未通过语义门槛

日期：2026-11-03。仅调用已运行的 `http://127.0.0.1:18501/v1/chat/completions`，模型别名 `MiniCPM5-2B`，响应指纹 `b11960-8642541b2`。模型配置由父任务确认是 Q4。本轮没有下载或切换模型、停止服务、修改生产源文件或现有测试；全部输入均为合成文本。

**2026-11-04后续：** 下文保留本次实验的结论及当时的few-shot建议。生产正常作业随后发生示例复述，当前输入已改为“连贯全文语义上下文＋独立定位行表”，移除其他作文示例。该修正没有通过语义8-case，不能据此宣布语义能力改善；当前正常作业与实际漏报见 [后续验证](../review-recovery-normal-flow-20261104.md)。

## 当前决定：按用户选择保留 2B，语义准确性仍未通过

**“先生成内部最小修订候选，再由应用定位差分”解决了一部分输出负担，但没有解决当前模型的语义错误。** 整篇合成作文可提取出 9–10 处有位置的修改；8-case 正反对照仍只找对 2/4 个预期错误，并额外建议一个错误逗号。逐句聚焦也未改善。后续中文理由阶段还把主谓一致、过去时和复数错误一律解释成拼写错误。

因此本轮没有得到可称为“可靠、通过验收”的 2B Q4 prompt/契约。**用户随后明确选择“先保留 2B，完成当前版本”**：当前不下载或切换 8B，不再追加 prompt 实验。保留模型是本版的交付决定，不代表语义 8-case 已通过。

本版建议沿用父侧正在采用的**完整原文上下文 + few-shot 最小批注示例 + 精确引用校验**，不在收尾阶段接入本实验的两阶段链路。两阶段虽然减轻索引任务，但本次中文原因不合格，尚无足够证据支持它优于当前实现。父侧另行报告两份合成图已自动完成，分别为 9 条有效/1 条剔除、6 条有效/4 条剔除；这属于父侧后续候选的证据，不是本轮对这些图片的独立复测，也不改变本轮 8-case 失败的记录。

2B 当前可用契约应明确：模型按全文理解、只提最小基础错误；应用逐字验证 quote 与具体位置，失配的建议剔除并保留计数；合法引用只证明挂对位置，不能证明建议语义正确。原文不可被建议覆盖，不用人工逐字核对作为主流程，也不用固定词表或通用理由填补模型漏报。确定性 diff 函数保留为后续研究参考。

本结论针对已测的配置和本产品门槛，不归因于所有 2B 模型、所有采样参数或所有 MiniCPM 模型。试验使用 `temperature=0.2, top_p=0.95, min_p=0, seed=42`；OpenBMB 的 MiniCPM5-2B Think 示例推荐 `temperature=1.0`，本轮未测该参数。父任务要求停止继续枚举提示后，本轮不再追加推理。[官方部署与采样说明](https://github.com/OpenBMB/MiniCPM/blob/main/docs/deployment/llama_cpp.md)

## 8-case 对照：门槛未放宽

输入和预期沿用 [现有集成测试](<project-root>/Tests/PaperReviewCoreTests/ModelIntegrationTests.swift)。四个正例必须都命中，四个负例不能被修改。所有推理函数只收到原文和通用指令；评估答案只在独立的 `evaluate_semantic8` 中比较，没有输入模型，也没有用于词表替换。

| 方案 | 命中预期错误 | 额外错误修改 | 生成耗时 | 结果文件 |
|---|---:|---:|---:|---|
| 父侧早期 line/quote/occurrence schema 基线 | 1/4 | 另有 1 条被拒绝，原始模型输出未保存于该证据 | 22.72 s | [原基线](<project-root>/docs/verification/semantic-8case-result.json) |
| 整篇候选，含语义/保留原意约束，默认 Think | 2/4 | 1 处错误逗号 | 49.50 s | [semantic8-result.json](<project-root>/docs/verification/semantic-experiment/semantic8-result.json) |
| 整篇候选，最短英语教师提示，默认 Think | 2/4 | 同样的错误逗号 | 60.13 s | [simple-semantic8-result.json](<project-root>/docs/verification/semantic-experiment/simple-semantic8-result.json) |
| 整篇候选，语义约束，显式 No-think | 0/4 | 0 | 1.54 s | [nothink-semantic8-result.json](<project-root>/docs/verification/semantic-experiment/nothink-semantic8-result.json) |
| 整篇候选，最短提示，显式 No-think | 0/4 | 0 | 1.29 s | [nothink-simple-semantic8-result.json](<project-root>/docs/verification/semantic-experiment/nothink-simple-semantic8-result.json) |
| 逐句聚焦并带全文上下文，No-think | 0/4 | 0 | 2.13 s，总计 9 次 | [focus-semantic8-result.json](<project-root>/docs/verification/semantic-experiment/focus-semantic8-result.json) |
| 同一逐句聚焦，Think | 2/4 | 同样的错误逗号 | 39.63 s，总计 9 次 | [focus-think-semantic8-result.json](<project-root>/docs/verification/semantic-experiment/focus-think-semantic8-result.json) |
| 中文自然语言逐项错误清单，无 schema | 无可验收最终正文 | 不适用 | 84.70 s | [截断记录](<project-root>/docs/verification/semantic-experiment/natural-list-semantic8.json) |

逐句为 9 次，是因为第 5 行包含两个句子；没有把照片换行当成句界。无结构错误清单耗尽 4096 个 completion tokens 后 `finish_reason=length`、最终 `content=""`，不能算作找到了任何错误。

默认 Think 的关键最终文本为：

```text
The box of old books is heavy.
Everyone was there, accept Tom.
Please accept my apology.
I have lived here since three years.
I visited Paris last year. I live in London now.
If I were you, I would wait.
I do not like tea.
It was beautiful.
```

它保留了四个正确负例，却仍漏 `accept → except`、`since → for`，并把错误的 `accept` 当成可用逗号修补的表达。这是已经摆脱复杂批注 schema 后仍出现的判断失败。

## 合成作文：候选召回提升，解释仍失败

原文来自 [synthetic-essay.md](<project-root>/docs/fixtures/synthetic-essay.md)。默认 Think 在 39.65 s 给出 9 处修改，遗漏 `exciting → excited`；No-think 在 1.80 s 给出以下 10 处修改。[默认 Think 原始结果](<project-root>/docs/verification/semantic-experiment/essay-result.json)、[No-think 原始结果](<project-root>/docs/verification/semantic-experiment/nothink-essay-result.json)

```text
goed → went        freind → friend       were → was
plays → played     hour → hours          don't → doesn't
see → saw          beautifull → beautiful
exciting → excited taked → took
```

No-think 候选还合并了部分物理换行。原文从未被覆盖，token diff 的位置始终来自原文，不依赖候选换行。`don't → doesn't` 保留“妹妹通常不喜欢运动”的合理读法，没有强迫全文统一过去时。

将 10 处差分连同原文交给第二阶段，要求只按应用生成的 ID 分类、返回中文原因：

- 第一版输出因英文理由被实验校验拒绝；只捕获到首条失败字段，未保留完整响应，见 [失败记录](<project-root>/docs/verification/semantic-experiment/classification-language-failure.json)。
- 增强中文输出约束后，12.23 s 返回完整的 10 个 ID 和含中文的说明，但内容仍不合格。例如 `were → was` 的理由为“were 是 were 的拼写错误，正确形式为 was”；`plays → played` 也被解释成拼写错误。`goed`、`taked` 被归为 spelling，而没有解释不规则过去式。[完整实际 JSON](<project-root>/docs/verification/semantic-experiment/nothink-essay-result-classified.json)

第二版的汉字开头 regex 约束也没有在返回值中得到遵守；本轮不依赖该约束。中文字符、合法类别和完整 ID 只能验证形式，不能证明解释语义正确。

## 可交付接口：语言模型不再负责计算原文位置

[experiment.py](<project-root>/docs/verification/semantic-experiment/experiment.py) 提供三个清楚的边界：

```python
correct_text(source, prompt, thinking, temperature)
# -> corrected_candidate, request_evidence

token_edits(source, corrected_candidate)
# -> [{id, quote, suggestion, start, length, line, occurrence, context, operation}]

explain_edits(source, edits, thinking)
# -> [{...edit, accept, kind, explanation}], request_evidence
```

其中 **`token_edits` 是可移植的确定性定位参考；两个推理函数仍是未通过语义门槛的实验实现**。它没有错误词表，也不依赖评估答案。使用原文 token 序列与候选 token 序列求 diff，输出原文的 UTF-16 范围，适配 Swift `NSRange`。插入可借相邻原词形成非空 quote；同一锚点上的插入会合并，避免范围重叠。

[test_diff.py](<project-root>/docs/verification/semantic-experiment/test_diff.py) 的 8 项离线定位测试通过：替换、标点插入、词插入、引号插入、删除、重复词第二次出现、emoji 前缀的 UTF-16 位置、跨物理行。该函数忽略纯空白变动；它不是成熟分词器或语言审核引擎。`focused.py` 中的简单句子切分器只用于本轮合成 fixture，正式 App 应用系统语言切分并保留原始范围。

父侧若采用两阶段结构，建议如下：

1. OCR 原文和 revision 保持不可变；模型修订全文只作为内部候选。
2. 应用计算最小 token 差分和原文范围，不让模型输出 line、quote 位置或 occurrence。
3. 第二阶段仅按应用生成的 ID 核实候选、分类和解释；ID 集必须完整且唯一，拒绝项和缺项分别记录。
4. 以原文范围创建现有 `ReviewIssue`，`lineID` 从 `Transcript.lines` 范围映射，不使用实验中的物理行号替代 App 行对象。跨行 span 不能硬塞进单行 quote 契约。
5. 保留“候选生成失败”“理由失败”和实际不接受的修改，不能降级为固定文案、词表替换或默认为审核通过。

建议的结构减少了模型的索引任务，便于检查和迁移更强模型；它不替代 8-case 与作文实际语义检查。

## 以后若重开升级评估：官方 MiniCPM4.1-8B Q4_K_M

本节保留已核实的资源信息，**不属于当前执行计划**。若用户以后重开升级评估，建议候选为 OpenBMB 官方仓库的 **`MiniCPM4.1-8B-Q4_K_M.gguf`**，不选第三方重打包版本，也不把 MiniCPM5 的 2B 型号名称与 4.1 的 8B 型号混淆。官方模型卡明确提供 llama.cpp 用法，并标记 Apache-2.0。[官方模型卡](https://huggingface.co/openbmb/MiniCPM4.1-8B-GGUF)、[官方文件页](https://huggingface.co/openbmb/MiniCPM4.1-8B-GGUF/blob/main/MiniCPM4.1-8B-Q4_K_M.gguf)

- 精确文件尺寸：**4,965,526,048 bytes，4.966 GB / 4.625 GiB**。保留现有 2B 文件时，这是新增模型文件占用，不能只计算两模型差值。[官方文件元数据](https://huggingface.co/api/models/openbmb/MiniCPM4.1-8B-GGUF?blobs=true)
- [官方权重链接](https://huggingface.co/openbmb/MiniCPM4.1-8B-GGUF/resolve/main/MiniCPM4.1-8B-Q4_K_M.gguf) 仅供确认后下载；本轮只读取模型卡、配置和文件元数据，没有下载权重。
- 4.1-8B 的官方配置为 hidden size 4096、32 个 attention heads、32 层、2 个 KV heads。按标准 F16 K/V、单序列 8192 token 估算，KV 为 `2 × 32 × 2 × 128 × 2 × 8192 = 268,435,456 bytes`，即 **256 MiB**；4096 token 则为 128 MiB。这里 `128=4096/32`，第一个 2 为 K/V，第二个 2 为每个 F16 元素的 bytes。[官方配置](https://huggingface.co/openbmb/MiniCPM4.1-8B/blob/main/config.json)

**24 GiB Apple Silicon 有开展 4k–8k、单序列受控本机试验的合理资源空间。** 权重文件加上述理想 8k KV 约 4.875 GiB，但实际还包括计算缓冲、Metal 分配、操作系统、Codex、OCR/Jev 与图像临时内存，不能用该加和宣布三模型并行峰值已经通过。此处是资源可行性推断，不是运行测量。

若以后获准试验，应保留当前服务与恢复路径，在独立候选端口验证同一 8-case、合成作文的时态及中文理由，再决定是否替换审核模型；不一开始打开 64k context 或多并行。本轮没有 8B 推理结果，不能承诺更大模型已满足语义门槛。当前按用户决定保留 2B，本轮不执行这些操作。

## 复现位置与证据范围

所有请求最终文本、参数、耗时和 usage 保存在结果 JSON；不保存模型私有 reasoning 字段。脚本仅使用 Python 标准库，所有推理目标固定为本机 18501。

```bash
python3 <project-root>/docs/verification/semantic-experiment/test_diff.py
# 以下会重新调用本机模型，本报告交付后未继续运行：
python3 <project-root>/docs/verification/semantic-experiment/experiment.py --no-explain
python3 <project-root>/docs/verification/semantic-experiment/focused.py --case semantic8 --think --no-explain
python3 <project-root>/docs/verification/semantic-experiment/classify_existing.py nothink-essay-result.json
```

这些是本机真实模型、合成输入的观测，不是学生真实作业准确率、原生 App 全流程、发行或设备验收。旧 skill 调查中“保留 2B 作为初始语义审核候选”的质量判断，现由本报告的失败证据限定；本版是否保留该模型则遵循用户后续决定。skill 的最小修改与原意保留原则仍可用。
