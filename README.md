# ansible-arch

![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=flat&logo=ansible&logoColor=white)
![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat&logo=arch-linux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=flat)
![Last Commit](https://img.shields.io/github/last-commit/thejollydev/ansible-arch?style=flat)

Idempotent Ansible playbook for automated Arch Linux workstation provisioning and configuration management.

## Overview

A single playbook that fully configures an Arch Linux workstation from a minimal base install — packages, AUR helper, dotfiles, services, and system settings. Machine differences are handled via host variable feature flags, keeping the codebase DRY across multiple targets.

**Targets:**
| Host | Role | Connection |
|------|------|------------|
| `jolly-LOQ-arch` | Physical dev laptop (NVIDIA, Hyprland, DisplayLink) | local |
| `forge-dev` | Arch Linux KDE VM on Proxmox (XRDP, no GPU) | SSH |

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
ansible-playbook site.yml -l forge-dev --ask-become-pass

# Single role
ansible-playbook site.yml -l jolly-LOQ-arch --tags editor --ask-become-pass

# Dry run — see what would change without applying
ansible-playbook site.yml -l forge-dev --check --diff --ask-become-pass

# List all tasks
ansible-playbook site.yml --list-tasks
```

## Roles

| Role | Description | Conditional |
|------|-------------|-------------|
| `base` | Core packages, paru (AUR helper), locale, timezone, hostname, kernels, GRUB, snapper, zram, reflector | — |
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
| `apps` | firefox, discord, thunderbird, obsidian, libreoffice, etc. | — |
| `apps-aur` | bitwarden, vscode, jetbrains-toolbox, slack, zoom, etc. | — |
| `printing` | CUPS, sane-airscan, Canon PIXMA driver | `printing` |
| `hardware` | DisplayLink, iOS tools, Plymouth | per-flag |
| `insync` | Insync + Dolphin plugin | `insync` |
| `remote-desktop` | XRDP + xorgxrdp | `remote_desktop` |
| `dotfiles` | Clone dotfiles repo, GNU Stow deploy | — |
| `services` | Enable all system + user systemd services | per-flag |

## Host Variables

Machine differences are controlled by feature flags in `inventory/host_vars/`. Each role checks its relevant flag before running:

```yaml
# inventory/host_vars/forge-dev.yml (excerpt)
gpu_nvidia: false
hyprland: false
bluetooth: false
wifi: false
remote_desktop: true
printing: true
insync: true
```

No duplicate roles, no separate playbooks — variables drive the differences.

## Structure

```
ansible-arch/
├── inventory/
│   ├── hosts.yml
│   └── host_vars/
│       ├── jolly-LOQ-arch.yml
│       └── forge-dev.yml
├── roles/
│   └── <role>/tasks/main.yml
├── site.yml
├── requirements.yml
└── ansible.cfg
```

## Stack

- **Ansible** — configuration management
- **community.general** — `pacman` module for native packages
- **kewlfft.aur** — `aur` module wrapping `paru` for AUR packages
- **GNU Stow** — dotfiles symlink management
