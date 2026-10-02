**macOS Bootstrap** (Apple Silicon and Intel)

**Pre Setup**:
- nothing to install manually. Homebrew (including the Xcode Command Line Tools) is installed by the script if missing.
- download this repo (or clone it, macOS asks to install the Command Line Tools on the first `git` call) and make the script executable:
```bash
chmod +x bootstrap.sh
```

**Start**:
- run in *Terminal.app* as your **normal user**, NOT with sudo (the script asks for your password once):
```bash
./bootstrap.sh
```
- logs are written to *logs/*. the script can be run again at any time, already installed software and unchanged dotfiles are skipped.
- after the script finished: **log out and log in again**, then open **iTerm2**.
- on the first start of iTerm2 the Powerlevel10k configuration wizard opens. afterwards copy *~/.p10k.zsh* into the dotfiles repo, then it is deployed automatically (run the wizard again with `p10k configure`).

**What it does**:
1. *modules/brew.sh*: installs Homebrew if missing, then everything from *config/software.json* (formulae, casks, official install scripts, git repos)
2. *modules/package_manager.sh*: installs Node.js via Volta and Python 3.14 via uv
3. *modules/dotfiles.sh*: clones the dotfiles repo to *~/dotfiles* and copies the configs as defined in *config/dotfiles.json*. changed files are backed up as *.bak*
4. *modules/shell.sh*: makes sure zsh is the default shell and sets the iTerm2 profile from the dotfiles as default profile

**Shell & Terminal**:
- iTerm2 with zsh, Oh My Zsh, Powerlevel10k and the plugins zsh-autosuggestions / zsh-syntax-highlighting.
- the iTerm2 profile (*iterm2/pico.json* in the dotfiles) is a Dynamic Profile: font, colors (Catppuccin Mocha), transparency and window size. iTerm2 loads it automatically.

**LibreWolf policies**:
- the policies from *mf-base/policies.json* are merged into LibreWolf's own *policies.json* inside the app (*/Applications/LibreWolf.app/Contents/Resources/distribution/*). the original is saved once as *policies.json.orig*. a LibreWolf update replaces the app, so run the script again after an update.

**Manual steps**:
- import *mf-base/tabliss.json* in the Tabliss addon settings (path is shown at the end of the script).

**Notes**:
- all software comes from Homebrew (current versions). only Oh My Zsh, Powerlevel10k and the zsh plugins are installed directly from their official sources.
- the scripts are compatible with the bash 3.2 that ships with macOS.
