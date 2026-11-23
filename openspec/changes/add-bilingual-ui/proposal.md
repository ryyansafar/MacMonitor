# Proposal

## Why

MacMonitor 的主程序界面目前只有英文硬编码文案，中文用户无法选择或切换语言。随着界面覆盖 Dashboard、设置、首次启动、菜单栏和系统弹窗，需要建立一致的双语体验，避免只汉化局部页面后出现中英文混杂。

## What Changes

- 在设置中增加语言选项，支持“跟随系统”“简体中文”和“English”，默认跟随系统。
- 语言选择持久化；手动切换后，已打开的 SwiftUI 页面和 AppKit 界面立即刷新，无需重启。
- 主程序内所有用户可见文案支持英文和简体中文，包括 Dashboard、设置、首次启动向导、右键菜单、窗口标题、菜单栏提示、系统弹窗和更新状态。
- “跟随系统”按以下规则解析：简体中文或繁体中文系统使用简体中文，英文系统使用英文，其他未支持语言回退英文。
- 将温度状态等兼作显示文案和业务判断的字符串改为稳定内部状态，再由本地化层负责展示。
- 保留 CPU、GPU、ANE、DRAM、MHz、GB/s、W、°C、RPM、mAh 等技术缩写和单位；芯片型号、进程名和应用名保持原值。
- 本次不修改 Widget 的语言行为。

## Capabilities

### New Capabilities

- `app-localization`: 定义主程序的语言选择、系统语言解析、持久化、即时刷新、双语覆盖范围和不可翻译内容边界。

### Modified Capabilities

无。

## Impact

- SwiftUI：`PopoverView.swift`、`WelcomeView.swift`、`MenuBarLayout.swift`
- AppKit：`AppDelegate.swift` 中的右键菜单、窗口标题和菜单栏 tooltip
- 模型与弹窗：`SystemStatsModel.swift` 以及 `UpdateChecker.swift` 的用户可见错误状态
- 项目资源：新增主程序 String Catalog，并在 Xcode 项目中声明 `zh-Hans`
- 测试与验证：覆盖语言持久化、跟随系统回退、即时刷新、AppKit 文案刷新以及中英文窄宽度布局
- 不涉及 Widget target 的本地化
