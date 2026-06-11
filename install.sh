#!/usr/bin/env bash
set -euo pipefail

# WSL Ubuntu 一键初始化脚本
# 包含：
#   1. 基础软件：zsh / unzip / curl / git / zoxide / zsh 插件
#   2. Starship
#   3. fnm
#   4. Git 全局配置
#   5. SSH key
#   6. Docker Engine + Buildx + Compose plugin
#
# 用法：
#   chmod +x ./wsl-dev-setup-with-docker.sh
#   ./wsl-dev-setup-with-docker.sh
#
# 可选参数：
#   GIT_NAME="你的名字" GIT_EMAIL="你的邮箱" ./wsl-dev-setup-with-docker.sh
#
#   INSTALL_DOCKER=0 ./wsl-dev-setup-with-docker.sh
#   RUN_DOCKER_TEST=0 ./wsl-dev-setup-with-docker.sh
#   OVERWRITE_STARSHIP=1 ./wsl-dev-setup-with-docker.sh
#

GIT_NAME="${GIT_NAME:-aaa}"
GIT_EMAIL="${GIT_EMAIL:-aaa@aaa.com}"

INSTALL_DOCKER="${INSTALL_DOCKER:-1}"
RUN_DOCKER_TEST="${RUN_DOCKER_TEST:-1}"
OVERWRITE_STARSHIP="${OVERWRITE_STARSHIP:-0}"

log() {
  printf "\n\033[1;32m==> %s\033[0m\n" "$1"
}

warn() {
  printf "\n\033[1;33m[WARN] %s\033[0m\n" "$1"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

append_or_replace_block() {
  local file="$1"
  local start_marker="$2"
  local end_marker="$3"
  local content="$4"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -qF "$start_marker" "$file"; then
    local tmp
    tmp="$(mktemp)"
    awk -v start="$start_marker" -v end="$end_marker" -v block="$content" '
      BEGIN { in_block=0 }
      index($0, start) {
        print block
        in_block=1
        next
      }
      index($0, end) {
        in_block=0
        next
      }
      !in_block { print }
    ' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
  else
    printf "\n%s\n" "$content" >> "$file"
  fi
}

install_base_packages() {
  log "更新系统并安装基础软件"

  sudo apt update
  sudo apt upgrade -y
  sudo apt install -y \
    zsh \
    unzip \
    curl \
    git \
    ca-certificates \
    gnupg \
    zoxide \
    zsh-autosuggestions \
    zsh-syntax-highlighting

  mkdir -p "$HOME/.local/bin"
}

install_starship() {
  log "安装 Starship 到 ~/.local/bin"

  if need_cmd starship || [ -x "$HOME/.local/bin/starship" ]; then
    echo "Starship 已存在，跳过安装。"
  else
    curl -sS https://starship.rs/install.sh | sh -s -- -b "$HOME/.local/bin" -y
  fi

  log "生成 Starship 配置"
  mkdir -p "$HOME/.config"

  if [ -f "$HOME/.config/starship.toml" ] && [ "$OVERWRITE_STARSHIP" != "1" ]; then
    echo "~/.config/starship.toml 已存在，跳过生成。"
  else
    PATH="$HOME/.local/bin:$PATH" starship preset pastel-powerline -o "$HOME/.config/starship.toml"
  fi
}

install_fnm() {
  log "安装 fnm"

  if need_cmd fnm || [ -x "$HOME/.local/share/fnm/fnm" ]; then
    echo "fnm 已存在，跳过安装。"
  else
    # --skip-shell 避免 fnm 安装器自动改 shell 配置，本脚本会统一写入 ~/.zshrc
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
  fi
}

configure_zshrc() {
  log "写入 ~/.zshrc"

  local zshrc="$HOME/.zshrc"
  local start_marker="# ===== BEGIN WSL DEV SETUP ====="
  local end_marker="# ===== END WSL DEV SETUP ====="

  local block
  block="$(cat <<'EOF'
# ===== BEGIN WSL DEV SETUP =====

# completion
autoload -Uz compinit
compinit

# basic PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.local/share/fnm:$PATH"

# fnm
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

# zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# starship
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# git aliases
alias gs="git status"
alias ga="git add"
alias gaa="git add --all"
alias gc="git commit"
alias gcm="git commit -m"
alias gp="git push"
alias gl="git pull"
alias gb="git branch"
alias gco="git checkout"
alias gcb="git checkout -b"
alias gd="git diff"
alias gds="git diff --staged"
alias logg="git log --oneline --graph --decorate --all"

# ls aliases
alias ls='ls --color=auto'
alias l='ls -lah --color=auto'
alias la='ls -lAh --color=auto'
alias ll='ls -lh --color=auto'
alias lsa='ls -lah --color=auto'

# zsh plugins
if [ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

if [ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# ===== END WSL DEV SETUP =====
EOF
)"

  if [ -f "$zshrc" ]; then
    cp "$zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
  fi

  append_or_replace_block "$zshrc" "$start_marker" "$end_marker" "$block"
  echo "已写入 ~/.zshrc；如果原文件存在，已自动备份。"
}

configure_git_and_ssh() {
  log "设置 Git 全局用户名和邮箱"

  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main

  echo "Git user.name  = $(git config --global user.name)"
  echo "Git user.email = $(git config --global user.email)"
  echo "Git init.defaultBranch  = $(git config --global init.defaultBranch)"

  log "生成 SSH key"

  local ssh_key="$HOME/.ssh/id_ed25519"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [ -f "$ssh_key" ]; then
    echo "SSH key 已存在：$ssh_key，跳过生成。"
  else
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$ssh_key" -N ""
  fi
}

install_docker_engine() {
  if [ "$INSTALL_DOCKER" != "1" ]; then
    log "跳过 Docker 安装"
    return 0
  fi

  log "安装 Docker Engine / CLI / Buildx / Compose plugin"

  if need_cmd docker && docker compose version >/dev/null 2>&1; then
    echo "Docker 和 Docker Compose plugin 已存在，跳过安装。"
  else
    # 如果之前装过 Ubuntu 仓库里的旧 Docker 包，先移除，避免和 Docker 官方源冲突。
    # 新装 WSL 一般没有这些包；没有也没关系。
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
      sudo apt remove -y "$pkg" >/dev/null 2>&1 || true
    done

    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update
    sudo apt install -y \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-buildx-plugin \
      docker-compose-plugin
  fi

  log "启动 Docker 服务"

  if command -v systemctl >/dev/null 2>&1 && systemctl >/dev/null 2>&1; then
    sudo systemctl enable docker >/dev/null 2>&1 || true
    sudo systemctl start docker
  else
    warn "当前 WSL 可能没有启用 systemd，尝试用 service 启动 Docker。"
    sudo service docker start || warn "Docker 服务启动失败。重启 WSL 后再试：sudo service docker start"
  fi

  log "把当前用户加入 docker 用户组"

  if groups "$USER" | grep -qw docker; then
    echo "当前用户已经在 docker 用户组中。"
  else
    sudo usermod -aG docker "$USER"
    warn "已加入 docker 用户组，但必须退出 WSL 并在 PowerShell 执行 wsl --shutdown 后才会生效。"
  fi

  if [ "$RUN_DOCKER_TEST" = "1" ]; then
    log "验证 Docker 安装"
    sudo docker run --rm hello-world
    docker compose version || true
  else
    echo "已跳过 hello-world 验证。"
  fi
}

set_default_shell() {
  log "设置默认 shell 为 zsh"

  local zsh_path
  zsh_path="$(command -v zsh)"

  local current_shell
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"

  if [ "$current_shell" = "$zsh_path" ]; then
    echo "当前默认 shell 已经是 zsh。"
  else
    sudo chsh -s "$zsh_path" "$USER" || warn "chsh 失败。你可以手动执行：chsh -s $zsh_path"
  fi
}

main() {
  install_base_packages
  install_starship
  install_fnm
  configure_zshrc
  configure_git_and_ssh
  install_docker_engine
  set_default_shell

  log "全部完成"

  echo "下一步："
  echo "1. 退出当前 WSL：exit"
  echo "2. 回到 Windows PowerShell 执行：wsl --shutdown"
  echo "3. 重新进入 Ubuntu"
  echo "4. 验证：zsh --version && starship --version && fnm --version && git --version"
  echo "5. 验证 Docker：docker run --rm hello-world && docker compose version"
  echo "6. 查看 SSH 公钥并添加到 GitHub/GitLab：cat ~/.ssh/id_ed25519.pub"
}

main "$@"


