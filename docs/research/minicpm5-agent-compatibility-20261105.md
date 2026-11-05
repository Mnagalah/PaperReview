# MiniCPM5-2B 本机 Agent 工具调用兼容性

核查日期：2026-11-05。范围为现有 `MiniCPM5-2B Q4_K_M`、`llama.cpp b11960` 与 Apple Silicon。依据本次实际打开的官方文档、固定标签源码，以及本地动态库只读检查；未启动模型或服务，未安装后端、下载权重或调用付费 API。

## 结论：保留现有 llama.cpp 路线，具备接工具循环的原生基础

**b11960 已有 MiniCPM5 专用 XML 工具调用解析器。** 不能因为 OpenBMB 推荐 SGLang，就认定当前本机模型只能做固定提示词节点，或必须换后端才能成为工具调用 Agent。模型选择下一步工具、服务端解析调用、宿主执行工具循环是三层不同能力；现有路线的关键剩余工作在宿主接线与实际验证。

### 模型与格式

- OpenBMB 将 MiniCPM5-2B 的工具调用定义为 XML 风格，并推荐由 SGLang 的 `minicpm5` parser 转成 OpenAI 兼容 `tool_calls`；这是推荐实现，不是模型只支持 SGLang 的声明。[官方 README](https://github.com/OpenBMB/MiniCPM#tool-calling)、[官方 GGUF 模型卡](https://huggingface.co/openbmb/MiniCPM5-2B-GGUF#tool-calling)
- 官方 llama.cpp 指南直接提供 `MiniCPM5-2B-Q4_K_M.gguf`，说明支持 Apple Silicon，并以 `llama-server ... --jinja` 提供 `/v1/chat/completions`；该示例只验证普通聊天，没有验证完整工具循环。[llama.cpp 部署指南](https://github.com/OpenBMB/MiniCPM/blob/main/docs/deployment/llama_cpp.md)

### b11960 服务解析

- `common/chat.cpp` 第 1397–1403 行识别模板中的 `Tool usage guidelines:`、`<function name="` 和 `<param name="`，选择 `common_chat_params_init_minicpm5`，不是依赖通用兜底解析。[固定标签识别入口](https://github.com/ggml-org/llama.cpp/blob/b11960/common/chat.cpp#L1397-L1403)
- `common/parsers/minicpm5.cpp` 直接解析 `<function name="…"><param name="…">…</param></function>`，支持字符串 CDATA、JSON 类型参数、推理内容分离、工具调用语法约束，并按 `parallel_tool_calls` 控制单次或多次调用。[专用解析器](https://github.com/ggml-org/llama.cpp/blob/b11960/common/parsers/minicpm5.cpp)
- 解析后的调用由公共聊天消息转换为 `tool_calls[].function.name` 和字符串 `arguments`，对外不要求 SDK 自己解析 XML。[OpenAI 兼容消息映射](https://github.com/ggml-org/llama.cpp/blob/b11960/common/chat.cpp#L218-L240)
- 本地 `/Users/melchior/Documents/ChatGPT/OpenBMB/.local-models/runtime/llama-b11960/libllama-common.0.8.0.dylib` 的只读 `strings` 检查也找到 `Using specialized template: MiniCPM5` 与对应函数符号，说明现有动态库编入了该处理器；尚未验证运行时是否命中当前 GGUF 的嵌入模板。

### `--jinja` 的作用与宿主契约

`--jinja` 启用支持工具的模板路线；b11960 在模板匹配时可选择上述专用处理器。因此可以保留当前后端，无需预先另写 XML 正则适配器。**单加该开关不会自动执行工具或形成 Agent。** [llama.cpp 工具调用说明](https://github.com/ggml-org/llama.cpp/blob/b11960/docs/function-calling.md)、[Jinja 分派与专用处理器选择](https://github.com/ggml-org/llama.cpp/blob/b11960/common/chat.cpp)

拟接入的宿主或 SDK 适配层需要：

1. 通过 `/v1/chat/completions` 发送 `messages`、工具定义 `tools` 与适当的 `tool_choice`，而非仅把工具名称写进普通提示词。
2. 读取并保留 assistant 的 `tool_calls`，验证函数名、参数与权限；执行允许的工具后，将结果以 `role: "tool"` 和对应 `tool_call_id` 回填，再请求模型继续。官方模板负责把工具定义、历史调用和工具结果转换为模型所需格式。[官方聊天模板](https://huggingface.co/openbmb/MiniCPM5-2B/blob/main/chat_template.jinja)
3. 在宿主控制步数、时间、取消、失败恢复和最终提交。只支持某家 Responses 协议的默认适配器，不能仅修改 `base_url` 就视为已兼容；应选择或实现 Chat Completions 模型适配层。具体框架兼容性仍需对其请求、返回及工具回填协议单独验收。

源码还给出一个接线取舍：MiniCPM5 解析器先判断 `json_schema`，再进入工具分支。由此建议工具选择回合不同时强制最终报告的 `response_format`；最终结构化报告放在收尾回合，避免把两种输出契约混在一次生成中。[解析分支顺序](https://github.com/ggml-org/llama.cpp/blob/b11960/common/parsers/minicpm5.cpp#L49-L62)

## macOS 官方推荐按目标区分，不必为了 Agent 迁移

- **保留 GGUF、本机 HTTP 服务或不使用 Python：** llama.cpp 是官方 CPU、边缘与消费级 GPU 路线，覆盖 Apple Silicon。[llama.cpp 指南](https://github.com/OpenBMB/MiniCPM/blob/main/docs/deployment/llama_cpp.md)
- **Apple Silicon 单 Python 进程、追求吞吐：** OpenBMB 推荐 MLX，但使用独立 MLX 格式，不是现有 Q4_K_M 文件的原地替代；这份指南的推荐不等于本机工具循环已经验收。[MLX 指南](https://github.com/OpenBMB/MiniCPM/blob/main/docs/deployment/mlx.md)
- **官方工具调用示范：** SGLang 明确提供 `--tool-call-parser minicpm5`，示例使用 BF16 模型与 CUDA 环境。文档同页仍保留“等待 v0.5.13”的旧 pip 提示，却又列出 `>=0.5.16` 安装行；本次没有核验 pip 发行或运行 SGLang，不据此断言当前 pip 是否包含解析器，也不将其当作 Apple Silicon / GGUF 的直接替换方案。[SGLang 指南](https://github.com/OpenBMB/MiniCPM/blob/main/docs/deployment/sglang.md)

## 接入前尚未验证的三件事

1. 当前 GGUF 嵌入模板能否在现有启动参数下命中 MiniCPM5 处理器，返回真正的 `tool_calls`，而非 XML 文本。
2. 选定 SDK / 宿主能否完成“模型选工具 → 执行 → 回填 → 再选工具或结束”的多步闭环，正确保留 ID、参数和必要历史。
3. Q4_K_M 在本项目任务中的工具选择、参数完整性、停止行为及延迟。模型卡的工具能力说明与源码支持，不能替代这一量化配置的任务验收。

方案建议：先保留当前模型与 b11960，在受限工具集上验证上述闭环；只有实际证据表明该路线不满足要求时，再比较换后端或模型的收益与迁移成本。
