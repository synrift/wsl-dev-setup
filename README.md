# WSL Dev Setup

Windows 11 / WSL2 / Debian 13 development environment bootstrap, with zsh as
the default shell. The installer supports Debian 13 on WSL 2 and enables
systemd for Docker.

The repository contains one installer. From a checkout, run it as your normal
WSL user:

```bash
./install.sh
```

Running `bash install.sh` is equivalent.

## Shell Configuration

The installer configures Starship with the `pastel-powerline` preset and loads
`zsh-autosuggestions` and `zsh-syntax-highlighting`. There is one prompt
configuration, with no terminal-specific mode selection.

zoxide is not installed or initialized; use normal shell navigation (`cd`,
`pushd`, `popd`).

The `.zshenv` runtime initialization supports `zsh -c`, as well as the
existing Bash login/interactive initialization and inherited `BASH_ENV` path.
An independently launched Bash without `BASH_ENV` should still use `bash -lc`.
Agent shell options that disable startup files (such as `zsh -f`) can bypass
this initialization. The script prepares development dependencies; it does not
install Codex, Cursor, or OpenDesign themselves.

## What It Installs

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
- systemd
- systemd-sysv
- zenity (used by OpenDesign Web mode)
- xdg-utils
- util-linux
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
- Docker Engine (required)
- containerd (with Docker)
- Docker Buildx plugin (with Docker)
- Docker Compose plugin (with Docker)
- Bubblewrap AppArmor profile when Debian enables the unprivileged user
  namespace restriction
- WSL-native `TMPDIR=/tmp` for Node.js and other Unix development tools
- WSL-native `COREPACK_HOME=~/.cache/node/corepack` for Corepack and pnpm
- Playwright-managed Chromium as the default via `PLAYWRIGHT_MCP_BROWSER`

## Remote Installation

Run this inside Debian 13 on WSL 2:

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

## Docker

Docker Engine and the Compose plugin are always installed. The installer
enables systemd in WSL and enables Docker to start with the distribution. After
installation, shut WSL down and start Debian again so systemd can start Docker
and the Docker group membership takes effect.

The installer verifies the Docker daemon and Compose plugin. To also run
Docker's `hello-world` smoke test:

```bash
RUN_DOCKER_HELLO_WORLD=1 GIT_NAME="your-name" GIT_EMAIL="you@example.com" bash -c "$(curl -fsSL https://raw.githubusercontent.com/synrift/wsl-dev-setup/main/install.sh)"
```

## pnpm With Corepack

The installer prepares the initial Node LTS with the official Corepack npm
package and `corepack enable`. Shell startup only initializes fnm and selects
an **already installed** Node using recursive `.node-version` / `.nvmrc`
lookup. It does not install Node, prepare Corepack, read signing-key caches,
or repair package-manager links. `engines.node` does not select a Node version.

zsh uses fnm's official directory-change hook, including in `zsh -c` commands.
Bash selects Node at startup; after changing projects in an existing Bash,
run `fnm use` explicitly. No custom `fnm`, `cd`, `pushd`, or `popd` wrappers,
installation locks, compatibility maps, or periodic signing-key refreshes are
installed. Corepack uses its own signature verification and cache management.
The existing environment flags prevent automatic packageManager edits and
latest-version lookups; project-pinned pnpm may still download on first use.

Prepare a newly required Node before starting your agent. For example, for a
project declaring Node 22 or 24, from its root:

```bash
fnm install
fnm use
npm install --global --engine-strict corepack@latest
corepack enable
pnpm install
```

For older Node releases, select a Corepack version compatible with that Node
instead of `corepack@latest`; the installer no longer maintains a legacy
compatibility table. A Node installation normally needs Corepack setup once;
different projects can still select different pnpm versions via `packageManager`.

A new shell selects its own project's Node (or the fnm default), including
non-interactive `zsh -c` and Bash with inherited `BASH_ENV`. An independently
launched Bash without `BASH_ENV` should use `bash -lc`. A missing declared Node
stops startup before the task runs and must be installed explicitly; startup
never downloads it. Use an already prepared directory to open a setup shell,
or `zsh -f` to bypass user startup when repairing the environment.

Manual `fnm use` and `fnm exec --using` use native behavior. There is no custom
manual-version inheritance across fresh shells. On a directory change, fnm's
native zsh hook reports errors but does not restore directories or guarantee
that a chained command stops. Prepare project versions first; when changing
to an unprepared project, use `cd project && fnm use && <command>` explicitly.
A CLI environment snapshot or disabled startup files can also bypass fresh
project selection; verify `node --version` when changing projects inside an agent.

The script installs development dependencies, not Codex or Cursor. Their
official standalone installers can be used independently of project npm globals.
Orca and actual CLI behavior must still be checked on your Windows/WSL setup.

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
official Debian dependencies.

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

After the script finishes, exit Debian and run this in PowerShell:

```powershell
wsl --shutdown
```

Then start Debian again.

This starts systemd and Docker and applies the Docker group membership.

Inside Debian, run the following as your normal user, without `sudo`:

```bash
ps -p 1 -o comm=
systemctl is-active docker
docker info
docker compose version
command -v node npm corepack pnpm playwright-cli
node --version
corepack --version
pnpm --version
playwright-cli --version
```

The first command should print `systemd`, Docker should report `active`, and
all commands should succeed. Running `docker info` without `sudo` checks that
the new Docker group membership has taken effect. Chromium's actual launch
and page-load check runs during installation.

## Notes

- Run the script as your normal WSL user, not as root.
- The script may ask for your sudo password.
- WSL 2 version 0.67.6 or newer is required for systemd. The installer enables
  systemd in `/etc/wsl.conf`; systemd starts after the recommended
  `wsl --shutdown` and Debian restart.
- On Debian 13, the script checks whether AppArmor is actively restricting
  unprivileged user namespaces. Only when required, it installs
  `apparmor-profiles` and `apparmor-utils`, copies the Bubblewrap profile into
  `/etc/apparmor.d`, and loads it. If AppArmor or that restriction is disabled,
  the step is skipped.
- `~/.zshenv` initializes the project runtime for both interactive and
  non-interactive zsh, rather than placing a fixed default Node on PATH.
  Bash initialization is configured through `~/.bashrc`, `~/.profile`, and
  inherited `BASH_ENV`. The Node helper initializes only once per Bash process,
  including when a login shell reads multiple startup files; child Bash shells
  select their own project independently. fnm uses recursive version-file lookup
  and does not infer or upgrade Node from `engines.node`.
- `TMPDIR` and `COREPACK_HOME` are also exported at the beginning of the
  installer, so installation steps use WSL's Linux filesystem before
  `~/.zshenv` is created. Windows-provided `TEMP`, `TMP`, and `LOCALAPPDATA`
  remain unchanged for compatibility with Windows executables invoked from WSL.
- The script updates `~/.zshrc` inside a managed block named `codex-wsl-dev-env`.
- Re-running the script replaces only that managed block and keeps your other
  `~/.zshrc` content.
- The SSH public key is printed at the end so you can add it to GitHub.

## Verification

Installation errors report stage, line, command, and exit code. The installer
checks the Starship version, tools in new shells (including `zsh -c`), the Docker daemon and Compose, and an actual
Chromium launch and page load. These checks run automatically before
the installer prints its completion message.

## Repository Checks

Run `bash -n install.sh`, `shellcheck install.sh`, and
`python3 -m unittest discover -s tests -v` (requires Bash, zsh, and Python 3).
The isolated tests exercise generated startup configuration, package selection
and shell loading without installing system packages. For real runtime checks,
provide a fnm binary, an fnm directory with prepared Node 22 and 24 installations,
and an optional already warmed Corepack cache:

```bash
FNM_TEST_BIN=/path/to/fnm FNM_TEST_DIR=/path/to/fnm-data \
  FNM_TEST_PNPM_CACHE=/path/to/corepack-cache \
  PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

These checks never download tools. Without the test variables, real runtime
checks are skipped. They do not replace full installation or actual Orca/CLI
checks on Debian 13 / WSL 2.
