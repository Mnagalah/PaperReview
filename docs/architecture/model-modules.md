# 模型模块

比赛版已接入本地模块。API 模块留待下一阶段，不改变当前运行路径。

```text
PaperReview：工作区、图像处理、作业队列、保存、定位、导出
        ↓ ModelModule / ModelSession
PaperReviewLocalModels：本机配置、设置界面、下载、启停、OCR、Jev、基础审核
        ↓
既定三个模型与 llama.cpp
```

## 共享部分

`PaperReviewCore` 保存转写、页行词结构、批注与版本，以及小型模型接口。`WorkspaceStore` 仍是业务流程的唯一负责人：整页识别 → 全部词区核验 → Jev → 基础审核。图像增强、阅读顺序、质量门、定位和保存不交给模型模块调度。

`ModelModule` 提供就绪状态、识别参数、任务会话和退出准备。设置窗口保留共享的外观部分，模型设置内容由应用入口注入。

`ModelSession` 提供识别、图文复核和全文审核。会话在任务开始时固定配置；后续保存设置不会改变进行中的任务。工作区不接触服务地址、HTTP 协议或下载脚本。缓存标识由会话提供，避免换地址后沿用其他模型结果。

## 本地模块

`Sources/PaperReviewLocalModels/` 包含：

- `Inference/`：地址校验、请求、提示词、解析及 2B 审核策略。
- `Management/`：下载进度、暂停恢复、删除保护和进程控制。
- `Views/`：本机模型与高级设置。
- `LocalModelModule.swift`：配置保存、健康检查、会话创建与退出准备。

配置继续读取原有 `modelConfiguration` 和 `modelHome`，作业与下载记录路径不变。比赛版仍要求 OCR、Jev、审核三个服务就绪；地址只允许 loopback，学生图片不会被重定向到外部。

本次没有修改模型、提示词、采样参数、审核步骤、透视算法或逐词覆盖规则。退出仍只暂停下载，模型服务可在设置中单独停止。

## 以后接 API

新增 API 模块，在应用入口替换模块实例和设置内容；不复制工作区和数据层。DeepSeek / OpenAI 兼容请求、密钥和专用错误归该模块负责。Jev 可选状态与云端恢复在该阶段补齐并验证，当前不增加空实现或隐藏开关。

底层 `ModelClient`、`ModelConfiguration` 的开发调用改为导入 `PaperReviewLocalModels`；函数签名与本机地址限制保留。共享业务只依赖 `PaperReviewCore` 的接口。

[API 方案](api-edition-architecture.md) · [本轮验证](../verification/local-model-module-20261105.md)
