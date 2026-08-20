# ansible-arch

![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=flat&logo=ansible&logoColor=white)
![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat&logo=arch-linux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=flat)
![Last Commit](https://img.shields.io/github/last-commit/thejollydev/ansible-arch?style=flat)

**Status:** ✅ Active, maintenance tempo. Durable project knowledge lives in the OKF vault — `aiw project path ansible-arch`.

Idempotent Ansible playbook for automated Arch Linux workstation provisioning and configuration management.

## Overview

A single playbook that fully configures an Arch Linux workstation from a minimal base install — packages, AUR helper, dotfiles, services, and system settings. Machine differences are handled via host variable feature flags, keeping the codebase DRY across multiple targets.

**Targets:**
| Host | Role | Connection |
|------|------|------------|
| `jolly-LOQ-arch` | Physical dev laptop (NVIDIA, Hyprland, DisplayLink) | local |

## Prerequisites

```bash
# Install Ansible
sudo pacman -S ansible

# Install required collections
ansible-galaxy collection install -r requirements.yml
```

SSH key auth must be configured for any remote hosts.

## Usage

```bash
# Full run against a single host
ansible-playbook site.yml -l jolly-LOQ-arch --ask-become-pass

# Single role
ansible-playbook site.yml -l jolly-LOQ-arch --tags editor --ask-become-pass

# Dry run — see what would change without applying
ansible-playbook site.yml -l jolly-LOQ-arch --check --diff --ask-become-pass

# List all tasks
ansible-playbook site.yml --list-tasks
```

## Roles

`site.yml` is authoritative for the role list and the execution order; this table is a description of what each one does.

| Role | Description | Conditional |
|------|-------------|-------------|
| `base` | Core packages, paru (AUR helper), locale, timezone, hostname, kernels, bootloader (rEFInd or GRUB), snapper, zram, reflector | — |
| `networking` | NetworkManager, wireguard-tools, avahi, iwd | `wifi` |
| `bluetooth` | bluez, bluez-utils | `bluetooth` |
| `audio` | Full PipeWire stack | — |
| `gpu-nvidia` | nvidia-dkms, CUDA, cuDNN | `gpu_nvidia` |
| `desktop-kde` | KDE Plasma 6, SDDM, fonts | — |
| `desktop-hyprland` | Hyprland, uwsm, wofi, dunst, grim | `hyprland` |
| `shell` | zsh, plugins, starship, default shell | — |
| `terminal` | kitty, zellij, tmux | — |
| `editor` | Neovim | — |
| `dev-tools` | git, docker, languages, CLI utilities | — |
| `ai-tools` | Antigravity CLI (`agy`), Antigravity 2.0, Antigravity IDE, Codex CLI. Install-if-absent — all four self-update, so pinned versions are bootstrap only. Auth is never automated; see `~/POST-INSTALL.md` | `ai_tools` |
| `apps` | firefox, discord, thunderbird, obsidian, libreoffice, etc. | — |
| `apps-aur` | bitwarden, vscode, jetbrains-toolbox, slack, zoom, etc. | — |
| `aur-audit` | Weekly read-only AUR supply-chain audit — maintainer churn detection, user timer, `--self-test` | — |
| `printing` | CUPS, sane-airscan, Canon PIXMA driver | `printing` |
| `hardware` | DisplayLink, iOS tools, Plymouth | per-flag |
| `insync` | Insync + Dolphin plugin | `insync` |
| `remote-desktop` | XRDP + xorgxrdp. **Legacy** — `gnome-remote-desktop` is the standard choice for GNOME hosts, installed outside this playbook | `remote_desktop` |
| `syncthing` | Peer-to-peer file sync | `syncthing` |
| `dotfiles` | Clone dotfiles repo, GNU Stow deploy | — |
| `ai-workspace` | The `aiw` CLI, OKF validators, and the shared agent skills. Runs after `dotfiles`: stow owns harness config, this role owns system behaviour | — |
| `services` | Enable all system + user systemd services | per-flag |

## Host Variables

Machine differences are controlled by feature flags in `inventory/host_vars/`. Each role checks its relevant flag before running:

```yaml
# inventory/host_vars/<hostname>.yml (excerpt)
gpu_nvidia: false
hyprland: false
bluetooth: false
wifi: false
remote_desktop: true
printing: true
insync: true
```

No duplicate roles, no separate playbooks — variables drive the differences.

Host flags have no default anywhere: a flag left out of a host_vars file means the role never runs for that host. Role-internal tunables are different and *do* have defaults, in that role's `defaults/main.yml` (`ai-tools`, `ai-workspace`, `networking`).

## Structure

```
ansible-arch/
├── inventory/
│   ├── hosts.yml
│   └── host_vars/
│       └── jolly-LOQ-arch.yml
├── roles/
│   └── <role>/
│       ├── tasks/main.yml        # every role
│       ├── defaults/main.yml     # role-internal tunables, where needed
│       ├── templates/            # base, ai-tools
│       ├── files/                # aur-audit
│       └── handlers/             # networking
├── site.yml
├── requirements.yml
├── ansible.cfg
└── AGENTS.md                     # repository agent policy
```

## Stack

- **Ansible** — configuration management
- **community.general** — `pacman` module for native packages
- **kewlfft.aur** — `aur` module wrapping `paru` for AUR packages
- **GNU Stow** — dotfiles symlink management

## Notes

**Applying is a manual step.** A merged change to this repository has not
changed any machine until `ansible-playbook` is run against it. Apply, then
apply again — the second run should report `changed=0`.

**AUR installs are interactive by design.** paru presents PKGBUILDs for
review; the guarantee is the *absence* of a `SkipReview` setting. A run that
appears to hang on an AUR package is waiting for you.
