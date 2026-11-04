# ModelBest 官方 API 对照：转写与 Jev 的修正依据

核实日期：2026-11-03。本文由资料核实代理编写，根代理负责代码修改和实际验证；本轮未调用云模型、未读取密钥、未上传作业、未改变服务。

## 当前决定：OCR 改用官方未量化 F16，Jev 与文本模型暂留 Q4

用户最新要求不再下载 OCR 量化模型。官方 [OCR GGUF 模型卡](https://huggingface.co/openbmb/MiniCPM-OCR-1.0-gguf/blob/59e3a326776d9de961957f05dedd7202cefa93d1/README.md)明确把 F16 列为未量化参考版本。完整图像推理需要主模型与 projector 两个文件，保持配套：

| 官方仓库 revision | 文件 | bytes |
|---|---|---:|
| `openbmb/MiniCPM-OCR-1.0-gguf` / `59e3a326776d9de961957f05dedd7202cefa93d1` | `MiniCPM-OCR-1_0-F16.gguf` | 1,516,288,352 |
| 同上 | `mmproj-model-f16-4x.gguf` | 901,017,536 |

共 2,417,305,888 bytes（约 2.417 GB）；无需下载 Q8、无需自行转换。沿用本地 b11960 Metal 服务，仅替换 `--model`，`--mmproj` 不变，首轮不开 DSpark。[固定 revision 主模型](https://huggingface.co/openbmb/MiniCPM-OCR-1.0-gguf/resolve/59e3a326776d9de961957f05dedd7202cefa93d1/MiniCPM-OCR-1_0-F16.gguf)、[projector](https://huggingface.co/openbmb/MiniCPM-OCR-1.0-gguf/resolve/59e3a326776d9de961957f05dedd7202cefa93d1/mmproj-model-f16-4x.gguf)。

原始 BF16 仓库为 `openbmb/MiniCPM-OCR-1.0`，revision `38498ccffef88bd38298d8df3a4eb3dca7bf4513`；`model.safetensors` 为 2,600,969,816 bytes，官方元数据记载 1,300,434,160 个 BF16 参数。F16 GGUF 是官方浮点格式转换，不是 Q 系列量化，但与原始 BF16 数值格式不同。Apple Silicon 24 GiB 的最短路线是现有 llama.cpp，运行内存仍以切换后的实际进程为准，不能凭文件尺寸断言峰值占用或效果提升。元数据：[GGUF](https://huggingface.co/api/models/openbmb/MiniCPM-OCR-1.0-gguf)、[原始 BF16](https://huggingface.co/api/models/openbmb/MiniCPM-OCR-1.0)。

## 已回到用户提供的原页面核实

核实原件：

- [Document Parsing API](https://platform.modelbest.ai/console/docs/api/document-parse)，页面内容标记更新时间 2026-10-27。
- [OCR Correctness Decision API](https://platform.modelbest.ai/console/docs/api/ocr-jev)，页面内容标记更新时间 2026-10-29。

两页是客户端渲染页面。网页读取器不能提取正文，当前环境也没有可用浏览器；直接访问原 URL 返回公开 HTML。HTML 引用 [index-zgqWkfqg.js](https://platform.modelbest.ai/console/assets/index-zgqWkfqg.js)，其中 `/docs/*` 公开路由加载 [index-C6-Rq7xv.js](https://platform.modelbest.ai/console/assets/index-C6-Rq7xv.js)。后者包含这两页的全部正文、表格、例子与共用段落。本研究逐段读取了 `de("document-parse", …)`、`wa`、`Oa`、`Ra`，以及 `Qt`、`Ma`、`Ca` 和例子常量；未访问认证接口，也未执行下载的应用代码。

本机阅读副本为 `/tmp/modelbest-document-parse-page.html`、`/tmp/modelbest-ocr-jev-page.html`、`/tmp/modelbest-console-index.js`、`/tmp/modelbest-console-docs.js`。以下契约来自这些原页面的公开文档内容，而非仅复用旧 README。

## 三种协议必须分清

| 服务 | 请求与响应 | 本项目处理 |
|---|---|---|
| 云端文档解析 | `/v1/document-parse` 或 `/jobs`；包含版面处理、识别、Markdown 装配和坐标 | 参考其区域模型与坐标约定，不直接改为云调用 |
| 云端 Jev | `/v1/chat/completions`，顶层 `minicpm_ocr_jev`；默认服务端渲染，评分 JSON 位于 `choices[0].message.content` 字符串中 | 不照搬为本地请求结构 |
| 本地 llama.cpp | OCR 用 chat；Jev 用 `/v1/systemone`，`state + files + questions`；直接返回类别分布 | 保留现有 loopback 路线 |

`ModelClient.swift` 当前本地 Jev 路由不是错误。云接口的 `MiniCPM-OCR-Jev` 大小写、`verdict` 信封、`render_images`，与本地 `answers.consistency.probabilities["1"]` 不可混用。本地证据见[官方 adapter](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/scripts/minicpm-ocr-jev/sdk/jev_score/backends/llamacpp_backend.py)。不因用户提供云文档就启用学生作业上云。

## 文档解析契约对本地实现的启示

原页面的同步接口仅接收单图；JSON `image`、`file_id`、`url` 三选一，PDF 用异步任务。`upright` 默认开启；`recognize_seal` 默认开启。其图像/原件上限、PDF 页数与渲染 DPI 是云服务限制，不是本地必须照抄的预处理参数。[Document Parsing API](https://platform.modelbest.ai/console/docs/api/document-parse)

关键结果含义：

- `choices[0].message.content` 是按阅读顺序组织的页面 Markdown，表格为 HTML，公式为 LaTeX。
- `ocr.image_width/image_height` 是坐标所在页面的像素尺寸。
- `blocks[].order/label/content/status` 保留块级来源；`bbox/regions` 使用 `[x1,y1,x2,y2]`、左上原点。
- `rotation.applied=true` 时，框对应已摆正的页面；`total_angle` 逆时针为正，显示原图也要应用同一变换。
- 页完成不代表所有块成功；不能把 `failed` 块当成空白。页眉、页脚、页码等可能仍在 blocks，但不进入整页 Markdown。

因此，不能把本地一次整页 chat 文本加 Vision 推测位置，称为已经获得这份 API 的真实 bbox。当前产品可继续本地识别，但区域 ID、源图坐标、识别文字和候选必须由本地管线明确维护。

## Jev 原页面说明了什么，也没有说明什么

原页面要求候选描述同一图像的同一部分，推荐使用正文、公式或表格块；`text/formula/table` 必须和内容相符。单次最多 64 项，选优按候选总数计。Jev 分类而不生成正文，不需要 temperature、top_p、max_tokens 或额外识别提示。[OCR Correctness Decision API](https://platform.modelbest.ai/console/docs/api/ocr-jev)

云端三种模式为 `score`、`score_best`、`score_best_batch`；选优返回输入候选原文，不会纠错。HTTP 200 只说明请求已处理，只有 `scored` 的分数可用；所有候选失败时 `best_index=0` 可能只是回退。自带渲染图会跳过服务端预检和渲染，调用方要保证文本—渲染图一致，渲染变化会改变分数。

两份原页面均未列出默认渲染的字体、字号、画布宽度、行距或留白数值；也没有把自然流排版或贴图方案规定为唯一实现。不得把本项目的 Times、Helvetica、46 px 等配置称为官方规范。原页面没有 `score_success` 字段：成功依据是 `verdict=scored` 或候选的 `verdicts[i]=scored`。逐区域也没有独立 `/region` 路由：云端 `score` 的 `items[]` 每项传 `image + ocr_text + category`，`score_best_batch` 每项传 `image + category + candidates`；本地 `/v1/systemone` 需按区域调用。文档解析响应的 `bbox/regions` 是结果坐标，不是 Jev 自动切块参数。

文档将 `threshold` 默认值列为 **0.5**，用于 `score` 的统计达标判断；它没有把 0.5 或本项目的 0.90 指定为英语手写转写的通用验收线。`pass_rate` 是评分成功比例，`throughput_rate` 是质量达标比例，不是每秒吞吐量。原页面没有规定“低 Jev 分必须重复整页 OCR 直到过线”。

文档提到的重试是请求/条目失败处理：参数问题先改参数；限流退避；服务失败有限次重试；部分失败只处理失败项。本地可以采用同样的错误分类原则，但不能把服务器异常当成低质量分，也不应为一次 Jev 服务失败重做已完成的 OCR。

## 必须修正的代码点

以下是核实时的代码快照定位，后续行号可能随根代理修改移动。按实际方法定位，不覆盖其他正在进行的修改。

### P0：取消未经校准的整页硬门控，改成区域级证据

文件：[WorkspaceStore.swift](<project-root>/Sources/PaperReview/Stores/WorkspaceStore.swift)，`process`（核实时约 169–191 行）。当前在整页 `score >= configuration.threshold` 且 Vision 字符差异为空时才进入审核，否则三次后失败。

**修正：**使用同一词/行区域的候选比较和覆盖完整性来完成自动复识，整页分数仅作诊断。不要把任意 0.90 包装为官方规定，也不要把所有 Vision 差异都当成未通过：独立识别器自身也会错。低分触发的追加候选、服务故障重试、输出截断应是三种不同状态。保持“先显示转写，再开始基础审核”的阶段反馈，不恢复人工确认默认门控。

`verifyLiteral` 当前前 12 个差异词限制、`LiteralVerification.accepts` 的固定 0.05 分差都属于应用实验参数。必须记录处理/未处理覆盖量，不让第 13 个差异词被当成已自动核验；分差不能写成校准后的正确概率。

父代理报告的实证：同一词图上，局部 MiniCPM OCR Q4 返回 `beautifull`；Jev 对 `beautiful` 为 0.0439、对 `beautifull` 为 0.2122。它支持这一词图内选择原词，**不支持拿绝对分 0.2122 判失败，也不证明整页手写已验收**。切换 F16 后这是需要保留的反例回归，不能假设升级自动解决。

### P0：Jev 渲染与界面贴图分开，禁止逐行非等比拉伸参与评分

文件：[TranscriptRenderer.swift](<project-root>/Sources/PaperReview/Services/TranscriptRenderer.swift)，`png`、`TextDrawing.draw`（约 24–66 行）。当前评分图按 Vision 行框绘制，并以 `rect.width/size.width`、`rect.height/size.height` 独立缩放每行。

**修正：**保留这种贴图作为视觉对齐方案时，不将它复用为 Jev 的候选图。评分图使用独立、固定、正常字形比例的正文渲染器；候选变化不改变字号、横纵比例或固定留白策略。保证整个提交文本均已绘制，没有因行框对齐遗漏或把两行挤成一行。正文块用对应正文 crop，单词比较继续共用 `wordCanvasWidth`，不要分别把两个词强制拉成相同长度。

当前 `wordPNG` 采用相同字体、相同画布比较两候选，方向正确。`rendererVersion` 必须随实际渲染策略变化，并进入证据与缓存版本。

### P0：保留完整识别源，不让辅助 Vision 裁切决定哪些字永远消失

文件：[PhotoProcessor.swift](<project-root>/Sources/PaperReview/Services/PhotoProcessor.swift)，`prepare`（约 31–92 行）。当前先缩到最长边 2600，再按 Vision 框联合裁切；`page.source` 实际已经是裁切后的图，而非完整规范化原图。

**修正：**区分原始文件、方向归一后的完整识别图、显示增强图与局部 ROI。保存缩放、旋转和 crop 变换，所有坐标都明确属于哪个图像尺寸。未被 Vision 检出的最后一行/词不能因此从全部 OCR 尝试中移除。完整图保留供自动覆盖检查和必要的整图复识，局部高分只能说明该 ROI。

2600 是应用取舍，不是官方 API 要求；小字、标点、双写字母的局部复识应能从足够分辨率的源图裁取。增强图服务于左侧阅读，不应无条件变成识别与评分唯一来源。EXIF 方向归一也不等同于文档自适应旋转；如新增摆正，必须把相同变换应用到源图、区域框与候选裁切。

### P1：保留本地协议，补上区域与失败类型的接口语义

文件：[ModelClient.swift](<project-root>/Sources/PaperReviewCore/ModelClient.swift)，`recognize`、`score`。当前本地路由、图片顺序、分类 0/1 键读取、loopback 与禁止重定向均应保留。

**修正：**让调用方保存明确的区域 ID、候选 ID、模型格式/revision、渲染版本和 scoring 成败；不要只把 `Double` 和“识别过线”绑定。OCR `finish_reason=length` 不能继续当完整文本。若以后接入文档 SDK，其 block 状态和旋转元数据需有独立解析路径，不要将云信封强塞进当前 chat 解码器。当前未授权云连接，不新增云 endpoint 或密钥入口。

### P1：模型/渲染切换后，旧的局部判别缓存不能沿用

文件：[WorkspaceStore.swift](<project-root>/Sources/PaperReview/Stores/WorkspaceStore.swift)，`literalCache`、`verifyLiteral`。当前缓存键包含作业 ID、rect 和两段文本，不包含模型 revision/精度、渲染版本或预处理版本。

**修正：**F16 切换是实际发生的前提变化；清除相关缓存，或把这些版本纳入缓存键。旧 Q4 的 keep/replace 决定不能充当 F16 的新判别结果。保留 `rawText`、自动修复记录与最终转写版本，审核批注绑定最终版本，避免旧文字偏移漂移。

## 根代理修改后的必要证据

1. F16 服务实际加载的是主模型与正确 projector；不继续使用旧 Q4/Q8 文件名或缓存决定。
2. `beautifull` 最小反例仍保留，后续拼写批注能定位到原词；同时测 `beautiful` 正确词，防止自动复识把正确词改坏。
3. 同区域候选、文本与渲染图一一对应；渲染器不随候选长度拉伸字形，不含高亮或修改建议。
4. 未被 Vision 发现的行不被预裁切永久丢掉；旋转与坐标变换在两侧显示一致。
5. Jev 服务失败只重试评分，截断文本不冒充完成，局部低绝对分不再被整页硬阈值误判。

这些是当前改动直接影响的验证点，不以云调用、真实学生数据上传或默认人工核对作为前提。真实手写的错拼保留率仍需单独建立，合成印刷反例只证明对应路径。
