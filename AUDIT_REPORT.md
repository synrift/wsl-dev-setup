# 单一 Starship 配置审计报告

## 当前配置

安装器恢复为单一 Starship 配置：始终安装 Starship，生成 `pastel-powerline`
preset，并在交互 zsh 中加载 Starship、`zsh-autosuggestions` 和
`zsh-syntax-highlighting`。已移除 `PROMPT_MODE`、Warp 分支、后备 prompt
及 Warp 设置说明。

继续不安装、不初始化 zoxide。保留 compinit、别名及原有项目运行时初始化。
安装后始终执行 Starship `--version` 检查；独立 `zsh -c` 工具检查以及
原有 `zsh -lc`、`zsh -ic`、Bash、Docker 和 Chromium 验证均保留。

fnm、Node、npm、Corepack、pnpm、Playwright、Docker、WSL/systemd、
Bubblewrap/AppArmor、Git/SSH 的安装和运行时函数未修改。

## 已执行验证

- `bash -n install.sh`：通过。
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`：4 项通过。
  - 捕获 apt 参数，确认包含两个 zsh 插件且不包含 zoxide；不执行 apt。
  - 检查生成的配置内容和 Bash/zsh 语法。
  - 模拟外部工具调用，确认安装后执行 Starship 版本检查和各 shell 验证。
  - 实际运行 zsh 的 `-c`、`-lc`、`-ic`、`-lic`，确认运行时加载、
    交互 Starship 初始化和 compdef 可用。运行时 helper 和 Starship 二进制
    使用模拟实现，不代表实际 fnm 或 Starship 渲染验证。
- 对照修改前文件，确认上述开发运行时及服务安装函数保持一致。
- 当前环境无 ShellCheck，未重新执行该检查。

## 验证边界

本次未在 Debian 13 / WSL 2 中执行完整安装，未验证真实服务启动、
Node 下载与切换、Chromium 启动或实际终端渲染。隔离测试不替代这些检查。
安装器仍面向全新 WSL 环境；本次未新增配置迁移支持。
