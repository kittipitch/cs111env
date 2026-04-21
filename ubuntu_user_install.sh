#!/bin/bash
# Ubuntu Setup Script for CS Department
# @Author: kk
# @Date:   2024-05-05 23:58:35
# @Last Modified by:   kk
# @Last Modified time:  2026-04-05 11:00:00
#
# This script follows the steps in UBUNTU.md for Ubuntu 24.04 setup

# ============================================================
# LAB_MACHINE: Set to true for lab machines (includes Ruby, Prolog, Racket)
# Set to false for standard student setup (Python, Haskell, C/C++, Go, NodeJS, Docker)
# ============================================================
LAB_MACHINE=false

# ============================================================
# System Setup
# ============================================================

echo "==> Updating system..."
sudo apt update && sudo apt upgrade -y

echo "==> Setting timezone..."
sudo timedatectl set-timezone Asia/Bangkok

# ============================================================
# Basic Tools (UBUNTU.md Step 2)
# ============================================================

echo "==> Installing basic tools..."
sudo apt install -y \
  tar zip unzip git build-essential \
  python3-pip python3-venv pipenv mypy \
  tmux dos2unix xclip \
  emacs-nox vim neovim bat \
  wget curl gnupg ca-certificates \
  kdiff3

# ============================================================
# Dot Files (UBUNTU.md Step 3)
# ============================================================

echo "==> Installing dot files..."
git clone --depth 1 -q https://github.com/kittipitch/ubuntu_home.git /tmp/temp 2>/dev/null || true
if [ -d /tmp/temp ]; then
  cd /tmp/temp/
  mv .bashrc ~/ 2>/dev/null || true
  mv .bash_profile ~/ 2>/dev/null || true
  mv .dircolors ~/ 2>/dev/null || true
  mv .gitconfig ~/ 2>/dev/null || true
  mv .emacs.d ~/ 2>/dev/null || true
  mv .config ~/ 2>/dev/null || true
  source ~/.bash_profile 2>/dev/null || true
  cd
fi

# ============================================================
# Programming Fonts (UBUNTU.md Step 4)
# ============================================================

echo "==> Installing programming fonts..."
# FiraCode (simple option)
sudo apt install -y fonts-firacode 2>/dev/null || true

# IosevkaTerm Nerd Font (optional, prettier)
cd ~/Downloads 2>/dev/null || cd ~/ && cd Downloads
wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/IosevkaTerm.zip 2>/dev/null || true
if [ -f IosevkaTerm.zip ]; then
  unzip -q IosevkaTerm.zip -d iosevka
  sudo mkdir -p /usr/share/fonts/truetype/iosevka/
  sudo cp iosevka/*.ttf /usr/share/fonts/truetype/iosevka/
  sudo fc-cache -f -v 2>/dev/null || true
  # Set terminal font (may fail on non-GUI)
  dconf write /org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9/font "'IosevkaTerm Nerd Font Mono 15'" 2>/dev/null || true
  dconf write /org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9/use-system-font false 2>/dev/null || true
fi
cd ~

# ============================================================
# Base16 Color Scheme (UBUNTU.md Step 5)
# ============================================================

echo "==> Installing Base16 color scheme..."
git clone -q https://github.com/tinted-theming/tinted-shell.git "$HOME"/.config/tinted-shell 2>/dev/null || true

# ============================================================
# Python Setup (UBUNTU.md Steps 6-8)
# ============================================================

echo "==> Checking Python..."
python3 --version

echo "==> Installing uv"
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
if [ ! -d "$HOME/.venv" ]; then
    uv venv ~/.venv
else
    echo "Environment already exists! Moving on..."
fi

echo "==> Installing NumPy and Pandas..."
uv pip install numpy pandas --python ~/.venv

# ============================================================
# Sublime Text (UBUNTU.md Step 9)
# ============================================================

echo "==> Installing Sublime Text 4..."
sudo apt install -y apt-transport-https
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null
echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
sudo apt update
sudo apt install -y sublime-text

# ============================================================
# Haskell Setup via GHCup (UBUNTU.md Step 16)
# ============================================================

echo "==> Installing Haskell dependencies..."
sudo apt install -y build-essential curl libffi-dev libffi8 libgmp-dev libgmp10 libncurses-dev pkg-config

echo "==> Installing GHCup + GHC 9.6.7 + Cabal + Stack + HLS (non-interactive)..."
if ! command -v ghcup &> /dev/null; then
  # Set environment variables for non-interactive bootstrap
  # These match the pre-selected options:
  # - Base channel: ghcup (GHCup maintained)
  # - Pre-releases: No
  # - PATH: Append/Prepend (Adjust BASHRC)
  export BOOTSTRAP_HASKELL_NONINTERACTIVE=1
  export BOOTSTRAP_HASKELL_NO_UPGRADE=1
  export BOOTSTRAP_HASKELL_GHC_VERSION=9.6.7
  export BOOTSTRAP_HASKELL_CABAL_VERSION=3.10.3.0
  export BOOTSTRAP_HASKELL_INSTALL_STACK=1
  export BOOTSTRAP_HASKELL_INSTALL_HLS=1
  export BOOTSTRAP_HASKELL_ADJUST_BASHRC=1
  
  # Ensure we use the ghcup channel if requested (default is stable)
  export GHCUP_INSTALL_CHANNEL=ghcup

  curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh

  [[ -f "$HOME/.ghcup/env" ]] && source "$HOME/.ghcup/env"
fi

# Source env for rest of script
[[ -f "$HOME/.ghcup/env" ]] && source "$HOME/.ghcup/env"

echo "==> Verifying Haskell tools..."
ghcup --version
ghc --version
cabal --version

echo "==> Installing stack, HUnit, and HLS..."
ghcup install stack latest 2>/dev/null || true
ghcup install hls latest 2>/dev/null || true

if command -v cabal &> /dev/null; then
  cabal update 2>/dev/null || true
  cabal install --lib HUnit 2>/dev/null || true
fi

echo "==> Installing Ormolu (Haskell formatter)..."
if command -v stack &> /dev/null; then
  # Matches UBUNTU.md Step 17.1
  stack install ormolu-0.7.2.0 --resolver lts-22.44 2>/dev/null || true
fi

# ============================================================
# Git Configuration (UBUNTU.md Step 11)
# ============================================================

echo "==> Note: Remember to configure your Git identity later:"
echo "    git config --global user.name \"Your Name\""
echo "    git config --global user.email \"your.email@example.com\""

# ============================================================
# Java Setup (UBUNTU.md Step 17)
# ============================================================

echo "==> Installing OpenJDK 21..."
sudo apt install -y openjdk-21-jdk

echo "==> Checking Java version..."
java -version

# ============================================================
# NodeJS Setup (UBUNTU.md Step 19)
# ============================================================

echo "==> Installing NodeJS 24 LTS..."
sudo apt install -y curl gnupg ca-certificates
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs

# ============================================================
# Bun 1.3.11 (alternative to NodeJS)
# ============================================================

if ! command -v bun &> /dev/null; then
  echo "==> Installing Bun 1.3.11 (alternative to NodeJS)..."
  [[ -d ~/Downloads ]] || mkdir ~/Downloads
  cd ~/Downloads
  wget -q https://github.com/oven-sh/bun/releases/download/bun-v1.3.11/bun-linux-x64.zip --no-check-certificate
  unzip -q bun-linux-x64.zip
  sudo cp bun-linux-x64/bun /usr/bin/
  cd ~
fi

# ============================================================
# Go Setup (UBUNTU.md Step 20)
# ============================================================

echo "==> Installing Go 1.19.13..."
if ! command -v go &> /dev/null; then
  [[ -d ~/Downloads ]] || mkdir ~/Downloads
  cd ~/Downloads
  wget -q --no-check-certificate https://go.dev/dl/go1.19.13.linux-amd64.tar.gz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf go1.19.13.linux-amd64.tar.gz

  # Add to PATH (in .bashrc from dotfiles)
  [[ -f ~/.bash_profile ]] || ln -s ~/.profile ~/.bash_profile
  echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bash_profile 2>/dev/null || true
  source ~/.bash_profile 2>/dev/null || true
  cd ~
fi

echo "==> Checking Go version..."
go version

# ============================================================
# Docker Setup (UBUNTU.md Step 23)
# ============================================================

echo "==> Installing Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
sudo systemctl enable docker
sudo systemctl start docker

# ============================================================
# lazydocker (Terminal UI for Docker)
# ============================================================

if ! command -v lazydocker &> /dev/null; then
  echo "==> Installing lazydocker..."
  [[ -d ~/Downloads ]] || mkdir ~/Downloads
  cd ~/Downloads
  LAZYDOCKER_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
  curl -sLo lazydocker.tar.gz "https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz"
  tar xfz lazydocker.tar.gz
  sudo mv lazydocker /usr/local/bin
  cd ~
fi

# ============================================================
# fzf (UBUNTU.md Step 24)
# ============================================================

echo "==> Installing fzf..."
if ! [ -d ~/.fzf ]; then
  git clone -q --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
  yes | ~/.fzf/install
fi

# ============================================================
# Clean Utility (UBUNTU.md Step 25)
# ============================================================

if ! command -v clean &> /dev/null; then
  echo "==> Installing Clean language..."
  [[ -d ~/Downloads ]] || mkdir ~/Downloads
  cd ~/Downloads
  wget -qO clean.tar.bz2 https://master.dl.sourceforge.net/project/clean/clean/3.4/clean-3.4.tar.bz2
  tar xvf clean.tar.bz2
  cd clean-3.4
  make all
  sudo make install
  cd ~
fi

# ============================================================
# GitHub CLI (UBUNTU.md Step 26)
# ============================================================

echo "==> Installing GitHub CLI..."
if ! command -v gh &> /dev/null; then
  (type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) && \
  sudo mkdir -p -m 755 /etc/apt/keyrings && \
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.d/github-cli.list > /dev/null && \
  sudo apt update && sudo apt install gh -y
fi

# ============================================================
# Disable conflicting terminal shortcut (UBUNTU.md Step 15.6)
# ============================================================

echo "==> Disabling conflicting terminal shortcut..."
gsettings set org.gnome.desktop.wm.keybindings switch-group "['<Super>Above_Tab']" 2>/dev/null || true

# ============================================================
# LAB MACHINE ONLY: Ruby, Prolog, Racket
# ============================================================

if [ "$LAB_MACHINE" = true ]; then
  echo "==> Installing lab machine languages (Ruby, Prolog, Racket)..."

  # Ruby
  if ! [[ -x "/usr/bin/ruby" ]]; then
    sudo apt -y install ruby
  fi

  # Prolog (SWI-Prolog)
  if ! [[ -x "/usr/bin/swipl" ]]; then
    sudo apt-add-repository -y ppa:swi-prolog/stable
    sudo apt update
    sudo apt -y install swi-prolog
  fi

  # Racket
  if ! [[ -x "/usr/bin/racket" ]]; then
    [[ -d ~/Downloads ]] || mkdir ~/Downloads
    cd ~/Downloads
    wget -q https://download.racket-lang.org/releases/8.12/installers/racket-minimal-8.12-x86_64-linux-bc.sh
    chmod +x racket-minimal-8.12-x86_64-linux-bc.sh
    sudo bash ./racket-minimal-8.12-x86_64-linux-bc.sh
    sudo ln -s /usr/racket/bin/* /usr/bin/
    cd ~
  fi
fi

# ============================================================
# Done
# ============================================================

echo ""
echo "==> Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Log out and back in for all PATH changes to take effect"
echo "  2. For mypy in Sublime Text, see UBUNTU.md section 14"
echo "  3. For Terminus in Sublime Text, see UBUNTU.md section 15"
echo "  4. For Haskell LSP and Ormolu in Sublime Text, see UBUNTU.md section 17"
echo ""
