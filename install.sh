#!/usr/bin/env bash
set -Eeuo pipefail

# WSL Ubuntu 24.04 / Debian 13 development environment bootstrap.
# Defaults are public-safe placeholders. Override them like:
#   GIT_NAME="your-name" GIT_EMAIL="you@example.com" bash install.sh

GIT_NAME="${GIT_NAME:-your-name}"
GIT_EMAIL="${GIT_EMAIL:-you@example.com}"
RUN_DOCKER_HELLO_WORLD="${RUN_DOCKER_HELLO_WORLD:-0}"
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
    die "Cannot find /etc/os-release. Use Ubuntu 24.04 or Debian 13 on WSL."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}:${VERSION_ID:-}" in
    ubuntu:24.04 | debian:13) ;;
    *) die "Supported systems: Ubuntu 24.04 and Debian 13. Detected ${ID:-unknown}:${VERSION_ID:-unknown}." ;;
  esac

  if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]] && ! grep -qi microsoft /proc/version 2>/dev/null; then
    warn "This does not look like WSL. Continuing on ${PRETTY_NAME:-$ID}."
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
    util-linux \
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

# This helper prepares Corepack for the ACTIVE Node. It never selects Node,
# parses project files, or proxies node/npm/npx. Native Corepack owns pnpm.
write_node_helpers() {
  mkdir -p "$HOME/.local/lib/wsl-dev" "$HOME/.local/bin" "$HOME/.local/share/wsl-dev"
  touch "$HOME/.local/share/wsl-dev/node.lock"
  cat > "$HOME/.local/lib/wsl-dev/prepare-node" <<'EOF'
#!/usr/bin/env -S BASH_ENV= bash
set -Eeuo pipefail
stage=corepack-bootstrap
rc=0
trap 'rc=$?; printf "[error] stage=%s line=%s command=%s exit=%s\n" "$stage" "$LINENO" "$BASH_COMMAND" "$rc" >&2; exit "$rc"' ERR
export TMPDIR=/tmp
export COREPACK_HOME="$HOME/.cache/node/corepack"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export COREPACK_ENABLE_AUTO_PIN=0
export COREPACK_DEFAULT_TO_LATEST=0
node_path="$(node -p 'process.execPath')"
node_bin="${node_path%/*}"
# Pins and engines: github.com/nodejs/corepack/blob/v<VERSION>/package.json.
# Refuse unsupported runtimes rather than silently upgrading a project's Node.
corepack_version="$("$node_path" -e '
const [a,b,c] = process.versions.node.split(".").map(Number);
if (a >= 24 || a === 22 && b >= 11 || a === 20 && b >= 10) console.log("0.34.6");
else if (a === 18 && (b > 17 || b === 17 && c >= 1) || a === 23) console.log("0.31.0");
else if (a === 21 || a === 22) console.log("0.29.4");
else if (a > 16 || a === 16 && b >= 20) console.log("0.20.0");
else { console.error("Unsupported Node " + process.version + " for configured Corepack releases; Node was not changed."); process.exit(1); }
')"
cache="$HOME/.local/share/wsl-dev/corepack"
package="$cache/$corepack_version/node_modules/corepack"
keys_fresh=0
if [[ -f "$cache/npm-keys.json" ]]; then
  keys_age=$(( $(date +%s) - $(stat -c %Y "$cache/npm-keys.json") ))
  if (( keys_age < 2592000 )); then keys_fresh=1; fi
fi
# Prepared tools must work when Codex permits only read access to HOME.
if [[ -f "$cache/npm-keys.json" && ( "$keys_fresh" == 1 || ! -w "$cache" ) && \
      -f "$package/dist/corepack.js" && \
      -x "$node_bin/corepack" && -x "$node_bin/pnpm" && \
      "$(readlink "$node_bin/corepack" || true)" == "$package/dist/corepack.js" && \
      "$(readlink -f "$node_bin/pnpm" || true)" == "$package/dist/pnpm.js" ]]; then
  export COREPACK_INTEGRITY_KEYS
  COREPACK_INTEGRITY_KEYS="$(cat "$cache/npm-keys.json")"
  # Corepack 0.20's package-manager cache replacement is not atomic. Warm the
  # selected pnpm while holding our lock so simultaneous Node 16 shells cannot
  # race on a cold package-manager cache.
  if [[ "$corepack_version" == 0.20.0 ]]; then
    stage=corepack-pnpm-cache
    if [[ -w "$cache" ]]; then
      exec 9> "$cache/prepare.lock"
      flock 9
      "$node_bin/pnpm" --version >&2
      flock -u 9
      exec 9>&-
    else
      "$node_bin/pnpm" --version >&2
    fi
  fi
  if [[ "${1:-}" == --run ]]; then
    shift
    export BASH_ENV="$HOME/.local/lib/wsl-dev/node-env.sh"
    exec "$@"
  fi
  exit 0
fi
mkdir -p "$cache"
# One lock covers install/publication/shims. Never keep it during user commands.
exec 9> "$cache/prepare.lock"
flock 9
# Refresh registry keys every 30 days while holding the cache lock. Keep the
# previous valid file if a scheduled refresh cannot reach the registry.
keys_refresh=1
if [[ -f "$cache/npm-keys.json" ]]; then
  keys_age=$(( $(date +%s) - $(stat -c %Y "$cache/npm-keys.json") ))
  if (( keys_age < 2592000 )); then keys_refresh=0; fi
fi
if [[ "$keys_refresh" == 1 ]]; then
  if [[ -f "$cache/npm-keys.json" ]]; then
    stage=corepack-keys-refresh
  else
    stage=corepack-keys
  fi
  key_scratch="$(mktemp "$cache/.keys.XXXXXX")"
  trap 'rm -rf -- "${scratch:-}" "${key_scratch:-}"' EXIT
  if curl -fsSL --retry 3 https://registry.npmjs.org/-/npm/v1/keys | \
    jq -e '{npm: .keys} | select(.npm | type == "array" and length > 0)' > "$key_scratch"; then
    mv "$key_scratch" "$cache/npm-keys.json"
    key_scratch=
  else
    keys_rc=$?
    rm -f -- "$key_scratch"
    key_scratch=
    if [[ -s "$cache/npm-keys.json" ]]; then
      printf '[warn] stage=corepack-keys-refresh line=%s command=curl/jq exit=%s; using cached signing keys\n' "$LINENO" "$keys_rc" >&2
    else
      printf '[error] stage=corepack-keys line=%s command=curl/jq exit=%s\n' "$LINENO" "$keys_rc" >&2
      exit "$keys_rc"
    fi
  fi
fi
package="$cache/$corepack_version/node_modules/corepack"
if [[ ! -f "$package/dist/corepack.js" ]]; then
  stage=corepack-install
  scratch="$(mktemp -d "$cache/.install.XXXXXX")"
  trap 'rm -rf -- "${scratch:-}"' EXIT
  "$node_path" "$node_bin/../lib/node_modules/npm/bin/npm-cli.js" install \
    --prefix "$scratch" --engine-strict --ignore-scripts --no-audit --no-fund \
    --package-lock=false "corepack@$corepack_version" >&2
  mv "$scratch" "$cache/$corepack_version"
  scratch=
fi
export COREPACK_INTEGRITY_KEYS
# Corepack 0.20 predates npm signing-key verification; newer pinned releases
# receive the current registry keys and verify package-manager signatures.
COREPACK_INTEGRITY_KEYS="$(cat "$cache/npm-keys.json")"
stage=corepack-enable
if [[ "$(readlink "$node_bin/corepack" || true)" != "$package/dist/corepack.js" ]]; then
  ln -sfn "$package/dist/corepack.js" "$node_bin/corepack"
fi
if [[ ! -x "$node_bin/pnpm" || "$(readlink -f "$node_bin/pnpm")" != "$package/dist/pnpm.js" ]]; then
  "$node_path" "$package/dist/corepack.js" enable --install-directory "$node_bin" pnpm >&2
fi
if [[ "$corepack_version" == 0.20.0 ]]; then
  stage=corepack-pnpm-cache
  "$node_bin/pnpm" --version >&2
fi
flock -u 9
exec 9>&-
case "${1:-}" in
  --run) shift; export BASH_ENV="$HOME/.local/lib/wsl-dev/node-env.sh"; exec "$@" ;;
esac
EOF
  chmod 755 "$HOME/.local/lib/wsl-dev/prepare-node"
  cat > "$HOME/.local/lib/wsl-dev/node-env.sh" <<'EOF'
# Sourced by zsh (all modes) and bash. No output on stdout during startup.
export TMPDIR=/tmp COREPACK_HOME="$HOME/.cache/node/corepack"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0 COREPACK_ENABLE_AUTO_PIN=0 COREPACK_DEFAULT_TO_LATEST=0
export PLAYWRIGHT_MCP_BROWSER=chromium
export BASH_ENV="$HOME/.local/lib/wsl-dev/node-env.sh"
# fnm exec prepends a concrete installation bin; preserve its explicit context.
_wsl_inherited_node=$(command -v node 2>/dev/null || true)
case "$_wsl_inherited_node" in
  "${FNM_DIR:-$HOME/.local/share/fnm}"/node-versions/*/installation/bin/node) export WSL_FNM_EXPLICIT=1 ;;
esac
_wsl_inherited_version=
if [ "${WSL_FNM_EXPLICIT:-0}" = 1 ]; then
  _wsl_inherited_version=$(node --version) || exit $?
fi
export PATH="$HOME/.local/share/fnm:$HOME/.local/bin:$PATH"
if [ -n "${ZSH_VERSION:-}" ]; then
  _wsl_fnm_env=$(XDG_RUNTIME_DIR=/tmp command fnm env --shell zsh --version-file-strategy recursive --resolve-engines=false) || exit $?
  eval "$_wsl_fnm_env"
else
  _wsl_fnm_env=$(XDG_RUNTIME_DIR=/tmp command fnm env --shell bash --version-file-strategy recursive --resolve-engines=false) || exit $?
  eval "$_wsl_fnm_env"
fi
_wsl_node_select() {
  local dir declared=0 rc
  # fnm resolves version files against the real directory. Match that when
  # the shell entered through a symlink, including links to project children.
  dir=$(pwd -P) || return $?
  while :; do
    if [ -f "$dir/.node-version" ] || [ -f "$dir/.nvmrc" ]; then declared=1; break; fi
    [ "$dir" = / ] && break
    dir=${dir%/*}; [ -n "$dir" ] || dir=/
  done
  if [ "$declared" = 1 ]; then
    # Native recursive lookup, with serialized first installation.
    # Open the existing lock read-only: flock itself does not alter the file.
    if flock -x "$HOME/.local/share/wsl-dev/node.lock" fnm use --install-if-missing >&2; then
      :
    else
      rc=$?
      printf '[error] stage=node-select line=%s command=fnm use --install-if-missing exit=%s\n' "$LINENO" "$rc" >&2
      return "$rc"
    fi
    unset WSL_FNM_EXPLICIT
  elif [ ! -x "$FNM_MULTISHELL_PATH/bin/node" ]; then
    if command fnm use default >&2; then
      :
    else
      rc=$?
      printf '[error] stage=node-select line=%s command=fnm use default exit=%s\n' "$LINENO" "$rc" >&2
      return "$rc"
    fi
  fi
  if "$HOME/.local/lib/wsl-dev/prepare-node"; then
    :
  else
    rc=$?
    printf '[error] stage=node-prepare line=%s command=prepare-node exit=%s\n' "$LINENO" "$rc" >&2
    return "$rc"
  fi
  export COREPACK_INTEGRITY_KEYS
  if COREPACK_INTEGRITY_KEYS=$(cat "$HOME/.local/share/wsl-dev/corepack/npm-keys.json"); then
    :
  else
    rc=$?
    printf '[error] stage=corepack-keys line=%s command=cat npm-keys.json exit=%s\n' "$LINENO" "$rc" >&2
    return "$rc"
  fi
}
# fnm remains the native version manager. Only successful manual `use` gets
# an inheritance marker; `exec` keeps native option/version parsing below.
fnm() {
  local action= rc
  local -a global_opts=() exec_opts=()
  # fnm's global flags can precede the subcommand. Keep them native while
  # locating explicit `use` / `exec` invocations that need a child marker.
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --fnm-dir|--log-level|--arch|--node-dist-mirror|--version-file-strategy)
        [ "$#" -ge 2 ] || { command fnm "${global_opts[@]}" "$@"; return; }
        global_opts+=("$1" "$2"); shift 2 ;;
      --resolve-engines)
        shift
        if [ "${1:-}" = true ] || [ "${1:-}" = false ]; then
          global_opts+=("--resolve-engines=$1"); shift
        else
          global_opts+=(--resolve-engines=true)
        fi ;;
      --fnm-dir=*|--log-level=*|--arch=*|--node-dist-mirror=*|--version-file-strategy=*|--resolve-engines=*)
        global_opts+=("$1"); shift ;;
      --corepack-enabled)
        global_opts+=("$1"); shift ;;
      -h|--help|-V|--version)
        command fnm "${global_opts[@]}" "$@"; return ;;
      -*) command fnm "${global_opts[@]}" "$@"; return ;;
      *) action=$1; shift; break ;;
    esac
  done
  [ -n "$action" ] || { command fnm "${global_opts[@]}" "$@"; return; }
  if [ "$action" = exec ]; then
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --using|--fnm-dir|--log-level|--arch|--node-dist-mirror|--version-file-strategy)
          [ "$#" -ge 2 ] || { command fnm "${global_opts[@]}" exec "${exec_opts[@]}" "$@"; return; }
          exec_opts+=("$1" "$2"); shift 2 ;;
        --resolve-engines)
          shift
          if [ "${1:-}" = true ] || [ "${1:-}" = false ]; then
            exec_opts+=("--resolve-engines=$1"); shift
          else
            # fnm's option takes an optional value. Use the explicit form so
            # our injected helper cannot be mistaken for that value.
            exec_opts+=(--resolve-engines=true)
          fi ;;
        --using=*|--fnm-dir=*|--log-level=*|--arch=*|--node-dist-mirror=*|--version-file-strategy=*|--resolve-engines=*)
          exec_opts+=("$1"); shift ;;
        --corepack-enabled|--using-file) exec_opts+=("$1"); shift ;;
        --) shift; break ;;
        -*) command fnm "${global_opts[@]}" exec "${exec_opts[@]}" "$@"; return ;;
        *) break ;;
      esac
    done
    [ "$#" -gt 0 ] || { command fnm "${global_opts[@]}" exec "${exec_opts[@]}"; return; }
    WSL_FNM_EXPLICIT=1 command fnm "${global_opts[@]}" exec "${exec_opts[@]}" "$HOME/.local/lib/wsl-dev/prepare-node" --run "$@"
    return
  fi
  if [ "$action" = use ]; then
    if flock -x "$HOME/.local/share/wsl-dev/node.lock" fnm "${global_opts[@]}" use "$@"; then
      rc=0
    else
      rc=$?
    fi
  else
    if command fnm "${global_opts[@]}" "$action" "$@"; then
      rc=0
    else
      rc=$?
    fi
  fi
  [ "$rc" = 0 ] || return "$rc"
  if [ "$action" = use ]; then
    export WSL_FNM_EXPLICIT=1
    "$HOME/.local/lib/wsl-dev/prepare-node" || return
    export COREPACK_INTEGRITY_KEYS
    COREPACK_INTEGRITY_KEYS=$(cat "$HOME/.local/share/wsl-dev/corepack/npm-keys.json") || return
  fi
}
if [ -n "$_wsl_inherited_version" ]; then
  command fnm use "$_wsl_inherited_version" >&2 || exit $?
  "$HOME/.local/lib/wsl-dev/prepare-node" || exit $?
  export COREPACK_INTEGRITY_KEYS
  COREPACK_INTEGRITY_KEYS=$(cat "$HOME/.local/share/wsl-dev/corepack/npm-keys.json") || exit $?
else
  _wsl_node_select || { _wsl_rc=$?; exit "$_wsl_rc"; }
fi
unset _wsl_inherited_node _wsl_inherited_version _wsl_fnm_env
if [ -n "${ZSH_VERSION:-}" ]; then
  _wsl_node_restoring_dir=0
  _wsl_node_chpwd_ran=0
  _wsl_node_chpwd_status=0
  _wsl_node_chpwd_select() {
    [ "${_wsl_node_restoring_dir:-0}" = 1 ] && return 0
    _wsl_node_chpwd_ran=1
    local old_dir="${1:-${OLDPWD:-}}" failed_dir="$PWD" old_version old_explicit old_rc
    old_version=$(command node --version 2>/dev/null || true)
    old_explicit="${WSL_FNM_EXPLICIT:-}"
    if _wsl_node_select; then
      _wsl_node_chpwd_status=0
      return 0
    else
      old_rc=$?
    fi
    _wsl_node_chpwd_status=$old_rc
    if [ -n "$old_dir" ] && [ -d "$old_dir" ] && [ "$old_dir" != "$PWD" ]; then
      printf '[error] stage=node-select line=%s command=cd\ %s exit=%s; restoring %s\n' "$LINENO" "$failed_dir" "$old_rc" "$old_dir" >&2
      _wsl_node_restoring_dir=1
      builtin cd -- "$old_dir" >/dev/null 2>&1 || true
      _wsl_node_restoring_dir=0
    fi
    # Preparation can fail after fnm switched Node even when `cd .` leaves
    # the directory unchanged. Restore the runtime and manual choice too.
    if [ -n "$old_version" ]; then
      flock -x "$HOME/.local/share/wsl-dev/node.lock" fnm use "$old_version" >&2 || true
    fi
    if [ -n "$old_explicit" ]; then export WSL_FNM_EXPLICIT="$old_explicit"; else unset WSL_FNM_EXPLICIT; fi
    return "$old_rc"
  }
  _wsl_node_check_navigation() {
    local old_dir="$1"
    if [ "$_wsl_node_chpwd_ran" = 1 ]; then
      return "$_wsl_node_chpwd_status"
    fi
    [ "$PWD" != "$old_dir" ] || return 0
    _wsl_node_chpwd_select || return $?
    return 0
  }
  cd() {
    local old_dir="$PWD"
    _wsl_node_chpwd_ran=0
    _wsl_node_chpwd_status=0
    builtin cd "$@" || return
    if [ "$_wsl_node_chpwd_ran" = 1 ]; then
      local rc="$_wsl_node_chpwd_status"
      _wsl_node_chpwd_ran=0
      return "$rc"
    fi
    _wsl_node_chpwd_select "$old_dir"
  }
  pushd() {
    local old_dir="$PWD" rc navigation_rc
    local -a old_stack=("${dirstack[@]}")
    _wsl_node_chpwd_ran=0
    _wsl_node_chpwd_status=0
    if builtin pushd "$@"; then navigation_rc=0; else return $?; fi
    if _wsl_node_check_navigation "$old_dir"; then
      return "$navigation_rc"
    else
      rc=$?
      if [ "$PWD" != "$old_dir" ]; then
        _wsl_node_restoring_dir=1
        builtin cd -- "$old_dir" >/dev/null 2>&1 || true
        _wsl_node_restoring_dir=0
      fi
      dirstack=("${old_stack[@]}")
      return "$rc"
    fi
  }
  popd() {
    local old_dir="$PWD" rc navigation_rc
    local -a old_stack=("${dirstack[@]}")
    _wsl_node_chpwd_ran=0
    _wsl_node_chpwd_status=0
    if builtin popd "$@"; then navigation_rc=0; else return $?; fi
    if _wsl_node_check_navigation "$old_dir"; then
      return "$navigation_rc"
    else
      rc=$?
      if [ "$PWD" != "$old_dir" ]; then
        _wsl_node_restoring_dir=1
        builtin cd -- "$old_dir" >/dev/null 2>&1 || true
        _wsl_node_restoring_dir=0
      fi
      dirstack=("${old_stack[@]}")
      return "$rc"
    fi
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook -d chpwd _wsl_node_select _wsl_node_chpwd_select 2>/dev/null || true
  add-zsh-hook chpwd _wsl_node_chpwd_select
else
  # Bash has no chpwd hook. Check every directory-changing builtin, and keep
  # its directory stack intact when project preparation fails.
  _wsl_node_navigate() {
    local action="$1" old_dir="$PWD" old_version old_explicit failed_dir rc i
    local -a old_stack=("${DIRSTACK[@]}")
    shift
    old_version=$(command node --version 2>/dev/null || true)
    old_explicit="${WSL_FNM_EXPLICIT:-}"
    builtin "$action" "$@" || return
    if [ "$action" != cd ] && [ "$PWD" = "$old_dir" ]; then return 0; fi
    if _wsl_node_select; then
      return 0
    else
      rc=$?
    fi
    failed_dir="$PWD"
    builtin cd -- "$old_dir" >/dev/null 2>&1 || true
    builtin dirs -c
    for ((i=${#old_stack[@]}-1; i>0; i--)); do
      builtin pushd -n -- "${old_stack[i]}" >/dev/null
    done
    if [ -n "$old_version" ]; then
      flock -x "$HOME/.local/share/wsl-dev/node.lock" fnm use "$old_version" >&2 || true
    fi
    if [ -n "$old_explicit" ]; then export WSL_FNM_EXPLICIT="$old_explicit"; else unset WSL_FNM_EXPLICIT; fi
    printf '[error] stage=node-select line=%s command=%s\ %s exit=%s; restored %s\n' "$LINENO" "$action" "$failed_dir" "$rc" "$old_dir" >&2
    return "$rc"
  }
  cd() { _wsl_node_navigate cd "$@"; }
  pushd() { _wsl_node_navigate pushd "$@"; }
  popd() { _wsl_node_navigate popd "$@"; }
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
  "$HOME/.local/lib/wsl-dev/prepare-node"
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

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
  # zoxide normally calls builtin cd directly, so route its jumps through the
  # checked wrapper above and return project-selection failures to the caller.
  __zoxide_cd() { cd -- "$@"; }
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

configure_bash() {
  local file
  for file in "$HOME/.bashrc" "$HOME/.profile"; do
    # shellcheck disable=SC2016
    printf '\n# WSL project Node initialization\n[ -z "${BASH_VERSION:-}" ] || . "$HOME/.local/lib/wsl-dev/node-env.sh" || exit $?\n' >> "$file"
  done
}

verify_installation() {
  log "Verifying tools in new interactive and non-interactive shells"
  local check='set -e; command -v fnm node npm corepack pnpm playwright-cli; node --version; npm --version; corepack --version; pnpm --version; playwright-cli --version'
  # Use a project-free directory, with no inherited multishell or manual choice.
  (cd /tmp; unset FNM_MULTISHELL_PATH WSL_FNM_EXPLICIT; zsh -lc "$check"; zsh -ic "$check"; BASH_ENV="$HOME/.local/lib/wsl-dev/node-env.sh" bash -c "$check")
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

  local codename arch distro
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu | debian) distro="$ID" ;;
    *) die "Unsupported Docker distribution: ${ID:-unknown}." ;;
  esac
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
  local restart_reason="zsh and the docker group membership take effect"

  cat <<EOF

Done.

Recommended next steps:
  1. Exit the WSL distribution.
  2. Run this in PowerShell: wsl --shutdown
  3. Start the WSL distribution again so ${restart_reason}.

In a project (or its subdirectories), use node/npm/pnpm normally.
The nearest .node-version selects Node; packageManager selects pnpm.
Missing Node/Corepack/pnpm downloads require network access on first use.
Manual fnm use / fnm exec overrides are preserved.
Project Playwright versions may require their own browser downloads.

Your SSH public key:
EOF

  if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
    cat "$HOME/.ssh/id_ed25519.pub"
  else
    warn "No SSH public key found."
  fi
}

main() {
  local step

  for step in ensure_supported_system ensure_sudo \
    install_system_packages install_starship \
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
