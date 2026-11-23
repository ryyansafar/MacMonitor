# Design

## Context

主程序是 macOS 13+ 的 SwiftUI + AppKit 菜单栏应用。当前所有界面文案都是英文源码字符串，项目仅声明英文区域，且部分英文同时承担显示文本和业务判断，例如温度状态字符串。SwiftUI 页面分别通过 popover、欢迎窗口和设置窗口创建，右键菜单、窗口标题、tooltip 和系统弹窗由 AppKit 管理。

实现必须满足 `specs/app-localization/spec.md` 中定义的即时切换、系统语言解析、持久化和完整覆盖要求。Widget 是独立 target，本轮不共享语言选择。

## Goals / Non-Goals

**Goals:**

- 使用 Apple 原生本地化资源维护英文和简体中文文案。
- 用一个全局语言状态控制所有主程序 SwiftUI 页面，并让 AppKit 界面读取同一解析结果。
- 让显式语言切换即时影响已打开界面，不要求重启。
- 将显示文案与温度状态等业务判断解耦。
- 保持 340 点宽 Dashboard 在中英文下都可读、无重叠。

**Non-Goals:**

- 不为 Widget 增加本地化或跨进程语言同步。
- 不增加简体中文和英文以外的界面语言。
- 不本地化芯片型号、进程名、应用名、技术缩写或计量单位。
- 不引入系统级语言切换或修改用户的 macOS 语言设置。

## Decisions

### Use a String Catalog in the main app target

新增主程序 `Localizable.xcstrings`，包含 `en` 和 `zh-Hans`，并在 Xcode 项目中声明简体中文区域。SwiftUI 静态文案继续使用可本地化的 `LocalizedStringKey` 路径；AppKit 和需要返回 `String` 的辅助代码通过统一的本地化查询读取同一资源。

选择 String Catalog 是因为项目已经启用 `SWIFT_EMIT_LOC_STRINGS` 和 `STRING_CATALOG_GENERATE_SYMBOLS`，可以复用 Xcode 的提取、校验和后续扩展能力。相比手写双语字典，它更容易发现缺失键并支持复数、插值等本地化语法；相比多个独立 `.strings` 文件，它集中维护两种语言，减少键漂移。

### Centralize language state and inject a resolved Locale

增加持久化的应用语言枚举，取值为 System、Simplified Chinese 和 English。一个全局可观察语言状态负责读取和写入 UserDefaults，并按规格解析最终语言与 Locale。每个主程序 `NSHostingController` 的根视图都通过统一的本地化容器注入该 Locale，因此 popover、设置和欢迎窗口无需各自维护语言副本。

选择单一全局状态而不是每个 View 单独使用 `@AppStorage`，是因为后者无法可靠保证所有已打开窗口同步刷新，也容易让 AppKit 与 SwiftUI 读取到不同状态。

### Separate stable state from localized presentation

温度状态改为稳定内部枚举，颜色和阈值判断只依赖枚举；UI 再按当前语言映射为“正常”“偏高”“严重”“危急”等文字。电池状态、进程指标、主题名称和菜单栏指标标题也采用“稳定值 + 本地化展示”的方式，不能本地化 raw value。

这避免切换语言后因字符串比较失效而改变状态颜色或菜单栏行为。替代方案是保留英文内部字符串并在显示时翻译，但该方案把文案和业务逻辑继续耦合，未来新增语言时风险更高。

### Refresh SwiftUI and AppKit through one language-change signal

语言状态变更后，SwiftUI 通过注入的新 Locale 重新渲染。AppDelegate 同时订阅语言变化，刷新菜单栏 tooltip 和设置窗口标题；右键菜单在每次打开时按当前语言创建，系统弹窗在展示时读取当前语言。这样无需重建 popover 或重启应用，也能覆盖 AppKit 文案。

选择观察全局状态而不是依赖应用重启，是因为规格要求即时刷新。为保证可靠性，任何保存 AppKit 字符串的长期对象都必须注册刷新，不能只在初始化时读取一次。

### Keep source data and compact technical identifiers intact

翻译仅作用于描述性界面文字。芯片型号、进程名、应用名、CPU、GPU、ANE、DRAM 以及单位保持原值。菜单栏使用紧凑技术缩写时继续保留其既有格式，但 tooltip 和菜单项使用完整本地化文案。

### Defer widget localization

Widget 使用独立进程和资源 bundle，且当前没有 App Group 共享语言偏好。本轮保持 Widget 原行为，避免为单一语言开关引入额外共享容器和迁移。未来若需要 Widget 跟随 App 语言，应单独设计共享偏好和资源打包。

## Risks / Trade-offs

- **由 `String` 参数传入的标签绕过自动本地化** → 将可翻译标签改为可本地化键或统一查询结果，并在测试中搜索残留硬编码文案。
- **AppKit 文案只在创建时读取语言，导致切换后残留旧语言** → 订阅语言变化并刷新长期存在的标题和 tooltip；上下文菜单与弹窗按需创建。
- **在 `NSHostingController` 边缘遗漏 Locale 注入** → 所有窗口统一通过同一个本地化根视图创建，并覆盖三个入口做切换验证。
- **中文文案改变 Dashboard 的 340 点布局** → 为中英文分别做界面验证，优先允许说明文字换行，避免压缩数值列或产生重叠。
- **繁体中文系统被映射为简体中文可能与部分用户预期不同** → 这是本次已确认的回退规则；未来增加繁体中文时可扩展语言枚举和资源，而无需改动业务状态。
- **新增翻译键未被 AppKit 路径使用** → 将 AppKit 查询集中到统一入口，并在任务中加入中英文两条路径的人工检查。

## Migration Plan

1. 新增语言偏好键；不存在该键时解析为 System，不迁移或覆盖现有的主题、菜单栏和登录启动设置。
2. 加入主程序 String Catalog 与 `zh-Hans` 项目区域，再逐页替换文案。
3. 在测试构建中验证默认跟随系统、三个语言选项、即时刷新和 AppKit 界面刷新。
4. 若需回滚，移除语言设置入口和本地化资源即可；既有用户偏好键可安全忽略，不影响监控数据或其他设置。
