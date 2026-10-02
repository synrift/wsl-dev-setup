#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  printf '%s\n' 'Use Bash: bash install-ai-tools-wsl.sh. Sourcing from other shells is unsupported.' >&2
  return 1 2>/dev/null || exit 1
fi

# Layer 2 only: Ubuntu 24.04 / WSL2 / x86_64, after ./install.sh.
# No authentication, project initialization, or system package provisioning.

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\n[warn] %s\n' "$*" >&2; }
die() { printf '\n[error] %s\n' "$*" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
working_command() { command_exists "$1" && "$1" --version >/dev/null 2>&1; }

verify_command() {
  command -v "$1" || die "Missing command after installation: $1"
  "$1" --version || die "$1 --version failed."
}

# WSL environment variables alone cannot distinguish WSL1 from WSL2.
# Require the WSL2 kernel marker; fail closed for unknown/custom kernels.
wsl2_kernel() {
  local release
  release="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$release" == *microsoft* && "$release" == *wsl2* ]]
}

ensure_wsl2() {
  [[ "$(uname -s)" == Linux ]] || die "Authoritative target: Ubuntu 24.04 on WSL2 (Linux x86_64)."
  local release
  release="$(tr '[:upper:]' '[:lower:]' < /proc/sys/kernel/osrelease)"
  if ! wsl2_kernel "$release"; then
    if [[ "$release" == *microsoft* || -n "${WSL_INTEROP:-}${WSL_DISTRO_NAME:-}" ]]; then
      die "WSL1 or an unrecognized WSL kernel ($release). WSL2 is required."
    fi
    die "This is not WSL2. Authoritative target: Ubuntu 24.04 on WSL2."
  fi
  [[ "$(uname -m)" == x86_64 ]] || die "This bootstrap requires Linux x86_64."
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release."
  local ID VERSION_ID
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] ||
    die "Authoritative target: Ubuntu 24.04 on WSL2; detected ${ID:-unknown} ${VERSION_ID:-unknown}."
  [[ "$EUID" -ne 0 ]] || die "Run as your normal WSL user, not root."
}

prepare_runtime() {
  # These paths are owned by install.sh (including fnm's default alias).
  BIN_DIR="$HOME/.local/bin"
  FNM_DIR="$HOME/.local/share/fnm"
  NODE_BIN="$FNM_DIR/aliases/default/bin"
  export PATH="$BIN_DIR:$NODE_BIN:$FNM_DIR:$PATH"
  export TMPDIR=/tmp
  export COREPACK_HOME="$HOME/.cache/node/corepack"
  hash -r
}

ensure_prerequisites() {
  local cmd
  [[ -d "$BIN_DIR" && -x "$FNM_DIR/fnm" && -d "$NODE_BIN" ]] ||
    die "Missing canonical fnm/default Node layout. Run ./install.sh first."
  for cmd in node npm pnpm; do
    [[ -x "$NODE_BIN/$cmd" ]] || die "Missing $NODE_BIN/$cmd. Run ./install.sh first."
  done
  for cmd in git curl zsh node npm pnpm python3; do
    command_exists "$cmd" || die "Missing $cmd. Run ./install.sh first."
  done
  "$FNM_DIR/fnm" --version >/dev/null || die "fnm is not working. Run ./install.sh first."
  "$NODE_BIN/node" --version >/dev/null || die "Default Node is not working. Run ./install.sh first."
  "$NODE_BIN/npm" --version >/dev/null || die "Default npm is not working. Run ./install.sh first."
  # Do not invoke pnpm here: a Corepack shim may download or pin a project PM.
  for cmd in sha256sum awk mktemp; do
    command_exists "$cmd" || die "Missing base utility $cmd. Run ./install.sh first."
  done
  command_exists xz || die 'Missing xz.

Install xz-utils first, for example:

sudo apt update
sudo apt install xz-utils

Then rerun ./install-ai-tools-wsl.sh.'
}

ensure_openspec_runtime() {
  # process.versions.node is a full SemVer. Stable releases newer than the
  # minimum pass; prereleases at exactly 20.19.0 sort below the minimum.
  "$NODE_BIN/node" -e '
    const match = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/.exec(process.versions.node);
    if (!match) process.exit(1);
    const actual = match.slice(1, 4).map(Number), minimum = [20, 19, 0];
    for (let i = 0; i < 3; i++) {
      if (actual[i] > minimum[i]) process.exit(0);
      if (actual[i] < minimum[i]) process.exit(1);
    }
    process.exit(match[4] ? 1 : 0);
  ' || die "OpenSpec requires Node.js >= 20.19.0. Update Layer 1 first; Layer 2 will not switch Node."

  local prefix default_root
  prefix="$("$NODE_BIN/npm" prefix --global)" || die "Cannot determine canonical npm global prefix."
  default_root="$(cd "$NODE_BIN/.." && pwd -P)"
  [[ -d "$prefix" ]] || die "npm global prefix does not exist: $prefix. Human must resolve custom npm prefix settings."
  [[ "$(cd "$prefix" && pwd -P)" == "$default_root" ]] ||
    die "Custom npm global prefix: $prefix (expected $default_root). Human must resolve .npmrc/environment prefix settings; no configuration was changed."
}

cleanup() {
  if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR"
  fi
}

download() {
  log "Downloading official $1 installer"
  curl -fsSL --retry 3 --connect-timeout 15 --max-time 180 \
    --proto '=https' --proto-redir '=https' "$2" -o "$3" || die "$1 installer download failed."
  [[ -s "$3" ]] || die "$1 installer is empty."
  bash -n "$3" || die "$1 installer failed bash -n."
}

shell_state() {
  local name path
  for name in .zshenv .zprofile .zshrc .bashrc .profile; do
    path="$HOME/$name"
    printf '%s\t' "$name"
    # Record symlinks as well as content, including dangling symlinks.
    if [[ -L "$path" ]]; then
      printf 'link:%s\t' "$(readlink "$path")"
    fi
    if [[ -f "$path" ]]; then
      sha256sum < "$path" || return 1
    elif [[ -e "$path" || -L "$path" ]]; then
      printf 'non-regular\n'
    else
      printf 'absent\n'
    fi
  done
}

check_shell_integrity() {
  local stage="$1" current
  current="$(shell_state)" || die "Cannot checksum shell startup files after $stage."
  if [[ "$current" != "$SHELL_BASELINE" ]]; then
    printf '%s\n' "$SHELL_BASELINE" > "$WORK_DIR/shell-before"
    printf '%s\n' "$current" > "$WORK_DIR/shell-after"
    diff -u "$WORK_DIR/shell-before" "$WORK_DIR/shell-after" >&2 || true
    die "$stage changed shell startup files. Inspect the files; nothing was restored or overwritten by this bootstrap."
  fi
}

run_installer() {
  local stage="$1" rc=0
  shift
  # Capture failure explicitly so the integrity check also runs on failure.
  # Each upstream script is a separate Bash process, not a conditional function.
  "$@" || rc=$?
  hash -r
  check_shell_integrity "$stage"
  [[ "$rc" -eq 0 ]] || die "$stage installer failed (exit $rc)."
}

# Only full-line equality is allowed, with exactly one match. Always write a
# distinct temporary copy; never modify the original download. Audited 2026-10-02.
replace_exact_line() {
  local source="$1" target="$2" before="$3" after="$4"
  [[ "$source" != "$target" ]] || die "Installer adaptation requires a separate copy."
  awk -v before="$before" -v after="$after" '
    $0 == before { count++; print after; next }
    { print }
    END { if (count != 1) exit 1 }
  ' "$source" > "$target" || die "Upstream installer changed: expected exactly one audited line: $before"
  bash -n "$target" || die "Adapted installer failed bash -n."
}

require_exact_line() {
  awk -v line="$2" '$0 == line { count++ } END { exit (count != 1) }' "$1" ||
    die "Upstream installer interface changed: expected exactly one audited line: $2"
}

install_codex() {
  log "1/5 Codex CLI"
  if working_command codex; then
    log "Reusing working Codex"
  else
    download Codex https://chatgpt.com/codex/install.sh "$WORK_DIR/codex.sh"
    run_installer Codex env CODEX_INSTALL_DIR="$BIN_DIR" CODEX_NON_INTERACTIVE=1 \
      bash "$WORK_DIR/codex.sh"
  fi
  verify_command codex
}

install_cursor() {
  log "2/5 Cursor Agent CLI"
  if working_command agent && working_command cursor-agent; then
    log "Reusing working Cursor Agent launchers"
  else
    download Cursor https://cursor.com/install "$WORK_DIR/cursor.sh"
    run_installer Cursor bash "$WORK_DIR/cursor.sh"
  fi
  verify_command agent
  verify_command cursor-agent
}

install_antigravity() {
  log "3/5 Antigravity CLI"
  if working_command agy; then
    log "Reusing working Antigravity"
  else
    download Antigravity https://antigravity.google/cli/install.sh "$WORK_DIR/antigravity.sh"
    # Flags belong to native `agy install`, not this wrapper. We deliberately
    # use its standard directory branch; both audited handoffs must match.
    replace_exact_line "$WORK_DIR/antigravity.sh" "$WORK_DIR/antigravity-step.sh" \
      '    "$BINARY_PATH" install --dir "$CUSTOM_DIR" || true' \
      '    "$BINARY_PATH" install --dir "$CUSTOM_DIR" --skip-path --skip-aliases'
    replace_exact_line "$WORK_DIR/antigravity-step.sh" "$WORK_DIR/antigravity-run.sh" \
      '    "$BINARY_PATH" install || true' \
      '    "$BINARY_PATH" install --skip-path --skip-aliases'
    run_installer Antigravity bash "$WORK_DIR/antigravity-run.sh"
    "$BIN_DIR/agy" --version || die "Canonical ~/.local/bin/agy failed; upstream may have refused an existing broken binary. Resolve it manually, then rerun."
  fi
  verify_command agy
}

install_openspec() {
  log "4/5 OpenSpec CLI"
  if working_command openspec; then
    log "Reusing working OpenSpec"
  else
    # OpenSpec is the only tool installed through npm global.
    run_installer OpenSpec "$NODE_BIN/npm" install --global @fission-ai/openspec@latest
  fi
  verify_command openspec
}

install_hermes() {
  log "5/5 Hermes"
  if working_command hermes; then
    log "Reusing working Hermes; managed runtime must also pass pm doctor"
  else
    download Hermes https://hermes-agent.nousresearch.com/install.sh "$WORK_DIR/hermes.sh"
    require_exact_line "$WORK_DIR/hermes.sh" \
      '        --non-interactive|-NonInteractive) NON_INTERACTIVE=true; shift ;;'
    # No skip-path option in the audited interface. Skip only this handoff;
    # keep PM, browser tooling, dependency and product stages upstream-owned.
    replace_exact_line "$WORK_DIR/hermes.sh" "$WORK_DIR/hermes-run.sh" \
      '    wire_shell_path' '    : # Layer 1 owns shell PATH configuration'
    # An inherited repository override must never select a third-party fork.
    run_installer Hermes env -u HERMES_REPO_URL bash "$WORK_DIR/hermes-run.sh" --non-interactive
  fi
  verify_command hermes
  hermes pm doctor || die "Hermes managed runtime failed hermes pm doctor."
}

final_verification() {
  log "Final command paths and versions"
  local cmd
  for cmd in codex agent cursor-agent agy openspec hermes; do
    verify_command "$cmd"
  done
  hermes pm doctor || die "Final Hermes managed runtime verification failed."
  log "Hermes informational diagnostics"
  if hermes doctor; then
    log "hermes doctor: OK"
  else
    warn "hermes doctor reported diagnostics. Installation hard gates passed; review the output and run hermes setup yourself."
  fi
  check_shell_integrity "Final verification"
}

print_next_steps() {
  cat <<'EOF'

AI tools installed or reused. Authentication remains a human step:

Codex:
  codex
  Sign in with ChatGPT
Cursor:
  agent login
Antigravity:
  agy
  complete browser authentication
Hermes:
  hermes setup
OpenSpec:
  no login required

Project workflows (including openspec init/update) are separate from bootstrap.
EOF
}

main() {
  ensure_wsl2
  prepare_runtime
  ensure_prerequisites
  ensure_openspec_runtime
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  SHELL_BASELINE="$(shell_state)" || die "Cannot checksum shell startup files."
  install_codex
  install_cursor
  install_antigravity
  install_openspec
  install_hermes
  final_verification
  print_next_steps
}

# File execution and bash -c raw execution run main; sourcing defines helpers.
if [[ -z "${BASH_SOURCE:-}" || "${BASH_SOURCE}" == "$0" ]]; then
  main "$@"
fi
