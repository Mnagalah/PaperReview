# MiniCPM 英语作文批改助手：模型与本地接口核实

核实日期：2026-11-03。依据为 OpenBMB 官方仓库、模型卡及 llama.cpp 官方服务文档；本记录没有安装依赖、下载权重或运行模型。

## 推荐实现：三个独立的本地模型服务

macOS 原生 App 负责图像预处理、候选文字渲染、行坐标及批注；三个 llama-server 分别负责 OCR、Jev 一致性判断、基础语言审核。这样可以绕开完整文档 SDK 的 Paddle 版面检测依赖，但 App 必须自己提供区域/行定位。以下端口是本项目建议，避免官方各示例重复使用 18499。

| 职责 | 初始候选 | 建议地址 | 输出 |
|---|---|---|---|
| 识别主体 | MiniCPM-OCR 1.0，Q4_K_M | `127.0.0.1:18499/v1/chat/completions` | 原样文本 |
| 识别复核 | MiniCPM-OCR Jev，Q4_K_M | `127.0.0.1:18500/v1/systemone` | 两类一致性分数 |
| 内容审核 | MiniCPM5-2B，Q4_K_M | `127.0.0.1:18501/v1/chat/completions` | 受约束 JSON 批注 |

用户决定第一轮全部 Q4，暂不下载 Q8。开发机为 Apple Silicon、24 GiB 统一内存，最终占用仍须实测。

### Runtime 固定 b11960，不使用 b11901 启动 Jev

OCR 文档的已验证参考版本是 b11901，但该版本的 [server-decision.cpp](https://github.com/ggml-org/llama.cpp/blob/b11901/tools/server/server-decision.cpp)尚无 MiniCPM-OCR-Jev 分支。其 `/v1/systemone` 存在，不代表支持此权重。Jev 支持在 [PR #30980](https://github.com/ggml-org/llama.cpp/pull/30980)、commit `7eed6b7685d2abc32182c0df330812e3848b862f` 合入。

采用 [v0.8.0](https://github.com/ggml-org/llama.cpp/releases/tag/v0.8.0) 对应的 nightly **b11960**，二者目标 commit 同为 `8642541b255bfb5dc39cd351a178be09013a55d6`。该 release 明列 OCR 与 Jev；[b11960 源码第 196 行](https://github.com/ggml-org/llama.cpp/blob/b11960/tools/server/server-decision.cpp#L196)已有 `COMMON_DECISION_TYPE_MINICPM_OCR_JEV`。下载 [macOS ARM64 archive](https://github.com/ggml-org/llama.cpp/releases/download/b11960/llama-b11960-bin-macos-arm64.tar.gz)，16,465,074 bytes。保持包中动态库与可执行文件的相对位置，无需源码构建。

### 第一轮下载清单

尺寸来自各官方 Hugging Face 仓库的 `tree/main` API 元数据，单位 bytes；权重运行时还需要 KV cache、图像编码和其他缓冲区。

| 文件 | 精确尺寸 | 官方直链 |
|---|---:|---|
| MiniCPM-OCR-1_0-Q4_K_M.gguf | 529,106,816 | [下载](https://huggingface.co/openbmb/MiniCPM-OCR-1.0-gguf/resolve/main/MiniCPM-OCR-1_0-Q4_K_M.gguf) |
| mmproj-model-f16-4x.gguf | 901,017,536 | [下载](https://huggingface.co/openbmb/MiniCPM-OCR-1.0-gguf/resolve/main/mmproj-model-f16-4x.gguf) |
| MiniCPM-OCR-Jev-Q4_K_M.gguf | 1,274,405,248 | [下载](https://huggingface.co/openbmb/MiniCPM-OCR-Jev-gguf/resolve/main/MiniCPM-OCR-Jev-Q4_K_M.gguf) |
| mmproj-model-f16.gguf | 671,372,416 | [下载](https://huggingface.co/openbmb/MiniCPM-OCR-Jev-gguf/resolve/main/mmproj-model-f16.gguf) |
| MiniCPM5-2B-Q4_K_M.gguf | 1,561,318,368 | [下载](https://huggingface.co/openbmb/MiniCPM5-2B-GGUF/resolve/main/MiniCPM5-2B-Q4_K_M.gguf) |

五文件共 **4,937,220,384 bytes（4.937 GB / 4.598 GiB）**，另加 runtime archive 约 16.5 MB。不含可选 DSpark。元数据来源：[OCR](https://huggingface.co/api/models/openbmb/MiniCPM-OCR-1.0-gguf/tree/main)、[Jev](https://huggingface.co/api/models/openbmb/MiniCPM-OCR-Jev-gguf/tree/main)、[文本模型](https://huggingface.co/api/models/openbmb/MiniCPM5-2B-GGUF/tree/main)。

## 1. OCR：文件、启动与请求

[官方 OCR llama.cpp 指南](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/llamacpp_deploy.md)使用匹配的主模型、4× projector、DSpark 头。第一轮使用上表 Q4 主模型与 projector，先不开 DSpark；若以后开启，另取匹配的 [dspark-MiniCPM-OCR-1_0-Q4_K_M.gguf](https://huggingface.co/openbmb/MiniCPM-OCR-1.0-DSpark-gguf/resolve/main/dspark-MiniCPM-OCR-1_0-Q4_K_M.gguf)，211,322,464 bytes，并增加 `--model-draft`、`--spec-type draft-dspark`、`--spec-draft-n-max 15`、`--gpu-layers-draft 99`。DSpark 头不能单独识别。

下列命令假设权重和配套 runtime 已准备好；它们不会下载权重：

```bash
llama-server \
  --model /path/to/MiniCPM-OCR-1_0-Q4_K_M.gguf \
  --mmproj /path/to/mmproj-model-f16-4x.gguf \
  --n-gpu-layers 99 --flash-attn on \
  --ctx-size 8192 --parallel 1 --host 127.0.0.1 --port 18499 \
  --alias minicpm-ocr --jinja --reasoning off
```

Metal 在 Apple Silicon 默认启用；本项目采用上面确认含 Jev 支持的 b11960 预编译包。

### 请求契约

以下结构来自 SDK 的 [dialects.py](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/sdk/minicpmvocr/backends/dialects.py)，不是把 Linux vLLM 参数照搬到 Mac：

```json
{
  "model": "minicpm-ocr",
  "messages": [{
    "role": "user",
    "content": [
      {"type": "image_url", "image_url": {"url": "data:image/png;base64,<PNG_BASE64>"}},
      {"type": "text", "text": "Text Recognition:"}
    ]
  }],
  "max_tokens": 4096,
  "stream": false,
  "temperature": 0.01,
  "top_p": 0.001,
  "top_k": 1,
  "repeat_penalty": 1.0
}
```

```bash
curl --noproxy 127.0.0.1 -f http://127.0.0.1:18499/health
curl --noproxy 127.0.0.1 -f http://127.0.0.1:18499/v1/chat/completions \
  -H 'Content-Type: application/json' --data-binary @ocr-request.json
```

读取 `choices[0].message.content`，同时保存 `finish_reason`；输出被长度限制截断时不能视为完整识别。官方正文识别提示就是 `Text Recognition:`，见 [prompts.py](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/sdk/minicpmvocr/prompts.py)。附加“不要纠错”等提示属于本应用待验证的提示设计，不能凭提示承诺忠实度。

### 坐标能力

直接模型 chat 返回文本，不附带现成的逐词/逐行框。完整 SDK 先做版面检测，再裁块识别；`--json` 可以得到 `ocr.blocks[]` 及图像尺寸、旋转状态，见 [SDK API](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/minicpm_ocr_sdk_api_en.md)。SDK 的 [_blocks.py](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/sdk/minicpmvocr/pipeline/_blocks.py)保存每块 `bbox`、`order`、`raw_content`、`content`。不能据此声称有逐词位置。若要求手写行对齐，App 需要独立检测行几何并维护“行 ID—源图区域—转写文本”的关系。

## 2. Jev：推荐原生直连，不经 Python 渲染服务

[Jev 指南](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/minicpm_ocr_jev_en.md)说明：它是 2B 二分类模型，输入为相同区域的原图、候选文本和候选渲染图；输出衡量识别候选与原图的一致程度。它既不生成 OCR 文本，也不评作文好坏。

[官方 Jev llama.cpp 部署指南](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/llamacpp_deploy_jev_en.md)列出 Apple Silicon ≥16 GB 统一内存的参考要求，Q4_K_M 是最小推荐构建。Jev 的 projector 始终为 `mmproj-model-f16.gguf`；不能与 OCR 的 `mmproj-model-f16-4x.gguf` 混用。精确尺寸与直链见下载清单。

```bash
llama-server \
  --model /path/to/MiniCPM-OCR-Jev-Q4_K_M.gguf \
  --mmproj /path/to/mmproj-model-f16.gguf \
  -ngl 99 -c 32768 --host 127.0.0.1 --port 18500
```

启动日志应出现 `decision model type: openbmb-minicpm-ocr-jev` 和监听地址，`GET /health` 成功后再做真实前向评分。

### 直接调用 `/v1/systemone`

以下是[官方 llama.cpp adapter 的精确结构](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/scripts/minicpm-ocr-jev/sdk/jev_score/backends/llamacpp_backend.py)：

```json
{
  "state": "The student's uncorrected OCR text.",
  "files": [
    "data:image/png;base64,<ORIGINAL_REGION_PNG_BASE64>",
    "data:image/png;base64,<RENDERED_CANDIDATE_PNG_BASE64>"
  ],
  "questions": {
    "consistency": {
      "type": "choice",
      "criteria": {"0": null, "1": null}
    }
  }
}
```

```bash
curl --noproxy 127.0.0.1 -f http://127.0.0.1:18500/v1/systemone \
  -H 'Content-Type: application/json' --data-binary @jev-request.json
```

读取 `answers.consistency.probabilities["1"]`，**越高越一致**，并要求 `"0"` 和 `"1"` 都存在、为有限数值且在 0–1 内。原图必须在第一张，候选渲染图在第二张；交换顺序不会必然报错，却会改变模型输入含义。分数已激活，不能再做一次 softmax。不要增加任务 `instructions`，Jev 的固定任务已在模板内，额外 instructions 会被拒绝。

### 若使用官方 SDK score service

其 `/v1/score` 接收 `{"items":[{"original_image":"<纯base64>","render_image":"<纯base64>","ocr_text":"..."}]}`，返回 `{"results":[{"prob_1":0.00227,"error":null}]}`。原始图片字段无 data URL 前缀；这与上面的直连协议不同。`JEV_BACKEND_CONFIG=sdk/backends/llamacpp.yaml` 必须设置，否则默认说 vLLM 协议。[配置来源](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/scripts/minicpm-ocr-jev/sdk/backends/llamacpp.yaml)

带渲染的 `/v1/rm/score*` 是第三种协议，见 [Docker/SDK API](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/minicpm_ocr_jev_docker_api_en.md)。只有 `verdict=scored` 才能使用 `prob_yes`，错误哨兵值不能当成普通低分。其默认 `threshold=0.5` 只影响汇总通过率，不是英语手写的已验证产品阈值。

Mac 原生渲染应固定字体、字号、宽度和留白，并把渲染配置版本与评分一起保存。官方 render+score 安装脚本依赖 Linux 字体栈，Mac 上的绝对分数不能直接套用其发布数字。

## 3. MiniCPM 内容审核：选 2B，但由应用校验定位

当前主线提供 MiniCPM5-2B 与 1B。采用 2B Q4 做基础语法/拼写审核候选，而不是直接退到 1B；这是应用选型判断，尚无本任务的实样本效果比较。[官方部署指南](https://github.com/OpenBMB/MiniCPM/blob/main/docs/deployment/llama_cpp.md)列出该 Q4 构建，精确尺寸与直链见下载清单。

```bash
llama-server \
  --model /path/to/MiniCPM5-2B-Q4_K_M.gguf \
  --alias MiniCPM5-2B --host 127.0.0.1 --port 18501 \
  -ngl 99 -c 8192 --jinja
```

使用 `/v1/chat/completions`，`messages` 为普通 system/user 文本。官方 Quickstart 推荐 `temperature=1.0, top_p=0.95, min_p=0.0`；尤其不能忘记 `min_p=0.0`，文档说明默认 0.05 可能引发重复输出。[MiniCPM README](https://github.com/OpenBMB/MiniCPM#quickstart)

结构化 JSON 是[llama.cpp 服务端能力](https://github.com/ggml-org/llama.cpp/blob/b11960/tools/server/README.md#post-v1chatcompletions-openai-compatible-chat-completions-api)：可传 `response_format={"type":"json_object","schema":{...}}`。这只约束结构，不保证错误判断正确。应用应发送带稳定 ID 的原文行，要求返回行 ID、逐字引用、修改建议与中文说明，再校验引用确实存在。定位失败的批注不能猜位置挂到另一个同词上。

审核输出只能增加批注，不覆盖 OCR 转写。拼写、大小写、标点和重复词均属于学生原作的一部分。无法辨认的笔迹和低 Jev 分数应走“待核对”，不能当成学生语言错误。

## 4. 阈值、重试与验收依据

Jev 官方建议用本应用样本选择阈值，并要求同一区域的候选保持相同 crop 与内容边界。建议产品实现限制重试次数、保留各候选及分数、选择已评分候选中的最佳值；超限仍不足则转老师复核，而不是无限循环。阈值只能作为可调实验参数。[Jev 用法与筛选说明](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/minicpm_ocr_jev_en.md#use-cases)

llama.cpp 明示分数未必对调用者数据校准，因此 UI 宜写“一致性分数”，不要写“原文准确率 98%”。Jev 最新官方指南也明示现有 AUROC 结果不建立通用默认阈值；SDK `tau=0.98` 是配置示例，不能代替手写样本校准。

当前查到的官方材料未给出本应用所需的英语学生手写作文、错词忠实保留和基础审核联合验收结果。之后应以脱敏真实手写样本分别测字符错误、错词被自动改正、漏字、行对齐、基础错误误报/漏报；不能用普通文档 benchmark 代替。

官方有可作导入/识别冒烟测试的[英文手写电场笔记原图](https://raw.githubusercontent.com/OpenBMB/MiniCPM-OCR/main/webdemo/frontend/src/pages/playground/assets/ocr-examples/electric-field.png)，已目视确认是手写英语与公式；它不是作文，不能当作文效果验收样本。

## 5. 许可

OCR 仓库代码采用 [Apache-2.0](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/LICENSE)。[OCR 1.0 模型卡](https://huggingface.co/openbmb/MiniCPM-OCR-1.0)、[Jev 模型卡](https://huggingface.co/openbmb/MiniCPM-OCR-Jev)、[MiniCPM5-2B 模型卡](https://huggingface.co/openbmb/MiniCPM5-2B)均标记 Apache-2.0。再分发时附许可证副本，保留版权和归属信息，保留适用 NOTICE（如上游有），对修改文件显著说明修改；许可不授商标权。按实际捆绑的 runtime、字体、图像处理依赖另行记录第三方许可。
