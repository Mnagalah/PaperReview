# API 在线版官方接口核查

资料日期：2026-11-05。本文记录接口事实与兼容性，尚未实施。OpenAI 与 DeepSeek 结论来自本次实际打开的官方页面；Jev 单独标明历史资料与本次缺口。

首版范围以[在线版首版架构](../architecture/api-edition-architecture.md)为准：固定主流程，首版不依赖自主 Agent。本页保留官方接口与模型能力事实，不把具备工具调用能力等同于必须引入 Agent。

## 本机 Jev 沿用比赛版下载源

在线版 Jev 区提供本机下载入口，沿用比赛版 `script/model_downloads.tsv` 中的官方来源，只下载 Jev 所需文件，不连带下载 OCR 和内容审核模型：

- [Jev Q4_K_M 主模型](https://modelscope.cn/models/OpenBMB/MiniCPM-OCR-Jev-gguf/resolve/master/MiniCPM-OCR-Jev-Q4_K_M.gguf)：1,274,405,248 字节。
- [Jev F16 图像投影](https://modelscope.cn/models/OpenBMB/MiniCPM-OCR-Jev-gguf/resolve/master/mmproj-model-f16.gguf)：671,372,416 字节。
- [llama.cpp b11960 Apple Silicon 运行时](https://github.com/ggml-org/llama.cpp/releases/download/b11960/llama-b11960-bin-macos-arm64.tar.gz)：16,465,074 字节。

按当前清单合计 1,962,242,738 字节，约 1.96 GB。下载区复用进度、速度、剩余量、暂停、退出恢复、重试续传和删除功能；下载由用户触发，不由 Agent 自行决定。

本机 Jev 需要独立下载就绪判断和启停入口。现有脚本要求三模型齐备，不能直接照搬来启动在线版 Jev。可由用户选择已有权重或兼容本机服务进行复用；默认不共用两版的可写下载/删除状态，只停止本版启动的实例，不停止比赛版服务。帮助页另保留[比赛版 0.1.2 安装包入口](https://github.com/Mnagalah/PaperReview/releases/tag/v0.1.2)。

## OpenAI：通用兼容与官方接口分别适配

OpenAI 官方推荐新项目使用 Responses，Chat Completions 仍被支持。方案保留两个服务类型：OpenAI 兼容类型默认使用 Chat Completions；官方 OpenAI 预置使用 Responses，同一类型的高级设置可选择接口格式，不把它当作第三家服务商。[官方迁移说明](https://developers.openai.com/api/docs/guides/migrate-to-responses)

- Chat Completions 用 `/chat/completions`、`messages`、图片 `image_url`；Responses 用 `/responses`、`input`、图片 `input_image`。请求、返回信封及 SSE 事件分别解析，不只替换 URL。[Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)、[Responses](https://developers.openai.com/api/reference/resources/responses/methods/create)
- 支持 Structured Outputs 的模型优先使用 JSON Schema；普通 JSON mode 只保证 JSON 语法，不保证字段符合约束。Chat 用 `response_format`，Responses 用 `text.format`。所有结果仍需做原文引用、位置和业务规则校验。[Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- OpenAI 兼容是接口约定，不代表每个服务及每个模型都支持视觉、严格 Schema 或相同的推理参数。本地请求中的 `top_k`、`min_p`、`repeat_penalty`、`chat_template_kwargs` 等不能直接照搬到云端。
- 通用视觉模型对小字、旋转文字和精确空间定位仍有限制。保留本地图像校正与布局定位，让本地维护坐标和区域 ID，不将聊天模型生成的框当成可靠词坐标。[Images and vision](https://developers.openai.com/api/docs/guides/images-vision)

## 现有本地模型的兼容性

核查对象为现有 MiniCPM-OCR 1.0 F16、Jev Q4_K_M、MiniCPM5-2B Q4_K_M 与 llama.cpp b11960。三者均可成为任务图节点，但不是三个同类的自主 Agent：

| 模型 | 接入方式 | 自主工具调用结论 |
|---|---|---|
| MiniCPM-OCR 1.0 | 裁图 + `Text Recognition:`，通过 `/v1/chat/completions` 返回原文 | 按专用读字工具接入；官方未提供把它当通用工具规划模型的使用契约 |
| Jev | 原图、候选渲染图及文本，经现有 `/v1/systemone` 获取判别分布 | 本身不生成文本，没有 LM head，不能承担规划、对话或工具选择 |
| MiniCPM5-2B | `/v1/chat/completions`，普通审核或 `tools` / `tool_calls` 循环 | 模型和 b11960 解析器具备原生基础，宿主闭环及当前 Q4 配置仍需实测 |

OCR 官方本就由 SDK 在外部做版面裁切、并发区域识别和阅读顺序装配；模型只处理区域。本项目可直接调用已裁区域，不需为了 Agent 引入官方完整 SDK 中的额外版面模型或 Python 环境。保持专用识别提示，不把 OCR 改成开放式作文纠错对话。[OCR 官方用法](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/minicpm_ocr_1dot0_en.md)

Jev 官方说明每次是两张图的单次前向计算，不生成 token；SDK 的 `/v1/score` 和 `/v1/rm/score*` 是另加服务层，不能与本项目直接连接 llama-server 的路径混用。[Jev llama.cpp 官方部署](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/llamacpp_deploy_jev_en.md)

MiniCPM5 官方将工具调用定义为 XML 风格。固定 b11960 的 `common/chat.cpp` 能识别 MiniCPM5 模板并分派专用解析器，转换为标准 `tool_calls[].function`。因此无需仅因文档推荐 SGLang 就更换当前后端，也无需先自行用正则解析 XML。[官方模型说明](https://github.com/OpenBMB/MiniCPM#tool-calling)、[b11960 模板识别](https://github.com/ggml-org/llama.cpp/blob/b11960/common/chat.cpp#L1397-L1403)、[专用解析器](https://github.com/ggml-org/llama.cpp/blob/b11960/common/parsers/minicpm5.cpp)

现有 `ModelClient` 尚未发送工具定义、解析工具调用或回填工具结果。若后续启用自主 Agent，宿主还需接通“发送 tools → 校验并执行 → 回填 tool_call_id → 再次生成或结束”，而不是单加 `--jinja`；这项工作不属于当前收敛后的首版范围。工具选择回合与最终 JSON 报告分开，保留原有普通审核入口；详情见 [MiniCPM5 兼容性记录](minicpm5-agent-compatibility-20261105.md)。当前没有运行实际 Agent 推理或据此宣称 Q4 工具选择可靠性通过。

本机三个服务当前均配置 `--parallel 1`。把两个审核 Agent 同时提交到同一服务仍会排队；`parallel_tool_calls` 只表示一条回复可包含多个工具调用，不代表模型服务器有多个推理槽。调整槽位前需比较上下文预算、内存、总吞吐和单篇延迟，不能据云端并发设计直接承诺本机加速。[llama.cpp b11960 服务参数](https://github.com/ggml-org/llama.cpp/blob/b11960/tools/server/README.md)

## 密钥与学生作业

首版建议由使用者填写自己的 API Key，存本机 Keychain，不写入设置 JSON、日志、导出配置或应用包。若改为提供统一额度，应增加服务端代理，不能把平台密钥内置到桌面应用。[OpenAI 鉴权说明](https://developers.openai.com/api/reference/overview)、[Apple Keychain](https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets)

远程服务使用 HTTPS，不向未配置域名重定向密钥或作业。第一次上云说明图片与文字分别发给哪家服务；OCR 发送必要图片，基础审核只发送转写。不为接图方便而将学生照片发布成公开 URL。

对支持的 OpenAI 接口显式设置 `store:false`，但这不等于供应商零留存；OpenAI 的滥用监控留存与应用状态留存有独立规则，其他服务按各自政策说明。[OpenAI 数据控制](https://developers.openai.com/api/docs/guides/your-data)

## DeepSeek 已支持图片，但模型必须选对

- OpenAI-compatible base URL 为 `https://api.deepseek.com`，聊天端点为 `POST /chat/completions`，鉴权为 `Authorization: Bearer <API key>`。[首次调用](https://api-docs.deepseek.com/)
- 当前名称是 `deepseek-flash`（DeepSeek-V4.1-Flash-1017）和 `deepseek-v4-pro`（DeepSeek-V4-Pro-0813）。**Flash 支持视觉，Pro 不支持视觉**；两者均支持 thinking、JSON Output 和工具调用。旧 Flash 名称仍被接受，但映射到当前 Flash，不能当固定旧模型版本。[模型能力表](https://api-docs.deepseek.com/quick_start/pricing/)
- Flash 可接图片并读截图文字；图片通过 `messages[].content[]` 的 `image_url`（base64 data URL 或公开 HTTPS URL），也可通过 Files API 引用。支持 JPEG、PNG、GIF、WebP；`detail=low` 降到 512×512，`high/original/auto` 保留原图入口，但服务端仍会执行视觉缩放。内联请求体上限 48 MiB，单张内联图片上限 32 MiB，Files 引用上限 64 MiB。**这些是输入能力，不是英文手写保错、漏词恢复或本项目 OCR 质量的验证结果。**[Vision 指南](https://api-docs.deepseek.com/guides/vision/)

## JSON mode 不等于最终答案的 strict JSON Schema

- Chat Completions 的 `response_format.type` 当前只列 `text`、`json_object`，没有 `json_schema`。不能把 OpenAI Structured Outputs 参数原样发给 DeepSeek 并承诺同等约束。[Chat Completions 参数](https://api-docs.deepseek.com/api/create-chat-completion/)
- JSON Output 要求提示词包含 `json` 并给出格式示例；合理设置输出上限。无法识别为 JSON 的内容可能被替换成空格，即使 `finish_reason=stop` 也可能只有空白。仍需解析、业务字段校验与有限恢复。[JSON Output](https://api-docs.deepseek.com/guides/json_mode/)
- DeepSeek 的 strict JSON Schema 是 **Tool Calls Beta**：base URL 改为 `https://api.deepseek.com/beta`，所有函数设 `strict=true`，服务器校验 schema；每个 object 的属性全部 required，并设 `additionalProperties=false`。官方明确它支持 thinking 与非 thinking。这约束的是工具调用参数，不是普通最终答案的 `response_format=json_schema`。[Tool Calls strict mode](https://api-docs.deepseek.com/guides/tool_calls/)

## Thinking 与强制结构化路径存在组合差异

`thinking.type` 可设 `enabled/disabled`，显式开关优先于 `reasoning_effort`。未设二者时默认开启；`reasoning_effort=none` 关闭，`low/high/max` 开启。thinking 下 `temperature` 不生效；`top_p` 行为依模型和模式而变，不能用统一采样参数承诺同样输出。**thinking 不支持 `tool_choice=required` 或指定函数，返回 400**；因此不能仅凭“strict 支持 thinking”推断必定返回期望工具结构。thinking 结果的 `reasoning_content` 应与最终 `content` 分开处理。[Chat Completions 参数与响应](https://api-docs.deepseek.com/api/create-chat-completion/)

独立 Thinking Mode 指南本次读取超时；以上结论来自已成功打开的 API 参考。`json_object` 与所有视觉/thinking 组合的实际效果、边缘行为及任务耗时尚未连接测试。

## SSE、用量与重试要按 DeepSeek 的实际协议处理

- `stream=true` 返回 data-only SSE，以 `data: [DONE]` 结束。当前参考明确：最后一个带 `finish_reason` 的 chunk 携带整次 `usage`，**不是另发 choices 为空的 usage-only chunk**；`include_usage=true` 时前面的 usage 为 null。流解析不要只兼容 OpenAI 某一种用量结尾。[流式参数](https://api-docs.deepseek.com/api/create-chat-completion/)
- 等待时，非流式可收到空行，流式可收到 `: keep-alive` 注释；10 分钟未开始推理会关闭连接。连接活着不等于结果已完成。[Rate Limit & Isolation](https://api-docs.deepseek.com/quick_start/rate_limit/)
- 400/422 应修请求，401 应修鉴权，402 应处理余额；429 调整速率，500/503 可短暂等待后重试。具体重试次数、退避与取消策略由应用限定；已消费的中断请求是否收费、是否有幂等保证，本次未确认。[错误码](https://api-docs.deepseek.com/quick_start/error_codes/)

## Jev：专用数值协议，不能用普通聊天评分替代

本次实际访问了 [OCR Correctness Decision API](https://platform.modelbest.ai/console/docs/api/ocr-jev)：网页读取器无法提取正文，公开 HTTP 请求只取得客户端 HTML，**未重新核实当前正文**。以下仅沿用项目 [2026-11-03 官方页面核实记录](../modelbest-api-alignment.md)，不是本次的现网确认：

- 云端使用 `/v1/chat/completions` 外层，但请求含专用 `minicpm_ocr_jev`，模型名为 `MiniCPM-OCR-Jev`；评分 JSON 在 `choices[0].message.content` 字符串里。它与本地 `/v1/systemone` 类别分布协议不同。
- 三种模式为 `score`、`score_best`、`score_best_batch`；候选必须描述同图同一部分。服务端默认渲染，也可提交渲染图；Jev 分类而不生成正文。
- 只有 `verdict=scored` / 相应 `verdicts[i]=scored` 的分数有效；HTTP 200、`best_index=0` 都不足以证明成功。失败、未运行与有效低分需要独立状态。

因此它是借 Chat Completions 外壳承载的**专用评分契约**，不是让任意聊天模型回答“打几分”。当前 base URL、鉴权细节、字段现行版本、流式行为、用量与价格仍需在后续获准接入前重新核实；不能据历史记录写成已连接。

## 接入时仍需核实

- 所选模型的真实手写效果、请求用量与费用。
- DeepSeek 视觉、thinking 与 JSON mode 组合的实际行为；strict 工具 Beta 不作为首版默认依赖。
- 中断请求收费与幂等保证。
- 云端 Jev 当前正文与连接协议；本机 Jev 则沿用比赛版模型和本机协议。
