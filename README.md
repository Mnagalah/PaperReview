# PaperReview · 作文批阅

**基于 [OpenBMB](https://github.com/OpenBMB) MiniCPM 模型的本地 macOS 英语作文批阅助手。**

导入一张手写作文照片，在原稿与识别稿之间对照阅读，定位拼写、语法、标点和大小写问题，再由老师逐条确认批注。照片、识别结果和批注分别保存，批阅建议不改写学生原文。

[下载最新正式版](https://github.com/Mnagalah/PaperReview/releases/latest) · [开始使用](#下载安装) · [OpenBMB 模型分工](#openbmb-如何支撑批阅) · [开发说明](docs/COLLABORATION.md)

## OpenBMB 如何支撑批阅

PaperReview 的三个核心模型均来自 **OpenBMB**，分别承担转写、图文复核和基础审核，让从照片到批注的模型推理都能在 Apple Silicon Mac 上完成。

**照片 → MiniCPM-OCR 转写 → Jev 图文复核 → MiniCPM5-2B 审核 → 教师确认**

### MiniCPM-OCR 1.0：把手写照片转为文字

[MiniCPM-OCR](https://github.com/OpenBMB/MiniCPM-OCR) 是文字识别的主体。应用先进行整页转写，立即展示识别结果，再对全部检测到的词区独立识别，结合原色与扫描增强图核对差异。当前使用官方 [F16 权重](https://modelscope.cn/models/OpenBMB/MiniCPM-OCR-1.0-gguf)。

### MiniCPM-OCR Jev：检查识别结果与照片是否一致

[Jev](https://github.com/OpenBMB/MiniCPM-OCR/blob/main/docs/minicpm_ocr_jev_en.md) 对原图、候选文字及其渲染图进行一致性评估。应用将这一信号与逐词识别证据结合，用于比较候选、决定是否重新识别，以及提示仍有疑义的位置。当前使用官方 [Q4_K_M 权重](https://modelscope.cn/models/OpenBMB/MiniCPM-OCR-Jev-gguf)。

Jev 检查的是“读得是否与图一致”；作文中的语言问题交给下一阶段审核。

### MiniCPM5-2B：结合上下文提出批阅建议

[MiniCPM5-2B](https://huggingface.co/openbmb/MiniCPM5-2B) 读取识别文字，结合上下文检查拼写、语法、标点和大小写。应用将审核候选与原文做差分、校验定位，再显示为可逐条确认或放弃的批注。当前使用官方 [Q4_K_M 权重](https://modelscope.cn/models/OpenBMB/MiniCPM5-2B-GGUF)。

**OpenBMB 提供核心模型能力，PaperReview 将这些能力接入老师的批阅流程。** 图像预处理、词区对齐、原稿定位、批注管理和原生界面由应用完成；三个模型通过 [llama.cpp](https://github.com/ggml-org/llama.cpp) 在本机运行。

## 为对照批阅设计

- **原稿、识别稿、建议一起看。** 原生三栏工作区支持左右、上下、滑动对照，以及普通阅读和单独原稿。窄窗将作业列表收为选择入口，批阅建议始终保留。
- **批注能回到原词。** 点击建议即可定位照片与识别稿中的问题；支持确认、放弃、恢复、撤销和重做，老师保留最终判断。
- **每个阶段都有结果。** 转写完成即显示文字，逐词识别、Jev 复核和基础审核继续运行。阶段条、分析状态和缩放保持同排，分析完成后阶段条仍可查看。
- **作业留在本机。** 模型下载完成后，识别与审核无需云端 API。照片和文字仅在本机处理。
- **融入 macOS。** SwiftUI 与 AppKit 原生界面，支持深色、浅色和跟随系统；新版 macOS 使用系统玻璃材质与分层应用图标。

## 下载安装

需要 **Apple Silicon Mac**，最低目标 **macOS 14**，建议 **24 GB 内存**。使用发行包无需安装 Xcode 或单独配置 Python。

1. 从 [Releases](https://github.com/Mnagalah/PaperReview/releases/latest) 下载 `PaperReview-0.1.4-macOS-arm64.zip`，解压后将 `PaperReview.app` 拖到“应用程序”。私有仓库需要登录有权限的 GitHub 账号。
2. 打开 **设置 → 本地服务 → 下载全部模型**，确认后开始下载。
3. 下载完成后点击 **启动全部**，待左下角显示“本机服务已就绪”即可导入作业。

首次下载约 **5.94 GB**：权重及投影文件约 5.924 GB，[llama.cpp b11960 官方运行时](https://github.com/ggml-org/llama.cpp/releases/tag/b11960)约 16.5 MB。模型不包含在应用 ZIP 中。

当前使用开发签名，尚未公证。若首次打开被 macOS 阻止，请确认下载来源后，在“系统设置 → 隐私与安全性”自行批准打开。

### 管理本地模型

下载区显示进度、速度、剩余量和预计时间，支持**暂停下载、继续下载、重试续传**，并跳过已完整下载的文件。退出应用会保留下载进度，重新打开后点击**继续下载**。

**删除全部模型…**经确认后，将当前模型及未完成下载移到废纸篓，保留运行时、作业和无关文件；正在使用的文件不可删除。关闭窗口后模型服务继续运行，需要时可在**设置 → 本地服务**停止。

## 批阅一份作业

1. **导入照片。** 点击左侧导入按钮（⌘O），或拖入 JPEG、PNG、HEIC、TIFF；重复文件会提醒。支持单张照片内的单页或左右双页，双页按左页、右页顺序识别。
2. **查看识别结果。** 转写后自动继续逐词识别、Jev 复核和基础审核；识别不稳定时自动重新识别，总计最多三轮。连续边栏行号、模板标签与学生正文分开保存。
3. **对照原稿。** 从顶部工具栏切换对照方式。底部可调整缩放，窄窗点击百分比打开缩放控件；点击 Jev 查看复核详情。可读性提示位于原稿显示选项下方，疑义标记默认关闭，需要时再开启。
4. **确认批注。** 在右侧选择**确认**或**放弃**；**已确认项**只统计确认的批注，垃圾桶图标可查看并恢复已放弃的问题。未采用的模型建议可从分段控件下方查看。
5. **完成并导出。** 右上角依次为**重新审核、完成批阅、分享**。完成批阅保存教师确认状态；分享可导出**识别结果**或**识别结果（含批注）** Markdown。机器分析完成与教师完成批阅分别记录。

列表右键或删除键可将作业副本移到废纸篓，来源照片保留；处理中的作业暂不可删除。

## 数据存储

- 作业：`~/Library/Application Support/PaperReview/Assignments/`
- 发行版模型：`~/Library/Application Support/PaperReview/Models/`
- 运行日志：模型目录下的 `run/`
- 本机服务端口：`18499 / 18500 / 18501`，仅监听本机。

## 开发

需要 Xcode / Swift 6.2+。开发模型放在 `.local-models/`；`dist/PaperReview.app` 是本机开发构建入口。

```sh
./script/setup_models.sh
./script/start_models.sh
swift test
bash Tests/ModelScriptsTests/startup_tests.sh
python3 Tests/ModelScriptsTests/download_resume_tests.py
python3 Tests/ModelScriptsTests/download_pause_tests.py
./script/build_and_run.sh --build-only
./script/package_release.sh
```

构建、独立测试目录和代码结构见[开发与协作](docs/COLLABORATION.md)。学生照片、作业记录、模型权重和本地验证资料不提交到 Git。

## 当前范围与已知问题

- 当前专注基础语言问题的批注，不做作文评分、扩写或润色。
- 连笔、淡字和词框边界仍可能造成识别误差；Jev 也可能偏向常见拼写，对非标准拼写仍需结合原稿核对。
- `accept → except`、`since → for` 的定向测试与正确用法控制已通过，其他语义错误仍可能漏报或误报，见[测试结果](docs/verification/lexical-review-20261104.md)。
- 暂不支持跨照片合并、任意弯曲书页展平和涂改笔迹解释。
- 发行包未在最低目标 macOS 或另一台 Mac 上验证。

## 开源致谢

感谢 **[OpenBMB](https://github.com/OpenBMB)** 开源 MiniCPM-OCR、MiniCPM-OCR Jev 与 MiniCPM5-2B，为本项目提供文字识别、识别质量评估和语言审核所依赖的模型能力；感谢 **[llama.cpp](https://github.com/ggml-org/llama.cpp)** 提供本地推理运行时。模型、运行时及其他资源的来源与许可见[第三方来源](docs/THIRD_PARTY.md)。

[产品范围](PRODUCT.md) · [设计规范](DESIGN.md) · [实现记录](docs/implementation-status.md) · [0.1.4 发布说明](docs/releases/0.1.4.md)
