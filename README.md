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

Playwright belongs to each project, not the base WSL environment. This installer
is intended for a fresh Debian installation: it does not install Playwright npm
packages, download browsers, install Agent Skills, or remove existing tools.
It also does not install Codex or OpenCode themselves.

Keep `@playwright/test` as an exact project development dependency and commit the
lockfile. It supplies the `playwright` command, browser automation library, and
`playwright cli` agent interface; no global `@playwright/cli` installation is
needed. These CLI instructions were checked against Playwright 1.64.1.

After cloning a project, run its documented setup. For a package that directly
declares `@playwright/test`, the basic commands are:

```bash
corepack pnpm install --frozen-lockfile
corepack pnpm exec playwright install --with-deps chromium
corepack pnpm exec playwright cli -s=review open http://localhost:3000 --browser=chromium
corepack pnpm exec playwright cli -s=review snapshot
corepack pnpm exec playwright cli -s=review close
```

Start the application separately before opening its URL. In a monorepo, run
`pnpm exec` in the package that declares the dependency, or use the project's
root scripts / `--filter` to select that package. Run E2E through the project's
documented test script and service setup, rather than assuming a generic test
command can prepare its database and application servers.

Chromium and its Linux dependencies are installed by the project's Playwright
version. Browser binaries normally share `~/.cache/ms-playwright`; different
projects can require different revisions. Keep the default cache location and
re-run the browser installation after upgrading Playwright. Do not force a
browser executable from another version or from Windows.

### Shared browser Skill for Codex and OpenCode

After the first project's dependencies are installed, run this once in the
package that declares `@playwright/test`:

```bash
corepack pnpm exec playwright cli install --skills=agents --global
```

This uses the project's local CLI to copy its bundled official browser Skill
and references into `~/.agents/skills/playwright-cli/`. Here `--global` means
user-level Skill placement only: it does not install a global npm package,
download a browser, or initialize the project's `.playwright` directory.
Codex and compatible OpenCode versions discover this shared Skill location.
Start a new agent session after installing it.

Keep the official Skill unchanged and install it only in that shared location.
The Skill already supports local `playwright cli` commands. A project's
`AGENTS.md` should specify its exact local command or package script, require
`--browser=chromium` when opening a browser, and prohibit falling back to a
global installation. Do not automatically overwrite the shared Skill from
every project's dependency installation. When deliberately updating it, use a
chosen project version and check compatibility with other projects.

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
command -v node npm corepack pnpm
node --version
corepack --version
pnpm --version
```

The first command should print `systemd`, Docker should report `active`, and
all commands should succeed. Running `docker info` without `sudo` checks that
the new Docker group membership has taken effect.

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
checks Node/npm/Corepack/pnpm in new shells and verifies the Docker daemon
and Compose. These checks run automatically before the installer prints its
completion message. Browser installation and browser smoke tests belong to
each project's setup and acceptance checks.
