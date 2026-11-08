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
  initialize independently. fnm uses recursive version-file lookup and does not
  infer or upgrade Node from `engines.node`.
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
checks tools in new shells, the Docker daemon and Compose, and an actual
Chromium launch and page load. These checks run automatically before
the installer prints its completion message.
