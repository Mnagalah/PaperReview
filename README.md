# 作文批阅

本地运行的 macOS 英语作文批阅工具。导入手写作业照片，识别原文，再标注拼写、语法、标点和大小写错误。批注不改写原文。

## 下载安装

从 [Releases](https://github.com/Mnagalah/PaperReview/releases) 下载 `PaperReview-0.1.1-macOS-arm64.zip`，解压后将 `PaperReview.app` 拖到“应用程序”。私有仓库需要登录有权限的 GitHub 账号。

打开应用的**模型设置 → 下载模型**，确认后自动下载；完成后点击**启动模型**。无需安装 Xcode 或单独配置 Python。需要 Apple Silicon Mac，最低目标 macOS 14，建议 24 GB 内存。

当前使用开发签名，尚未公证。若首次打开被 macOS 阻止，请确认下载来源后，在“系统设置 → 隐私与安全性”自行批准打开。

模型配置：

- 识别：[MiniCPM-OCR 1.0 F16](https://modelscope.cn/models/OpenBMB/MiniCPM-OCR-1.0-gguf)
- 图文复核：[Jev Q4_K_M](https://modelscope.cn/models/OpenBMB/MiniCPM-OCR-Jev-gguf)
- 内容审核：[MiniCPM5-2B Q4_K_M](https://modelscope.cn/models/OpenBMB/MiniCPM5-2B-GGUF)

权重及投影文件约 5.924 GB，[llama.cpp b11960 官方运行时](https://github.com/ggml-org/llama.cpp/releases/tag/b11960)约 16.5 MB。下载支持续传、跳过完整文件。首次下载约 5.94 GB，模型不包含在应用 ZIP 中。

下载区显示进度、速度、剩余量和预计时间；连接中断会显示重试状态，失败后可点击**重试续传**。**删除模型…**确认后将当前模型和未完成下载移到废纸篓，保留运行时、作业及无关文件；正在使用的文件不可删除。

## 使用

1. 在左侧点击**导入照片**（⌘O），或拖入 JPEG、PNG、HEIC、TIFF。重复文件会提醒。
2. OCR 完成后立即显示原文，随后进行逐词识别、Jev 复核和基础审核。识别不稳定时重新识别，总计最多三轮。
3. 在阶段栏右端切换**左右、上下、滑动对照**。支持同步滚动和双指缩放；转写保留物理换行，字号为 18pt。
4. 点击批注定位原词。红色表示拼写错误，橙色表示其他语言错误；紫色表示识别疑义，可用标题旁的**疑义标记**开关隐藏。
5. 点击顶部 **Jev** 查看识别复核详情。难以识读的作业会提示“这份作业可读性较差”，可通过**核对原文**修正后重新审核。
6. **忽略**隐藏批注，可在更多菜单中查看并恢复；**编辑原文**保存后重新审核；**导出**可保存原文或带批注的 Markdown。
7. 列表右键或删除键可将作业副本移到废纸篓，来源照片保留。处理中的作业暂不可删除。

支持单张照片内的单页或左右双页，按左页、右页顺序识别。连续边栏行号和模板标签与学生正文分开保存。

## 数据

照片和文字仅在本机处理。作业保存在 `~/Library/Application Support/PaperReview/Assignments/`，发行版模型默认保存在 `~/Library/Application Support/PaperReview/Models/`，日志在该目录的 `run/` 中。服务仅监听本机端口 `18499 / 18500 / 18501`。

关闭窗口后模型服务继续运行，可在模型设置中停止。

## 开发

```sh
./script/setup_models.sh
./script/start_models.sh
swift test
bash Tests/ModelScriptsTests/startup_tests.sh
python3 Tests/ModelScriptsTests/download_resume_tests.py
./script/build_and_run.sh --build-only
./script/package_release.sh
```

开发需要 Xcode / Swift 6.2+。开发模型放在 `.local-models/`；`dist/PaperReview.app` 是本机开发构建入口。构建、独立测试目录和代码结构见[协作说明](docs/COLLABORATION.md)。

## 已知问题

- `accept → except`、`since → for` 的定向测试与正确用法控制已通过，其他语义错误仍可能漏报或误报，见[测试结果](docs/verification/lexical-review-20261104.md)。
- 连笔、淡字和词框边界仍有识别误差。暂不支持跨照片合并、任意弯曲书页展平和涂改笔迹解释。
- 发行包尚未公证，未在最低目标 macOS 或另一台 Mac 上验证。

[产品范围](PRODUCT.md) · [设计规范](DESIGN.md) · [实现记录](docs/implementation-status.md) · [模型与运行时来源](docs/THIRD_PARTY.md)
