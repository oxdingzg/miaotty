# 架构

miaotty 是一个原生 macOS 终端：终端内核（Metal 渲染器、VT、PTY、shell 集成）fork
自 [Ghostty](https://ghostty.org)，并在其上叠加了一层加法式的控制/智能体层。本文
记录这套形态背后的耐久决策，以及 fork 是如何接线的。构建机制与 patch 系列见
[`miaotty/overlay/README.md`](../miaotty/overlay/README.md)，一页纸的介绍见
[根 README](../README.md)。

[English](ARCHITECTURE.md) · [中文](ARCHITECTURE.zh-CN.md)

更早的、逐条决策的历史（ADR 0001–0008）见 git log —— 本文取代它们。

## 1. 加法式 fork Ghostty

**背景。** miaotty 需要一个原生 macOS 终端——Metal 渲染、快速 VT 状态机、PTY 处理、
shell 集成、terminfo、AppleScript、自动更新。从零构建是数年的工程；我们真正想要的
差异化（智能体感知 UI、控制平面、类 IDE 侧栏）只是其上薄薄一层。

**决策。** fork Ghostty（MIT），只做加法式改动：

- 我们的代码放在 `miaotty/` 下——Swift `MiaottyKit`、Rust `miaotty-cli`、TS
  `@miao/miaotty`、resources、proto。
- 上游内部符号、文件名、crate 名保持不动。只重命名面向用户的身份（app 名、bundle
  id、URL scheme、`TERM_PROGRAM`、环境变量前缀），让上游合并保持廉价。
- checkout 内一小撮固定的 patch 点：导出
  `ghostty_surface_child_pid()` / `ghostty_surface_pane_id()`（只读 C API）、一个在
  启动时安装 MTP host 的 app hook、以及 `Info.plist` / bundle 元数据。

**后果。** 我们继承 Ghostty 的性能上限，也继承其快速演进的上游；我们钉住一个发布
tag（1.3.1），并把 `ghostty-org/ghostty` 作为 `upstream` 跟踪。自托管组件（IPC、
badge、侧栏）不得进入 `input → pty → vt → metal` 热路径（见 §3）。pbxproj 是最危险
的文件，因此我们的 Swift 放在本地 SPM 包（`MiaottyKit`）里，只留一行依赖。我们绝不
复制 Otty 的专有脚本/HTML；OSC 码是公开的。

`scripts/bootstrap-ghostty.sh` 可复现 fork 的搭建（默认只出计划；`--apply` 克隆并
打 patch，`--build` 再构建）。

## 2. MTP：一份契约，多种传输

**背景。** miao 和 miaotty 必须像一个产品，但它们的实现各自独立变化（今天是
plugin + CLI + socket；将来可能是进程内嵌入或远程）。把某一种集成机制写死，会把两条
发布周期绑在一起，并带来版本错配风险。

**决策。** 用 **MTP（Miaotty Terminal Protocol）** 作为稳定契约，单一 JSON-Schema
源（`miaotty/proto/mtp.schema.json`），为 Rust、Swift、TypeScript 生成代码。

- 一条连接、一种信封（`req`/`res`/`evt`）、四个平面：**state、context、control、
  UI**。
- 带版本（`v`）和能力握手（`hello`/`welcome`）；新字段是可选的，未知能力/字段被
  忽略。
- 传输被抽象（主用 Unix socket；stdio 与进程内后续支持）。
- 状态按 key `(pane, session)` 幂等、last-write-wins，带单调 `seq` 和用于对账的
  `revision`。

**后果。** 实现可在不改协议的前提下替换——Swift host 与 Rust CLI 已经通过 MTP 互通。
codegen 漂移会导致 CI 失败；schema 是唯一改类型的地方。对端必须处理版本错配并优雅
降级（终端从不依赖智能体）。纯 CLI 的临时集成是零安装的兜底层级，而非契约；进程内
嵌入不被排除。

## 3. 性能优先：动热路径之前先摸清线程模型

性能是 miaotty 的第一产品属性，而最快的路径就是我们不去碰的那条：
`input → pty → vt → metal`。badge 更新、IPC、plugin、侧栏都绝不能出现在那里。不弄清
fork 出来的构建里究竟是哪个线程/队列负责 PTY 读取、VT 解析、渲染提交与呈现，我们就
无法守住这条边界。

**决策。** 在写任何触碰终端行为的代码之前：

1. **记录上游线程模型**——枚举 fork 构建的线程/队列（PTY 读取、VT 解析、渲染/提交、
   呈现、主线程），以及我们代码允许的接触点（pane 生命周期事件；单一、合并后的主线程
   应用点）。
2. **采集基线**——`miaotty/bench/budgets.json` 里每一项目标（帧时间、按键→字形延迟、
   吞吐、冷启动、内存）都要在目标机器上采集。
3. **接上 CI 门控**——硬性目标上 >5% 的回退即构建失败。

**后果。** 所有新增都是事件驱动、可合并、有界、可关闭的；把所有附加项关掉后，性能
必须在 Ghostty 的噪声范围内。反模式是明确的：热路径上不做 I/O、不加锁、不分配；不
同步 IPC；不轮询定时器；不逐帧扫描；不无界队列。

> **未决：** 线程模型记录（第 1 步）尚未完成，阻塞热路径工作。

## 4. fork 如何接线

这一节全是加法式的，且都落在 §1 的 patch 点之后。patch 系列本身记录在
[`miaotty/overlay/README.md`](../miaotty/overlay/README.md)。

### 4.1 在 Xcode 26 / macOS 26 上构建

Ghostty 1.3.1 早于 Xcode 26，在 macOS 26 上构建暴露出三个互不相关的拦路石：

1. **Zig 0.15.2 无法链接 macOS 26 SDK**（未定义的 `__availability_version_check` /
   libSystem 符号）。让 zig 指向 macOS 15.4 SDK 即可解决，但 `SDKROOT` / `--sysroot`
   对 `zig build` runner 不生效——只有 `xcrun --show-sdk-path` 报告的 SDK 才管用。
2. **Metal Toolchain 是独立的 Xcode 组件**，必须安装
   （`xcodebuild -downloadComponent MetalToolchain`）；在此之前默认的 `metal` 只是个
   桩。
3. **Apple `libtool` 会静默丢弃 Zig 0.15.2 产出的归档成员**——Zig 核心对象与 C++ 依赖
   （imgui、oniguruma）会在 `libtool -static` 合并中消失。合并前先用 `ranlib` 重写每个
   归档的索引即可解决。

**决策。** 用受版本管理的配方复现构建：`scripts/xcrun-sdk-shim/xcrun` shim（为 zig
强制 15.4 SDK）、ranlib patch，以及 `scripts/bootstrap-ghostty.sh`（安装 Zig 0.15.2、
克隆钉住的 tag、打 patch、构建）。

**后果。** 只 patch 了恰好一个上游文件（`src/build/LibtoolStep.zig`），且它是货真价实
的上游修复候选。构建不是"`zig build` 一下"：它需要 shim、完整的 `xcode-select`、以及
Metal Toolchain。当上游能产出 libtool 兼容的归档时，ranlib patch 就不再需要。

### 4.2 把主干接进 app

MTP host 与 CLI 已经存在并互通，但还没有任何东西把 host 绑到真实终端 surface 上。
四处加法式改动完成接线：

1. **C API `ghostty_surface_child_pid`**——`termio.Exec` 把 spawn 出的子进程 PID 发布到
   每 surface 的 `std.atomic.Value(pid_t)`；内嵌 apprt 将其导出。只读、脱离热路径、不
   新增锁。
2. **app hook**——`AppDelegate` 在启动时启动 MTP host，并 `setenv`
   `MIAOTTY_SOCKET` / `MIAOTTY_PROTO` 让子进程继承；`SurfaceView` 在创建 surface 后调用
   `MiaottyIntegration.attach(surface:to:)`。
3. **本地 SPM 包**——`MiaottyKit` 作为本地包产物加入 `Ghostty.xcodeproj`（仿照
   Sparkle），让 app 只留一行依赖。
4. **`xcodebuild -scheme Ghostty`**——`-target` 会构建包产物但不传递其
   `.swiftmodule`，导致 import 失败；共享 scheme 修复了解析，`SYMROOT/OBJROOT=build`
   把输出留在 copy 步骤期望的位置。

badge 渲染是一个手绘帧的 `NSView` 覆盖层（无 Auto Layout，`draw` 期间不改 frame），由
注册表发出的**合并后的主线程通知**驱动——绝不轮询。

### 4.3 pane 身份、环境绑定与产品身份

- **内核持有 pane id。** `Surface` 在创建时生成 32 位十六进制 id，并把它作为
  `MIAOTTY_PANE_ID` 注入子进程环境（与 `MIAOTTY_SOCKET` 并列），通过
  `ghostty_surface_pane_id()` 暴露给 app。绑定是 O(1)，并能穿透嵌套/短命进程——热路径上
  无 PID 遍历。
- **CLI 从 `MIAOTTY_PANE_ID` 默认 `--pane`**，于是 hook 无需参数；对 pane 之外的进程，
  PID/tty 匹配仍是兜底。
- **app 在用户可见层面就是 `miaotty`。** `TERM_PROGRAM=miaotty`，
  `PRODUCT_NAME = miaotty`（它驱动 `CFBundleName`，即菜单栏名——生成值无法经
  `INFOPLIST_FILE` 覆盖），以及
  `PRODUCT_BUNDLE_IDENTIFIER = io.miaotty.terminal`。独立 id 消除了与已安装的上游
  Ghostty 的 LaunchServices 冲突。所有用户可见字符串（app 菜单、About 面板、退出/错误
  对话框、默认窗口标题、settings/error/intent 字符串、`Ghostty.sdef`）都已改名。可执行
  **文件名**保持 `ghostty`（`EXECUTABLE_NAME`），以免触碰内部 CLI/路径引用。
- **hook 经"启动时安装"分发。** app 在启动时把智能体 hook 脚本与 shell env 写到
  `~/.local/share/miaotty/...`（幂等），避免改动 Ghostty 的资源管线。
  `miaotty/resources/**` 仍是纯 CLI 用户的正典兜底。

**延后**（受分发决策约束）：app 图标（仍是幽灵）、URL scheme、Sparkle feed/公钥、
公证——app 目前是 ad-hoc 签名。

### 4.4 侧面板与命令历史

Otty 的窗口有一个左侧竖向 **tabs** 面板和一个右侧 **details** 面板
（Info / Outline / Git / Files）；Ghostty 没有侧面板也没有 `NSSplitView`，其 macOS
窗口是单个 SwiftUI `TerminalView` 托管一棵递归 split 树。miaotty 在终端区域两侧加了
两个可切换面板：

- **布局注入点**——`TerminalView.body` 把 split 树包进 `MiaottyPanelLayout`（一个
  `HSplitView`）。面板可见性挂在 `BaseTerminalController`
  （`miaottyShowTabsPanel` / `miaottyShowDetailsPanel`），在 `TerminalViewModel` 协议上
  声明以便 SwiftUI 视图观察；切换为 `@IBAction toggleTabsPanel:` /
  `toggleDetailsPanel:`（View 菜单；⌘⇧L / ⌘⌥D）。
- **面板是新的 Swift 文件**，位于 `macos/Sources/Miaotty/Panels/`（镜像到
  `miaotty/overlay/macos/Sources/Miaotty/Panels/`）：tabs 列表（对
  `NSWindow.tabGroup` 做 KVO、点击切换、`+` 新建 tab）与 details 面板
  （Info：cwd/actions/process/ports；Outline：命令历史；Git；Files）。面板隐藏时，一条
  细边缘条在悬停时露出显示按钮。
- **命令历史数据平面**——`MiaottyKit` 中的 `HistoryRegistry`（与 `AgentRegistry` 同款
  lock/revision/onChange 模型）、MTP 方法 `history.add` / `history.list`，以及由 app
  安装的 zsh hook。打过补丁的 Ghostty zsh 集成 source `$MIAOTTY_SHELL_HOOK`，其
  `preexec` 调用 `miaotty-cli history:add`——命令采集留在 app/CLI 层，Zig 内核不解析。

**后果。** patch 增加了四处上游 hunk（`TerminalView.swift`、
`BaseTerminalController.swift`、`MainMenu.xib`、zsh 集成）；所有新逻辑都留在 `Miaotty`
命名空间内。zsh 集成文件是 GPLv3（来自 Kitty），目前只接了 zsh。
