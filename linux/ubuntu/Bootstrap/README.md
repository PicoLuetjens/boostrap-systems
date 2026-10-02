**Ubuntu Bootstrap** (tested on Ubuntu 24.04 LTS, x86_64)

**Pre Setup**:
- nothing to install manually. apt, gcc/build tools (installed as `build-essential` if missing) and all other requirements are handled by the script.
- clone this repo (or download it) and make the script executable:
```bash
chmod +x bootstrap.sh
```

**Start**:
- run as your **normal user**, NOT with sudo (the script asks for your sudo password once):
```bash
./bootstrap.sh
```
- logs are written to *logs/*. the script can be run again at any time, already installed software and unchanged dotfiles are skipped.
- after the script finished: **log out and log in again** (zsh as new default shell, docker group membership).
- on the first start of kitty/zsh the Powerlevel10k configuration wizard opens. afterwards copy *~/.p10k.zsh* into the dotfiles repo, then it is deployed automatically (run the wizard again with `p10k configure`).

**What it does**:
1. *modules/apt.sh*: installs everything from *config/software.json*. apt is only used where Ubuntu's version is current, everything else comes directly from the official sources (external apt repos, .deb downloads, GitHub releases, official install scripts)
2. *modules/package_manager.sh*: installs Node.js via Volta and Python 3.14 via uv
3. *modules/dotfiles.sh*: clones the dotfiles repo to *~/dotfiles* and copies the configs as defined in *config/dotfiles.json*. changed files are backed up as *.bak*
4. *modules/shell.sh*: sets zsh as default shell

**Shell & Terminal**:
- kitty (official installer, *~/.local/kitty.app*, registered as default terminal) with zsh, Oh My Zsh, Powerlevel10k and the plugins zsh-autosuggestions / zsh-syntax-highlighting.

**LibreWolf policies**:
- the policies from *mf-base/policies.json* are merged with LibreWolf's default policies and written to */etc/librewolf/policies/policies.json*. this file replaces the default one completely, so the merge keeps all LibreWolf defaults (uBlock Origin, telemetry settings, ...). it is not touched by LibreWolf updates. run the script again after an update to pick up new LibreWolf defaults.

**Manual steps**:
- import *mf-base/tabliss.json* in the Tabliss addon settings (path is shown at the end of the script).

**Notes**:
- Docker: installs Docker Engine (official Docker apt repo), not Docker Desktop.
- installed directly instead of apt (apt versions too old): kitty, Neovim (*/opt/nvim*), Go (*/usr/local/go*), just, ripgrep, tree-sitter. versions are resolved at install time (latest release).
