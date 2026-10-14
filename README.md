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

The script keeps fnm and the npm bundled with each Node installation. In a
project or subdirectory, fnm uses the nearest `.node-version` (or `.nvmrc`),
automatically installing a missing runtime. Corepack uses the project's pinned
`packageManager` without rewriting it. Outside projects, the active Node is
preserved; a fresh shell starts with the default LTS. Corepack's bundled pnpm
default is used outside projects, without checking for newer releases.

Use `node`, `npm`, and `pnpm` normally. Manual `fnm use` and `fnm exec --using`
overrides are preserved, including in child shells. Explicit `fnm exec` retains
fnm's requirement that the requested Node is already installed.

Initialization runs in all zsh modes, including Codex's `zsh -c`. Bash login
and interactive shells also initialize it; child `bash -c` processes inherit
`BASH_ENV`. A standalone Bash process launched without that environment should
use `bash -lc`. There are no custom node/npm/npx/pnpm command proxies: a small
helper installs a pinned, compatible Corepack and its native shims for the
active Node. Preparation uses locks and atomic cache publication, with logs on
stderr. Prepared tools work with read-only HOME access; fnm's temporary shell
state lives in `/tmp`. A sandbox needs approval to download/install missing
tools into HOME, rather than silently running another Node. If a directory
change selects an invalid or unavailable runtime, the shell reports the failure
and stays in the previous directory/runtime. Configured Corepack releases
support Node 16.20.0 and newer; older Node fails explicitly instead of being
upgraded.

First use needs network access for missing Node, Corepack, and pnpm versions.
The compatibility pins are maintained in `install.sh`, based on Corepack's
published Node engine requirements. npm registry signing keys are cached on
first use and refreshed atomically every 30 days when HOME is writable. Corepack
0.20.0, used for older Node releases in the compatibility map, predates npm
package signature verification; newer configured Corepack versions verify
pnpm signatures using the cached registry keys. The legacy pnpm cache is warmed
under a lock to avoid concurrent first-use races.

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

The global CLI is for AI and browser automation and keeps the concrete Node
runtime captured at installation when projects or the fnm default select
another Node. Chromium is preinstalled and set as
the default through `PLAYWRIGHT_MCP_BROWSER=chromium`. Playwright installs Linux
system dependencies as part of the Chromium step. Browser binaries normally
live under `~/.cache/ms-playwright`.

The installer actually launches the CLI's matching Chromium and checks a page.
Project Playwright versions can require different browser revisions and their
own downloads; the global preinstallation does not replace those browsers.

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
- `~/.zshenv` initializes the project runtime for both interactive and
  non-interactive zsh, rather than placing a fixed default Node on PATH.
  Bash initialization is configured through `~/.bashrc`, `~/.profile`, and
  inherited `BASH_ENV`. fnm uses recursive version-file lookup and does not
  infer or upgrade Node from `engines.node`.
- `TMPDIR` and `COREPACK_HOME` are also exported at the beginning of the
  installer, so installation steps use WSL's Linux filesystem before
  `~/.zshenv` is created. Windows-provided `TEMP`, `TMP`, and `LOCALAPPDATA`
  remain unchanged for compatibility with Windows executables invoked from WSL.
- The script updates `~/.zshrc` inside a managed block named `codex-wsl-dev-env`.
- Re-running the script replaces only that managed block and keeps your other `~/.zshrc` content.
- The SSH public key is printed at the end so you can add it to GitHub.

## Layer 1 Verification

Installation errors report stage, line, command, and exit code. The installer
checks tools in new shells, Docker daemon availability, Compose, and actual
Chromium startup. The isolated integration suite can be run with:

```bash
bash tests/node-environment.sh
```

It writes only to a temporary HOME under `/tmp` and downloads test runtimes.
It covers subdirectories, nested declarations, missing tools, explicit fnm
selection, shell inheritance, read-only HOME access, concurrency, stdout cleanliness, and failure
before user commands execute. Current-WSL integration checks do not constitute
a full fresh-WSL installation or reboot acceptance test.

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
