# WSL Dev Setup

Ubuntu 24.04 on WSL development environment bootstrap script.

This script installs and configures:

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
- Git global config
- ed25519 SSH key
- Docker Engine
- Docker Buildx plugin
- Docker Compose plugin
- Bubblewrap AppArmor profile when Ubuntu enables the unprivileged user
  namespace restriction
- WSL-native `TMPDIR=/tmp` for Node.js and other Unix development tools
- WSL-native `COREPACK_HOME=~/.cache/node/corepack` for Corepack and pnpm

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
  inherited through `TEMP`, `TMP`, and `LOCALAPPDATA`.
- `TMPDIR` and `COREPACK_HOME` are also exported at the beginning of the
  installer, so installation steps use WSL's Linux filesystem before
  `~/.zshenv` is created. Windows-provided `TEMP`, `TMP`, and `LOCALAPPDATA`
  remain unchanged for compatibility with Windows executables invoked from WSL.
- The script updates `~/.zshrc` inside a managed block named `codex-wsl-dev-env`.
- Re-running the script replaces only that managed block and keeps your other `~/.zshrc` content.
- The SSH public key is printed at the end so you can add it to GitHub.
