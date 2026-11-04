# 下载暂停与分层图标

## 下载

- 设置内提供“暂停下载 / 继续下载”。暂停完成后才解锁其他模型操作，暂停时不显示旧速度和预计时间。
- 退出应用会等待下载停止并保存记录；重开显示已保存进度，点击继续后按临时文件的实际大小续传。
- 下载进程由应用持有的管道管理。管道关闭时，监督脚本只停止自己创建的下载进程组；模型服务独立运行。
- 启动恢复只读 Application Support 中的快照，不读取旧 Documents 模型目录。继续下载时才检查实际文件。

## 实测

环境：Apple Silicon、macOS 27.2。使用独立 bundle ID、作业目录及本机 HTTP 合成文件，不下载真实模型。

1. 原生设置开始下载，10,485,760 字节时暂停，文件停止增长。
2. 点击继续，服务器收到的 Range 起点与暂停时逐文件大小一致。
3. 下载中按 ⌘Q，退出时保存 40,632,320 字节；退出后文件停止增长。
4. 重新打开设置，显示 54%、40.6 MB / 74 MB 和“继续下载”。再次续传的 Range 起点与退出时逐文件大小一致。
5. 最终原生界面显示 100%。五个合成权重逐字节一致，运行时解包完成且可执行。

监督脚本测试另覆盖持有者被强制终止，确认没有活跃下载写入者，随后按原偏移续传。原断连/503/失败重试测试通过。`swift test` 共发现 129 项，118 项通过、11 项需要显式启用的诊断或真实模型测试跳过。

私有测试数据及日志在 `.local-tests/20261104-download-pause/`，不提交到仓库。

## 图标

- 使用原创 SVG 纸张与放大镜，在苹果 Icon Composer 中建立分层工程；不使用 SF Symbols 图形作为应用图标。
- 图形按视觉面积居中；镜框和手柄合成一个连续路径，没有重叠边缘。浅色、深色及透明单色使用同一套轮廓。
- 用官方 `ictool` 实际渲染并检查浅色、深色、透明单色版本。`actool` 生成的资源包含 Aqua、Dark Aqua、Tintable 三套图像栈，以及旧系统 ICNS。
- 实际 0.1.2 ZIP 解压后严格签名校验通过，原生 About 窗口显示新版图标和 0.1.2 (3)。包内下载地址仍为官方 HTTPS，未包含开发目录或测试服务地址。
- 外观由系统图标设置决定，不随应用内的深色主题选项切换。尚未改变用户的系统外观设置；Dock 自动切换未作系统级实测。

依据：[苹果 App icons 规范](https://developer.apple.com/design/human-interface-guidelines/app-icons)、[Icon Composer](https://developer.apple.com/icon-composer/)、[使用说明](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)。
