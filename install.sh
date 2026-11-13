#!/usr/bin/env bash
set -Eeuo pipefail

# WSL Debian 13 development environment bootstrap.
# Defaults are public-safe placeholders. Override them like:
#   GIT_NAME="your-name" GIT_EMAIL="you@example.com" bash install.sh

GIT_NAME="${GIT_NAME:-your-name}"
GIT_EMAIL="${GIT_EMAIL:-you@example.com}"
RUN_DOCKER_HELLO_WORLD="${RUN_DOCKER_HELLO_WORLD:-0}"

# A sudo-launched install still needs to write user configuration as the
# invoking user. Re-exec before any HOME-based setup or package installation.
if [[ "${BASH_SOURCE[0]:-}" == "$0" && "${EUID}" -eq 0 && \
  -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]] && \
  command -v sudo >/dev/null 2>&1 && id "${SUDO_USER}" >/dev/null 2>&1; then
  script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
  exec sudo -H -u "${SUDO_USER}" -- env \
    "GIT_NAME=${GIT_NAME}" \
    "GIT_EMAIL=${GIT_EMAIL}" \
    "RUN_DOCKER_HELLO_WORLD=${RUN_DOCKER_HELLO_WORLD}" \
    "${script_path}" "$@"
fi

STAGE=bootstrap
rc=0
trap 'rc=$?; printf "[error] stage=%s line=%s command=%s exit=%s\n" "$STAGE" "$LINENO" "$BASH_COMMAND" "$rc" >&2; exit "$rc"' ERR

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
  local exit_code=$?
  local source_line="${BASH_LINENO[0]:-${LINENO}}"
  local source_file="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  local source_command
  [[ "$exit_code" -ne 0 ]] || exit_code=1
  source_command="$(sed -n "${source_line}p" "$source_file" 2>/dev/null || true)"
  if [[ "$source_command" =~ ^[[:space:]]*die[[:space:]] && "$source_line" -gt 1 ]]; then
    local previous_command trailing_backslash=$'\\'
    previous_command="$(sed -n "$((source_line - 1))p" "$source_file" 2>/dev/null || true)"
    if [[ "$previous_command" == *"$trailing_backslash" ]]; then
      source_line=$((source_line - 1))
      source_command="${previous_command%"$trailing_backslash"} $source_command"
    fi
  fi
  [[ -n "$source_command" ]] || source_command="${BASH_COMMAND:-die}"
  printf '\n[error] stage=%s line=%s command=%s exit=%s: %s\n' \
    "$STAGE" "$source_line" "$source_command" "$exit_code" "$*" >&2
  exit "$exit_code"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_supported_system() {
  if [[ ! -f /etc/os-release ]]; then
    die "Cannot find /etc/os-release. Use Debian 13 on WSL 2."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}:${VERSION_ID:-}" in
    debian:13) ;;
    *) die "Supported system: Debian 13. Detected ${ID:-unknown}:${VERSION_ID:-unknown}." ;;
  esac

  if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]] && \
    ! grep -qi microsoft /proc/version 2>/dev/null; then
    die "This installer supports Debian 13 on WSL 2 only."
  fi

  if ! grep -qi WSL2 /proc/version 2>/dev/null && \
    ! grep -qi WSL2 /proc/sys/kernel/osrelease 2>/dev/null; then
    die "WSL 2 is required because this installer installs Docker Engine."
  fi
}

ensure_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    die "Run this script as your normal WSL user, not as root."
  fi

  command_exists sudo || die "sudo is required. Ask root to install sudo and grant this user sudo access, then log in again."
  sudo -v || die "The current user needs sudo access."
}

install_system_packages() {
  log "Updating apt packages and installing base tools"
  sudo apt update
  sudo apt upgrade -y
  local -a packages=(
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
    zenity \
    zsh \
    util-linux \
    bubblewrap \
    systemd \
    systemd-sysv \
    xdg-utils
  )

  packages+=(zsh-autosuggestions zsh-syntax-highlighting)

  sudo apt install -y "${packages[@]}"
}

configure_wsl_systemd() {
  log "Enabling systemd for WSL"

  local wsl_conf="/etc/wsl.conf"
  local tmp
  tmp="$(mktemp)"

  if [[ -f "$wsl_conf" ]]; then
    awk '
      function add_systemd_setting() {
        if (!boot_systemd_seen) print "systemd=true"
      }
      BEGIN { in_boot = 0; boot_seen = 0; boot_systemd_seen = 0 }
      /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
        if (in_boot) add_systemd_setting()
        in_boot = ($0 ~ /^[[:space:]]*\[boot\][[:space:]]*$/)
        if (in_boot) { boot_seen = 1; boot_systemd_seen = 0 }
        print
        next
      }
      in_boot && /^[[:space:]]*systemd[[:space:]]*=/ {
        if (!boot_systemd_seen) {
          print "systemd=true"
          boot_systemd_seen = 1
        }
        next
      }
      { print }
      END {
        if (in_boot) add_systemd_setting()
        if (!boot_seen) {
          if (NR > 0) print ""
          print "[boot]"
          print "systemd=true"
        }
      }
    ' "$wsl_conf" > "$tmp"
  else
    printf '[boot]\nsystemd=true\n' > "$tmp"
  fi

  sudo install -m 0644 "$tmp" "$wsl_conf"
  rm -f -- "$tmp"

  if [[ "$(< /proc/1/comm)" == systemd ]]; then
    log "systemd is already active"
  else
    log "systemd will start after restarting WSL"
  fi
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

# Only initialize/select an installed Node. Package-manager preparation belongs
# to installation or an explicit project setup step, never shell startup.
write_node_helpers() {
  mkdir -p "$HOME/.local/lib/wsl-dev"
  cat > "$HOME/.local/lib/wsl-dev/node-env.sh" <<'EOF'
# Shared by zsh (including -c), Bash startup files, and inherited BASH_ENV.
if [ -n "${BASH_VERSION:-}" ] && [ "${_wsl_node_initialized_pid:-}" = "$BASHPID" ]; then
  return 0
fi
export TMPDIR=/tmp COREPACK_HOME="$HOME/.cache/node/corepack"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0 COREPACK_ENABLE_AUTO_PIN=0 COREPACK_DEFAULT_TO_LATEST=0
export PLAYWRIGHT_MCP_BROWSER=chromium
export BASH_ENV="$HOME/.local/lib/wsl-dev/node-env.sh"
export PATH="$HOME/.local/share/fnm:$HOME/.local/bin:$PATH"

# Native zsh hooks also handle `cd project && ...` inside agent commands.
# Error-only logging keeps fnm's version messages out of command stdout.
if [ -n "${ZSH_VERSION:-}" ]; then
  _wsl_fnm_env=$(XDG_RUNTIME_DIR=/tmp command fnm env --shell zsh --use-on-cd --log-level error --version-file-strategy recursive --resolve-engines=false) || exit $?
else
  _wsl_fnm_env=$(XDG_RUNTIME_DIR=/tmp command fnm env --shell bash --version-file-strategy recursive --resolve-engines=false) || exit $?
fi
eval "$_wsl_fnm_env"
unset _wsl_fnm_env
# Use native recursive lookup/default selection, with no download prompt or
# auto-install. Exit on a missing version, including when Bash reads this file
# directly through BASH_ENV (return alone would still allow the task to run).
command fnm use --silent-if-unchanged </dev/null >&2 || exit $?
if [ -n "${BASH_VERSION:-}" ]; then
  _wsl_node_initialized_pid=$BASHPID
fi
EOF
}

install_fnm_and_node() {
  log "Installing fnm and a default Node.js LTS"
  mkdir -p "$COREPACK_HOME"
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
  export PATH="$HOME/.local/share/fnm:$HOME/.local/bin:$PATH"
  eval "$(fnm env --shell bash --resolve-engines=false)"
  fnm install --lts
  fnm default lts-latest
  fnm use default
  write_node_helpers
  # Official Corepack package and native shims for the initial LTS only.
  npm install --global --engine-strict corepack@latest
  corepack enable
  # Outside projects use Corepack's pinned built-in default, never pnpm@latest.
  COREPACK_DEFAULT_TO_LATEST=0 COREPACK_ENABLE_AUTO_PIN=0 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm --version
}

install_playwright() {
  log "Installing Playwright CLI and Chromium"

  # Use the active fnm-managed Node/npm as the normal WSL user so the global
  # CLI and browser cache stay user-owned. Playwright may elevate only for
  # official Chromium system dependencies.
  npm install --global @playwright/cli@latest
  playwright-cli install-browser chromium --with-deps
  write_playwright_launcher
}

write_playwright_launcher() {
  local node_path cli_path
  node_path="$(node -p 'require("node:fs").realpathSync(process.execPath)')"
  cli_path="$(realpath -e "$(npm root -g)/@playwright/cli/playwright-cli.js")" || \
    die "The global Playwright CLI entry point could not be resolved."
  [[ -x "$node_path" && -f "$cli_path" ]] || die "The global Playwright CLI runtime is incomplete."
  cat > "$HOME/.local/bin/playwright-cli" <<'EOF'
#!/usr/bin/env -S BASH_ENV= bash
# Global automation CLI owns its bootstrap runtime; projects own their Playwright.
EOF
  printf 'exec %q %q "$@"\n' "$node_path" "$cli_path" >> "$HOME/.local/bin/playwright-cli"
  chmod 755 "$HOME/.local/bin/playwright-cli"
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
# Initialize project Node even in zsh -c (Codex), before .zshrc.
source "$HOME/.local/lib/wsl-dev/node-env.sh" || exit $?
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
EOF
  printf '%s\n' "$end" >> "$tmp"

  mv "$tmp" "$zshrc"
}

configure_bash() {
  local file
  for file in "$HOME/.bashrc" "$HOME/.profile"; do
    # shellcheck disable=SC2016
    printf '\n# WSL project Node initialization\n[ -z "${BASH_VERSION:-}" ] || . "$HOME/.local/lib/wsl-dev/node-env.sh" || exit $?\n' >> "$file"
  done
}

verify_installation() {
  log "Verifying Starship"
  "$HOME/.local/bin/starship" --version
  log "Verifying tools in new interactive and non-interactive shells"
  local check='set -e; command -v fnm node npm corepack pnpm playwright-cli; node --version; npm --version; corepack --version; pnpm --version; playwright-cli --version'
  # Use a project-free directory, with no inherited multishell or manual choice.
  (cd /tmp; unset FNM_MULTISHELL_PATH WSL_FNM_EXPLICIT; zsh -c "$check"; zsh -lc "$check"; zsh -ic "$check"; BASH_ENV="$HOME/.local/lib/wsl-dev/node-env.sh" bash -c "$check")
  log "Verifying Docker daemon and Compose"
  sudo docker info >/dev/null
  docker compose version
  log "Launching installed Chromium using the global CLI's own Playwright"
  node - "$(npm root -g)/@playwright/cli" <<'EOF'
const {createRequire} = require('node:module');
const path = require('node:path');
const cliRequire = createRequire(path.join(process.argv[2], 'package.json'));
(async () => {
  const {chromium} = cliRequire('playwright-core');
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage();
    await page.setContent('<title>WSL Chromium check</title>');
    if (await page.title() !== 'WSL Chromium check') throw new Error('Chromium page check failed');
    console.log('Chromium launch OK:', browser.version());
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
EOF
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

  local codename arch distro=debian
  # shellcheck disable=SC1091
  . /etc/os-release
  codename="${VERSION_CODENAME:?Missing VERSION_CODENAME in /etc/os-release}"
  arch="$(dpkg --print-architecture)"

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${distro}/gpg" | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/${distro}
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  if [[ "$(< /proc/1/comm)" == systemd ]]; then
    sudo systemctl enable --now docker || die "Failed to enable or start Docker."
  else
    sudo systemctl enable docker || die "Failed to enable Docker for the next WSL start."
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
  local restart_reason="systemd, Docker, zsh, and docker group membership take effect"

  cat <<EOF

Done. Starship prompt configured.

Recommended next steps:
  1. Exit the WSL distribution.
  2. Run this in PowerShell: wsl --shutdown
  3. Start the WSL distribution again so ${restart_reason}.

After restarting, run these inside Debian as your normal user (without sudo):
  ps -p 1 -o comm=
  systemctl is-active docker
  docker info
  docker compose version
  command -v node npm corepack pnpm playwright-cli
  node --version
  corepack --version
  pnpm --version
  playwright-cli --version
Expect systemd as PID 1, Docker active, and all commands to succeed.

In a project (or its subdirectories), use node/npm/pnpm normally.
The nearest .node-version selects Node; packageManager selects pnpm.
For a new Node version, run fnm install / fnm use, then install compatible
Corepack and run corepack enable. Shell startup never installs or repairs tools.
fnm use / fnm exec use native fnm behavior; new shells select their own project.
Project Playwright versions may require their own browser downloads.

EOF

  printf '\nYour SSH public key:\n'
  if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
    cat "$HOME/.ssh/id_ed25519.pub"
  else
    warn "No SSH public key found."
  fi
}

main() {
  local step

  for step in ensure_supported_system ensure_sudo \
    install_system_packages configure_wsl_systemd install_starship \
    install_fnm_and_node install_playwright configure_zshenv configure_zshrc \
    configure_bash set_default_shell_to_zsh configure_git_and_ssh; do
    STAGE="$step"
    "$step"
  done

  STAGE=install_docker
  install_docker

  for step in configure_bubblewrap_apparmor verify_installation print_next_steps; do
    STAGE="$step"
    "$step"
  done
}

# Allow isolated verification to source functions without running installation.
if [[ "${BASH_SOURCE[0]:-}" == "$0" || -z "${BASH_SOURCE[0]:-}" ]]; then
  main "$@"
fi
