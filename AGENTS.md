# Working in this repository

This is a [chezmoi](https://www.chezmoi.io) dotfiles repository. These notes
cover what is specific to it; the machine-wide agent rules in
`~/.config/AGENTS.md` and `~/.claude/rules/` (rendered from the partials in
`home/.chezmoitemplates/ai/`) still apply here.

## Layout

| Path                      | What it holds                                        |
|---------------------------|------------------------------------------------------|
| `home/`                   | chezmoi source for `$HOME` (`.chezmoiroot` points here) |
| `home/.chezmoitemplates/` | shared template partials, included by name           |
| `home/.chezmoiscripts/`   | `run_once_` / `run_onchange_` hooks run on apply     |
| `root/`                   | source for system files applied to `/`               |
| `cascadeur/`              | chezmoi source rendering this repo's `.gitmodules`   |
| `modules/`                | symlinks and large submodules, for quick navigation  |
| `scripts/lib/`            | bash libraries                                       |
| `scripts/test/`           | bats tests, run through `scripts/test.sh`            |
| `secrets/`                | age-encrypted secrets                                |
| `install.sh`, `prerequisites.sh` | fresh-machine bootstrap (chezmoi, Homebrew); never run them to test |

## Chezmoi conventions

- Edit the source under `home/`, never the applied file in `$HOME`. The repo
  runs in `mode: symlink`, so a file in `$HOME` may be a symlink back into
  this tree — editing it there hides the change from review.
- File name prefixes carry meaning and are parsed by
  `scripts/lib/chezmoi_attrs.sh`: `dot_`, `private_`, `executable_`,
  `symlink_`, `encrypted_`, and the `.tmpl` suffix for Go templates.
- Check a template renders before committing:

  ```bash
  chezmoi execute-template --source . --file home/path/to/file.tmpl
  ```

- Never run `chezmoi apply` to "test" a change. Show `chezmoi diff` instead
  and let the user apply.
- chezmoi ignores `.gitignore`: an untracked file under `home/` (such as a
  `CLAUDE.md` that claude-mem writes) is applied to `$HOME` unless
  `home/.chezmoiignore.tmpl` lists it. It is a template; add OS-specific
  entries inside the matching `{{ if }}` block.
- Factor text shared between several files into `home/.chezmoitemplates/` and
  include it with `{{ template "dir/name.md.tmpl" . }}`, rather than copying
  it. Claude's instruction files are thin wrappers around the partials in
  `home/.chezmoitemplates/ai/`: the absolute rules in `CLAUDE.md.tmpl`, one
  partial per file in `rules/`. Both Claude config dirs carry identical
  copies (`home/private_dot_claude/` and
  `home/Working/Enterprise/TCV/private_dot_claude/`). A new partial goes into
  `ai/all.md.tmpl` and a matching rule file in both `rules/` dirs, except the
  absolute rules (`credentials`, `destructive-commands`), which live in
  `CLAUDE.md.tmpl`. Nothing checks this yet: the `claude_rules.bats` that
  `all.md.tmpl` mentions does not exist.

## Shell code

- Libraries are bash, sourced (not executed), and named `scripts/lib/<area>.sh`
  with functions namespaced `<area>::<verb>`.
- They build on the `dybatpho` submodule (`scripts/lib/dybatpho`): use its
  helpers (`dybatpho::die`, `dybatpho::is`, `dybatpho::opts::*`) instead of
  hand-rolling argument parsing or error handling. This holds for every bash
  script in the tree, including `scripts/*.sh` and `.chezmoiscripts/` hooks,
  not only the libraries.
- Lint every shell script you add or change with `dyshellint`, and fix what
  it reports rather than disabling the rule; a deliberate exception carries
  `# dyshellint disable=<CODE> <reason>` on the line above it.
- Document with the existing comment style: `# @file`, `# @brief`,
  `# @description`, `# @arg`, `# @stdout`.
- How to use dybatpho itself is in its skill (`scripts/lib/dybatpho/skills/dybatpho`,
  shared to every agent as `~/.agents/skills/dybatpho`). Pitfalls specific to
  this tree:
  - `dyshellint` exits 0 on warnings alone; pass `-warnings-as-errors` when its
    status decides anything.
  - A source named `executable_*` is stored without the executable bit, so
    `BSG037` fires on it: run `dyshellint -exclude-rules BSG037` on such files
    rather than `chmod +x` the source.
  - `cmd | grep -q pattern` under `pipefail` can fail with status 141 (SIGPIPE);
    capture the output first, or drop `-q` and redirect to `/dev/null`.

## Checks before reporting work done

```bash
dyshellint <changed scripts>   # shellcheck + shfmt + its own rules
prek run --all-files           # incl. betterleaks and detect-private-key
scripts/test.sh --changed      # bats files covering what changed since main
scripts/test.sh --pkgs         # the tool-list schema, on its own
scripts/test.sh --secrets      # the secrets schema, on its own
scripts/test.sh --all          # every bats file, once before a merge
```

- Use `--changed` while working. `scripts/lib/test_select.sh` picks the bats
  file named after each changed file, plus any bats file that mentions its
  name. A change to the runner or the selector itself, or to a non-prose file
  no test names, runs the whole suite instead.
- Run `--pkgs` and `--secrets` as separate checks every time, whatever
  `--changed` picked, and report each result on its own.
- A new library `scripts/lib/<area>.sh` needs `scripts/test/<area>.bats`:
  `dyshellint` fails it with `BSG060` until the test file exists.
- The pkgs tests render `home/dot_config/pkg_installer/tools.yaml.tmpl` for
  the current OS, so an entry for another OS is checked only on that OS. A
  shell tool's `dependencies` must name another entry: the installer skips an
  unknown one without a word.
- The runner uses the bats bundled with dybatpho, else one on `PATH`. When
  both are missing, fetch it with
  `git -C scripts/lib/dybatpho submodule update --init --recursive`.
- `--secrets` points at a `secrets_schema.bats` that does not exist yet, so it
  fails until that file is written; report the failure, do not skip it.

Say which checks ran.

## Repository-specific rules

- There is deliberately no `CHANGELOG.md` here. Do not create one; the history
  lives in commit messages.
- Do not commit inside a submodule (`home/dot_config/nvim`, `modules/icons`,
  `scripts/lib/dybatpho`, the browser profiles, `secrets/data`, …) unless asked. A
  submodule pointer bump is its own commit.
- `secrets/data/` holds live credentials and is off limits — see the
  credentials section of the machine-wide agent rules.
- `.worktrees/` at the repository root is where worktrees go, and is already
  covered by the global gitignore.
