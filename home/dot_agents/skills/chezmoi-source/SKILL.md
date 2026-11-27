---
name: chezmoi-source
description: Use when adding, renaming, or editing a dotfile on this machine - maps a $HOME path to its chezmoi source file under ~/Dotfiles/home, explains the dot_/private_/executable_/symlink_/encrypted_/.tmpl naming, and the diff-before-apply rule.
---

# Editing dotfiles through chezmoi

`$HOME` on this machine is rendered by chezmoi from `~/Dotfiles/home`
(`.chezmoiroot` points there) in `mode: symlink`. Many files under `$HOME`
are symlinks back into that tree, so an edit "in place" silently changes the
repo without review. Always edit the source.

## Find the source file

```bash
chezmoi managed | rg '<fragment>'        # is it managed at all?
chezmoi source-path ~/.config/foo/bar    # exact source file to edit
```

Not managed yet: `chezmoi add ~/.config/foo/bar`, then edit the file it
created. Never write a new file into `$HOME` and expect chezmoi to notice.

## Source name grammar

Attribute prefixes come in a fixed order, then `dot_` for a leading dot. The
same rule applies to every directory component.

| Prefix / suffix | Effect |
|-----------------|--------|
| `create_` | write once, never overwrite |
| `encrypted_` | stored age-encrypted in the repo |
| `private_` | mode 0600 / 0700 |
| `readonly_` | strip write bit |
| `empty_` | keep even if empty |
| `executable_` | set the executable bit |
| `symlink_` | file content is the link target |
| `dot_` | leading dot in the target name |
| `.tmpl` | Go template rendered at apply time |

Examples:

| Target | Source |
|--------|--------|
| `~/.config/fish/config.fish` | `home/dot_config/fish/config.fish.tmpl` |
| `~/.claude/CLAUDE.md` | `home/private_dot_claude/CLAUDE.md.tmpl` |
| `~/.local/bin/rootmoi` | `home/dot_local/bin/executable_rootmoi.tmpl` |

`scripts/lib/chezmoi_attrs.sh` builds these names in code for encrypted
files that `chezmoi add` cannot handle; it marks every dotted directory
`private_` as well.

Scripts in `home/.chezmoiscripts/` run on apply: `run_once_` runs a single
time per machine, `run_onchange_` reruns when its rendered content changes.

## Templates

Shared text lives in `home/.chezmoitemplates/` and is included with
`{{ template "dir/name.md.tmpl" . }}`. The AI instruction files
(`CLAUDE.md.tmpl`, `AGENTS.md.tmpl`) are thin wrappers around
`home/.chezmoitemplates/ai/`; change the partial, not the wrapper.

Check a template renders before committing:

```bash
chezmoi execute-template --source ~/Dotfiles --file home/path/to/file.tmpl
```

## Preview, never apply

```bash
chezmoi diff --exclude encrypted,templates   # what apply would change, secrets left out
```

Show the diff and stop. `chezmoi apply`, `chezmoi destroy`, and
`chezmoi forget` write over the real `$HOME` and need the user's yes.

## Gotchas

- In `mode: symlink`, a plain source file is linked into `$HOME`, but a
  `.tmpl` is rendered into a real copy. Editing that copy looks like it
  works until the next apply silently reverts it.
- `chezmoi execute-template` renders partials from the source it is pointed
  at. In a worktree under `.worktrees/<name>`, pass
  `--source <that worktree>`, or it renders the main checkout's
  `.chezmoitemplates` and the check proves nothing.
- A partial in `home/.chezmoitemplates/ai/` feeds the instruction file of
  every agent. Claude reads it through the `rules/` dir of each Claude config
  dir (`home/private_dot_claude/` and
  `home/Working/Enterprise/TCV/private_dot_claude/`), so a new partial needs
  a rule file in both; `scripts/test/claude_rules.bats` catches a missing one. Byte-compare a rendered wrapper before and after a
  refactor with `/usr/bin/cmp`, since the agent shell may wrap `diff`.
- A `symlink_<name>` source holds the link *target* as its content, and may
  be a template. Change the target's source, not the link.
- Only the TCV config dir has a `settings.json`. It is rendered from
  `ai/ai-data.yaml.tmpl` (plugins, marketplaces, permission policy) plus
  literals in `settings.json.tmpl`; change the data partial, not the JSON.

## Off limits

`secrets/data/`, `*.age`, and anything under `~/.ssh`, `~/.gnupg`, `~/.aws`
hold live credentials. Edit the shape (key names, templates, schemas), never
the value, and never run a decrypting command.
