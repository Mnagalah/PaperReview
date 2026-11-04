# 基于语义的英语基础审核：skill 调查与推荐

核实日期：2026-11-03。目标是原生 macOS 纸质英语作文助手的拼写、语法、标点与大小写审核，不做润色、扩写或作文评分。本轮只调查技能与官方资料；没有安装 skill、下载新模型或调用付费 API。

## 推荐：借鉴纠错 skill，落实为 MiniCPM 的运行时审核规则

**有相关 skill 可以借鉴，但不建议靠“安装一个 skill”完成 App 的语义审核。** 最接近本任务的是作者原仓库中的 **English Coach**：它区分语法正确性与表达自然度，并要求尽量少改、保留学习者原意和句型。建议只提炼其纠错原则，保留现有 **MiniCPM5-2B Q4** 作为内容理解与审核主体，再由应用验证每条批注的原文定位。完整技能中的润色、翻译和媒体功能不进入本产品。[English Coach 原文](https://github.com/BlueBirdBack/english-coach/blob/main/SKILL.md)

这里的“基于语义”应落实为：理解句子在说谁、什么事、何时发生、肯定还是否定，再结合前后文判断词形、时态、搭配和标点是否真的有错；不能把关键词命中、词典查不到或“另一个说法更自然”直接当成语法错误。下面的运行时规则和例子是本项目据此提出的设计，不是上游 skill 已验证的产品能力。

## 三种东西要分开

1. **Codex 开发 skill**：让开发助手按固定方法工作，可用于维护审核提示、测试用例和文档。
2. **App 运行时审核指令**：由 macOS App 明确放进本地 MiniCPM 请求里的任务说明、上下文和输出约束。
3. **审核模型或工具**：真正执行语言判断的模型、规则引擎及其运行依赖。

OpenAI 官方将 skill 定义为指令与资源的集合，模型先发现元数据，再按需读取完整内容。由此可知，装入 Codex 的 `SKILL.md` 不会自动出现在另一个 macOS App 的本地模型请求里，也不会给 MiniCPM 增加训练后的语言能力；App 必须显式接入所需指令或工具。[OpenAI 官方 skills 文档](https://developers.openai.com/plugins/concepts/skills)

### 本机已安装技能没有直接对应项

本轮检查了本机全局 skills、`.agents/skills` 及已提供插件的技能说明，未找到直接承担“英语学生作文、按上下文做基础纠错、输出精确批注”的已安装技能。相近项的用途不同：

- [clear-chinese-writing](~/.codex/skills/clear-chinese-writing/SKILL.md) 面向中文写作与改稿。
- [writing-shape](~/.codex/skills/writing-shape/SKILL.md)、[writing-beats](~/.codex/skills/writing-beats/SKILL.md) 面向成文组织。
- [writing-for-agents](~/.codex/skills/writing-for-agents/SKILL.md) 面向代理文档和技能编写。
- [Mobbin plain-writing](~/.codex/plugins/cache/openai-curated-remote/app-69fdb9081018819193707354f21b366e/1.5.0/skills/plain-writing/SKILL.md) 只约束 Mobbin 报告的行文，不是英语纠错引擎。

## 保留三项候选，分别说明能解决什么

### 1. English Coach：最适合提炼“最小修改、保留原意”的 skill

来源是 BlueBirdBack 的独立作者仓库，不是技能聚合页。仓库提供技能原文、README 和 MIT 许可；这能核实指令来源与复用条件，不能据此推断英语作文纠错准确率。[作者仓库](https://github.com/BlueBirdBack/english-coach)、[MIT 许可](https://github.com/BlueBirdBack/english-coach/blob/main/LICENSE)

- **可取之处**：纠错部分分开检查语法与自然度，优先小幅修改，并保留措辞、句型与含义；有改动说明。
- **不能照搬之处**：它同时提供自然度提升、替代说法和整句修订，没有要求机器可验证的最小 span、唯一定位和逐项理由；也没有给出在本机 MiniCPM5-2B Q4 上的效果证据。
- **采用方式**：只借鉴语法与自然度分离、保留原意、最小修改的原则。App 仍只附加基础错误批注，不输出更地道版本。若实际复制或改编上游文本，保留其 MIT 版权与许可。[纠错规则原文](https://github.com/BlueBirdBack/english-coach/blob/main/SKILL.md#correction--polish)

**结论：推荐作为运行时规则的参考，不整包安装或嵌入。**

### 2. CoEdIT：真实的学习式文本编辑模型，留作研究对照

这是研究作者发布的任务指令微调模型，不是一个 `SKILL.md`。官方实现提供语法纠错用法；CoEdIT-large 为 770M 参数，模型卡列出英语、FLAN-T5 基座，并标记权重为 **CC-BY-NC-4.0**。[作者官方实现](https://github.com/vipulraheja/coedit)、[官方模型卡与许可标记](https://huggingface.co/grammarly/coedit-large/blob/main/README.md)、[原论文](https://aclanthology.org/2023.findings-emnlp.350/)

- **可取之处**：这是通过训练实现、按编辑指令生成修订文本的路线，能够作为学习式 GEC 的对照，而非把规则匹配包装成语义模型。
- **局限**：还覆盖改写、简化和正式化等任务；生成的是编辑后文本，不能直接得到本 App 需要的最小错误 span 和中文理由。还需对齐、范围过滤及独立语义审核。
- **本项目决定**：不下载、不接入，不替换当前 MiniCPM 主体。其非商业许可也不宜直接作为默认产品依赖；作者 GitHub 仓库根目录本轮未见单独 LICENSE，不能拿模型卡许可替代代码许可确认。[模型输出方式](https://huggingface.co/grammarly/coedit-large/blob/main/README.md#text-revision-task)

**结论：仅保留为未来离线研究对照；本轮没有验证它在 Apple Silicon 上的速度、内存或学生作文效果。**

### 3. LanguageTool：可本地运行的补漏工具，不承担语义主审

LanguageTool 官方支持本地 HTTP server，核心仓库采用 **LGPL 2.1 或更高版本**。官方明确说明这种本地 server 不含云端 AI-based rules，不能把在线服务的 AI 能力套用到本地版本。[官方本地部署说明](https://dev.languagetool.org/http-server.html)、[官方仓库与许可说明](https://github.com/languagetool-org/languagetool)、[许可证](https://github.com/languagetool-org/languagetool/blob/master/COPYING.txt)

- **可取之处**：可为拼写、常见语法、标点和大小写提供另一组候选；官方示例的输出含 `offset`、`length`、`replacements`、`message` 和规则分类，便于转换成有位置的批注。[官方响应示例](https://github.com/languagetool-org/languagetool/blob/master/multiLanguageSupport.md)
- **局限**：这些字段并不保证 span 总是最小、建议总是正确，规则说明也不是逐条理解作者意图的证据。它有上下文相关检查，但不能据此称为完整语义理解。
- **采用方式**：如后续确需补漏，可将其结果作为 MiniCPM 的待审候选，过滤风格类规则，不自动修改 OCR 原文；不能用它决定 MiniCPM 只能检查哪些位置，否则会继承其漏报。正式捆绑前另行落实 LGPL 与实际附带组件的许可要求。

**结论：可选辅助，当前不新增这项依赖，也不用它替代“基于语义”的要求。**

## 把语义要求落实到现有审核流程

以下为建议给实现方的行为规则，字段名沿用应用已有契约，不另造一套不兼容 schema。

### 审核看到完整句子，批注只圈最小错误片段

- 输入保留全文或必要段落上下文，并提供稳定的原文行/片段 ID。照片的物理换行不是句界；跨行句子要一起理解，返回时仍定位到原始片段。
- 先结合上下文确定事件、时间关系、指代及句法角色，再判定错误。不要求所有句子机械统一时态，不把英美合法变体或仅仅不够地道当错误。
- 只报告拼写、语法、标点/大小写。真实存在的单词用错，也须结合句意判断，例如表示“除了”时误用 `accept`。
- 每条返回逐字原文、最小必要替换建议和简短中文理由。理由说明当前句子中的依据，例如主语是谁、时间词是什么，不只写“语法错误”。
- 保留人物、事实、时间、数量、否定和可能性。存在多种合理原意、没有足够上下文支持唯一修正时，不编造一个确定错误。
- 没有错误时返回空批注，不为了展示能力而改词或改句型。

### 定位由应用验证，不能靠模型猜

原文引用必须在指定片段逐字成立。重复短语用 occurrence 或应用已有的位置机制区分；插入标点等零长度修改需要明确左右锚点或受验证的位置。跨行、重复词和插入均不能退回“找到第一个相似词就挂上批注”。

引用合法只能证明批注挂对了地方，不能证明判断正确。格式约束、字典命中和第二次问同一个模型也不能独立证明语义正确。

### OCR 保真与语言审核各负其责

MiniCPM-OCR + Jev 负责自动识别和图文一致性处理；语义审核读取其未纠正原文，并附加批注，不回写转写。对仍有识别不确定的区域，保留“识别待确认”状态，不能把该状态伪装成学生语言错误。

可靠部分仍自动进入审核。老师只在必要时处理局部歧义或最终采纳建议，不设置“每篇先人工逐字核对才能审核”的主流程。这与项目的原文/建议分离原则一致。[产品约定](<project-root>/PRODUCT.md)

## 判断是否真正有帮助，要看语义对照而不只看 JSON

下面是本项目自拟的区分用例，不是已运行结果，也不是任何候选的 benchmark 成绩。

| 原文与上下文 | 应有行为 | 主要辨别点 |
|---|---|---|
| `The box of old books are heavy.` | `are` → `is`，说明主语为 `box` | 不被最近的复数名词误导 |
| `Everyone was there accept Tom.` | `accept` → `except`，说明此处表达“除了” | 真实词的语境误用 |
| `Please accept my apology.` | 无错误 | 同一个词在另一语境合法 |
| `I have lived here since three years.` | `since` → `for`，说明 `three years` 是时长 | 理解时间关系 |
| `I visited Paris last year. I live in London now.` | 无错误 | 时态变化有合理语义依据 |
| `If I were you, I would wait.` | 无错误 | 不把虚拟语气误改成 `was` |
| `I do not like tea.` | 无错误，不删 `not` | 不改变否定含义 |
| `It was beautifull.` | 只建议 `beautifull` → `beautiful`；OCR 原文不变 | 错词保留与基础纠错分离 |

还应在实际模型上覆盖跨行句子、重复词的第二次出现、缺标点插入、合法英美拼写、上下文不足的句子与混合错误。分开记录错误精确率/召回率、定位通过率、过度改写和含义改变；不能用结构化输出通过率替代语法判断效果。

本次调查建立了可借鉴的技能来源、运行时设计方向和替代工具边界。**当前最短路径仍是 MiniCPM 语义主审 + 最小批注契约 + 应用定位校验**。MiniCPM5-2B Q4 的实际误报、漏报和上下文处理能力，需由这套运行时指令的真实推理结果及脱敏学生样本来判断；外部技能的名称和说明不能替代这部分证据。
