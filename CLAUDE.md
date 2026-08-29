# CLAUDE.md — ansible-arch

`AGENTS.md` is authoritative. Read it first; everything harness-neutral lives
there on purpose, because Codex and Antigravity read it too and a rule written
only here is invisible to both (`adr-deven-0005`).

This file carries Claude-Code-specific notes only.

## Claude Code specifics

- Machine-wide conventions are in `~/.claude/CLAUDE.md`. Do not restate them.
- **Never run `ansible-playbook` through Bash**, in apply mode or with
  `--check`. `AGENTS.md` explains why `--check` is not safe in this repository.
  Hand Joseph the command; he runs it.
- The `never4ga-startup` Skill opens a session against this workspace. Prefer
  it over assembling the startup commands by hand.
