#!/usr/bin/env bash
# Ubuntu Setup Script for CS Department
# @Author: kk
# @Date:   2024-05-05 23:58:35
# @Last Modified by:   kk
# @Last Modified time:  2026-04-05 11:00:00
#
# This script follows the steps in UBUNTU.md for Ubuntu 24.04 setup

# ============================================================
# LAB_MACHINE=true ticks every optional language in the menu below (Haskell,
# Java, Go, Ruby, Racket, Prolog); false ticks only Haskell. The student can
# still change the ticks, or skip the menu with INSTALL=... (see the menu).
# ============================================================
LAB_MACHINE=false

# Per-user install: everything lands in $HOME. Run as root (sudo bash ...,
# or a WSL distro whose default user is root) and it all goes to /root.
if [ "$(id -u)" -eq 0 ] && [ "${ALLOW_ROOT:-}" != 1 ]; then
    echo "ERROR: do not run this script as root or with sudo." >&2
    echo "Run it as your normal user: bash ubuntu_user_install.sh (it calls sudo itself)." >&2
    echo "WSL logged in as root? Create a user first: https://learn.microsoft.com/windows/wsl/setup/environment" >&2
    exit 1
fi

# Check if running in WSL
IS_WSL=false
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then
    IS_WSL=true
fi

# --- language menu begin ---
# Optional languages. Python/mypy/uv, Sublime, git, Node, Bun, Docker, Clean,
# gh and the basic tools always install. Pick the rest:
#   checkbox menu (arrow keys/j/k, space, a = all, Enter) on a terminal,
#   y/N questions when TERM=dumb or MENU_STYLE=yn,
#   INSTALL=haskell,java (or all / none) skips the menu for unattended runs.
# No terminal and no INSTALL: the defaults below, without asking.
LANGS=(haskell java go ruby racket prolog)
declare -A LANG_LABEL=(
  [haskell]="Haskell (GHC 9.6.7, cabal, stack, HLS, ormolu, HUnit, QuickCheck)"
  [java]="Java (OpenJDK 21)"
  [go]="Go 1.19.13"
  [ruby]="Ruby"
  [racket]="Racket 8.12 (Scheme)"
  [prolog]="SWI-Prolog"
)
declare -A WANT=()
want() { [ "${WANT[$1]:-0}" = 1 ]; }

lang_defaults() {  # Haskell for CS115; a lab machine gets everything
  local l
  for l in "${LANGS[@]}"; do
    if [ "${LAB_MACHINE:-false}" = true ] || [ "$l" = haskell ]; then WANT[$l]=1; else WANT[$l]=0; fi
  done
}

lang_from_list() {  # lang_from_list "haskell,java" | all | none
  local l item
  for l in "${LANGS[@]}"; do WANT[$l]=0; done
  case "$1" in
    all) for l in "${LANGS[@]}"; do WANT[$l]=1; done; return 0 ;;
    none|"") return 0 ;;
  esac
  for item in ${1//,/ }; do
    [ -n "${LANG_LABEL[$item]+x}" ] || {
      echo "ERROR: unknown INSTALL item '$item' (choose from: ${LANGS[*]}, all, none)" >&2; return 1; }
    WANT[$item]=1
  done
}

lang_draw() {
  local i l
  for i in "${!LANGS[@]}"; do
    l=${LANGS[$i]}
    printf '%s [%s] %s\033[K\n' "$([ "$i" = "$1" ] && echo '>' || echo ' ')" \
      "$(want "$l" && echo x || echo ' ')" "${LANG_LABEL[$l]}" >&3
  done
}

lang_checkbox() {  # keys from fd 4, screen on fd 3
  local n=${#LANGS[@]} cur=0 key rest l all
  printf '\nChoose languages to install (up/down move, space ticks, a = all, Enter = go):\n' >&3
  lang_draw "$cur"
  while IFS= read -rsn1 -u 4 key; do
    case "$key" in
      $'\e') IFS= read -rsn2 -t 0.1 -u 4 rest
             case "$rest" in '[A') cur=$(( (cur+n-1) % n )) ;; '[B') cur=$(( (cur+1) % n )) ;; esac ;;
      k) cur=$(( (cur+n-1) % n )) ;;
      j) cur=$(( (cur+1) % n )) ;;
      ' ') l=${LANGS[$cur]}; WANT[$l]=$(( 1 - WANT[$l] )) ;;
      a) all=1; for l in "${LANGS[@]}"; do want "$l" || all=0; done
         for l in "${LANGS[@]}"; do WANT[$l]=$(( 1 - all )); done ;;
      ''|$'\r') break ;;
    esac
    printf '\033[%dA' "$n" >&3
    lang_draw "$cur"
  done
}

lang_yesno() {  # one question per language, answers from fd 4
  local l ans
  for l in "${LANGS[@]}"; do
    printf 'Install %s? [%s] ' "${LANG_LABEL[$l]}" "$(want "$l" && echo Y/n || echo y/N)" >&3
    IFS= read -r -u 4 ans || ans=""
    case "$ans" in [yY]*) WANT[$l]=1 ;; [nN]*) WANT[$l]=0 ;; esac
  done
}

choose_languages() {
  local tty="${MENU_TTY:-/dev/tty}" l
  lang_defaults
  if [ -n "${INSTALL+x}" ]; then
    lang_from_list "$INSTALL" || exit 2
  elif ( : < "$tty" ) 2>/dev/null; then
    exec 4< "$tty" 3> "${MENU_OUT:-$tty}"
    if [ "${MENU_STYLE:-}" = yn ] || [ "${TERM:-dumb}" = dumb ]; then lang_yesno; else lang_checkbox; fi
    exec 3>&- 4<&-
  else
    echo "    no terminal for the menu: using the defaults (set INSTALL=... to choose)"
  fi
  CHOSEN_LANGS=""
  for l in "${LANGS[@]}"; do want "$l" && CHOSEN_LANGS="${CHOSEN_LANGS:+$CHOSEN_LANGS }$l"; done
  echo "==> Optional languages: ${CHOSEN_LANGS:-none}"
}
# --- language menu end ---
choose_languages

# Downloads and builds happen here, never in ~/Downloads: on WSL that is a link
# to the Windows Downloads folder (WINDOWS.md), where unzip/tar cannot set file
# modes or times ("fchmod (file attributes) error: Operation not permitted").
WORK_DIR="$HOME/.cache/cs111_install"
mkdir -p "$WORK_DIR"

# ============================================================
# System Setup
# ============================================================

echo "==> Updating system..."
sudo apt update && sudo apt upgrade -y

echo "==> Setting timezone..."
# timedatectl needs systemd; WSL without [boot] systemd=true has none -> set the link directly
sudo timedatectl set-timezone Asia/Bangkok 2>/dev/null || sudo ln -sf /usr/share/zoneinfo/Asia/Bangkok /etc/localtime

# ============================================================
# Basic Tools (UBUNTU.md Step 2)
# ============================================================

echo "==> Installing basic tools..."
PKGS="tar zip unzip git build-essential bash-completion xz-utils python3-pip python3-venv pipenv pipx mypy tmux byobu dos2unix vim neovim bat wget curl gnupg ca-certificates"
if [ "$IS_WSL" = false ]; then
  # xclip: X11 clipboard. wl-clipboard: Wayland clipboard (wl-copy). Both are
  # needed so byobu mouse-highlight copy works regardless of session type;
  # the tmux-clip helper (installed below) picks the right one at runtime.
  PKGS="$PKGS xclip wl-clipboard kdiff3"
fi
sudo apt install -y $PKGS
# emacs-nox would otherwise add a mail server that this course does not need
sudo apt install -y --no-install-recommends emacs-nox

# Clipboard helper used by the byobu copy bindings (~/.byobu/.tmux.conf).
# Auto-detects Wayland (wl-copy) vs X11 (xsel/xclip) at runtime; on WSL it hands
# the text to the WINDOWS clipboard (clip.exe), the one students paste from.
# The dot files install .byobu on WSL too, so the helper must exist there.
echo "==> Installing /usr/local/bin/tmux-clip ..."
sudo tee /usr/local/bin/tmux-clip >/dev/null <<'TMUXCLIP'
#!/bin/sh
# tmux-clip — copy stdin to the system clipboard, auto-detecting Wayland vs X11.
if command -v clip.exe >/dev/null 2>&1; then
    # WSL: clip.exe reads UTF-16LE; plain UTF-8 would garble Thai text
    iconv -f UTF-8 -t UTF-16LE | clip.exe
elif [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy >/dev/null 2>&1; then
    exec wl-copy
elif [ -n "$DISPLAY" ] && command -v xsel >/dev/null 2>&1; then
    exec xsel -i -b
elif [ -n "$DISPLAY" ] && command -v xclip >/dev/null 2>&1; then
    exec xclip -i -selection clipboard
else
    exec cat >/dev/null
fi
TMUXCLIP
sudo chmod 755 /usr/local/bin/tmux-clip

# WSL: the dot files set git's merge tool to kdiff3, but KDiff3 is a Windows app
# (WINDOWS.md Step 6). This wrapper runs the Windows one, turning Linux file
# paths into Windows paths (git passes /home/... names).
if [ "$IS_WSL" = true ]; then
  echo "==> Installing /usr/local/bin/kdiff3 (runs Windows KDiff3)..."
  sudo tee /usr/local/bin/kdiff3 >/dev/null <<'KDIFF3'
#!/usr/bin/env bash
# kdiff3 for git inside WSL: start the Windows KDiff3 with Windows paths.
lad="$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')"
for exe in "/mnt/c/Program Files/KDiff3/bin/kdiff3.exe" "/mnt/c/Program Files/KDiff3/kdiff3.exe" \
           "$( [ -n "$lad" ] && wslpath -u "$lad")/Programs/KDiff3/bin/kdiff3.exe"; do
  [ -x "$exe" ] && break
done
[ -x "$exe" ] || { echo "kdiff3: Windows KDiff3 not found; install it (WINDOWS.md Step 6)" >&2; exit 1; }
args=()
for a in "$@"; do
  # only real files: git also passes labels such as "file.txt (Base)"
  [ -e "$a" ] && a="$(wslpath -w "$a")"
  args+=("$a")
done
exec "$exe" "${args[@]}"
KDIFF3
  sudo chmod 755 /usr/local/bin/kdiff3
fi

# ============================================================
# Dot Files (UBUNTU.md Step 3)
# ============================================================

echo "==> Installing dot files..."
rm -rf /tmp/temp
git clone --depth 1 -q https://github.com/kittipitch/ubuntu_home.git /tmp/temp 2>/dev/null || true
if [ -d /tmp/temp ]; then
  cd /tmp/temp/
  # Back up what is already there (a re-run or an existing WSL/Ubuntu home), never overwrite blind.
  DOT_BAK="$HOME/.dotfiles_backup_$(date +%s)"
  # .config: only the subfolders the dot files replace (the rest, e.g. browser profiles, stays put)
  # Explicit list — skip .git, .gitignore, and .ghcup (user installs own GHCup).
  for item in .bashrc .bash_profile .bash_aliases .dircolors .gitconfig .byobu .emacs.d \
              $(cd .config 2>/dev/null && for d in *; do printf '.config/%s ' "$d"; done); do
    [ -e "$item" ] || continue
    if [ -e "$HOME/$item" ] || [ -L "$HOME/$item" ]; then
      # cp -aL: back up the content, not the link (a symlinked ~/.bashrc
      # would otherwise be "backed up" as a link to the file we overwrite)
      mkdir -p "$DOT_BAK/$(dirname "$item")" \
        && cp -aL "$HOME/$item" "$DOT_BAK/$item" 2>/dev/null \
        || { echo "WARNING: could not back up ~/$item, left it alone"; continue; }
      # rm before cp: cp follows a pre-existing symlink and overwrites its target
      rm -rf "${HOME:?}/$item"
    fi
    mkdir -p "$HOME/$(dirname "$item")" && cp -r "$item" "$HOME/$item"
  done
  [ -d "$DOT_BAK" ] && echo "    previous dot files backed up to $DOT_BAK"
  source ~/.bash_profile 2>/dev/null || true
  cd
fi

# ============================================================
# Programming Fonts (UBUNTU.md Step 4)
# ============================================================

if [ "$IS_WSL" = true ]; then
  # Fonts inside WSL are never used: Windows Terminal and Sublime on Windows
  # draw with Windows fonts (WINDOWS.md Step 4 installs them on Windows).
  echo "==> Skipping programming fonts (WSL: install them on Windows, WINDOWS.md Step 4)"
else
echo "==> Installing programming fonts..."
# FiraCode (simple option)
sudo apt install -y fonts-firacode 2>/dev/null || true

# IosevkaTerm Nerd Font (optional, prettier)
# Re-run safe (same pattern as ubuntu_lab_install.sh do_fonts): skip when the
# font is already installed; extract into a fresh temp dir with unzip -o, so a
# leftover ~/Downloads/iosevka (root-owned, or on a Windows drive) can never
# trigger unzip's "replace ...? [y]es, [n]o" prompt or fchmod errors.
if ! fc-list 2>/dev/null | grep -qi "IosevkaTerm"; then
  IOS_TMP="$(mktemp -d)"
  if wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/IosevkaTerm.zip -O "$IOS_TMP/I.zip" \
      && unzip -qo "$IOS_TMP/I.zip" -d "$IOS_TMP/i"; then
    sudo mkdir -p /usr/share/fonts/truetype/iosevka/
    sudo install -m 644 "$IOS_TMP"/i/*.ttf /usr/share/fonts/truetype/iosevka/
    sudo fc-cache -f 2>/dev/null || true
  else
    echo "WARNING: IosevkaTerm download failed (FiraCode still installed)."
  fi
  rm -rf "$IOS_TMP"
fi
# Set terminal font (may fail on non-GUI)
dconf write /org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9/font "'IosevkaTerm Nerd Font Mono 15'" 2>/dev/null || true
dconf write /org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9/use-system-font false 2>/dev/null || true
cd ~
fi

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

export PATH="$HOME/.local/bin:$PATH"
if command -v uv >/dev/null 2>&1; then
    echo "uv already installed: $(uv --version)"
else
    echo "==> Installing uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
if [ ! -d "$HOME/.venv" ]; then
    uv venv ~/.venv
else
    echo "Environment already exists! Moving on..."
fi

# ============================================================
# Sublime Text (UBUNTU.md Step 8)
# ============================================================

# WSL: students use Sublime Text on WINDOWS (WINDOWS.md §2, §16-17, §20), which reaches
# mypy/HLS inside WSL. So on WSL skip the Linux Sublime and set up the Windows
# one from here: Package Control 4.2.8 plus the WSL variants of the settings.
setup_windows_sublime() {
  local appdata userprofile st user_dir bin_dir bin_win ts f
  appdata="$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r')"
  userprofile="$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')"
  if [ -z "$appdata" ] || [ -z "$userprofile" ] || [ "$appdata" = "%APPDATA%" ]; then
    echo "    WARNING: WSL interop unavailable (cmd.exe); set up Windows Sublime by hand (WINDOWS.md §16-20)."
    return 0
  fi
  # same search as ubuntu_home .bashrc ("For Sublime Text & VSCODE on WSL"): C:/D: Program Files, then PATH
  local subl_found="" dir exe
  for dir in "/mnt/c/Program Files/Sublime Text" "/mnt/c/Program Files (x86)/Sublime Text" \
             "/mnt/d/Program Files/Sublime Text" "/mnt/d/Program Files (x86)/Sublime Text"; do
    for exe in subl.exe sublime_text.exe; do
      [ -x "$dir/$exe" ] && { subl_found="$dir/$exe"; break 2; }
    done
  done
  [ -n "$subl_found" ] || subl_found="$(command -v subl.exe || command -v sublime_text.exe || true)"
  if [ -z "$subl_found" ]; then
    echo "    Windows Sublime Text not found; trying winget..."
    winget.exe install -e --id SublimeHQ.SublimeText.4 --accept-package-agreements --accept-source-agreements \
      >/dev/null 2>&1 || echo "    WARNING: winget failed; install Sublime Text from sublimetext.com (WINDOWS.md §2)."
  fi
  st="$(wslpath -u "$appdata")/Sublime Text"
  user_dir="$st/Packages/User"
  ts="$(date +%s)"
  # back up an existing config before touching it
  [ -d "$user_dir" ] && cp -a "$user_dir" "$user_dir.bak_$ts" && echo "    backed up $user_dir.bak_$ts"
  mkdir -p "$user_dir" "$st/Installed Packages"
  if [ -f "$HOME/.config/sublime-text/Installed Packages/Package Control.sublime-package" ]; then
    [ -f "$st/Installed Packages/Package Control.sublime-package" ] && \
      cp -a "$st/Installed Packages/Package Control.sublime-package" "$st/Installed Packages/Package Control.sublime-package.bak_$ts"
    cp "$HOME/.config/sublime-text/Installed Packages/Package Control.sublime-package" "$st/Installed Packages/"
  fi
  for f in "Package Control.sublime-settings" Preferences.sublime-settings Python.sublime-settings Haskell.sublime-settings; do
    [ -f "$HOME/.config/sublime-text/Packages/User/$f" ] && cp "$HOME/.config/sublime-text/Packages/User/$f" "$user_dir/"
  done

  # mypy bridge (WINDOWS.md §16.3): Windows paths -> WSL paths, then wsl mypy
  bin_dir="$(wslpath -u "$userprofile")/bin"
  bin_win="$userprofile\\bin\\mypy-wsl.bat"
  mkdir -p "$bin_dir"
  sed 's/$/\r/' > "$bin_dir/mypy-wsl.bat" <<'BAT'
@echo off
setlocal enabledelayedexpansion

set "final_args="

:loop
if "%~1"=="" goto :done
set "arg=%~1"
if "!arg:~1,2!"==":\" (
    for /f "delims=" %%P in ('wsl wslpath "!arg!" 2^>nul') do (
        set "final_args=!final_args! "%%P""
    )
) else (
    set "final_args=!final_args! !arg!"
)
shift
goto :loop

:done
wsl mypy %final_args%
endlocal
BAT

  cat > "$user_dir/SublimeLinter.sublime-settings" <<EOF
{
  "linters": {
    "mypy": {
      "disable": false,
      "executable": ["${bin_win//\\/\\\\}"],
      "args": ["--ignore-missing-imports"]
    }
  }
}
EOF
  cat > "$user_dir/LSP.sublime-settings" <<'EOF'
{
  "lsp_format_on_save": true,

  "clients": {
    "haskell-language-server": {
      "enabled": true,
      "command": [
        "wsl",
        "bash",
        "-c",
        "source ~/.ghcup/env && haskell-language-server-wrapper --lsp"
      ],
      "selector": "source.haskell",
      "settings": {
        "haskell.formattingProvider": "ormolu"
      }
    }
  }
}
EOF
  cat > "$user_dir/Terminus.sublime-settings" <<'EOF'
{
    "default_config": {
        "linux": "Bash",
        "osx": "Zsh",
        "windows": "WSL"
    },
    "shell_configs": [
        {
            "name": "WSL",
            "cmd": ["wsl.exe"],
            "cwd": "${project_path:${folder}}",
            "env": {},
            "enable": true,
            "default": true
        }
    ]
}
EOF
  cat > "$user_dir/Default (Windows).sublime-keymap" <<'EOF'
[
  {
    "keys": ["alt+`"],
    "command": "toggle_terminus_panel",
    "args": {
      "config_name": "WSL"
    }
  }
]
EOF
  # Sublime sends file:///C:/... ; HLS inside WSL resolves it as /C:/... (clementine 2026-11-13)
  for d in /mnt/[a-z]; do
    [ -d "$d" ] && sudo ln -sfn "$d" "/$(basename "$d" | tr a-z A-Z):"
  done
  # clementine 2026-11-13: Lib/ owned by SYSTEM/Administrators -> Sublime cannot import its libraries
  if [ -d "$st/Lib" ] && ! touch "$st/Lib/.write_test" 2>/dev/null; then
    echo "    WARNING: Sublime's Lib folder is not writable by you. In an ADMIN PowerShell run:"
    echo "      takeown /f \"\$env:APPDATA\\Sublime Text\\Lib\" /r /d y"
    echo "      icacls \"\$env:APPDATA\\Sublime Text\\Lib\" /grant \"\${env:USERNAME}:(OI)(CI)F\" /t"
  else
    rm -f "$st/Lib/.write_test"
  fi
  echo "    Windows Sublime configured: $user_dir"
  echo "    mypy bridge: $bin_win"
}

if [ "$IS_WSL" = true ]; then
  echo "==> Configuring Windows Sublime Text for WSL..."
  setup_windows_sublime
else
  echo "==> Installing Sublime Text 4..."
  sudo apt install -y apt-transport-https
  # Fetch key to a temp file; install ONLY if non-empty so a failed download
  # never writes an empty key (an empty key breaks every later apt update).
  SUBL_KEY="$(mktemp)"
  curl -fsSL --retry 3 https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor > "$SUBL_KEY" 2>/dev/null
  if [ -s "$SUBL_KEY" ]; then
    sudo install -m644 "$SUBL_KEY" /etc/apt/trusted.gpg.d/sublimehq-archive.gpg
    echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list > /dev/null
    sudo apt update
    sudo apt install -y sublime-text
  else
    echo "    WARNING: could not download Sublime key; skipping Sublime."
    sudo rm -f /etc/apt/sources.list.d/sublime-text.list
  fi
  rm -f "$SUBL_KEY"
fi

if want haskell; then
# ============================================================
# Haskell Setup via GHCup (UBUNTU.md Step 15)
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
  export BOOTSTRAP_HASKELL_CABAL_VERSION=3.16.1.0
  export BOOTSTRAP_HASKELL_HLS_VERSION=2.14.0.0
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

# Re-run safety: the bootstrap above only runs when ghcup is absent. A first run
# killed mid-GHC leaves ghcup installed but GHC unset and cabal missing, so pin
# both here every time (ghcup skips what is already installed).
if command -v ghcup &> /dev/null; then
  ghcup install ghc 9.6.7 && ghcup set ghc 9.6.7
  # A killed unpack still counts as "installed" but ghc cannot load its libs.
  # `ghcup install --force` then aborts on leftover files (GHCup-00140), so
  # remove that one broken version dir first, as ghcup's error says to.
  if ! ghc --numeric-version &> /dev/null; then
    echo "==> GHC 9.6.7 is broken (interrupted install?), reinstalling it..."
    rm -rf "$HOME/.ghcup/ghc/9.6.7"
    ghcup install ghc --force 9.6.7 && ghcup set ghc 9.6.7
  fi
  ghcup install cabal 3.16.1.0 && ghcup set cabal 3.16.1.0
fi

echo "==> Verifying Haskell tools..."
ghcup --version
ghc --version
cabal --version

echo "==> Installing stack, HUnit, and HLS..."
ghcup install stack 3.7.1 2>/dev/null || true
ghcup set stack 3.7.1 2>/dev/null || true
ghcup install hls 2.14.0.0 2>/dev/null || true
ghcup set hls 2.14.0.0 2>/dev/null || true

if command -v cabal &> /dev/null; then
  cabal update 2>/dev/null || true
  cabal install --lib HUnit-1.6.2.0 --constraint='call-stack ==0.4.0' --force-reinstalls 2>/dev/null || true
  # QuickCheck: same version set as the grader (204115 property tests)
  cabal install --lib QuickCheck-2.14.3 \
    --constraint='containers installed' --constraint='bytestring installed' \
    --constraint='directory installed' --constraint='mtl installed' --constraint='stm installed' \
    --constraint='splitmix ==0.1.3.2' --constraint='random ==1.2.1.3' \
    --force-reinstalls 2>/dev/null || true
fi

echo "==> Installing Ormolu (Haskell formatter)..."
if command -v stack &> /dev/null; then
  # Matches UBUNTU.md Step 16.1
  stack install ormolu-0.7.2.0 --resolver lts-22.44 2>/dev/null || true
fi
# stack puts it in ~/.local/bin (on PATH via .bash_profile/.bashrc in new shells)
if [ -x "$HOME/.local/bin/ormolu" ]; then
  "$HOME/.local/bin/ormolu" --version | head -1
else
  echo "WARNING: ormolu missing after install (re-run the script)"
fi

# The installs above hide their errors (2>/dev/null || true), so check every
# pin here: a wrong version must print, not hide. HLS drift used to be
# invisible: 2.13.0.0 has no noble bindist and a silent fallback shipped
# 2.14.x with no wrapper symlink at all.
echo "==> Checking Haskell versions (UBUNTU.md / grader parity)..."
hs_pin() {  # hs_pin <wanted> <command...>
  local out; out="$("${@:2}" 2>&1 | head -1)"
  case "$out" in *"$1"*) echo "    OK $1" ;; *) echo "WARNING: wanted $1, got: ${out:-missing}" ;; esac
}
hs_pin 9.6.7    ghc --version
hs_pin 3.16.1.0 cabal --version
hs_pin 3.7.1    stack --version
hs_pin 2.14.0.0 haskell-language-server-wrapper --version
hs_pin 0.7.2.0  "$HOME/.local/bin/ormolu" --version
HS_T="$(mktemp -d)"
printf 'import Test.HUnit\nimport Test.QuickCheck\nmain :: IO ()\nmain = pure ()\n' > "$HS_T/T.hs"
runghc "$HS_T/T.hs" 2>/dev/null && echo "    OK HUnit + QuickCheck import" \
  || echo "WARNING: HUnit/QuickCheck not importable (re-run the script)"
rm -rf "$HS_T"
fi  # want haskell

# ============================================================
# Git Configuration (UBUNTU.md Step 10)
# ============================================================

echo "==> Note: Remember to configure your Git identity later:"
echo "    git config --global user.name \"Your Name\""
echo "    git config --global user.email \"your.email@example.com\""

if want java; then
# ============================================================
# Java Setup (UBUNTU.md Step 19)
# ============================================================

echo "==> Installing OpenJDK 21..."
sudo apt install -y openjdk-21-jdk

echo "==> Checking Java version..."
java -version
fi  # want java

# ============================================================
# NodeJS Setup (UBUNTU.md Step 21)
# ============================================================

echo "==> Installing NodeJS 24 LTS..."
sudo apt install -y curl gnupg ca-certificates
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs
node -v && npm -v && npx -v
# A NodeSource failure (proxy, captive portal) silently lands Ubuntu's nodejs 18 without npm.
node -v 2>/dev/null | grep -q '^v24\.' || echo "WARNING: NodeJS is not v24 (NodeSource unreachable?); re-run the script"

# ============================================================
# Bun 1.3.14 (alongside NodeJS)
# ============================================================

if [ "$(bun --version 2>/dev/null)" != "1.3.14" ]; then
  echo "==> Installing Bun 1.3.14..."
  cd "$WORK_DIR"
  # -O / unzip -o: a re-run after a half-finished install must not save
  # bun-linux-x64.zip.1 or stop at unzip's "replace ...?" prompt
  wget -q https://github.com/oven-sh/bun/releases/download/bun-v1.3.14/bun-linux-x64.zip -O bun-linux-x64.zip \
    && unzip -qo bun-linux-x64.zip \
    && sudo install -m 0755 bun-linux-x64/bun /usr/local/bin/bun
  cd ~
fi
bun --version

if want go; then
# ============================================================
# Go Setup (UBUNTU.md Step 22)
# ============================================================

echo "==> Installing Go 1.19.13..."
# Check the install dir, not PATH: go lives in /usr/local/go/bin, which this
# shell may not have yet, and a PATH-only check re-downloads it on every run.
if ! /usr/local/go/bin/go version 2>/dev/null | grep -q 'go1\.19\.13'; then
  cd "$WORK_DIR"
  if wget -q https://go.dev/dl/go1.19.13.linux-amd64.tar.gz -O go1.19.13.linux-amd64.tar.gz; then
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go1.19.13.linux-amd64.tar.gz
  else
    echo "WARNING: Go download failed."
  fi
  cd ~
fi
# Add to PATH once (in .bashrc from dotfiles)
[[ -f ~/.bash_profile ]] || ln -s ~/.profile ~/.bash_profile
grep -qs '/usr/local/go/bin' ~/.bash_profile || echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bash_profile
export PATH="$PATH:/usr/local/go/bin"

echo "==> Checking Go version..."
go version
fi  # want go

# ============================================================
# Docker Setup (UBUNTU.md Step 25)
# ============================================================

echo "==> Installing Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
# Temp-file + non-empty guard; install -m644 also avoids gpg's interactive
# "overwrite?" prompt when the key already exists.
DOCKER_KEY="$(mktemp)"
curl -fsSL --retry 3 https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor > "$DOCKER_KEY" 2>/dev/null
# The repo list is written only with a good key: a list without its key is an
# unsigned repo, and every later apt update fails.
if [ -s "$DOCKER_KEY" ]; then
  sudo install -m644 "$DOCKER_KEY" /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo "WARNING: Docker key download failed; Docker skipped (re-run the script)."
  [ -s /etc/apt/keyrings/docker.gpg ] || sudo rm -f /etc/apt/sources.list.d/docker.list
fi
rm -f "$DOCKER_KEY"
sudo usermod -aG docker $USER
if [ -d /run/systemd/system ]; then
  sudo systemctl enable docker
  sudo systemctl start docker
else
  echo "    NOTE: no systemd here (WSL?): add '[boot]' 'systemd=true' to /etc/wsl.conf, run 'wsl --shutdown' in PowerShell, reopen Ubuntu; Docker then starts on its own."
fi

# ============================================================
# lazydocker (Terminal UI for Docker)
# ============================================================

if ! command -v lazydocker &> /dev/null; then
  echo "==> Installing lazydocker..."
  cd "$WORK_DIR"
  LAZYDOCKER_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
  curl -fsLo lazydocker.tar.gz "https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz" \
    && tar xfz lazydocker.tar.gz lazydocker \
    && sudo install -m 0755 lazydocker /usr/local/bin/lazydocker \
    || echo "WARNING: lazydocker install failed (GitHub API rate limit?)."
  cd ~
fi

# ============================================================
# fzf (UBUNTU.md Step 27)
# ============================================================

echo "==> Installing fzf..."
if ! [ -d ~/.fzf ]; then
  git clone -q --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
  yes | ~/.fzf/install
fi

# ============================================================
# Clean Utility (UBUNTU.md Step 28)
# ============================================================

if ! command -v clean &> /dev/null; then
  echo "==> Installing Clean language..."
  cd "$WORK_DIR"
  wget -qO clean.tar.bz2 https://master.dl.sourceforge.net/project/clean/clean/3.4/clean-3.4.tar.bz2
  # build only inside clean-3.4: a failed cd must not run make in $WORK_DIR
  tar xf clean.tar.bz2 && cd clean-3.4 && make all && sudo make install
  cd ~
fi

# ============================================================
# GitHub CLI (UBUNTU.md Step 29)
# ============================================================

echo "==> Installing GitHub CLI..."
if ! command -v gh &> /dev/null; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  # Temp-file + non-empty guard; never install an empty keyring.
  GH_KEY="$(mktemp)"
  curl -fsSL --retry 3 https://cli.github.com/packages/githubcli-archive-keyring.gpg > "$GH_KEY"
  if [ -s "$GH_KEY" ]; then
    sudo install -m644 "$GH_KEY" /etc/apt/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    # NOTE: must be sources.list.d (the old code used sources.d — apt ignores it).
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update && sudo apt install gh -y
  else
    echo "    WARNING: could not download the GitHub CLI key; skipping gh."
  fi
  rm -f "$GH_KEY"
fi

# ============================================================
# Disable conflicting terminal shortcut (UBUNTU.md Step 14.7)
# ============================================================

# GNOME only: WSL has no desktop, and Windows Sublime's Alt+` is not taken
if [ "$IS_WSL" = false ]; then
  echo "==> Disabling conflicting terminal shortcut..."
  gsettings set org.gnome.desktop.wm.keybindings switch-group "['<Super>Above_Tab']" 2>/dev/null || true
fi

# ============================================================
# Optional: Ruby, Prolog, Racket (picked in the menu at the start)
# ============================================================

# Ruby
if want ruby && ! command -v ruby &> /dev/null; then
  echo "==> Installing Ruby..."
  sudo apt -y install ruby
fi

# Prolog (SWI-Prolog)
if want prolog && ! command -v swipl &> /dev/null; then
  echo "==> Installing SWI-Prolog..."
  sudo apt-add-repository -y ppa:swi-prolog/stable
  sudo apt update
  sudo apt -y install swi-prolog
fi

# Racket 8.12 BC (the grader's build). --in-place --dest: no questions asked.
# The installer refuses an existing dest when it cannot ask ("exists, delete?
# Aborting"), so relink an install that is already there, and move a broken
# one aside first. Links land in /usr/local/bin, so check PATH.
if want racket && ! command -v racket &> /dev/null; then
  echo "==> Installing Racket 8.12..."
  if [ ! -x /usr/racket/bin/racket ]; then
    [ -e /usr/racket ] && sudo mv /usr/racket "/usr/racket.bak_$(date +%s)"
    cd "$WORK_DIR"
    wget -q https://download.racket-lang.org/releases/8.12/installers/racket-minimal-8.12-x86_64-linux-bc.sh -O racket-minimal-8.12-x86_64-linux-bc.sh \
      && sudo sh ./racket-minimal-8.12-x86_64-linux-bc.sh --in-place --dest /usr/racket </dev/null
    cd ~
  fi
  [ -x /usr/racket/bin/racket ] && sudo ln -sf /usr/racket/bin/* /usr/local/bin/
fi

# ============================================================
# Done
# ============================================================

echo ""
echo "==> Setup complete!"
echo ""
echo "Next steps:"
if [ "$IS_WSL" = true ]; then
  # WSL has no log out: PATH, the docker group and systemd need the VM restarted
  echo "  1. Close Ubuntu, run 'wsl --shutdown' in PowerShell, then open Ubuntu again"
else
  echo "  1. Log out and back in for all PATH changes to take effect"
fi
if [ "$IS_WSL" = true ]; then
  echo "  2. Windows Sublime Text is configured for WSL (mypy, Terminus, Haskell LSP)."
  echo "     Start Sublime Text; Package Control installs LSP, SublimeLinter and Terminus on first start."
  echo "     Restart it once or twice until a .hs file shows 'LSP: haskell-language-server' (WINDOWS.md section 20)."
else
  echo "  2. For mypy in Sublime Text, see UBUNTU.md section 13"
  echo "  3. For Terminus in Sublime Text, see UBUNTU.md section 14"
  echo "  4. For Haskell LSP and Ormolu in Sublime Text, see UBUNTU.md section 16"
fi
echo ""
