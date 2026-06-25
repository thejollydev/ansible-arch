---
vault_canonical: 05_Projects/ansible-arch/
vault_mirrors: []
---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Idempotent Ansible playbook for provisioning and managing Arch Linux workstations. A single playbook (`site.yml`) targets multiple machines — differences are handled entirely via host variable feature flags.

**Targets:**
- `jolly-LOQ-arch` — physical dev laptop, local connection (NVIDIA, Hyprland, DisplayLink)

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

19 roles run in sequence via `site.yml`. Every role uses only `tasks/main.yml` — no `defaults/`, `vars/`, or `handlers/` subdirectories. All configuration is driven from host variables.

Role execution order matters (dependencies flow top to bottom):
`base` → `networking` → `bluetooth` → `audio` → `gpu-nvidia` → `desktop-kde` → `desktop-hyprland` → `shell` → `terminal` → `editor` → `dev-tools` → `apps` → `apps-aur` → `printing` → `hardware` → `insync` → `remote-desktop` → `dotfiles` → `services`

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

Available flags: `gpu_nvidia`, `hyprland`, `bluetooth`, `wifi`, `displaylink`, `ios_tools`, `printing`, `insync`, `remote_desktop`, `plymouth`, `btrfs`, `node_exporter`, `syncthing`

### Bootloader Variable

`bootloader` is a string (not a boolean flag) controlling which bootloader is installed and configured:
- `refind` — installs rEFInd, deploys `refind.conf` from template, syncs rEFInd-minimal theme, installs `refind-btrfs` (AUR, when `btrfs: true`)
- `grub` — installs GRUB package only (no `grub-install` automation)

Additional rEFInd host_vars (required when `bootloader: refind`):
- `refind_default_selection` — kernel name string for `default_selection` in refind.conf
- `refind_background_src` — absolute path to source image (JPEG/PNG); converted to PNG and copied to ESP

The rEFInd theme (`rEFInd-minimal`) is cloned from GitHub to `/tmp/rEFInd-minimal` on first run (idempotent via `update: false`) and rsynced to `/boot/EFI/refind/themes/rEFInd-minimal/`. The background is only converted once (`creates:` guard).

### Variables Scope

**No group_vars, no role defaults — all variables live in host_vars.** Variables available to roles: `hostname`, `timezone`, `locale`, `kernels` (list), `dotfiles_packages` (list), `bootloader` (string), and all feature flags above.

### Package Installation Modules

- **Native packages (pacman):** `community.general.pacman:`
- **AUR packages:** `kewlfft.aur.aur:` with `use: paru`

AUR tasks must run as non-root — always set `become: false` on AUR tasks.

### Privilege Pattern

The play runs with `become: true`. Override selectively:
- `become: false` — AUR installs (makepkg requires non-root)
- `scope: user` on `ansible.builtin.systemd` — user-level services (PipeWire, etc.)

### Idempotency Conventions

- Use `state: present` for packages
- Use `lineinfile` with `regexp:` for config file edits
- Use `creates:` with command tasks (e.g., `creates: /usr/bin/paru` for the paru bootstrap)
- Use `update: false` on `git` tasks (clone once, don't pull on every run)
- Add `changed_when: false` to commands that always report changed (e.g., `locale-gen`, `stow --restow`)

### Adding a New Role

1. Create `roles/<name>/tasks/main.yml`
2. Add the role to `site.yml` in the appropriate sequence position with a matching `tags:` entry
3. If conditional, gate tasks with `when: <flag> | bool` and add the flag to both host_vars files
4. If it installs services, add enablement tasks to `roles/services/tasks/main.yml`
