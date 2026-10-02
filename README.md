# WSL Dev Setup

Windows 11 / WSL2 / Ubuntu 24.04 / Linux x86_64 development environment
bootstrap, with zsh as the default shell.

Provisioning has two layers:

| Layer | Script | Responsibility |
| --- | --- | --- |
| 1 | `install.sh` | Base development environment |
| 2 | `install-ai-tools-wsl.sh` | AI development tools |

The standard fresh-machine sequence is:

```text
fresh WSL2 Ubuntu → install.sh → install-ai-tools-wsl.sh
```

From a checkout, run as your normal WSL user:

```bash
# Base environment
./install.sh
# Follow Layer 1's restart instructions, then install AI tooling
./install-ai-tools-wsl.sh
```

Both scripts also support `bash <script-name>`.

**Validation status:** The WSL AI tooling bootstrap has been statically reviewed
but has not yet completed final real-machine fresh-install, idempotency, and
remote-install validation on the target WSL2 workstation. Implementation +
static validation PASS; real WSL2 provisioning validation PENDING. No release
tag is associated with this pending acceptance.

## Layer 1: Base Environment

`install.sh` installs and configures:

- zsh
- unzip
- Bubblewrap
- build-essential
- ca-certificates
- curl
- Git
- jq
- OpenSSH client
- pkg-config
- Python 3
- ripgrep
- zoxide
- zsh-autosuggestions
- zsh-syntax-highlighting
- Starship prompt
- fnm
- Node.js LTS
- npm bundled with Node.js
- Corepack
- Corepack-managed pnpm
- Playwright CLI
- Playwright-managed Chromium
- Git global config
- ed25519 SSH key
- Docker Engine
- Docker Buildx plugin
- Docker Compose plugin
- Bubblewrap AppArmor profile when Ubuntu enables the unprivileged user
  namespace restriction
- WSL-native `TMPDIR=/tmp` for Node.js and other Unix development tools
- WSL-native `COREPACK_HOME=~/.cache/node/corepack` for Corepack and pnpm
- Playwright-managed Chromium as the default via `PLAYWRIGHT_MCP_BROWSER`

## Usage

Run this inside Ubuntu on WSL:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/synrift/wsl-dev-setup/main/install.sh)"
```

## Usage With Git Parameters

Set `GIT_NAME` and `GIT_EMAIL` before `bash`:

```bash
GIT_NAME="your-name" GIT_EMAIL="you@example.com" bash -c "$(curl -fsSL https://raw.githubusercontent.com/synrift/wsl-dev-setup/main/install.sh)"
```

The script uses these values for:

```bash
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
```

If you do not pass parameters, the script uses these placeholder defaults:

```bash
GIT_NAME="your-name"
GIT_EMAIL="you@example.com"
```

## Optional Docker Test

By default, the script installs Docker, starts and verifies the Docker daemon,
and shows the Docker Compose version, but it does not run `hello-world`.

To run Docker's `hello-world` test too:

```bash
RUN_DOCKER_HELLO_WORLD=1 GIT_NAME="your-name" GIT_EMAIL="you@example.com" bash -c "$(curl -fsSL https://raw.githubusercontent.com/synrift/wsl-dev-setup/main/install.sh)"
```

## pnpm With Corepack

The script keeps the npm version bundled with Node.js and uses Corepack to
manage pnpm. Outside a project, Corepack provides the latest pnpm version that
was selected during installation.

Windows environment variables such as `LOCALAPPDATA` are inherited by WSL.
Corepack may otherwise select a cache below `/mnt/c/Users/.../AppData/Local`,
which can fail in non-interactive tools such as Codex Desktop. The installer
exports the following value both during installation and from `~/.zshenv`:

```bash
export COREPACK_HOME="$HOME/.cache/node/corepack"
```

This keeps Corepack and its downloaded pnpm versions on WSL's Linux filesystem.

For a new project, first create `package.json`, then let Corepack select and pin
the current pnpm version:

```bash
npm init -y
corepack use pnpm@latest
```

`corepack use` writes an exact pnpm version to the `packageManager` field in
`package.json` and runs the initial install. Commit `package.json` and
`pnpm-lock.yaml`. After that, use pnpm normally:

```bash
pnpm install
pnpm add <package>
pnpm run dev
```

When another machine or a fresh WSL installation runs `pnpm` in that project,
Corepack reads `packageManager` and automatically uses the pinned pnpm version.

To update pnpm within the current major version for a project:

```bash
corepack up
```

To intentionally move a project to the latest pnpm release, including a new
major version:

```bash
corepack use pnpm@latest
```

## Playwright

The script installs the official Playwright coding-agent CLI globally with the
fnm-managed npm, then installs Playwright-managed Chromium and Chromium's
official Ubuntu dependencies.

The global CLI is for AI and browser automation. Chromium is preinstalled and
set as the default through `PLAYWRIGHT_MCP_BROWSER=chromium` in `~/.zshenv`.
Playwright installs Linux system dependencies as part of the Chromium step.
Browser binaries normally live under `~/.cache/ms-playwright`.

Applications should keep `@playwright/test` project-local rather than installing
it globally.

## After Installation

After the script finishes, exit Ubuntu and run this in PowerShell:

```powershell
wsl --shutdown
```

Then start Ubuntu again.

This reloads the default zsh shell and applies Docker group membership.

## Notes

- Run the script as your normal WSL user, not as root.
- The script may ask for your sudo password.
- On Ubuntu 24.04, the script checks whether AppArmor is actively restricting
  unprivileged user namespaces. Only when required, it installs
  `apparmor-profiles` and `apparmor-utils`, copies the Bubblewrap profile into
  `/etc/apparmor.d`, and loads it. If AppArmor or that restriction is disabled,
  the step is skipped.
- The script updates `~/.zshenv` so Codex Desktop and other non-interactive zsh
  commands can find the default fnm-managed Node.js version. It also exports
  `TMPDIR=/tmp` and `COREPACK_HOME="$HOME/.cache/node/corepack"`, preventing
  Node.js, Unix tools, and Corepack from using Windows `/mnt/c/...` paths
  inherited through `TEMP`, `TMP`, and `LOCALAPPDATA`. The same managed block
  exports `PLAYWRIGHT_MCP_BROWSER=chromium` so Playwright CLI/MCP automation
  uses Playwright-managed Chromium by default.
- `TMPDIR` and `COREPACK_HOME` are also exported at the beginning of the
  installer, so installation steps use WSL's Linux filesystem before
  `~/.zshenv` is created. Windows-provided `TEMP`, `TMP`, and `LOCALAPPDATA`
  remain unchanged for compatibility with Windows executables invoked from WSL.
- The script updates `~/.zshrc` inside a managed block named `codex-wsl-dev-env`.
- Re-running the script replaces only that managed block and keeps your other `~/.zshrc` content.
- The SSH public key is printed at the end so you can add it to GitHub.

## Layer 2: AI Tooling

Run Layer 2 after Layer 1 in Ubuntu 24.04 on WSL2, as a non-root user:

```bash
./install-ai-tools-wsl.sh
# Equivalent
bash install-ai-tools-wsl.sh
```

Installation order and official sources:

| Tool | Installation policy | Official source |
| --- | --- | --- |
| Codex CLI | Official standalone installer; `CODEX_INSTALL_DIR=~/.local/bin`, `CODEX_NON_INTERACTIVE=1` | [Installer](https://chatgpt.com/codex/install.sh) |
| Cursor Agent CLI | Official CLI installer; both `agent` and `cursor-agent` required | [Installer](https://cursor.com/install) |
| Antigravity CLI | Official CLI installer; native `agy install --skip-path --skip-aliases` handoff | [Installer](https://antigravity.google/cli/install.sh) |
| OpenSpec CLI | Canonical fnm default npm global: `@fission-ai/openspec@latest` | [OpenSpec](https://github.com/Fission-AI/OpenSpec) |
| Hermes | Official installer with `--non-interactive`, full managed runtime | [Installer](https://hermes-agent.nousresearch.com/install.sh) |

OpenSpec is the only npm global installation in Layer 2. Its
[Node.js minimum is 20.19.0](https://github.com/Fission-AI/OpenSpec#quick-start).
The script checks the full version using the canonical default Node and
requires npm's resolved global prefix to equal that Node installation's root.
Custom npm prefix settings cause a failure for human resolution; `.npmrc` is
never rewritten. Layer 2 does not install or switch Layer 1 runtimes.

Canonical Layer 1 paths, read from `install.sh`, are:

```text
~/.local/bin
~/.local/share/fnm/fnm
~/.local/share/fnm/aliases/default/bin/{node,npm,pnpm}
```

Layer 2 constructs its own process PATH from those paths, so an interactive
fnm multishell is unnecessary. It also uses Layer 1's Linux `TMPDIR=/tmp` and
`COREPACK_HOME=~/.cache/node/corepack`. It requires Linux x86_64, a kernel release
containing both `microsoft` and `WSL2`, and Ubuntu 24.04. WSL1, ordinary Linux,
and ambiguous/custom WSL kernel releases fail before installation.

Layer 2 checks `git`, `curl`, `zsh`, `node`, `npm`, `pnpm`, `python3`, the canonical
fnm layout, and checksum/temporary-file utilities. Missing base prerequisites
produce `Run ./install.sh first.` It only checks `xz`; it never runs `sudo` or
apt. If `xz` is missing, install it yourself before rerunning:

```bash
sudo apt update
sudo apt install xz-utils
```

Working commands are reused without forced upgrades. Cursor requires both
launchers to work. Authentication, model/provider settings, histories, and
existing configuration directories are not deleted or reset. Interrupted
installs can be retried through the official installers; the script is not a
migration manager. The audited Antigravity wrapper refuses an existing binary,
even if broken: in that case the version gate fails and a human must resolve
the file before retrying.

Shell installers are downloaded to a cleaned-up `mktemp -d` directory with
HTTPS-only curl redirects, retries, and timeouts, then checked with `bash -n`
and explicitly executed. Codex and Cursor installers run unchanged with
`~/.local/bin` already on PATH. As audited on 2026-10-02, Antigravity's skip flags
belong to the native setup handoff, and Hermes has no skip-path flag. Temporary
copies adapt only the two exact Antigravity handoff lines (also removing error
suppression) and Hermes's exact `wire_shell_path` call. Every audited line must
appear exactly once; upstream changes cause failure before execution. Original
downloads are preserved until cleanup. Unknown native skip flags or native
setup failures also fail the bootstrap.

Layer 1 owns `.zshenv`, `.zprofile`, `.zshrc`, `.bashrc`, and `.profile`. Layer 2
records checksums, symlink targets, and absent states before installers run,
then checks them after every installation stage, including a failed installer,
and after final verification. A change fails with the responsible stage and
file differences; the script never restores or overwrites user startup files.

Hermes is a hard requirement and installs last. Its official PM owns its
Python, Node/npm, ripgrep, FFmpeg, browser tooling, and dependencies. Layer 2
does not supply Layer 1's Python/Node/browser to Hermes or pass `--skip-browser`.
An inherited `HERMES_REPO_URL` override is removed from the installer process
so it uses the official repository. Upstream retains runtime management and
normal configuration maintenance; Layer 2 does not set providers or models.

All six launchers must pass `command -v` and `--version`. `hermes pm doctor`
must succeed both in its installation/reuse stage and in final verification.
`hermes doctor` prints informational diagnostics: success is reported as OK,
and nonzero status is a warning. No diagnostic text is parsed and no
`doctor --fix` is run. Native commands normally resolve through `~/.local/bin`,
OpenSpec through the canonical default Node bin, and Hermes through upstream's
published launcher. The script does not relocate upstream artifacts.

After installation, authenticate manually:

| Tool | Human action |
| --- | --- |
| Codex | Run `codex`, then Sign in with ChatGPT |
| Cursor | Run `agent login` |
| Antigravity | Run `agy` and complete browser authentication |
| Hermes | Run `hermes setup` |
| OpenSpec | No login required |

Project-level `openspec init` / `openspec update` and workflow edits are separate
human decisions and are never part of this bootstrap.

For a future Gitea raw installation, substitute the actual raw script URL:

```bash
bash -c "$(curl -fsSL 'https://<gitea-host>/<owner>/wsl-dev-setup/raw/branch/main/install-ai-tools-wsl.sh')"
```

File execution and raw `bash -c` execution invoke `main`. Sourcing the file
defines helpers without running `main` (it enables Bash strict mode). Sourcing
from zsh or other non-Bash shells is rejected before `main`. Remote
execution support is implemented and mock-tested; target-machine remote
acceptance remains pending.
