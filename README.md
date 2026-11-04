# 作文批阅

本地运行的 macOS 英语作文批阅工具。导入手写作业照片，识别原文，再标注拼写、语法、标点和大小写错误。批注不改写原文。

## 启动

需要 Apple Silicon Mac 和 Xcode / Swift 6.2+，目标系统为 macOS 14+。

```sh
./script/setup_models.sh
./script/start_models.sh
./script/build_and_run.sh
```

模型配置：

- 识别：MiniCPM-OCR 1.0 F16
- 图文复核：Jev Q4_K_M
- 内容审核：MiniCPM5-2B Q4_K_M

权重及投影文件约 5.924 GB，llama.cpp b11960 运行时约 16.5 MB。文件下载到 `.local-models/`，支持续传。

也可通过 Codex Run 或 `dist/PaperReview.app` 启动。模型可在应用设置中启停。

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

照片和文字仅在本机处理。作业保存在 `~/Library/Application Support/PaperReview/Assignments/`，模型日志在 `.local-models/run/`。服务仅监听本机端口 `18499 / 18500 / 18501`。

关闭窗口后模型服务继续运行。停止服务：

```sh
./script/stop_models.sh
```

## 开发

```sh
swift test
bash Tests/ModelScriptsTests/startup_tests.sh
./script/build_and_run.sh --build-only
```

构建、独立测试目录和代码结构见[协作说明](docs/COLLABORATION.md)。

## 已知问题

- 语义测试仍漏报 `accept → except`、`since → for`，部分类别判断不准，见[测试结果](docs/verification/workspace-review-20261104.md)。
- 连笔、淡字和词框边界仍有识别误差。暂不支持跨照片合并、任意弯曲书页展平和涂改笔迹解释。
- 当前构建为本机 ad-hoc 签名，尚无公证安装包。

[产品范围](PRODUCT.md) · [设计规范](DESIGN.md) · [实现记录](docs/implementation-status.md) · [模型与运行时来源](docs/THIRD_PARTY.md)
