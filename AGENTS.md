<!-- AIW-MANAGED: repository-agent-policy-v2 -->
# Repository Agent Policy — ansible-arch

Project ID: `ansible-arch`

## Resolve durable project knowledge at runtime

```bash
aiw project path ansible-arch      # preferred
# fallback: $AIW_VAULT/10-projects/ansible-arch
```

Read `90-ai/context.md` first — it carries the boundaries and the traps. Then
`index.md`, `project.md` and the standards profile, before substantial work.
Migrated to the OKF vault 2026-08-15; the old Master-Mind directory is
historical.

The bundle also holds what this file deliberately does not duplicate:

| Question | Document |
|---|---|
| Why is it built this way? | `00-governance/decisions/` — eight ADRs |
| What must be true before work is done? | `60-quality/quality-plan.md` |
| How do I operate or deploy it? | `70-operations/runbook.md`, `deployment.md` |
| What is next, and what blocks it? | `10-planning/roadmap.md` → `50-execution/phases/` |

## What This Is

Idempotent Ansible playbook for provisioning and managing Arch Linux workstations. A single playbook (`site.yml`) targets multiple machines — differences are handled entirely via host variable feature flags.

**Targets:**
- `jolly-LOQ-arch` — physical dev laptop, local connection (NVIDIA, Hyprland, DisplayLink). Also the **control node**: the playbook runs against the machine it runs on.

There is no second target. The `forge-dev` VM was destroyed 2026-06-24 (FORGE-73); VLAN 30 is reserved for a replacement that does not exist. This is why fresh-machine reproducibility is still unproven — every role runs against a machine already in the target state.

## Common Commands

```bash
# Install required collections (one-time setup)
ansible-galaxy collection install -r requirements.yml

# Full run against a single host
ansible-playbook site.yml -l jolly-LOQ-arch --ask-become-pass

# Run a single role by tag
ansible-playbook site.yml -l jolly-LOQ-arch --tags editor --ask-become-pass

# Dry run — see what would change without applying
ansible-playbook site.yml -l jolly-LOQ-arch --check --diff --ask-become-pass

# List all tasks
ansible-playbook site.yml --list-tasks
```

## Architecture

### Role Structure

Roles run in sequence via `site.yml`, which is **authoritative for the role list and the order**. Do not copy that list into a document — a "19 roles" claim written on 2026-03-25 was still being repeated in four places on 2026-08-19, by which time there were 23.

```bash
ls -d roles/*/ | wc -l                    # roles on disk
grep -cE '^\s+- role: ' site.yml          # roles wired into the play
```

Most roles are a single `tasks/main.yml`. Some carry more, and that is fine when it is warranted:

- `defaults/` — role-internal tunables with sensible defaults (`ai-tools`, `ai-workspace`, `networking`). **Not** for host feature flags.
- `templates/` — `ai-tools`, `base` (`refind.conf`).
- `files/` — `aur-audit` (`aur-audit.sh`).
- `handlers/` — `networking`.

Order matters, and flows: foundation (`base` first — packages, paru, locale, kernels, bootloader) → desktop → userland → applications → hardware and sync → configuration (`dotfiles`, then `ai-workspace`) → `services`.

The `services` role always runs last — it enables systemd services for everything installed by prior roles.

### Feature Flag Pattern

Host differences are controlled by boolean flags in `inventory/host_vars/<hostname>.yml`. Roles check these at the task level with `when: <flag> | bool`. Always use the `| bool` filter.

```yaml
# In inventory/host_vars/<hostname>.yml
gpu_nvidia: false
hyprland: false
bluetooth: false
remote_desktop: true
```

```yaml
# In a role's tasks/main.yml
- name: Install NVIDIA drivers
  community.general.pacman:
    name: nvidia-dkms
  when: gpu_nvidia | bool
```

Available flags: `ai_tools`, `gpu_nvidia`, `hyprland`, `bluetooth`, `wifi`, `displaylink`, `ios_tools`, `printing`, `insync`, `remote_desktop`, `plymouth`, `btrfs`, `node_exporter`, `syncthing`

Two roles are gated at the **role** level in `site.yml` rather than per-task — `ai-tools` (`ai_tools`) and `syncthing` (`syncthing`). Everything else gates inside the role, so the role runs and its tasks skip.

### Bootloader Variable

`bootloader` is a string (not a boolean flag) controlling which bootloader is installed and configured:
- `refind` — installs rEFInd, deploys `refind.conf` from template, syncs rEFInd-minimal theme, installs `refind-btrfs` (AUR, when `btrfs: true`)
- `grub` — installs GRUB package only (no `grub-install` automation)

Additional rEFInd host_vars (required when `bootloader: refind`):
- `refind_default_selection` — kernel name string for `default_selection` in refind.conf
- `refind_background_src` — absolute path to source image (JPEG/PNG); converted to PNG and copied to ESP

The rEFInd theme (`rEFInd-minimal`) is cloned from GitHub to `/tmp/rEFInd-minimal` on first run (idempotent via `update: false`) and rsynced to `/boot/EFI/refind/themes/rEFInd-minimal/`. The background is only converted once (`creates:` guard).

### Variables Scope

**There is no `group_vars`.** Two kinds of variable exist, and conflating them is the common mistake:

| Kind | Lives in | Examples |
|---|---|---|
| Host feature flags and machine identity | `inventory/host_vars/<host>.yml` | `hostname`, `timezone`, `locale`, `kernels`, `dotfiles_packages`, `bootloader`, every flag above |
| Role-internal tunables | that role's `defaults/main.yml` | `aiw_install_mode`, `networking_dns_servers`, `antigravity_hub_version` |

Host flags have **no default anywhere** — not in `group_vars`, not via `| default(...)`. Every gate is a bare `when: <flag> | bool`.

⚠️ **An absent flag is a hard failure, not a skip.** Ansible treats an undefined variable in a `when:` as fatal, so the play **aborts on that host mid-run** — after the earlier roles have already applied, leaving the machine half-configured:

```
fatal: [host]: FAILED! => A 'when' expression failed: 'syncthing' is undefined
```

That is the intended safety property — a missing flag is loud rather than silently guessed — but it means **every flag must be present in every host_vars file**, not merely the ones a given machine wants on.

### Package Installation Modules

- **Native packages (pacman):** `community.general.pacman:`
- **AUR packages:** `kewlfft.aur.aur:` with `use: paru`

AUR tasks must run as non-root — always set `become: false` on AUR tasks.

### Privilege Pattern

The play runs with `become: true`. Override selectively:
- `become: false` — AUR installs (makepkg requires non-root)
- `scope: user` on `ansible.builtin.systemd` — user-level services (PipeWire, the `aur-audit` timer)

**Facts gather as root, so `ansible_env.HOME` is `/root`.** Write user-level paths explicitly — `/home/joseph/...` — as `dotfiles`, `dev-tools`, `services`, `aur-audit`, `ai-tools` and `ai-workspace` all do. A first cut of `aur-audit` used `ansible_env.HOME` and created `/root/.config`.

### Idempotency Conventions

- Use `state: present` for packages
- Use `lineinfile` with `regexp:` for config file edits
- Use `creates:` with command tasks (e.g., `creates: /usr/bin/paru` for the paru bootstrap)
- Use `update: false` on `git` tasks (clone once, don't pull on every run)
- Add `changed_when: false` to commands that always report changed (e.g., `locale-gen`, `stow --restow`)

**Verify idempotency by applying twice.** The second run must report `changed=0`; a task that reports `changed` on every run is a bug to file, not noise to wave through. One such task appended 19 duplicate `github.com` entries to `known_hosts` across repeated applies before anyone looked.

**A `creates:` guard that is already satisfied makes a task report `ok` without executing.** A green run only proves the code path ran if you know the guard was open.

### Adding a New Role

1. Create `roles/<name>/tasks/main.yml`
2. Add the role to `site.yml` in the appropriate sequence position with a matching `tags:` entry
3. If conditional, gate tasks with `when: <flag> | bool` and add the flag to every host_vars file
4. If it installs services, add enablement tasks to `roles/services/tasks/main.yml`
5. Update the role table in `README.md`


## Change isolation and completion

Substantial writes go on an ordinary task branch in this checkout —
`ai/<agent>/<task-id>-<slug>`. **Never a git worktree**, unless Joseph asks for
one explicitly. Merges to `main` are Joseph's unless the task brief records a
delegation.

Run the applicable quality gates and record the evidence before declaring work
complete. The gates and the current measured lint baseline are in
`60-quality/quality-plan.md` in the knowledge bundle.

**Merged is not shipped.** This repository configures a machine; a merged PR
changes nothing until `ansible-playbook` has been applied and the recap read.
`ansible-playbook` apply runs are human-only — the play runs as root against
the daily-driver laptop. Agents may run `--syntax-check`, `--list-tasks`,
`ansible-lint` and `yamllint` freely, and hand over apply commands one per
message.

⚠️ **`--check` is not a safe preview in this repo.** Four tasks carry
`check_mode: false` — `roles/ai-workspace/tasks/main.yml:28` and
`roles/ai-tools/tasks/main.yml:27,97,144`, documented as deliberate at
`ai-tools` line 17 — so a check run **really creates those directories** and
still needs the become password. Treat `--check --diff` as a run that writes,
and hand it over like any apply.

## Security posture (do not "improve" away)

- `SkipReview` must stay ABSENT — paru reviews PKGBUILDs by default and the
  absence of the opt-out is the guarantee.
- The passwordless-pacman grant and `--noconfirm` paru bootstrap are
  documented conveniences with revisit conditions in `roles/base/tasks/main.yml`.
