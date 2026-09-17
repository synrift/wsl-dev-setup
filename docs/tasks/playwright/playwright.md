**FROZEN — READY TO EXECUTE**

## Goal

Add the official Playwright coding-agent CLI, Playwright-managed Chromium, and Chromium's official Ubuntu dependencies to the fresh Ubuntu 24.04 WSL bootstrap as a small additive capability.

## IN

- Modify only `install.sh` and `README.md`.
- Add a standalone `install_playwright()` function immediately after `install_fnm_and_node()` in the main flow.
- Install `@playwright/cli@latest` globally with normal-user npm.
- Install Chromium and its official Linux dependencies with the current supported Chromium-only `--with-deps` command.
- Configure Chromium as the default in the existing managed `~/.zshenv` block.
- Document the installed CLI, browser, dependencies, cache location, and project-local role of `@playwright/test`.

## OUT

- Changes to fnm, Node LTS, npm, Corepack, pnpm, PATH, zsh architecture, Docker, Bubblewrap/AppArmor, Git/SSH, or base packages.
- `sudo npm`, global `@playwright/test`, project Playwright files, skills, Firefox, WebKit, Chrome, Edge, custom apt dependency lists, `PLAYWRIGHT_BROWSERS_PATH`, new configuration files, or unrelated refactoring.

## Implementation

1. In `install.sh`, add `install_playwright()` that runs as the normal WSL user:

   ```bash
   npm install --global @playwright/cli@latest
   playwright-cli install-browser chromium --with-deps
   ```

   Verify current official documentation for exact argument ordering without installing anything locally. Allow Playwright to elevate only its official system-dependency step; keep npm and the browser cache normal-user owned.
2. Call `install_playwright` immediately after `install_fnm_and_node`.
3. Add `export PLAYWRIGHT_MCP_BROWSER=chromium` to the existing managed `~/.zshenv` block. Do not introduce another shell configuration mechanism.
4. Update `README.md` concisely: the global CLI is for AI/browser automation; Chromium is preinstalled and the default; Playwright installs Linux dependencies; browser binaries normally live under `~/.cache/ms-playwright`; applications should keep `@playwright/test` project-local.

## Validation

- During implementation, run only `bash -n install.sh`, `git diff --check`, `git status`, diff inspection, and read-only official-documentation checks.
- Do not run `install.sh`, npm global installation, `playwright-cli install-browser`, apt installation, or any browser installation in the development WSL.
- Later, on a fresh/disposable Ubuntu 24.04 WSL, run `install.sh` and verify CLI availability, Chromium installation/default selection, a headless launch, normal-user cache ownership, and a safe rerun.

## Acceptance Criteria

- Only `install.sh` and `README.md` are changed by implementation.
- A small `install_playwright()` follows Node/npm setup and installs the official global CLI plus Chromium with official dependencies.
- No npm or browser-cache files are created as root; only Playwright's dependency installation may elevate.
- Chromium is the configured default through the existing managed `~/.zshenv` block.
- All explicit non-goals remain absent.
- Non-destructive repository implementation checks pass. Runtime acceptance on a fresh/disposable Ubuntu 24.04 WSL is a separate post-implementation validation step that may remain unverified during repository implementation and does not require mutating the current development WSL.
