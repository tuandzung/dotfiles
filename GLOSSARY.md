# Dotfiles

One person's machines, set up from a single chezmoi source: the shell, the
desktop, the tools, and the AI agents that work on them.

## Language

**Context**:
A work identity with its own home tree under `~/Working`, such as
`Enterprise/TCV` or `Personal`, each with its own tools and credentials.
_Avoid_: workspace, profile, environment

**Config dir**:
The Claude directory a context runs from, named by `CLAUDE_CONFIG_DIR`;
`~/.claude` is the one used outside any context.
_Avoid_: Claude home, Claude profile
