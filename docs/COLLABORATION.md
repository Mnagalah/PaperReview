# 本机协作基线

协作仓库：[Mnagalah/PaperReview](https://github.com/Mnagalah/PaperReview)，2026-11-04已核实为Private。源码与可重跑测试进入Git；模型权重、学生作业、私有截图和运行日志保留在本机。下列命令是协作者取得源码后的入口，当前已知质量限制见后文。

## 构建与运行

需要Apple Silicon、Xcode / Swift 6.2+；包的最低目标为macOS 14。实际开发验证机为macOS 27.2、24 GiB，最低系统与其他内存配置尚未做设备验收。

```sh
swift test
bash Tests/ModelScriptsTests/startup_tests.sh
./script/build_and_run.sh --build-only
```

启动前单独下载模型，并确认磁盘空间及官方许可：

```sh
./script/setup_models.sh
./script/start_models.sh
./script/build_and_run.sh
```

固定模型是 **MiniCPM-OCR F16、Jev Q4_K_M、MiniCPM5-2B Q4_K_M**；不得为了解决准确率问题擅自换型号。当前五个权重/投影文件约5.924 GB，运行时另计。模型与运行时在被忽略的`.local-models/`，不提交到Git；新协作者需自行下载。下载脚本使用官方发布源，可续传。

构建入口是`dist/PaperReview.app`，链接到`~/Library/Developer/PaperReview/Build/PaperReview.app`。构建脚本保留旧构建并校验项目归属。它只提供本机ad-hoc签名，未做Developer ID发行、公证或安装包。

## 不用学生数据做默认测试

普通`swift test`使用合成数据，不要求模型服务，不读取学生作业。真实模型用例是显式开启的集成测试，不能把默认跳过算成通过。

```sh
PAPERREVIEW_REAL_MODELS=1 \
PAPERREVIEW_SEMANTIC_EVIDENCE=/tmp/PaperReview-semantic.json \
swift test --filter semanticReviewUnderstandsContext
```

私有手写样本测试还需要本机保存的record.json，不随Git提供。它的参考答案仅用于测试断言，不进入模型请求。当前模型准确率、耗时和未通过项以`verification/workspace-review-20261104.md`为准；运行成功或定位成功不代表语义正确。

在隔离目录做完整UI测试，不导入日常作业库：

```sh
./script/build_and_run.sh --verify \
  --data-root /tmp/PaperReview-collaboration-QA \
  --import /absolute/path/to/a-consented-test-image.png
```

默认日常作业位于`~/Library/Application Support/PaperReview/Assignments/`，包含照片、文字和审核历史，不上传到协作仓库。`.local-tests/`同样是私有证据，不上传。合成图片的来源与范围在`fixtures/README.md`；照片上传需另行确认来源、许可和去标识化。

## 修改边界

- `Sources/PaperReviewCore/`：文本结构、精确UTF16定位、模型协议、质量门与可读性规则。
- `Sources/PaperReview/`：原生UI、图像预处理、作业持久化和本机进程管理。
- `script/`：构建、固定模型下载与服务启停；只操作路径和端口均匹配的本项目进程，不增加登录自启。
- `Tests/`：保真、结构、布局、数据恢复、服务失败和显式模型集成测试。
- `PRODUCT.md`、`DESIGN.md`：用户已确认的功能与界面约束；`docs/implementation-status.md`保留历史失败和最新状态。

不要把纠错草稿写回OCR原文；不要为了让测试通过降低既有预期；不要把模型连接失败归为作业可读性较差。合作前确认仓库为Private，按角色邀请协作者，再推送不含权重、作业或原始私有日志的源码。
