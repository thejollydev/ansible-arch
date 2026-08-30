# ansible-arch — Agent Instructions

## What this repository is

An idempotent Ansible playbook that rebuilds an Arch Linux **workstation** from
a minimal install to a fully configured machine. One `site.yml`, 23 roles, and
every machine difference expressed as a boolean feature flag in
`inventory/host_vars/<hostname>.yml` — no per-host playbooks and no
`group_vars`.

It manages exactly one host today, `jolly-LOQ-arch`, which is both the control
node and the managed node over a `local` connection.

**Servers are out of scope.** Those live in `bezaforge-infrastructure`.

The `dotfiles` role here redeploys the `~/dotfiles` stow packages, so a change
there and a change here are frequently one task: **stow owns harness
configuration, this repository owns system behaviour.**

## Hard rules

- **Never execute `ansible-playbook` in apply mode.** This playbook mutates a
  daily-driver laptop, and `become: true` means a bad task runs as root against
  a live system. Hand the command to the maintainer instead, one per message.
- **`--check` is not a safe read-only run here.** Four tasks carry
  `check_mode: false`, so a check run really creates directories and still needs
  the become password. The genuinely read-only commands are `--syntax-check`,
  `--list-tasks`, `ansible-lint` and `yamllint`; run those freely.
- **Edit and commit freely** — roles, `site.yml`, inventory and host_vars,
  repository docs — on a branch, through a pull request.
- **Merging to `main` is the maintainer's** unless a task record delegates it.

## Settled — do not re-raise

- **Feature flags live in host_vars** and nowhere else.
- **AUR packages go through `paru`**, with a recorded supply-chain posture.
- **`dotfiles` is a separate repository.**
- **rEFInd over GRUB**; `bootloader` is a string, not a flag.
- **Role names are hyphenated** (`desktop-kde`, `apps-aur`) and the `site.yml`
  tag always matches the role name. `ansible-lint` objects to this; it is house
  convention and the objection is expected.
- **The laptop is its own control node.**
- **XRDP is being phased out.**

## Traps

Each line is something that actually went wrong here.

- **A merged PR has changed nothing on the laptop.** This is a
  config-management repo: merged is not shipped. Work ships when
  `ansible-playbook` has been applied and the result verified live.
- **An always-`changed` task is an idempotency bug, not noise.** The
  `Accept GitHub SSH host key` task reported `changed` on every run for at least
  three applies and was written off as "SSH host key only" — it had appended
  **19 duplicate** `github.com` entries to `known_hosts`. If the recap says
  `changed=1`, find out which task.
- **A `creates:` guard makes a task report `ok` without ever running.** An apply
  returned `ok=9 changed=1 failed=0` and was nearly recorded as proof that link
  mode worked; the install task had been skipped by its own guard and the mode
  variable was never read. A green run proves the code path executed only if you
  know the guard was open.
- **`site.yml` runs `become: true`, so facts gather as root.**
  `ansible_env.HOME` is `/root`. Write user paths explicitly.
- **AUR tasks must set `become: false`** — `makepkg` refuses to run as root.
- **The paru guarantee is the *absence* of `SkipReview`**, asserted in
  `roles/base`. Never "improve" this by adding an explicit enable flag — there
  isn't one, and adding a lookalike would hide a removal.
- **`ansible-lint` fails 42 checks today and that is the known baseline**, not a
  regression you introduced. Nine are `role-name` on hyphenated names, which is
  house convention.

## Two roles provision something retired

`roles/ai-workspace` and parts of `roles/ai-tools` install tooling for a project
that has been retired, and neither its checkout nor its CLI exists on this
machine any more.

Those roles have not been reworked. Treat them as stale rather than
authoritative — raise it rather than following it, and do not quietly delete
them either; what replaces them is the maintainer's call.

## Adding a role

A new role is added to `site.yml` in dependency order with a matching tag, its
flag goes into host_vars, and any service it installs is enabled in
`roles/services` — which always runs last.

- Every role has a `tasks/main.yml`. Five have grown `defaults/`, `templates/`,
  `files/` or `handlers/`; nothing else should without a reason.
- All variables live in host_vars. No `group_vars`, no role `defaults/` for
  feature flags — a flag that is not in host_vars is invisible.
- Always filter with `| bool`: `when: hyprland | bool`.

## Contributing

```bash
git switch -c <short-descriptive-branch>
git push -u origin <branch>
gh pr create --fill
```

Nothing is committed or pushed directly to `main`.
