# Warp / Starship 选择性安装审计报告

## 结论

本次实现面向全新 Debian 13 / WSL2 的一次性安装。新增 `PROMPT_MODE=warp|starship`，默认 `starship`。已完成代码修改、隔离测试和原版对照审计。

在已验证范围内，未发现对原有开发运行时配置的回归。Warp 模式有意减少 Starship 和两个传统 zsh 行编辑插件；其他开发工具仍走原有安装流程。默认 Starship 生成的交互配置仅移除 zoxide 初始化，其余非空内容与原版一致。

这不是完整的 WSL2 / Warp / agent 端到端稳定性认证。当前执行环境为 Debian 13 Linux 云容器，不是 WSL2，没有运行 Windows Warp、WSL 内的 Codex CLI、Cursor CLI 或 OpenDesign；完整安装被原有平台检测拒绝。此限制不应被静态检查或模拟测试替代。

## 改动范围

- `install.sh`：新增模式变量、安装前校验及 sudo 重执行时的参数传递。
- Warp 模式不安装 Starship，不下载其安装器，不生成其 preset，也不初始化它。
- 仅 Starship 模式安装并加载 `zsh-autosuggestions` 和 `zsh-syntax-highlighting`。
- 两种模式保留 zsh、默认 shell 设置、compinit 及原有别名；按用户要求移除 zoxide 安装及初始化，不替换其目录跳转功能。
- Warp 模式生成简单的 zsh PROMPT、空 RPROMPT，作为基础后备提示符；Warp 中需手动选择内置 Warp prompt。Starship 模式在 Warp 中需选择 Shell prompt。
- 选择结果直接写入 `.zshrc`，后续 shell 无需继承 `PROMPT_MODE`。不添加终端检测、Warp 专用 hooks 或额外 prompt 引擎。
- 原有安装后验证增加 Starship 模式下的版本检查，并增加独立 `zsh -c` 工具检查。原有 zsh 登录/交互、Bash 非交互、Docker 和 Chromium 检查均保留。
- `README.md`：新增选择方式、远程安装示例、功能矩阵、agent 启动边界与测试命令。
- `tests/test_prompt_modes.py`：新增隔离验证，不执行系统安装。

不加入重复安装、配置迁移或两种模式来回切换的支持；不安装 Codex、Cursor、OpenDesign 本体。

## 兼容性审计

| 项目 | 审计结果 | 证据及边界 |
| --- | --- | --- |
| 默认 Starship 配置 | 保留 prompt 与插件行为，移除 zoxide | 从原版去掉 zoxide 初始化区块后，非空内容完全一致 |
| fnm / Node / npm / Corepack / pnpm | 实现未变 | `install_fnm_and_node`、`write_node_helpers`、`write_prepare_node` 函数一致；生成的两个 helper 字节一致 |
| 项目版本递归查找、显式 fnm 覆盖、锁、缓存、失败恢复 | 实现未变 | 位于未修改的运行时 helper 内；本次没有重新执行真实多版本 Node 下载和切换 |
| zsh 非交互初始化 | 保持原有入口 | `configure_zshenv` 未变，生成 `.zshenv` 字节一致；增加安装后的 `zsh -c` 检查 |
| Bash / BASH_ENV | 保持原有机制 | `configure_bash` 未变，生成 `.bashrc`、`.profile` 字节一致 |
| TMPDIR / COREPACK_HOME / Playwright 环境变量 | 实现未变 | 共用运行时初始化不依赖 prompt 模式 |
| Playwright CLI 固定运行时、Chromium | 安装及验证实现未变 | `install_playwright`、`write_playwright_launcher` 一致；实际浏览器安装和启动未在本次运行 |
| Docker / Compose / systemd / WSL | 实现未变 | 对应函数及平台检查一致；真实 WSL 服务启动未验证 |
| Bubblewrap / AppArmor | 实现未变 | 对应函数一致；不宣称实际 agent sandbox 已验证 |
| Git / SSH / 默认 shell | 实现未变 | 对应函数一致 |
| 基础系统依赖 | 共用依赖保留 | 隔离捕获 apt 参数；移除 zoxide，两个 zsh UI 插件变为条件安装 |
| zoxide / 目录切换 hooks | 移除 zoxide，保留原有 Node hooks | 不再提供 `z` 跳转及 `__zoxide_cd`；`cd`、`pushd`、`popd` 的 Node 选择和恢复实现未变，与 Warp hooks 共存仍需实测 |
| 非 Warp 终端 | Warp 模式有明确 UI 差异 | 简单提示符、无上述两插件；不会自动恢复 Starship |
| shell 补全 | compinit 保留 | 实际 zsh 交互进程验证 compdef 可用；不代表 Warp 自有补全 UI 已验收 |
| WSL 内 Codex CLI / Cursor CLI / OpenDesign | 开发环境入口保留 | 未更改运行时路径和浏览器/GUI依赖；没有启动这些产品或验证其具体 shell 配置 |

原版对照共确认 18 个已有函数完全一致；6 个函数按本次目标修改；新增 1 个模式校验函数。模式变量使用 `${PROMPT_MODE-starship}`，未设置时默认 Starship，显式空值则拒绝；拼写错误不会悄悄选择其他模式。sudo 重执行显式传递模式，避免丢失选项。

## 已执行的验证

1. `bash -n install.sh`：通过。
2. ShellCheck 0.11.0：通过，无诊断。
3. `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`：7 项测试全部通过：
   - 默认值及两种合法模式。
   - 非法/空值在系统安装之前失败。
   - 两种模式的 apt 包选择（模拟 sudo，不执行 apt）。
   - Warp 分支不调用 Starship 下载或写入 preset。
   - 两种模式生成的配置内容及 Bash/zsh 语法。
   - 两种模式生成的共用运行时和启动文件一致。
   - 真实 zsh 的 `-c`、`-lc`、`-ic`、`-lic` 共 8 种组合：交互模式初始化所选 prompt，非交互模式不初始化 prompt；compdef 在交互模式中可用。此项模拟了运行时 helper 和 Starship 二进制，验证的是 shell 加载边界，不是实际 fnm 或 Starship 渲染。
4. 从 Git HEAD 提取原版脚本，对比函数定义及两版生成的启动文件：上述一致性检查通过；后续移除 zoxide 后，Starship 对照排除原版 zoxide 区块。
5. `git diff --check`：通过。
6. `PROMPT_MODE=warp bash install.sh`：退出码 1，输出 WSL2-only 错误，符合当前非 WSL2 主机的预期；未执行系统安装。此项属于平台保护检查通过，不属于完整安装通过。

## 仍需实际 WSL2 验证的项目

在各自的全新 Debian 13 / WSL2 测试实例中分别执行两种模式，避免把模式切换当作本次功能：

- 完整安装结束，并按说明 `wsl --shutdown` 后重启。
- 普通用户运行原 README 的 Docker、Compose、Node、Corepack、pnpm、Playwright 检查。
- Warp UI 中选择相应 prompt，验证提示符、命令块、输入建议、退出状态、Ctrl-C、多行输入。
- 从 Warp 的 WSL 会话进入含版本文件的项目及子目录，验证正确 Node/pnpm；验证手动 fnm 选择及失败恢复。不把 Cursor IDE 集成终端纳入使用场景。
- 验证 `cd`、`pushd`、`popd` 的运行时选择 hooks 与 Warp 的 shell hooks 共存。
- 从 WSL 中实际运行的 Codex CLI、Cursor CLI，以及需要时的 OpenDesign 执行 Node/pnpm、目录切换和浏览器相关操作；观察它们真正采用的 shell 与启动选项。
- Starship 模式实际加载 preset；Warp 模式无 Starship 调用，非 Warp 终端保留简单提示符。

## 既有边界与剩余风险

以下是需要理解的现有行为，不是本次新增的回归：

- 独立 `bash -c` 若未继承 `BASH_ENV`，不会自动获得共用初始化；此场景应使用 `bash -lc`。`zsh -f` 等禁用启动文件的选项也能绕过初始化。
- shell 启动可能为缺失 Node/Corepack/pnpm 下载内容，仍依赖网络和 HOME 写权限；已准备工具的只读 HOME 路径保留原有实现。本次未进行真实只读 sandbox 回归测试。
- 安装器仍依赖上游未固定的工具版本和下载内容；本次不修改既有升级策略、TLS、签名或校验机制。
- zsh/Node 的目录切换函数与 Warp 集成的具体相互作用没有实际 Warp 会话证据。未为“看起来兼容”而删除原有 hooks 或绕过运行时校验。
- Warp 官方文档读取在当前网络中返回 HTTP 403；具体 UI 名称和集成表现仍应以用户安装版本为准。未通过不受支持的网络方式绕过限制。

因此准确结论是：核心环境生成结果保持一致，已执行检查未发现回归；UI 依赖按模式有意区分，WSL2 与实际产品集成的稳定性仍待上述端到端验证。

## 后续调整：移除 zoxide 与明确 CLI 场景

按用户最新要求，两种模式均不安装 zoxide，删除 `zoxide init zsh` 及专用 `__zoxide_cd` 包装。`z`/`zi` 历史目录跳转不再由安装器提供；正常 shell 导航及其项目运行时校验保持原实现。未修改 fnm、Corepack、Node 或 Bash 初始化。

目标场景为 Warp 连接 WSL，并在 WSL 内运行 Codex CLI 与 Cursor CLI；不再为 Cursor IDE 集成终端作兼容性设计或验收。基本 PROMPT 保留为 shell 后备值，不增加额外终端逻辑。其他原有开发依赖仍保留。测试已更新为断言 apt 参数和生成 `.zshrc` 中均不存在 zoxide。
