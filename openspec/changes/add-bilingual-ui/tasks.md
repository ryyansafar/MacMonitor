# Tasks

## 1. Localization Foundation

- [x] 1.1 增加可注入首选语言列表的应用语言枚举和解析逻辑，覆盖简体中文、繁体中文、英文及未支持语言回退；在 `Tests/ProcessIORanking` 风格的命令行测试中加入断言并确认全部通过。
- [x] 1.2 增加可观察的全局语言状态，将选择持久化为 `appLanguage`，缺省值为跟随系统；测试首次启动缺省值、三种选择写回以及重新读取，并确认主题和菜单栏设置不受影响。
- [x] 1.3 在主程序 target 新增 `Localizable.xcstrings`，声明 `en`、`zh-Hans` 和本地化资源，并提供 SwiftUI/AppKit 共用的本地化查询入口；使用 `plutil -lint` 检查资源格式并确认构建产物包含本地化资源。

## 2. Runtime Switching

- [x] 2.1 将全局解析后的 Locale 注入 popover、设置窗口和欢迎窗口的统一 SwiftUI 根视图，并让 AppDelegate 订阅语言变化；验证三个入口在语言变化时重新渲染且无需关闭窗口。
- [x] 2.2 在 Settings 增加语言选择项，提供跟随系统、简体中文和 English；验证选择后立即生效、重启后保留，并确认选择项自身随当前界面语言更新。

## 3. Main App Surfaces

- [x] 3.1 本地化 Dashboard 的分区标题、指标说明、电池状态、进程表头、操作按钮、空状态和辅助文字，包括经过 `String` 辅助组件传输的标签；逐项切换中英文，确认除批准的技术标识、单位和源数据外无英文残留。
- [x] 3.2 本地化 Settings 和首次启动向导的全部标题、说明、模式卡片、权限说明、按钮、更新状态及版本提示；在向导打开时切换语言，确认所有步骤立即更新。
- [x] 3.3 本地化菜单栏指标名称、行列文案和主题名称，但保留紧凑技术缩写；切换语言后确认已选择的指标、排序和布局不发生变化。

## 4. State And AppKit Integration

- [x] 4.1 将温度状态等兼作显示文案和业务判断的字符串替换为稳定内部状态，并单独映射本地化显示文字；验证中英文下相同状态保持相同阈值、颜色和菜单栏行为。
- [x] 4.2 本地化右键菜单、设置窗口标题、菜单栏 tooltip 和系统告警，并在语言变化时刷新长期存在的 AppKit 文案；切换后依次打开各入口，确认全部使用新语言。
- [x] 4.3 本地化更新检查的下载、安装、完成、失败状态和用户可见错误，同时保持版本号与文件信息原样；验证切换语言前后各错误状态显示对应语言。

## 5. Integration Verification

- [x] 5.1 运行本地化命令行测试及完整的 `xcodebuild -project Macmonitor.xcodeproj -scheme Macmonitor build CODE_SIGNING_ALLOWED=NO`，确认无编译错误和缺失本地化资源。
- [x] 5.2 执行三种语言模式的行为矩阵：首次启动、显式中英文、系统中文、系统英文、未支持系统语言、应用重启和运行中切换；记录实际观察结果并确认满足规格。
- [x] 5.3 在 340 点宽 Dashboard、设置窗口和 480x420 欢迎窗口中分别检查中英文截图，确认文字不重叠、不截断且数值列保持稳定；如有溢出，调整布局后重新截图验证。
- [x] 5.4 检查最终差异，确认 Widget target、芯片型号、进程名、应用名、技术缩写和单位未被意外修改；运行 `openspec validate add-bilingual-ui --strict` 并确认通过。

## Verification Record

- 默认跟随系统：中文系统首次启动显示中文欢迎页和中文 Dashboard。
- 显式语言：英文欢迎页、Dashboard 和设置页显示英文；简体中文 Dashboard 和设置页显示中文。
- 系统语言回退：系统英文显示英文；未支持的日语系统语言回退英文。
- 运行中切换：在已打开的英文设置窗口选择 Simplified Chinese 后，窗口标题、正文、语言分段和外观分段立即更新为中文，无需重启。
- 持久化：隔离测试偏好域写入了 `appLanguage = zh-Hans`；语言解析命令行测试覆盖三种选择、重启读取和不受其他设置影响。
- 布局：340 点宽 Dashboard、设置窗口和 480x420 欢迎窗口均完成中英文截图检查，未发现文字重叠、截断或数值列移位。
- 构建：`xcodebuild` 成功，App 包包含 `en.lproj/Localizable.strings` 和 `zh-Hans.lproj/Localizable.strings`。
