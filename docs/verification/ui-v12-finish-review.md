disposition: fix

角色替代：由独立通用代理按所给 finish-reviewer 合同完成本轮只读审查；未提供独立 QUALITY BAR 卡或静态批准合成图，以用户固定的两份 HTML、原生 macOS 指引和方向合同为准。未重新运行测试、操作应用或改动实现；未通读未改动的模型推理代码。

## persistence

**fail — 两处教师记录恢复路径未满足承诺，设计文档尚待本轮收尾更新。**

- `/Users/melchior/Documents/ChatGPT/OpenBMB/PRODUCT.md` 与已提交方向合同存在。此轮为用户指定 HTML 的原生适配，不是代理另创方向的合成图复刻；不要求另行随机选题、资产制作或图像差分流水线。
- 七张指定截图均存在、可读，内容与命名一致。真实应用截图为 1480×920pt 主窗口及设置；四张当前源码截图为 2× Retina 的 1440×900、1280×800、1024×768pt 合成夹具。窄窗标题栏缺失是已说明的夹具边界，不是截图损坏。实际上下对照照片的底部裁切属于可滚动视口，不是空白捕获。
- 教师批注、保留原文、评语、完成时间与机器建议分层存储；原稿和转写没有被接受建议动作替换。保存失败保留内存修改、显示重试并阻止完成与退出，正常记录可重开。旧忽略项的撤回与失效记录的恢复仍有下述具体缺口。
- 已有日志 `/Users/melchior/Documents/ChatGPT/OpenBMB/.local-tests/20261105-ui-v12/tests-final.log` 记录 142 项测试、11 项 opt-in 跳过；它早于最后的响应式与导出兼容小改。`/Users/melchior/Documents/ChatGPT/OpenBMB/.local-tests/20261105-ui-v12/layout-final.log` 记录当前快照、词焦点和重开记录三项通过。此次不把既有通过扩张为最终全量验收，也不把合成夹具当作真实 OCR 质量证据。
- `/Users/melchior/Documents/ChatGPT/OpenBMB/DESIGN.md` 仍写旧的灰色主操作、旧三栏尺寸、旧忽略流程与旧完成语义；父任务已安排收尾更新，但当前交付包尚未一致。
- VoiceOver 实际朗读顺序、系统减少动态效果和降低透明度的实机切换尚无本轮操作证据；这是相关可访问性验收范围的证据缺口，不是从截图推断出的功能失败。真实模型未重跑，本轮不判定识别或语言审核质量。

## fidelity

| 显著元素／承诺 | 判断 | 依据与后果 |
| --- | --- | --- |
| TYPE：系统正文与控件层级 | match | 原生系统字体、18pt 普通阅读、16pt 建议词与较小元信息符合固定 HTML 和方向合同。没有把网页的陈列字体禁令套到原生桌面控件。 |
| MATERIAL：侧栏和文稿材质 | match | 实际应用保留原生侧栏／标题栏材质，文稿为稳定平面；照片保留原纸面，未用装饰性玻璃、假物理阴影或生成插图取代证据。 |
| GROUND：中性近黑工作面 | match | 实际深色截图与 `/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Models/WorkspaceAppearance.swift:20–29` 的 #18191b 工作面、#202226 面板及局部中性选中层一致，没有漂成蓝黑科技外壳；浅色另行校准。 |
| 来源栏、主工作面、右侧检查器拓扑 | match | 216pt 来源栏、共享标题栏、圆角连续工作面、右侧待处理／已处理列表均在指定截图可见；导入、搜索与三类作业筛选位置明确。 |
| 紧凑建议与完整句子上下文 | match | 只有当前建议展开上下文、原因和两个教师动作，其余按短行排列；当前词蓝色与句子上下文对应。 |
| 原生设置 | adaptation | 四组保留为独立 macOS 设置窗口／TabView，而非复制网页弹层；依据原生指引及 HTML“设置通过 App 菜单／⌘,”要求。服务操作明确标为“全部”，并列出三个比赛模型，没有暗示逐模型操作。 |
| 窄窗阅读与物理行对照 | adaptation | 1024pt 视口收起来源栏、保留阅读和检查器；1280pt 对照中的长物理行由共享水平画布承载，不额外软换行。这是 PRODUCT 和父任务明确的原生数据／布局约束，不是丢失正文。普通阅读使用宽度跟踪的 NSTextView。 |
| 教师完成与机器完成分离 | match | 主标题栏显示教师状态和完成动作；底部处理详情另记“分析完成”。完成后保留当前作业，保存评语会重新进入批阅中。 |
| 旧忽略记录迁移后可撤回 | contradicted | `/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Models/Assignment.swift:33–37` 在每次读取旧记录时重新生成 TeacherDecision UUID；`/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Stores/WorkspaceReview.swift:19–20` 再次读取并按旧 UUID 删除，故 UI 的“恢复为待处理”删不中迁移决定。旧测试只调用按语义匹配的纯模型 restore，未覆盖这条实际调用链。 |
| 失效位置历史的恢复动作 | contradicted | `/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Views/ReviewInspector.swift:125–141` 对“位置待确认”的旧决定仍提供“恢复为待处理”；`/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Stores/WorkspaceReview.swift:19–22` 在找不到当前匹配建议时也移除记录。校对后旧 revision 不会匹配当前建议，因此动作会使教师历史消失，却不产生任何待处理项。 |
| 原有操作与阶段反馈 | match | 采样源码保留导入／重复提醒／废纸篓确认、原色／增强、复制／校对／导出、阶段详情／重试／Jev、左右／上下／滑动及共享缩放；父任务已有撤销／重做和滑杆键盘操作记录。此判断限于本轮界面与调用路径，不冒充模型端重新验证。 |

## ceiling

固定 HTML 的原生桌面方向已经落到来源列表、连续工作面、句子阅读和单项判断上；不需要增加插图、装饰、卡片或转场来提高“完成度”。未使用但可选的细节只有 `/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Views/ComparisonView.swift:117–123` 阅读／批注预览页签的当前态：目前主要依靠字重，独立低强度选中态会更清楚。这是可选打磨，不构成下列修复的前置任务。独立 QUALITY BAR 卡未提供，未据此虚构更高视觉规格。

## material_fixes

1. **旧记录恢复／原始迁移要求：**修复 `/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Models/Assignment.swift:33–37` 与 `/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Stores/WorkspaceReview.swift:17–22` 的身份不稳定问题；迁移一次并保留稳定身份，或使用 TeacherDecision.matches 的语义身份恢复。新增“解码旧 dismissed 记录 → 通过 WorkspaceStore.restoreSuggestion 恢复 → 待处理数增加并重开保持”的实际路径测试，不能只测 TeacherReview.restore。
2. **失效位置保留／动作真实含义：**修复 `/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Views/ReviewInspector.swift:125–141` 和 `/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Stores/WorkspaceReview.swift:17–22`：只有能定位到当前匹配建议时才允许“恢复为待处理”；否则保留带“位置待确认”的教师历史并给出明确不可恢复状态，不得在零新增待处理项时静默删除旧批注。覆盖 transcript revision 已变及同 revision 重审后建议已消失两种来源。
3. **交付文档一致性：**收尾文档负责人更新 `/Users/melchior/Documents/ChatGPT/OpenBMB/DESIGN.md:1–75`，同步新的蓝色主操作／焦点规则、1000pt 窗口下限与1180pt侧栏折叠阈值、普通阅读、教师决定／完成／保存失败语义；记录七张截图各自真实应用或合成夹具的证据属性及未完成的可访问性验证。

## keep

修复时保留学生原文不变、原图／转写／机器建议／教师决定分层、当前建议单项展开、完成由教师明确确认、物理行共同画布及原生浅深色材质，不为修复恢复逻辑而重做视觉方向或改动模型链路。

---

## verdict

2026-11-06，限定 Verdict Pass。角色替代仍为独立通用代理按所给 finish-reviewer 合同评分；本轮仅裁定上述三条 material fixes，不重新搜索全屏缺陷，不操作应用、不运行测试。以下评分更新前述三项修复状态。

1. **resolved — 旧记录恢复。** `/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Models/Assignment.swift:33–41` 让旧忽略决定沿用原建议 ID；`/Users/melchior/Documents/ChatGPT/OpenBMB/Sources/PaperReview/Stores/WorkspaceReview.swift:17–23` 改用语义身份恢复。`/Users/melchior/Documents/ChatGPT/OpenBMB/Tests/PaperReviewMacTests/TeacherWorkflowTests.swift:133–151` 覆盖从磁盘解码、显示决定、Store 恢复、保存再重开的完整路径，最终日志记录通过，待处理数与决定列表得到恢复。
2. **resolved — 失效历史保留。** Store 同时要求决定仍锚定当前转写且存在当前匹配建议；检查器仅在这两个条件成立时显示恢复按钮。`/Users/melchior/Documents/ChatGPT/OpenBMB/Tests/PaperReviewMacTests/TeacherWorkflowTests.swift:154–168` 覆盖新 revision 与同 revision 重审后建议消失两种条件，日志均通过。真实应用截图 `/Users/melchior/Documents/ChatGPT/OpenBMB/.impeccable/review/actual-macos-stale-history-fixed.png` 可见“已添加批注／位置待确认／历史记录”，原决定、建议和说明保留，没有“恢复为待处理”按钮。
3. **resolved — 交付文档一致性。** `/Users/melchior/Documents/ChatGPT/OpenBMB/DESIGN.md` 已同步蓝色主操作／焦点、1000×680pt 最小窗口、1180pt 侧栏阈值、普通阅读、教师决定与保存／完成语义；`/Users/melchior/Documents/ChatGPT/OpenBMB/PRODUCT.md` 同步当前视图和阶段／Jev 入口；`/Users/melchior/Documents/ChatGPT/OpenBMB/.impeccable/design.json` 对应当前原生布局、颜色与证据范围。文档明确区分三张原始真实应用截图与四张离屏合成夹具，并列出尚未实际验证的可访问性项目；新历史状态截图及最终测试见 `/Users/melchior/Documents/ChatGPT/OpenBMB/docs/verification/ui-v12-update-20261106.md`。

复核证据：重新打开全部七张原指定截图及新增历史截图，捕获均有效；四张同路径 native 截图已更新，未见本次恢复逻辑／文档修复引入的布局回归。`/Users/melchior/Documents/ChatGPT/OpenBMB/.local-tests/20261105-ui-v12/review-fixes.log` 记录相关针对性测试通过；`/Users/melchior/Documents/ChatGPT/OpenBMB/.local-tests/20261105-ui-v12/tests-delivery-final.log` 记录最终 148 项测试、11 项既有条件跳过，其余通过。行为评分依据实际调用路径源码、已有运行日志和父任务提供的真实应用截图；合成截图只用于布局，不能扩张为 OCR 或模型质量证据。

## remaining

三项已评分修复：**clear**。未发现这批修复引入的新增回归。

整屏最终视觉验收仍开放：用户随后指出原生标题栏与下方内容的分隔过强，未达到固定参考稿的沉浸融合；此新增视觉反馈由主代理继续实施，完成后以新证据进行新的视觉审阅，不由本次限定评分覆盖。VoiceOver 实际朗读、系统减少动态效果与降低透明度的实机切换仍沿用已记录的证据边界。

本次 ship 仅覆盖以上三项已评分修复，不代表整屏最终验收。

disposition: ship
