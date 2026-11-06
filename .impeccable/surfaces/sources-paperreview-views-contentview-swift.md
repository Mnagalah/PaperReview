---
version: 1
slug: "sources-paperreview-views-contentview-swift"
primary_target: "Sources/PaperReview/Views/ContentView.swift"
related_targets: ["Sources/PaperReview/Views/ComparisonView.swift","Sources/PaperReview/Views/ReviewInspector.swift","Sources/PaperReview/Views/ModelSettingsView.swift"]
---

# 批阅工作区 1.2

Mode: Operate。对象是连续处理英语纸质作文的教师。窗口结构与材质采用用户指定的 Device Hub；Apple 原生规范与 Codex 完成度目标继续适用，HTML 保留为内容组织依据。保留本机模型和全部既有能力，用户已确认同时实现可持久化的新增批阅交互。

## Direction contract

THESIS: 原稿是证据，识别稿承载阅读，右侧建议支持教师判断；机器完成不再冒充教师完成。

OWN-WORLD: 中性近黑工作面、原生材质侧栏、低对比列表；蓝色仅用于主操作和当前字词焦点。系统字体，18pt 自然正文，13–14pt 控件，8/12/16/24pt 间距。

STORY: 导入后自动完成模型流程；教师可逐条确认或放弃建议、撤销和确认完成，所有操作保存但不覆写学生文字。

FIRST VIEWPORT: 左侧 216pt 来源列表、搜索和三类筛选；中央平整文稿，顶部原生玻璃视图工具，默认左右对照，另有上下、叠图和普通阅读；右侧 328pt 建议列表，仅当前建议展开上下文及处理按钮。顶部右侧完成批阅，底部阶段条、分析状态和缩放同排且右对齐；无保存状态底栏。

FORM: 以 Device Hub 约束原生窗口结构、工具栏分组及液态玻璃；Apple 指引约束交互，HTML 1.2 提供内容组织参考，使用原生 SwiftUI/AppKit 适配，不另创方向。网页外观与原生行为冲突时保留原生行为。seed: none (user-specified reference)。签名交互为文字、照片与建议定位联动，150ms 以内且尊重减少动态效果。

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## 本轮原生适配目标与验收

本轮直接采用 Device Hub 的原生三栏与工具栏层级，移除内嵌圆角外壳；文稿和建议正文保持平整，玻璃用于系统导航和操作。设计依据见 Apple 的 [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)、[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) 与 [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)。

以下约束继续用于候选验收。2026-11-06 已补原生分栏、800×600pt 内容最小尺寸、控件换排和校对 sheet 适配；实际宽窄窗口未再出现双标题。程序驱动连续尺寸测试、实际窗口操作及剩余验收见 `docs/verification/responsive-workspace-20261106.md`。

1. 保留系统交通灯、窗口拖动、键盘快捷键与菜单行为；顶部按钮可独立操作，不与拖动区域争夺点击。
2. 顶部与中央／右侧连续工作面在材质和空间关系上融合，避免出现另加一层网页导航栏的割裂感。
3. 文档标题位于工作面所属区域，不跨越侧栏与工作面的接缝；长文件名在可用区域内处理，不挤占窗口控制或主操作。
4. “完成批阅”主操作固定在右上；完成后的“下一份”沿用这一位置，不随标题长度或侧栏显隐漂移。
5. 作业列表图标对齐文件名首行，状态另起一行；多行内容不以整行垂直居中造成图标上下跳动。
6. 已发现问题／已确认项控件有完整可见、可点击并可键盘操作的高度；文字、选中态与焦点轮廓不被垂直裁切。
7. 重复打包更新延续既有文稿访问授权，不因更新反复索要相同授权；共享打包脚本已检查本轮更新的证书和 designated requirement 连续性；正式文稿权限数据库的实际复用未在隔离界面验证中重测。首次访问新位置仍按系统授权处理。

完成条件：修复后的真实原生窗口同时满足上述关系和交互，保留已实现的批注、保存与本机模型流程，再更新最终审查结论。Apple 指引用作设计和检查依据，不表述为苹果全项认证或已通过全部规范。

当前布局以用户后续明确要求为准：移除两侧手动收合按钮及相应命令；宽窗保持三栏，窄窗将来源列表改为作业选择 popover，建议栏常驻。右侧背景与分隔线贯通工作面顶部到底部，导出与完成批阅归属其顶部。使用真实 sidebar/content/inspector 分栏和跟随分隔工具项；标题及视图工具移至系统工具栏，保留 `WorkspaceGrid` 的 64pt 信息区和 20pt 内边距；44pt 底部区域仅供来源栏服务与设置入口，中央与检查器的状态底栏及分隔结构已移除。原稿提示占菜单下固定第二行，菜单只保留系统下拉箭头。

来源栏响应式切换使用 220ms、无回弹的原生分栏过渡；初始阈值 1180pt，连续调窗缩至低于 1156pt 收起、扩至 1204pt 展开，避免临界位置抖动。紧凑视图工具保持原生菜单；减少动态效果路径直接定位，不延迟普通拖窗和阅读操作。1015×998pt 实际窄窗已检查，并通过系统缩放往返宽窗；原生窗口测试验证中间帧和快速反向的最终状态。

完成批阅仍可用 ⌘Return；鼠标连续拖边／分隔条手感和系统辅助功能切换继续作为实机验收项。最新证据见 `docs/verification/device-hub-workspace-20261106.md`。
