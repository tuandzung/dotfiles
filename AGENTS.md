# Repository Guidelines

This repo manages personal dotfiles via `chezmoi` and system configuration via `rootmoi`. Keep changes minimal, reproducible, and focused on the target environments this setup supports.

## Project Structure & Module Organization
- `install.sh`: bootstrap entrypoint; installs chezmoi/age and applies home + root profiles.
- `prerequisites.sh`: OS bootstrap for macOS/Linux package managers.
- `home/`: chezmoi source directory (dotfiles, templates, private/ symlinked files).
- `root/`: rootmoi definitions for system-level configs.
- `modules/`: app/profile payloads (e.g., `nvim`, `firefox-profiles-*`, `zen-profiles-*`, `icons`).
- `scripts/`: helper scripts and logging utilities.
- `secrets/`: encrypted blobs (age). Do not commit plaintext secrets elsewhere.

## Build, Test, and Development Commands
- `./prerequisites.sh`: install baseline packages before syncing dotfiles.
- `DOTFILES_DEBUG=1 ./install.sh`: full dry-run; shows chezmoi/rootmoi actions without applying.
- `./install.sh`: apply home, root, and ssh configs; rewires repo remote for the author by default.
- `chezmoi apply --dry-run` / `chezmoi apply`: preview or apply home dotfile changes.
- `rootmoi apply --debug --dry-run` / `rootmoi apply`: preview or apply system configs.

## Coding Style & Naming Conventions
- Shell scripts use `bash` with `set -Eeuo pipefail`; prefer small, pure functions (`snake_case`).
- Keep indentation consistent (2 spaces in this repo) and avoid trailing whitespace.
- Name templates with `.tmpl`, executable files with `executable_` prefixes, and symlinks with `symlink_`.
- Follow existing directory naming for profiles (`*-profiles-*`) and dotfile mirrors (`dot_*`).

## Testing Guidelines
- No automated tests; rely on dry-runs: `DOTFILES_DEBUG=1 ./install.sh`, `chezmoi diff`, and `rootmoi apply --dry-run`.
- After changes, verify critical apps (shell, ssh, nvim, browsers) start cleanly and pick up configs.
- Keep secrets encrypted: use `age` keys and validate decrypted content locally only.

## Commit & Pull Request Guidelines
- Use conventional commits (`type(scope): subject`) as seen in history (`feat(nvim): ...`, `fix(mpv): ...`).
- Keep commits focused; include relevant paths or modules in scope for clarity.
- PRs should note target OS, what was changed, manual verification steps, and any screenshots for UI-facing profiles.
- If altering bootstrap behavior, call out impacts on first-time setup vs. updates.

## Security & Configuration Tips
- Store keys in age-encrypted form (`secrets/key.age`); do not add plaintext credentials.
- Avoid hard-coding hostnames or usernames; prefer templates and chezmoi variables.
- When testing remote changes, run `chezmoi apply --dry-run $HOME/.ssh` before applying to prevent SSH lockouts.
