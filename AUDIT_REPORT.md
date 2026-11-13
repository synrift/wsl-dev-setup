# Shell 运行时删减审计报告

## 当前实现

恢复单一 Starship 配置，继续不安装 zoxide。普通 shell 只初始化 fnm、选择
已安装的项目 Node，并设置必要环境变量，不再准备或修复 Corepack/pnpm。

删除自写 prepare-node、Node/Corepack 兼容表、独立 Corepack 安装缓存、
手动命令链接修复、npm 签名密钥下载和 30 天刷新、安装锁、Node 16 特殊处理、
fnm 命令包装、手动版本继承标记，以及 cd/pushd/popd 包装和失败回退。

初次安装仍安装默认 Node LTS，再用官方 npm 包安装 Corepack，执行
corepack enable，并预热 pnpm。新 Node 的 Corepack/pnpm 由用户或 agent
在项目准备阶段配置。较旧 Node 需要自行选择兼容的 Corepack 版本。
Corepack 使用其自身的签名验证机制；不关闭校验。

zsh 使用官方 fnm --use-on-cd hook；Bash 在启动时选版本，之后跨项目需
显式 fnm use。保留递归 .node-version/.nvmrc 查找和 resolve-engines=false。
缺失版本在 shell 启动时失败，不下载、不提示安装，不执行后续任务。
目录切换沿用 fnm 原生行为：失败会报错，但不恢复目录，也不能保证阻断
同一命令中的后续操作。未准备项目应显式使用 cd project && fnm use && command。
不再保证手动 fnm 选择跨新 shell 继承；新 shell 按自己的目录选择版本。

## 保留的功能

对比删减前本地提交 a0e7118，以下安装/配置/验证函数内容完全一致：
系统升级与 apt 包安装、WSL systemd、Bubblewrap/AppArmor、Starship 安装和
交互配置、Git 身份及 SSH 密钥、默认 zsh、Docker、Playwright 安装及固定
运行时启动器、zsh/Bash 启动入口，以及安装后的所有检查。

因此保留 Starship --version、zsh -c/-lc/-ic、Bash、Docker/Compose 和
Chromium 实际启动检查。TMPDIR、COREPACK_HOME、Playwright 默认浏览器及
Corepack 行为开关仍保留。Bash 的 BASH_ENV 和同进程去重也保留。

## 验证结果

- bash -n install.sh：通过。
- ShellCheck 0.11.0：通过。
- git diff --check：通过。
- 13 项 unittest 全部通过，其中 9 项使用真实 fnm 1.39.0、Node 22.23.5 /
  24.22.3；包管理器检查使用 Corepack 0.36.0 与预热的 pnpm 11.24.0。
- 覆盖新 zsh 的 -c/-lc/-ic/-lic、Bash -c/-lc、子 shell、父目录版本文件、
  .nvmrc、符号链接目录、默认版本、手动 fnm use/exec、官方目录切换 hook、
  并发启动、只读 HOME、缺失版本阻断，以及实际 npm/Corepack/pnpm 命令。
- pnpm 测试读取项目 packageManager 并执行 node，确认实际 Node 版本。
- Git 启动检查将 Node、npm、npx、Corepack、pnpm、curl、flock 替换成失败
  探针，仍成功执行 Git，确认没有调用这些工具。
- pnpm 下载在测试前完成；最终测试设置 COREPACK_ENABLE_NETWORK=0，
  不依赖测试过程中联网。

复现方法见 README 的 Repository Checks。未设置真实工具路径时，相关测试
会明确跳过，不应将默认测试命令的结果描述为真实运行时验证。

## 边界

未在 Windows/WSL 2 中执行完整安装，未启动真实 Orca/Codex/Cursor 会话，
也未进行实际 agent 工作负载计时。本次证明启动路径减少了准备工作，不对
实际任务提速幅度作承诺。fnm 的初始化、版本选择和目录 hook 仍有开销。
CLI 环境快照、禁用启动文件或显式覆盖 PATH 可能绕过新目录的版本选择。

脚本仍面向全新环境；未添加旧配置迁移和旧缓存清理功能。发布状态以
Git 分支和提交记录为准。
