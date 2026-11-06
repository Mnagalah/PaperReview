# PaperReview

PaperReview 是面向教师的 macOS 英语作文批阅应用，用于手写作文的文字识别、原稿核对和基础语言审核。应用将批注建议关联到原文位置，由教师确认处理结果，并保存作业与批阅记录。

[下载发行版](https://github.com/Mnagalah/PaperReview/releases/latest) · [使用说明](docs/RELEASE_USAGE.txt) · [开发文档](docs/COLLABORATION.md)

## 核心功能

- **作业识别**：导入 JPEG、PNG、HEIC、TIFF 格式的作文照片，支持单页及同一照片内的左右双页识别，保留原始照片与转写结果。
- **原稿核对**：对照照片与识别文本，按原文位置查看问题，支持人工校对和重新审核。
- **语言审核**：检查拼写、语法、标点和大小写等基础语言问题，生成附带原文引用与位置的批注建议。
- **批阅管理**：逐条确认或放弃建议，支持恢复、撤销和重做，保存教师的处理记录与批阅完成状态。
- **结果导出**：以 Markdown 格式导出识别文本，或包含批注及其处理状态的文档。

## 技术实现

### 应用架构

项目采用 Swift 6.2、SwiftUI 和 AppKit，通过 Swift Package Manager 组织与构建。最低部署目标为 macOS 14，当前发行版本面向 Apple Silicon Mac。

| 模块 | 职责 |
| --- | --- |
| `PaperReview` | 应用界面、图像处理、作业流程与数据存储 |
| `PaperReviewCore` | 文本结构、原文定位、批注状态、质量判断与模型接口 |
| `PaperReviewLocalModels` | 本地模型配置、下载、服务启停与推理调用 |

应用通过 `ModelModule` 和 `ModelSession` 调用模型能力，作业流程与具体推理实现分离。

### 图像处理与模型推理

图像处理使用 Apple Vision 和 Core Image，完成纸面检测、文字区域定位、透视校正与扫描增强。识别文本通过行、词坐标与原图建立对应关系。

模型通过 llama.cpp 在本机运行：

| 模型 | 规格 | 用途 |
| --- | --- | --- |
| MiniCPM-OCR 1.0 | F16 | 整页转写与词区域识别 |
| MiniCPM-OCR Jev | Q4_K_M | 评估候选文字与图像的一致性，辅助识别复核 |
| MiniCPM5-2B | Q4_K_M | 结合上下文生成基础语言审核建议 |

处理流程依次完成图像预处理、整页转写、逐词核验、图文复核和语言审核。应用根据核验结果选择识别候选，并在结果不稳定时自动重试，总计最多三轮。

语言审核先生成内部纠错草稿，再与原始转写比较差异，将建议映射到对应文本范围。识别文本、模型建议和教师决定分别记录。审核建议以批注形式保存，原始转写独立保留。

### 本地运行与数据保存

模型与运行时下载完成后，识别和语言审核均在本机执行。模型服务仅监听回环地址，应用通过本机 HTTP 接口调用。模型管理支持下载暂停、续传及服务启停。

作业以原始图片、处理后的图片和 JSON 记录保存，包含识别结果、文字坐标、审核历史及教师处理状态。默认存储位置为：

- 作业数据：`~/Library/Application Support/PaperReview/Assignments/`
- 发行版模型：`~/Library/Application Support/PaperReview/Models/`

模型来源与许可见[第三方说明](docs/THIRD_PARTY.md)，构建与测试方法见[开发文档](docs/COLLABORATION.md)。
