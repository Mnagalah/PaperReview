# 0.1.5（6）安装包与日常版同步 · 2026-11-06

## 范围

用户已接受识别风险建议与排队反馈，要求 GitHub 安装包与日常版一致。功能代码沿用 `f4c930e327b26a5d06aed12c4096badfe9804f27`，本次仅统一版本元数据为 0.1.5（6），更新包内使用说明和发布记录。README 与用户审阅附件逐字节一致，未再改写。

## 构建与安装包

- `./script/package_release.sh` 成功。产物：`dist/release/PaperReview-0.1.5-macOS-arm64.zip`，3,239,258 字节。
- ZIP 只含应用、使用说明与 macOS 归档元数据，不含学生作业、模型、源码或测试记录。
- 解压后验证 `CFBundleShortVersionString = 0.1.5`、`CFBundleVersion = 6`、架构 `arm64`、最低目标 `14.0`；发行包没有 `PaperReviewProjectRoot`。
- 解压应用通过 `codesign --verify --deep --strict`。在独立空作业、空模型目录冷启动，实际原生窗口显示三栏空状态、导入入口与本地服务未就绪；未触发下载或推理。
- Release 构建保留已有 Core Image 弃用警告及 SDK 调试模块路径警告；编译、链接、打包、签名和冷启动均成功。

## 日常版恢复

- 更新前四份作业均完成分析，无活动或排队任务；正常退出后执行 `./script/build_and_run.sh --verify`，构建、签名及启动检查通过。
- `dist/PaperReview.app` 仍指向 `~/Library/Developer/PaperReview/Build/PaperReview.app`，元数据同为 0.1.5（6）。旧包保留在 `Build/Previous/`。
- 更新后实际窗口恢复四份作业，问题数依次为 14、6、0、11；当前作业的识别风险标签直接显示。没有重新审核或更改正式作业。
- 更新前后本地服务均为未就绪，本次未自动启动或停止模型服务。

## 功能证据与边界

[已接受版本的功能测试和窗口验证](inline-review-feedback-20261106.md)继续适用：172 个测试函数中 156 个通过、16 个按开关跳过；本次没有修改功能代码，不重复运行相同测试。

本机验证环境为 Apple Silicon、macOS 27.2。应用使用开发签名，尚未公证；另一台 Mac 与最低目标系统未验证。发布说明保留首次打开的系统批准提示。旧 v0.1.4 标签与历史安装包不改写。

## GitHub 发布

- 发布提交和标签：`84968fc1db7ef739be40bda98feb48238bf79a89`、`v0.1.5`；作者、提交者、标签署名均为 `Mnagalah` 与既有 GitHub noreply 地址。
- 源码和文档内容通过 GitHub 插件上传；插件没有发行附件上传接口，因此用官方 `gh` 上传 ZIP，不使用浏览器。
- 先建草稿并核对附件为 `uploaded`、3,239,258 字节，再正式发布并设为 Latest。GitHub 插件回读 `/releases/latest` 返回 `v0.1.5`，非草稿、非预发行；发行 ID `436580489`，附件 ID `717388219`。
- 发布时间：2026-11-06 22:14:37（Asia/Shanghai）。[发行页](https://github.com/Mnagalah/PaperReview/releases/tag/v0.1.5) · [最新下载入口](https://github.com/Mnagalah/PaperReview/releases/latest)。
- 从 GitHub 重新下载已发布 ZIP，与本地产物逐字节相同；下载文件解压后的版本为 0.1.5（6），严格签名校验通过。
- 远端 README 与用户审阅附件逐字节一致，其中“下载发行版”链接使用 `releases/latest`，现已指向 0.1.5；旧 v0.1.4 仍是历史版本。
- 仓库保持原有 Private 权限；只有获准访问仓库的人可下载安装包。
