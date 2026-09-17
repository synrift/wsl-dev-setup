#!/usr/bin/env bash
set -Eeuo pipefail

# WSL Ubuntu 24.04 development environment bootstrap.
# Defaults are public-safe placeholders. Override them like:
#   GIT_NAME="your-name" GIT_EMAIL="you@example.com" bash install.sh

GIT_NAME="${GIT_NAME:-your-name}"
GIT_EMAIL="${GIT_EMAIL:-you@example.com}"
RUN_DOCKER_HELLO_WORLD="${RUN_DOCKER_HELLO_WORLD:-0}"

# Keep Linux tools on the WSL filesystem from the beginning of the install.
# Windows passes TEMP and TMP into WSL, but TMPDIR takes precedence for Node.js
# and other Unix tools without breaking Windows executables invoked via WSL.
export TMPDIR=/tmp

# Windows also passes LOCALAPPDATA into WSL. Corepack considers that variable
# when selecting its cache and can otherwise try to use a /mnt/c/... path.
# Keep Corepack and its package-manager downloads on the Linux filesystem.
export COREPACK_HOME="$HOME/.cache/node/corepack"

log() {
  printf '\n\033[1;36m==> %s\033[0m\n' "$*"
}

warn() {
  printf '\n\033[1;33m[warn]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\n\033[1;31m[error]\033[0m %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_ubuntu_wsl() {
  if [[ ! -f /etc/os-release ]]; then
    die "Cannot find /etc/os-release. Please run this inside Ubuntu on WSL."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    die "This script is intended for Ubuntu on WSL. Detected ID=${ID:-unknown}."
  fi

  if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]] && ! grep -qi microsoft /proc/version 2>/dev/null; then
    warn "This does not look like WSL. Continuing because the commands are still valid for Ubuntu."
  fi
}

ensure_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    die "Run this script as your normal WSL user, not as root."
  fi

  sudo -v
}

install_system_packages() {
  log "Updating apt packages and installing base tools"
  sudo apt update
  sudo apt upgrade -y
  sudo apt install -y \
    build-essential \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
    pkg-config \
    python3 \
    ripgrep \
    unzip \
    zoxide \
    zsh \
    zsh-autosuggestions \
    zsh-syntax-highlighting \
    bubblewrap
}

configure_bubblewrap_apparmor() {
  log "Checking AppArmor support for Bubblewrap"

  local apparmor_enabled
  local userns_restricted
  local profile_source
  local profile_target

  apparmor_enabled="$(
    cat /sys/module/apparmor/parameters/enabled 2>/dev/null || true
  )"
  userns_restricted="$(
    cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || true
  )"

  if [[ "$apparmor_enabled" != "Y" ]]; then
    log "AppArmor is not enabled; skipping Bubblewrap profile"
    return
  fi

  if [[ "$userns_restricted" != "1" ]]; then
    log "AppArmor user namespace restriction is not active; skipping Bubblewrap profile"
    return
  fi

  log "Installing the Bubblewrap AppArmor profile"
  sudo apt install -y apparmor-profiles apparmor-utils || \
    die "Failed to install Bubblewrap AppArmor dependencies."

  profile_source="/usr/share/apparmor/extra-profiles/bwrap-userns-restrict"
  profile_target="/etc/apparmor.d/bwrap-userns-restrict"

  if [[ ! -f "$profile_source" ]]; then
    die "Bubblewrap AppArmor profile was not found at $profile_source."
  fi

  sudo install -m 0644 "$profile_source" "$profile_target" || \
    die "Failed to install the Bubblewrap AppArmor profile."
  sudo apparmor_parser -r "$profile_target" || \
    die "Failed to load the Bubblewrap AppArmor profile."

  log "Bubblewrap AppArmor profile loaded"
}

install_starship() {
  log "Installing Starship"
  mkdir -p "$HOME/.local/bin"

  if command_exists starship || [[ -x "$HOME/.local/bin/starship" ]]; then
    log "Starship already exists; running installer to keep it current"
  fi

  curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"

  mkdir -p "$HOME/.config"
  "$HOME/.local/bin/starship" preset pastel-powerline -o "$HOME/.config/starship.toml" >/dev/null
}

install_fnm_and_node() {
  log "Installing fnm, Node.js LTS, Corepack, and pnpm"

  mkdir -p "$COREPACK_HOME"

  if ! command_exists fnm && [[ ! -x "$HOME/.local/share/fnm/fnm" ]]; then
    curl -fsSL https://fnm.vercel.app/install | bash
  else
    log "fnm already exists; skipping fnm installer"
  fi

  export PATH="$HOME/.local/share/fnm:$PATH"
  if command_exists fnm; then
    eval "$(fnm env --use-on-cd --shell bash)"
  elif [[ -x "$HOME/.local/share/fnm/fnm" ]]; then
    eval "$("$HOME/.local/share/fnm/fnm" env --use-on-cd --shell bash)"
  else
    die "fnm installation did not produce an executable."
  fi

  fnm install --lts
  fnm default lts-latest
  fnm use lts-latest

  # Keep the npm version bundled with Node.js. Corepack selects the pnpm
  # version declared by each project's packageManager field.
  npm install --global corepack@latest
  corepack enable pnpm
  corepack install --global pnpm@latest
}

install_playwright() {
  log "Installing Playwright CLI and Chromium"

  # Use the active fnm-managed Node/npm as the normal WSL user so the global
  # CLI and browser cache stay user-owned. Playwright may elevate only for
  # official Chromium system dependencies.
  npm install --global @playwright/cli@latest
  playwright-cli install-browser chromium --with-deps
}

configure_zshenv() {
  log "Configuring ~/.zshenv"
  local zshenv="$HOME/.zshenv"
  local begin="# >>> codex-wsl-dev-env >>>"
  local end="# <<< codex-wsl-dev-env <<<"
  local tmp
  tmp="$(mktemp)"

  touch "$zshenv"

  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$zshenv" > "$tmp"

  cat >> "$tmp" <<'EOF'

# >>> codex-wsl-dev-env >>>
# Keep the default fnm-managed Node.js available to non-interactive shells,
# including commands launched by Codex Desktop in WSL.
typeset -U path PATH
path=(
  "$HOME/.local/share/fnm/aliases/default/bin"
  "$HOME/.local/bin"
  "$HOME/.local/share/fnm"
  $path
)
export PATH

# Use WSL's native Linux temporary directory for Node.js and Unix tooling.
# Leave TEMP and TMP unchanged for compatibility with Windows executables.
export TMPDIR=/tmp

# Prevent Windows LOCALAPPDATA inherited by WSL from redirecting Corepack's
# package-manager cache to /mnt/c. Keep it on the Linux filesystem instead.
export COREPACK_HOME="$HOME/.cache/node/corepack"

# Default Playwright CLI/MCP automation to Playwright-managed Chromium.
export PLAYWRIGHT_MCP_BROWSER=chromium
# <<< codex-wsl-dev-env <<<
EOF

  mv "$tmp" "$zshenv"
}

configure_zshrc() {
  log "Configuring ~/.zshrc"
  local zshrc="$HOME/.zshrc"
  local begin="# >>> codex-wsl-dev-env >>>"
  local end="# <<< codex-wsl-dev-env <<<"
  local tmp
  tmp="$(mktemp)"

  touch "$zshrc"

  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$zshrc" > "$tmp"

  cat >> "$tmp" <<'EOF'

# >>> codex-wsl-dev-env >>>
autoload -Uz compinit
compinit

if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

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
alias ls="ls --color=auto"
alias l="ls -lah --color=auto"
alias la="ls -lAh --color=auto"
alias ll="ls -lh --color=auto"
alias lsa="ls -lah --color=auto"

if [ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

if [ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
# <<< codex-wsl-dev-env <<<
EOF

  mv "$tmp" "$zshrc"
}

set_default_shell_to_zsh() {
  log "Setting zsh as the default shell"
  local zsh_path
  zsh_path="$(command -v zsh)"

  if [[ "${SHELL:-}" == "$zsh_path" ]] || getent passwd "$USER" | awk -F: '{print $7}' | grep -qx "$zsh_path"; then
    log "Default shell is already zsh"
    return
  fi

  sudo chsh -s "$zsh_path" "$USER"
}

configure_git_and_ssh() {
  log "Configuring Git identity"
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main

  log "Ensuring an ed25519 SSH key exists"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    log "SSH key already exists at ~/.ssh/id_ed25519"
  else
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$HOME/.ssh/id_ed25519" -N ""
  fi
}

install_docker() {
  log "Installing Docker Engine and Compose plugin"

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  local codename arch
  # shellcheck disable=SC1091
  . /etc/os-release
  codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  arch="$(dpkg --print-architecture)"

  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  if command_exists systemctl && systemctl list-unit-files docker.service >/dev/null 2>&1; then
    if ! sudo systemctl enable --now docker; then
      warn "Could not start Docker with systemctl; trying service."
      sudo service docker start || die "Failed to start Docker."
    fi
  else
    sudo service docker start || die "Failed to start Docker."
  fi

  sudo docker info >/dev/null || die "Docker daemon is not available."

  if getent group docker >/dev/null; then
    sudo usermod -aG docker "$USER"
  fi

  docker compose version || die "Docker Compose plugin is not available."

  if [[ "$RUN_DOCKER_HELLO_WORLD" == "1" ]]; then
    sudo docker run hello-world
  fi
}

print_next_steps() {
  cat <<EOF

Done.

Recommended next steps:
  1. Exit Ubuntu.
  2. Run this in PowerShell: wsl --shutdown
  3. Start Ubuntu again so zsh and the docker group membership take effect.

Your SSH public key:
EOF

  if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
    cat "$HOME/.ssh/id_ed25519.pub"
  else
    warn "No SSH public key found."
  fi
}

main() {
  ensure_ubuntu_wsl
  ensure_sudo
  install_system_packages
  install_starship
  install_fnm_and_node
  install_playwright
  configure_zshenv
  configure_zshrc
  set_default_shell_to_zsh
  configure_git_and_ssh
  install_docker
  configure_bubblewrap_apparmor
  print_next_steps
}

main "$@"
