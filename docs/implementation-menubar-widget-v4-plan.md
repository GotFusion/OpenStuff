# OpenStaff 菜单栏 + 前台部件（v4）代码编写计划

版本：v0.1  
日期：2026-03-09  
对应设计：`docs/ui-design/target-ui-v4-refined-minimal/*`

## 1. 目标与范围

本计划用于把已确认的 v4 设计稿落地为可运行代码，重点实现：

1. 菜单栏采用 macOS 原生透明风格（系统感，不做重视觉包装）。
2. 前台部件精简模式改为“透明方框”并低打扰展示。
3. 详细模式时间轴采用无背景嵌入桌面效果。
4. 时间轴节点颜色调整为“透明带色调”，降低视觉抢占。
5. 统一字体层级、节点间距、文字截断规则并固化为常量。

## 2. 当前基线

当前代码已具备：

- `MenuBarExtra` 场景与菜单入口。
- 前台部件窗口（`Window` + floating 配置）。
- 精简/详细模式切换与时间轴数据组织。

当前文件：

- `apps/macos/Sources/OpenStaffApp/OpenStaffApp.swift`
- `apps/macos/Sources/OpenStaffApp/OpenStaffDesktopWidget.swift`

当前与 v4 的主要差异：

1. 精简模式仍偏“球体风格”，需替换为透明方框。
2. 详细模式时间轴仍有部分高饱和节点色，需透明化调色。
3. 字体/间距/截断规则未系统抽为常量与统一策略。

## 3. 设计到代码映射

设计来源：

- `docs/ui-design/target-ui-v4-refined-minimal/01-menubar-native-refined.svg`
- `docs/ui-design/target-ui-v4-refined-minimal/02-widget-compact-box-minimal.svg`
- `docs/ui-design/target-ui-v4-refined-minimal/03-timeline-embedded-refined.svg`
- `docs/ui-design/target-ui-v4-refined-minimal/04-typography-spacing-truncation-spec.md`

建议新增 UI token 结构（在 `OpenStaffDesktopWidget.swift` 或拆分文件）：

- `DesktopWidgetTypography`
- `DesktopWidgetSpacing`
- `DesktopWidgetColorPalette`
- `DesktopWidgetTruncationRule`

## 4. 分阶段任务（可直接执行）

## Phase A：基础样式收敛（1 天）

### A1. 字体层级常量化
- 将标题、一级任务、二级任务、时间信息字体从散点写法改为统一 token。
- 验收：切换模式后字体权重与尺寸一致，不出现局部漂移。

### A2. 间距常量化
- 提取一级节点、二级节点、组间距、轨道偏移为统一常量。
- 验收：时间轴各任务组间距稳定，新增数据不破版。

### A3. 截断规则统一
- 将 `truncate` 改为按场景策略（精简主行/次行、一级标题、二级说明）。
- 验收：超长 task/message 全部按规则省略，不撑开布局。

### Phase A 完成记录（2026-03-09）
- 已在 `OpenStaffDesktopWidget.swift` 提取 `DesktopWidgetTypography`、`DesktopWidgetSpacing`、`DesktopWidgetColorPalette`、`DesktopWidgetTruncationRule`。
- 精简模式当前任务与下一步任务采用不同截断长度（22/26）。
- 详细时间轴一级/二级标题与说明采用统一截断策略（44/42/52）并统一单行省略。
- 一级节点、二级节点、组间距与轨道偏移改为统一常量来源，去除散点硬编码。

## Phase B：精简模式改造（0.5 天）

### B1. 球体改透明方框
- 将 compact 视图主体从 `Circle + capsule` 改为低透明圆角矩形。
- 保留整块点击热区，点击切换详细模式。
- 验收：桌面干扰显著降低，信息可读性不下降。

### B2. 信息减噪
- 精简模式仅保留：当前任务、下一步任务、轻提示文案。
- 验收：在 1 米外可快速识别当前任务。

### Phase B 完成记录（2026-03-09）
- 已将 compact 主体从球体+胶囊改为低透明圆角方框（`fill 18% / stroke 38%`），并保留轻阴影。
- 已移除高饱和渐变球体与强调图标，精简模式仅展示“当前任务 / 下一步 / 点击展开(或收起)”三类信息。
- 精简模式整块区域保持 `Button` 点击热区，点击任意位置均可切换详细/精简。
- 前台部件初始窗口尺寸同步调整为方框版默认尺寸（`392 x 178`）。

## Phase C：详细时间轴调色与嵌入（1 天）

### C1. 透明节点色调
- 一级节点：fill 42%~46%，stroke 58%~62%。
- 二级节点：fill 30%~34%，stroke 45%~48%。
- 验收：节点可区分但不抢主体文字注意力。

### C2. 无背景嵌入确认
- 详细模式不使用重底板，仅保留轨道、节点、文字层。
- 验收：壁纸透出明显，文字仍可读。

### C3. 紧急停止状态视觉
- 保留细红色状态线提示，不扩大警示块。
- 验收：可感知安全状态变化但不过度干扰。

## Phase D：菜单栏原生化细节（0.5 天）

### D1. 菜单项层级优化
- 使用系统默认样式，减少自定义背景。
- 危险项仅文字色强调。
- 验收：与系统菜单视觉一致。

### D2. 模式切换联动
- 菜单栏切换模式时，如部件隐藏则自动显示。
- 验收：用户切换后可立即看到结果。

## Phase E：验证与回归（1 天）

### E1. 交互回归清单
- 菜单栏打开控制台。
- 显示/隐藏部件。
- 精简/详细双向切换（菜单栏 + 点击方框）。
- 紧急停止状态显示。

### E2. 数据回归清单
- 无日志数据时空态展示。
- 长 taskId / 长 message 截断。
- 多任务（>20）滚动与性能。

### E3. 构建与手测
- `swift build --package-path apps/macos --product OpenStaffApp`
- 验收：构建通过；交互全链路无崩溃。

## 5. 文件级改动计划

必改：

1. `apps/macos/Sources/OpenStaffApp/OpenStaffDesktopWidget.swift`
2. `apps/macos/Sources/OpenStaffApp/OpenStaffApp.swift`（仅菜单栏细节和窗口联动，少量）

可选拆分（建议）：

1. `apps/macos/Sources/OpenStaffApp/DesktopWidgetTheme.swift`
2. `apps/macos/Sources/OpenStaffApp/DesktopWidgetLayoutSpec.swift`

文档同步：

1. `docs/project-plan-and-progress.md`（补充本轮 UI 收敛进展）
2. `docs/user-manual.md`（补充菜单栏/前台部件使用说明）

## 6. 验收标准（DoD）

全部满足才算完成：

1. 精简模式为透明方框，球体样式已移除。
2. 详细时间轴无重背景，节点为透明色调。
3. 字体层级、间距、截断规则有统一常量来源。
4. 菜单栏保持原生观感，条目功能全部可用。
5. 构建通过且关键交互回归通过。

## 7. 风险与应对

1. 桌面壁纸复杂导致文字可读性波动。
- 应对：提高文字阴影与字重，不加重底板。

2. 截断规则过于激进影响信息密度。
- 应对：保留“模式 + taskId + 状态码”优先级。

3. 高 DPI 下间距/字号观感偏差。
- 应对：抽象为 token 后统一调参，避免散点修改。

## 8. 建议执行顺序（最小返工）

1. 先做 token（字体/间距/截断）。
2. 再做精简方框。
3. 再做详细时间轴节点透明化。
4. 最后做菜单栏细节与联动。
5. 收尾做回归与文档同步。
