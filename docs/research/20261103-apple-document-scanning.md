# macOS 既有照片：Apple 能做透视矫正，未核实即用的书页去曲 API

核查日期：2026-11-03。只研究 Apple 公开文档、WWDC 与根代理提供的 Apple SDK/运行证据；未修改应用、读取用户照片、下载模型或操作服务。固定识别组合不变：MiniCPM-OCR F16 + Jev Q4 + MiniCPM5-2B Q4。

## 首选：Vision 找纸面四角，Core Image 矫正透视，保留框外内容

**有现成的原生组件，适合修正平面纸张拍斜；没有核实到把任意既有弯曲书页自动展平的公开 macOS 即用 API。** 最小路线是 `VNDetectDocumentSegmentationRequest → CIPerspectiveCorrection(crop=false)`，再按需要轻度 `CIDocumentEnhancer`。这只增加图像几何与增强，不替换或新增文字识别模型。

Apple 自己在 [WWDC21《Extract document data using Vision》14:02 示例](https://developer.apple.com/videos/play/wwdc2021/10041/?time=842)中演示“已有图片 → 文档检测 → Core Image 透视矫正 → 后续分析”。同一讲解明确区分：文档分割找一个文档、返回四角与分割 mask；普通矩形检测找边线/交点，可以返回多个甚至嵌套矩形。**mask 是文档区域/像素置信度，不是纸张三维表面或去曲位移场。**

## 公开 API 的平台和能力边界

系统版本取自 Apple 文档公开 Markdown 的 `availability` 元数据；Core Image 旧滤镜与新 Swift 工厂接口分开记录。

| API | 已核实最低版本 | 能做什么 / 不能代替什么 |
|---|---|---|
| `VNDetectDocumentSegmentationRequest` | **macOS 12、iOS 15** | 对输入照片定位文档，提供四角与 saliency mask；不是矫正后的图像，也不是曲面展平 |
| Swift `DetectDocumentSegmentationRequest` | **macOS 15、iOS 18** | 同类几何请求，返回 `DetectedDocumentObservation`；支持对 URL/Data/CGImage/CIImage 等既有图片执行。换成 Swift 新名字不会新增去曲能力 |
| `VNDetectRectanglesRequest` | **macOS 10.13、iOS 11** | 寻找投影矩形，提供角点、置信度及长宽比/尺寸等约束；可作检测后备，但本身不做矫正 |
| `CIPerspectiveCorrection` | 旧字符串滤镜：**OS X 10.10 / iOS 8**；`CIFilter.perspectiveCorrection()`：**macOS 10.15 / iOS 13** | 四边形映射为矩形的**平面透视变换**；不能拉直书脊附近弯曲字行或恢复遮挡笔画 |
| `CIDocumentEnhancer` / `CIFilter.documentEnhancer()` | Swift 工厂：**macOS 10.15 / iOS 13** | 减弱阴影、提白背景、增强对比度；没有几何控制点，不负责去曲。强度需防止淡铅笔/细笔画受损 |
| `VNDocumentCameraViewController` | **iOS 13、Mac Catalyst 13.1** 等；**没有原生 macOS 可用性** | UIKit 的相机扫描界面，逐页拍摄后交付页图；不能直接作为 AppKit 控件，也不是“给一个已有 CIImage 自动扫描”的公开处理接口 |
| `RecognizeDocumentsRequest`（不建议本轮接入） | **macOS 26、iOS 26** | 提供词/行/段落、表格/列表等结构；公开结果是文档观察信息，不是去曲图像或形变网格。无需为本次几何任务引入它的文字结果 |

以上按六组一手依据核查，避免把不同框架的“扫描”混成同一能力：

1. **Vision 几何/结构 API 文档**：[旧文档分割](https://developer.apple.com/documentation/vision/vndetectdocumentsegmentationrequest)、[Swift 文档分割](https://developer.apple.com/documentation/vision/detectdocumentsegmentationrequest)、[矩形检测](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest)、[结构识别](https://developer.apple.com/documentation/vision/recognizedocumentsrequest)。
2. **WWDC21 官方实作与比较**：[Extract document data using Vision](https://developer.apple.com/videos/play/wwdc2021/10041/)。
3. **Core Image 透视滤镜**：[Swift 工厂与四角含义](https://developer.apple.com/documentation/coreimage/cifilter-swift.class/perspectivecorrection())、[旧滤镜参考与系统版本](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html#//apple_ref/doc/filter/ci/CIPerspectiveCorrection)，以及下述 Apple SDK 对 `crop` 的说明。
4. **文档增强滤镜**：[documentEnhancer()](https://developer.apple.com/documentation/coreimage/cifilter-swift.class/documentenhancer())。
5. **VisionKit 扫描控制器**：[VNDocumentCameraViewController](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller)。
6. **AppKit 的手机扫描导入**：[Supporting Continuity Camera in Your Mac App](https://developer.apple.com/documentation/appkit/supporting-continuity-camera-in-your-mac-app)。

## `crop=false` 的精确意义：不因检测四角而切掉框外字迹

根代理直接核实 Apple SDK 文件：

`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.2.sdk/System/Library/Frameworks/CoreImage.framework/Headers/CIFilterBuiltins.h:319–325`

其中 `CIPerspectiveCorrection.crop` 是 `bool`：**true 将输出裁到四角映射形成的矩形；false 保留四控制点以外的像素于输出中。** 根代理另用框外红色像素做了本机对照，确认 false 保留框外内容；本报告未重复执行该测试。

因此宜显式设 `crop=false`，并用滤镜的实际有效输出 extent 渲染；如果后面又裁成检测矩形，仍会丢掉原本保留的内容。它保留的是经过同一透视变换的框外像素，不代表像素坐标/尺寸保持原样，也不保证任意错误四角都能产生可用图像。当前 Apple `crop` 网页把 Bool 误写成 rectangle，不能沿用那一句说明。

## 对现有 App 的最低改动建议

1. **只改导入后的图像预处理入口。** 保留原照片；统一 EXIF 方向后检测文档。沿用既有 `VN…` 管线时先选 macOS 12 起的旧类，不为切换新 Swift API 提高最低系统或重写全管线。
2. **对每一页分别矫正，不把弯曲双页当一个平面。** 沿用既有分页/页面区域；有效四角才做透视矫正。检测失败或形状不可用时继续使用未裁切的输入，不添加老师默认人工核对关卡。矩形检测可作后备，但不能仅因“最大矩形”就删除页边文字。
3. **原图、矫正图与坐标版本分开保留。** 原图不覆盖；OCR/Jev 同一候选使用同一份图像坐标体系。新识别必须在矫正图上重新运行 OCR/Jev，不能用旧图分数通过新图的质量门。历史记录若只升级扫描显示，可以冻结已有转写、重新定位行/词并保存旧图恢复副本；旧分数必须带原扫描版本，保持历史分数含义，不能宣称是新图的重新验证。当前 App 采用这一区分，显示升级不会自动改写学生文字。
4. **阴影增强独立于几何。** `CIDocumentEnhancer` 作为可比较的轻度增强分支；不把“更白”当成“识别更忠实”。继续保留灰度/彩色细笔画，不用强二值化替代透视矫正。
5. **可选增加“从 iPhone 扫描导入”，不阻断照片导入。** AppKit Continuity Camera 从 **macOS 10.14 + iOS 12** 起支持手机扫描/拍照结果进入 Mac：菜单标识 `NSMenuItem.importFromDeviceIdentifier`，响应链实现 `validRequestor(forSendType:returnType:)`，由 `readSelection(from:)` 接收 pasteboard 内容并交给原导入流程。它是在手机端重新扫描、导入成品，不会替 Mac 自动去曲现有照片；也不要与 macOS 13 起“把 iPhone 当网络摄像头”的 AVFoundation Continuity Camera 混淆。[AppKit 官方接入说明](https://developer.apple.com/documentation/appkit/supporting-continuity-camera-in-your-mac-app)

## 曲面去曲的结论与验收边界

本轮核实的公开 Vision、Core Image、VisionKit 文档与 WWDC 示例，没有给出原生 macOS 上 **“既有弯曲书页照片 → 自动非线性展平图像”** 的即用处理 API。纸张轮廓检测、四角透视矫正、阴影增强和识别结构均不能据此承诺该能力；iOS 文件/备忘录扫描的产品效果也不能推导成向第三方 AppKit 公开的同等接口。不使用私有 `VisionKitCore` 作为交付路线。

**可以立即实施的首选是公开几何管线，产品名称应叫“透视矫正/文档增强”，不是“书页去曲”。** 根代理负责后续本机 SDK/现有代码检查及实际图像验收：框外笔画保留、倾斜平面变正、原图可回看、OCR/Jev/高亮同坐标。书脊弯曲字行仍须另有可验证的非线性方法；本轮不改变固定识别模型，也不宣称该缺口已经解决。
