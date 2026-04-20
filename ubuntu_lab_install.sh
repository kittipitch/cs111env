#!/bin/bash
# Ubuntu Lab Machine Setup Script
# @Author: kk
# @Date:   2026-04-06
#
# Global install for lab machines — all tools installed system-wide to /usr/local
# so every user on the machine can access them without per-user setup.
# Run as a user with sudo privileges.

set -e

# ============================================================
# System Setup
# ============================================================

echo "==> Updating system..."
sudo apt update && sudo apt upgrade -y

echo "==> Setting timezone..."
sudo timedatectl set-timezone Asia/Bangkok

# ============================================================
# Basic Tools
# ============================================================

echo "==> Installing basic tools..."
sudo apt install -y \
  tar zip unzip git build-essential xz-utils \
  python3-pip python3-venv pipenv mypy \
  tmux dos2unix xclip \
  emacs-nox vim neovim bat \
  wget curl gnupg ca-certificates \
  kdiff3

# ============================================================
# Python
# ============================================================

echo "==> Checking Python..."
python3 --version

echo "==> Installing NumPy and Pandas system-wide..."
sudo pip3 install --break-system-packages numpy pandas 2>/dev/null || sudo pip3 install numpy pandas

# ============================================================
# Sublime Text
# ============================================================

echo "==> Installing Sublime Text 4..."
sudo apt install -y apt-transport-https
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null
echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
sudo apt update
sudo apt install -y sublime-text

# ============================================================
# Haskell — Global Install (available to all users)
# ============================================================

echo "==> Installing Haskell dependencies..."
sudo apt install -y build-essential curl libffi-dev libffi8 libgmp-dev libgmp10 libncurses-dev pkg-config

# Part 1: GHC 9.6.7 from official tarball → /usr/local
echo "==> Installing GHC 9.6.7 globally..."
if ! command -v ghc &> /dev/null; then
  [[ -d ~/Downloads ]] || mkdir ~/Downloads
  cd ~/Downloads
  sudo rm -rf /usr/local/lib/ghc* 2>/dev/null || true
  sudo rm -f /usr/local/bin/ghc* 2>/dev/null || true
  curl -L -O https://downloads.haskell.org/~ghc/9.6.7/ghc-9.6.7-x86_64-ubuntu22_04-linux.tar.xz
  tar xf ghc-*.tar.xz
  cd ghc-9.6.7*/
  ./configure
  sudo make install
  sudo ln -sf /usr/local/bin/ghc /usr/bin/ghc
  cd ~
fi

echo "==> GHC version: $(ghc --version)"

# Part 2: GHCup binary → /usr/local/bin
echo "==> Installing GHCup globally..."
if ! command -v ghcup &> /dev/null; then
  sudo curl -L -o /usr/local/bin/ghcup \
    https://downloads.haskell.org/~ghcup/0.1.50.2/x86_64-linux-ghcup-0.1.50.2
  sudo chmod +x /usr/local/bin/ghcup
fi

# Part 3: Cabal via GHCup → /usr/local
echo "==> Installing Cabal globally..."
if ! command -v cabal &> /dev/null; then
  export GHCUP_INSTALL_BASE_PREFIX=/usr/local
  sudo -E ghcup install cabal 3.10.3.0
  sudo -E ghcup set cabal 3.10.3.0
  sudo ln -sf /usr/local/.ghcup/bin/cabal /usr/local/bin/cabal
fi

echo "==> Cabal version: $(cabal --version)"

# Part 4: HUnit into global package database
echo "==> Installing HUnit globally..."
sudo -E cabal update
sudo -E cabal --store-dir=/usr/local/lib/ghc-9.6.7/cabal-store install --lib HUnit call-stack \
  --package-db=/usr/local/lib/ghc-9.6.7/lib/package.conf.d \
  --package-env=/usr/local/lib/ghc-9.6.7/lib/ghc.env \
  --global --overwrite-policy=always

# Part 5: Ormolu
echo "==> Installing Ormolu globally..."
if ! command -v ormolu &> /dev/null; then
  sudo -E cabal install ormolu
  sudo ln -sf /root/.cabal/bin/ormolu /usr/local/bin/ormolu 2>/dev/null || \
  sudo ln -sf ~/.cabal/bin/ormolu /usr/local/bin/ormolu 2>/dev/null || true
fi

# Part 6: HLS via GHCup
echo "==> Installing Haskell Language Server globally..."
if ! command -v haskell-language-server-wrapper &> /dev/null; then
  export GHCUP_INSTALL_BASE_PREFIX=/usr/local
  sudo -E ghcup install hls latest
  sudo -E ghcup set hls latest
  for f in /usr/local/.ghcup/bin/haskell-language-server*; do
    sudo ln -sf "$f" /usr/local/bin/$(basename "$f")
  done
fi

# Verify
echo "==> Verifying Haskell install..."
ghc --version
cabal --version
ghc -package-db=/usr/local/lib/ghc-9.6.7/lib/package.conf.d \
    -package-env=/usr/local/lib/ghc-9.6.7/lib/ghc.env \
    -e "import Test.HUnit" \
    -e 'putStrLn "HUnit OK"'

# ============================================================
# Java
# ============================================================

echo "==> Installing OpenJDK 21..."
sudo apt install -y openjdk-21-jdk
java -version

# ============================================================
# NodeJS
# ============================================================

echo "==> Installing NodeJS 24 LTS..."
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs

# ============================================================
# Go
# ============================================================

echo "==> Installing Go 1.19.13..."
if ! command -v go &> /dev/null; then
  [[ -d ~/Downloads ]] || mkdir ~/Downloads
  cd ~/Downloads
  wget -q --no-check-certificate https://go.dev/dl/go1.19.13.linux-amd64.tar.gz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf go1.19.13.linux-amd64.tar.gz
  echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh
  export PATH=$PATH:/usr/local/go/bin
  cd ~
fi
go version

# ============================================================
# Docker
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
sudo systemctl enable docker
sudo systemctl start docker

# ============================================================
# GitHub CLI
# ============================================================

echo "==> Installing GitHub CLI..."
if ! command -v gh &> /dev/null; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt update && sudo apt install -y gh
fi

# ============================================================
# Lab Machine: Ruby, Prolog, Racket
# ============================================================

echo "==> Installing lab machine languages (Ruby, Prolog, Racket)..."

if ! command -v ruby &> /dev/null; then
  sudo apt install -y ruby
fi

if ! command -v swipl &> /dev/null; then
  sudo apt-add-repository -y ppa:swi-prolog/stable
  sudo apt update
  sudo apt install -y swi-prolog
fi

if ! command -v racket &> /dev/null; then
  [[ -d ~/Downloads ]] || mkdir ~/Downloads
  cd ~/Downloads
  wget -q https://download.racket-lang.org/releases/8.12/installers/racket-minimal-8.12-x86_64-linux-bc.sh
  chmod +x racket-minimal-8.12-x86_64-linux-bc.sh
  sudo bash ./racket-minimal-8.12-x86_64-linux-bc.sh
  sudo ln -sf /usr/racket/bin/* /usr/local/bin/
  cd ~
fi

# ============================================================
# Done
# ============================================================

echo ""
echo "==> Lab machine setup complete!"
echo ""
echo "All tools installed globally to /usr/local — available to all users."
echo "GHC package env: /usr/local/lib/ghc-9.6.7/lib/ghc.env"
echo ""
