# miaotty

为 `miao` AI 编程智能体打造的快速原生 macOS 终端——也适用于任何智能体。

> `miaotty` = `miao` + `tty`。开源（MIT），终端内核（Metal 渲染器、VT、PTY、shell
> 集成）fork 自 [Ghostty](https://ghostty.org)，并在其上扩展了一层控制/智能体层。

[English](README.md) · [中文](README.zh-CN.md)

## 当前状态

脚手架 + **可用的 Ghostty fork 构建**。

- Ghostty fork **能在这台机器上构建**：`zig build -Doptimize=ReleaseFast
  -Dxcframework-target=native` → `vendor/ghostty/zig-out/miaotty.app`（arm64，
  ReleaseFast，Metal）。Xcode 26 / macOS 26 的绕过办法见
  `docs/ARCHITECTURE.md` §4.1，复现步骤见 `scripts/bootstrap-ghostty.sh`。
- **badge 主干已在 app 内跑通**（`docs/ARCHITECTURE.md` §4.2）：
  `miaotty-cli pane list` 返回实时 pane 及子进程 PID，`state set` 驱动 pane 上的
  智能体 badge（processing / awaiting / error / idle）。
- **pane 身份与环境绑定**（`docs/ARCHITECTURE.md` §4.3）：
  内核在 spawn 时生成 pane id 并注入 `MIAOTTY_PANE_ID`；CLI 据此默认 `--pane`；
  app 对外声明 `TERM_PROGRAM=miaotty`，并在启动时把智能体 hook 安装到
  `~/.local/share/miaotty/`。
- **集成主干**已实现并端到端验证：
  - **MTP**（Miaotty Terminal Protocol）——state / context / control / UI 四个平面共用
    一份带版本、可协商能力的契约。单一 JSON-Schema 源，为 Rust、Swift、TS 生成代码。
  - **`miaotty-cli`**（Rust）——控制 CLI，含一个开发用 `mock-host`。
  - **`MiaottyKit`**（Swift）——app 内宿主：MTP server、智能体状态注册表、扩展点。
  - **`@miao/miaotty`**（TS）——miao 插件（server + TUI 入口）。
  - shell / 智能体集成资源、性能预算与门控。

## 目录结构

```
miaotty/
├── proto/            MTP schema（单一事实源）+ codegen
├── cli/              Rust workspace：`mtp` crate + `miaotty-cli`
├── macos/MiaottyKit/ Swift package：host、registry、extension points
├── overlay/          Ghostty fork 的加法式粘合层：受版本管理的 patch 系列 + Swift UI
├── plugin/           @miao/miaotty（miao 集成）
├── resources/        shell-integration + agent-integration
├── bench/            性能预算 + harness
└── tools/            本地工具链（zig；由 bootstrap 拉取，gitignore）
scripts/              bootstrap、build、doctor、codegen、e2e
docs/                 架构文档（公开）；设计文档位于 docs/private/（仅本地）
```

## 快速开始（仅主干）

```sh
# 1) 从 proto/mtp.schema.json 生成协议类型（Rust/Swift/TS）
scripts/codegen.sh

# 2) 构建并测试 Rust CLI
cd miaotty/cli && cargo test && cargo build

# 3) 构建 Swift 宿主（需要 Xcode）
swift build --package-path miaotty/macos/MiaottyKit

# 4) 端到端：启动开发宿主，然后与它通信
miaotty/cli/target/debug/miaotty-cli mock-host &      # 或：swift run --package-path ... miaotty-host
miaotty/cli/target/debug/miaotty-cli ping
miaotty/cli/target/debug/miaotty-cli state set --agent miao --state processing --pane pane_1
miaotty/cli/target/debug/miaotty-cli state list
```

## 原则

1. **性能优先** —— 我们新增的一切都活在 `input → pty → vt → metal` 热路径之外。
2. **加法式 fork** —— 上游内部符号保持不动；我们的代码放在 `miaotty/` 下，以及少数
   明确标注的 patch 点。
3. **契约优先** —— 实现（plugin / CLI / 进程内）可以变；MTP 不变。
4. **Fail open** —— 终端从不依赖智能体；关掉 AI ⇒ 性能等同于 Ghostty。

决策见 `docs/ARCHITECTURE.md`，完整设计集见 `docs/private/`（仅本地）。

## 许可证

MIT —— 见 [`LICENSE`](./LICENSE)。终端内核 fork 自
[Ghostty](https://ghostty.org)（MIT）。打过补丁的 zsh 集成派生自
[Kitty](https://sw.kovidgoyal.net/kitty/)，仍为 GPLv3（见
`docs/ARCHITECTURE.md` §4.4）。
