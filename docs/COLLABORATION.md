# 开发与协作

仓库：[Mnagalah/PaperReview](https://github.com/Mnagalah/PaperReview)（Private）。

## 环境

Apple Silicon、Xcode / Swift 6.2+。最低目标为 macOS 14；已测试环境为 macOS 27.2、24 GiB 内存。

模型下载和启动见[README](../README.md)。比赛使用 MiniCPM-OCR F16、Jev Q4_K_M、MiniCPM5-2B Q4_K_M，权重放在 `.local-models/`，由各开发者单独下载。

## 构建

```sh
swift test
bash Tests/ModelScriptsTests/startup_tests.sh
bash Tests/ModelScriptsTests/signing_tests.sh
bash Tests/ModelScriptsTests/portable_setup_tests.sh
python3 Tests/ModelScriptsTests/download_resume_tests.py
python3 Tests/ModelScriptsTests/download_pause_tests.py
./script/build_and_run.sh --build-only
./script/package_release.sh
```

`dist/PaperReview.app` 链接到 `~/Library/Developer/PaperReview/Build/PaperReview.app`。构建放在本地 Developer 目录，避免 Documents 文件提供程序改写签名；旧构建保存在 `Previous/`。

脚本优先沿用已有开发证书，可通过 `PAPERREVIEW_SIGNING_IDENTITY` 指定。没有证书时回退 ad-hoc 签名并提示权限可能重询。Release 位于 `~/Library/Developer/PaperReview/Release/`，ZIP 位于 `dist/release/`，不包含源码路径或模型。发行版模型默认使用 Application Support，可在应用内下载；无需源码目录。

下载清单由 `script/model_downloads.tsv` 统一定义，脚本和界面共用大小与文件路径。`download_file.sh` 输出逐文件状态；界面每 0.5 秒读取下载文件大小，以最近 5 秒的新增字节计算速度，不把缓存或续传起点算作本次速度。下载测试使用本机 HTTP 小文件，覆盖断连、503、重试、续传及运行时安装，不下载真实权重。

下载由 `download_supervisor.sh` 管理独立进程组；暂停或应用退出会关闭持有管道，停止该组下载。界面记录保存在 Application Support 的 `PaperReview/Downloads/`，重开只读取记录，不在启动时访问旧模型目录；继续时按实际文件大小续传。

图标源文件为 `Assets/PaperReview.icon/`，可直接用 Icon Composer 编辑。构建时由 `actool` 生成 `Assets.car` 和兼容旧系统的 ICNS，合并生成的图标配置到 Info.plist。

删除只处理清单内的模型、对应临时文件及就绪标记。先用 `lsof` 检查文件占用，再整体移到废纸篓；失败时恢复已移动文件。运行时、其他模型和作业目录不在删除范围内。

## 测试

普通 `swift test` 使用合成数据，无需模型服务。运行真实模型语义测试：

```sh
PAPERREVIEW_REAL_MODELS=1 \
PAPERREVIEW_SEMANTIC_EVIDENCE=/tmp/PaperReview-semantic.json \
swift test --filter semanticReviewUnderstandsContext
```

该测试目前命中 4/4 个预期错误，4 个正确控制行未改。扩展词义测试：

```sh
PAPERREVIEW_USAGE_REVIEW_EVIDENCE=/tmp/PaperReview-usage.json \
swift test --filter usageReviewFindsUnseenConfusionsAndPreservesCorrectMeanings
```

扩展测试命中 4/4 个错误，12 个正确控制行未改。其他结果和耗时见[测试记录](verification/lexical-review-20261104.md)。手写样本测试另需本机 `record.json`；参考答案仅用于断言。

用独立作业目录测试界面：

```sh
./script/build_and_run.sh --verify \
  --data-root /tmp/PaperReview-QA \
  --import /absolute/path/to/photo.png
```

默认作业目录是 `~/Library/Application Support/PaperReview/Assignments/`。学生照片、作业记录、模型权重和 `.local-tests/` 不提交到 Git。仓库内的图片是[合成测试样本](fixtures/README.md)。

## 代码结构

- `Sources/PaperReviewCore/`：文本结构、UTF16 定位、模型接口、识别质量与可读性规则。
- `Sources/PaperReview/`：SwiftUI / AppKit 工作区、图像处理、作业队列与存储。
- `Sources/PaperReviewLocalModels/`：本机模型配置、设置界面、推理调用、下载与启停。

模块边界见[模型模块](architecture/model-modules.md)。应用入口注入本地模块，共享工作区不绑定本机 HTTP 客户端。
- `script/`：构建、模型下载与服务启停。
- `Tests/`：单元测试、macOS 布局测试和模型集成测试。
- `PRODUCT.md`、`DESIGN.md`：产品范围和界面规范。

## 审核流程

先对 `accept` 和后接时长的 `since` 做短句词义选择，再在内部工作副本上进行拼写、快速语法和全文检查。系统词典仅提供拼写线索。程序始终以原始转写做差分和定位；一般候选由 2B 批量返回 `apply / keep_original` 和错误类别，词义选择结果单独合并。

一般审核最多四次批量请求，两次思考请求各限 512 token。每个符合条件的词增加一次无思考、最多 128 token 的短句请求；没有目标词则不增加请求。候选、判断和分段耗时写入审核历史。中文说明使用简短类别文案。

纠错草稿与 OCR 原文分开保存。服务失败保留已有结果，连接失败不计入作业可读性判断。
