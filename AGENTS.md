# ansible-arch — Agent Instructions

Read by every agent: Codex and Antigravity read this file natively, Claude Code
reads it through `CLAUDE.md`. Machine-wide conventions live in
`~/.claude/CLAUDE.md`.

## What this repository is

An idempotent Ansible playbook that rebuilds an Arch Linux **workstation** from
a minimal install to a fully configured machine. One `site.yml`, 23 roles, and
every machine difference expressed as a boolean feature flag in
`inventory/host_vars/<hostname>.yml` — no per-host playbooks and no
`group_vars` (`adr-ansib-0001`).

It manages exactly one host today, `jolly-LOQ-arch`, which is both the control
node and the managed node over a `local` connection (`adr-ansib-0007`).

**Servers are out of scope.** Those are `bezaforge-infrastructure`.

## One workspace, three repositories

`ansible-arch`, `dotfiles` and `dev-environment` are **one Never4gA workspace**,
not three — they are what it is, not things it depends on (ruled 2026-08-24).

- `never4ga workspace resolve` returns the same workspace from any of them.
- **The decision register is shared.** Records carry an origin prefix,
  `adr-ansib-NNNN_*` and `adr-deven-NNNN_*`, but they are one register binding
  all three. A `deven` decision constrains work here; read both prefixes.
- The `dotfiles` role in this repository redeploys the `~/dotfiles` stow
  packages, so a change there and a change here are frequently one task.
  **Stow owns harness configuration; this repository owns system behaviour.**

## Startup

```bash
never4ga --actor <client>/<model> context startup --client <client> --cwd "$PWD"
never4ga workspace resolve
```

`--actor` is a global flag and must come **before** the subcommand. Name
yourself in it (`claude-code/claude-opus-5`, not `claude-code`).

Without Never4gA available, the vault is at `~/Vaults/never-knowledge` and this
workspace at `10_Workspaces/Dev-Environment/`. Read
`Context/agent-context_ansible-arch.md`,
`Architecture/machine-reference_jolly-loq-arch.md` (a snapshot — verify against
the live box), `Architecture/runbook.md` and `Plans/quality-plan.md`.

## Hard rules

- **Never execute `ansible-playbook` in apply mode.** This playbook mutates
  Joseph's daily-driver laptop, and `become: true` means a bad task runs as root
  against a live system. Hand him the command instead, one per message.
- **`--check` is not a safe read-only run here.** Four tasks carry
  `check_mode: false` (in `ai-workspace` and `ai-tools`), so a check run really
  creates directories and still needs the become password. The genuinely
  read-only commands are `--syntax-check`, `--list-tasks`, `ansible-lint` and
  `yamllint`; run those yourself freely.
- **Edit and commit freely** — roles, `site.yml`, inventory and host_vars,
  repository docs — on a branch, through a pull request.
- **Merging to `main` is Joseph's** unless a task brief records a delegation.
- **Never add an AI as co-author** on a commit or in a contributors list.

## Settled — do not re-raise

- **Feature flags live in host_vars** and nowhere else (`adr-ansib-0001`).
- **AUR packages go through `paru`** (`adr-ansib-0002`), and the supply-chain
  posture is recorded in `adr-ansib-0005`.
- **`dotfiles` is a separate repository** (`adr-ansib-0004`).
- **rEFInd over GRUB** (`adr-ansib-0003`); `bootloader` is a string, not a flag.
- **Role names are hyphenated** (`desktop-kde`, `apps-aur`) and the `site.yml`
  tag always matches the role name (`adr-ansib-0006`). `ansible-lint` objects to
  this; it is house convention and the objection is expected.
- **The laptop is its own control node** (`adr-ansib-0007`).
- **XRDP is being phased out** (`adr-ansib-0008`).

## Traps

Each line is something that actually went wrong here.

- **A merged PR has changed nothing on the laptop.** This is a
  config-management repo: merged is not shipped. Work ships when
  `ansible-playbook` has been applied and the result verified live.
- **An always-`changed` task is an idempotency bug, not noise.** The
  `Accept GitHub SSH host key` task reported `changed` on every run for at least
  three applies and was written off in the log as "SSH host key only" — it had
  appended **19 duplicate** `github.com` entries to `known_hosts` (#755). If the
  recap says `changed=1`, find out which task.
- **A `creates:` guard makes a task report `ok` without ever running.** A
  2026-08-16 apply returned `ok=9 changed=1 failed=0` and was nearly recorded as
  proof that link mode worked. The install task had been skipped by its own
  guard and the mode variable was never read (#754). A green run proves the code
  path executed only if you know the guard was open.
- **`site.yml` runs `become: true`, so facts gather as root.**
  `ansible_env.HOME` is `/root`, not `/home/joseph`. Write user paths
  explicitly.
- **AUR tasks must set `become: false`** — `makepkg` refuses to run as root.
- **The paru guarantee is the *absence* of `SkipReview`**, asserted in
  `roles/base`. Never "improve" this by adding an explicit enable flag — there
  isn't one, and adding a lookalike would hide a removal.
- **`ansible-lint` fails 42 checks today and that is the known baseline**, not a
  regression you introduced. Nine are `role-name` on hyphenated names, which is
  house convention. Compare against `Plans/quality-plan.md` in the vault before
  reporting lint as broken.
- **`git remote get-url --all origin` returns fetch URLs — GitHub only.** Use
  `--push --all` for anything that iterates remotes.
- **`gh pr merge --delete-branch` deletes on GitHub only.** GitLab and Gitea
  keep the branch. Sweep the mirrors.

## Two roles now provision something retired

`roles/ai-workspace` and parts of `roles/ai-tools` install the `aiw` CLI and the
`ai-workspace` checkout. **That project is retired** — archived in the vault at
`90_Archive/Workspaces/AI-Workspace/`, superseded by Never4gA — and neither
`~/Projects/ai-workspace` nor `~/.local/bin/aiw` exists on this machine.

Those roles have not been reworked. Treat them, and any document referring to
`aiw`, as stale rather than authoritative; raise it rather than following it,
and do not quietly delete them either — what replaces them is Joseph's call.

## Adding a role

A new role is added to `site.yml` in dependency order with a matching tag, its
flag goes into host_vars, and any service it installs is enabled in
`roles/services` — which always runs last.

- Every role is `tasks/main.yml`. Five have grown `defaults/`, `templates/`,
  `files/` or `handlers/`; nothing else should without a reason.
- All variables live in host_vars. No `group_vars`, no role `defaults/` for
  feature flags — a flag that is not in host_vars is invisible.
- Always filter with `| bool`: `when: hyprland | bool`.

## Branching and remotes

```bash
git switch -c <short-descriptive-branch>
git push -u origin <branch>
gh pr create --fill
```

One `origin` with three push URLs — GitHub `thejollydev/ansible-arch` (fetch and
primary), GitLab, and Gitea at `git.bezaforge.dev:2222/joseph/ansible-arch` — so
a plain `git push origin` reaches all three, and `main` must be the same commit
on each.
