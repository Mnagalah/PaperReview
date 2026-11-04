# 开发与协作

仓库：[Mnagalah/PaperReview](https://github.com/Mnagalah/PaperReview)（Private）。

## 环境

Apple Silicon、Xcode / Swift 6.2+。最低目标为 macOS 14；已测试环境为 macOS 27.2、24 GiB 内存。

模型下载和启动见[README](../README.md)。比赛使用 MiniCPM-OCR F16、Jev Q4_K_M、MiniCPM5-2B Q4_K_M，权重放在 `.local-models/`，由各开发者单独下载。

## 构建

```sh
swift test
bash Tests/ModelScriptsTests/startup_tests.sh
./script/build_and_run.sh --build-only
```

`dist/PaperReview.app` 链接到 `~/Library/Developer/PaperReview/Build/PaperReview.app`。构建放在本地 Developer 目录，避免 Documents 文件提供程序改写签名；旧构建保存在 `Previous/`。

## 测试

普通 `swift test` 使用合成数据，无需模型服务。运行真实模型语义测试：

```sh
PAPERREVIEW_REAL_MODELS=1 \
PAPERREVIEW_SEMANTIC_EVIDENCE=/tmp/PaperReview-semantic.json \
swift test --filter semanticReviewUnderstandsContext
```

该测试目前命中 2/4 个预期错误，漏报 `accept → except`、`since → for`。其他结果和耗时见[测试记录](verification/workspace-review-20261104.md)。手写样本测试另需本机 `record.json`；参考答案仅用于断言。

用独立作业目录测试界面：

```sh
./script/build_and_run.sh --verify \
  --data-root /tmp/PaperReview-QA \
  --import /absolute/path/to/photo.png
```

默认作业目录是 `~/Library/Application Support/PaperReview/Assignments/`。学生照片、作业记录、模型权重和 `.local-tests/` 不提交到 Git。仓库内的图片是[合成测试样本](fixtures/README.md)。

## 代码结构

- `Sources/PaperReviewCore/`：文本结构、UTF16 定位、模型协议、识别质量与可读性规则。
- `Sources/PaperReview/`：SwiftUI / AppKit 界面、图像处理、作业存储和模型进程管理。
- `script/`：构建、模型下载与服务启停。
- `Tests/`：单元测试、macOS 布局测试和模型集成测试。
- `PRODUCT.md`、`DESIGN.md`：产品范围和界面规范。

## 审核流程

系统词典提供拼写线索，2B 模型生成纠错草稿，再进行快速语法检查和全文检查。程序对草稿与原文做差分，确定引用和 UTF16 范围；最后由 2B 模型逐项返回 `apply / keep_original` 和错误类别。

每篇最多四次批量请求，两次思考请求各限 512 token。候选、判断和耗时写入审核历史。中文说明使用固定类别文案。

纠错草稿与 OCR 原文分开保存。服务失败保留已有结果，连接失败不计入作业可读性判断。
