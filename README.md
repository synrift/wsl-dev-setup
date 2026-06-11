# WSL Dev Setup

Ubuntu 24.04 on WSL development environment bootstrap script.

This script installs and configures:

- zsh
- unzip
- zoxide
- zsh-autosuggestions
- zsh-syntax-highlighting
- Starship prompt
- fnm
- Node.js LTS
- latest npm
- latest pnpm
- Git global config
- ed25519 SSH key
- Docker Engine
- Docker Buildx plugin
- Docker Compose plugin

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

By default, the script installs Docker and shows the Docker Compose version, but it does not run `hello-world`.

To run Docker's `hello-world` test too:

```bash
RUN_DOCKER_HELLO_WORLD=1 GIT_NAME="your-name" GIT_EMAIL="you@example.com" bash -c "$(curl -fsSL https://raw.githubusercontent.com/synrift/wsl-dev-setup/main/install.sh)"
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
- The script updates `~/.zshrc` inside a managed block named `codex-wsl-dev-env`.
- Re-running the script replaces only that managed block and keeps your other `~/.zshrc` content.
- The SSH public key is printed at the end so you can add it to GitHub.

