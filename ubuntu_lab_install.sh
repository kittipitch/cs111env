#!/bin/bash
# Ubuntu Lab Machine Setup Script
# @Author: kk
# @Date:   2026-04-06
#
# Global install for lab machines — all tools installed system-wide to /usr/local
# so every user on the machine can access them without per-user setup.
# Run while logged in as the lab-admin (SUDOER_ACCOUNT) with sudo privileges.
#
# RESILIENT BY DESIGN:
#   * No `set -e`. One failing step never aborts the whole run.
#   * Every step is idempotent (safe to re-run; skips work already done).
#   * Each step's PASS/FAIL/SKIP is recorded and printed in a summary.
#   * A final verify_install() actually TESTS the installation. The script
#     exits non-zero if any CRITICAL check fails — "success" is earned, not
#     assumed.

# ============================================================
# Account Configuration  — EDIT THESE TWO BEFORE RUNNING
# ============================================================
# These two variables decide WHICH user accounts get the standard lab home
# environment (dot files from the ubuntu_home repo). They do NOT affect the
# system-wide tools, which always install to /usr/local for everyone.
#
#   SUDOER_ACCOUNT   The lab-admin account you are logged in as to run this
#                    script (it has sudo). Its OWN dot files are overwritten
#                    with the standard lab set — but ONLY if the user actually
#                    running the script equals this name. If someone runs the
#                    script from a different (e.g. personal) account, that
#                    account's dot files are LEFT UNTOUCHED. This guard exists
#                    because the dot files come from a shared repo and would
#                    otherwise clobber a personal setup.
#
#   STUDENT_ACCOUNT  The restricted, NO-sudo account students log in to. It is
#                    created automatically if missing (password from
#                    student_password.txt, else the built-in default) and
#                    ALWAYS receives the standard lab dot files.
#
# Change these to match your site before running. Each can also be overridden
# at run time via an environment variable, e.g. for non-interactive automation:
#   STUDENT_ACCOUNT=csmajor SUDOER_ACCOUNT=cscmu bash ubuntu_lab_install.sh
SUDOER_ACCOUNT="${SUDOER_ACCOUNT:-cscmu}"
STUDENT_ACCOUNT="${STUDENT_ACCOUNT:-student}"

# Password used when this script has to CREATE the student account.
# Read from a sibling student_password.txt if present, else this default.
DEFAULT_PASSWORD="i<3cscmu"

# Dot files / directories copied from the ubuntu_home repo into each managed
# home. This same list drives both the copy and the final verification, so
# "did every dot file land?" is checked against exactly what we install.
DOTFILE_ITEMS=(.bashrc .bash_profile .bash_aliases .dircolors .gitconfig \
               .byobu .config .emacs.d)

UBUNTU_HOME_REPO="https://github.com/kittipitch/ubuntu_home.git"
UBUNTU_HOME_TMP="/tmp/ubuntu_home"
# Haskell toolchain — PINNED to the versions in UBUNTU.md so lab machines
# mirror the autojudge. Do not bump these without updating UBUNTU.md too.
GHC_VER="9.6.7"
CABAL_VER="3.14.2.0"
STACK_VER="3.7.1"
HLS_VER="2.13.0.0"
HUNIT_VER="1.6.2.0"
ORMOLU_VER="0.7.2.0"
GHC_ENV="/usr/local/lib/ghc-${GHC_VER}/lib/ghc.env"
GHC_PKGDB="/usr/local/lib/ghc-${GHC_VER}/lib/package.conf.d"
CABAL_PKGDB="/usr/local/lib/ghc-${GHC_VER}/cabal-store/ghc-${GHC_VER}/package.db"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSWORD_FILE="$SCRIPT_DIR/student_password.txt"

# Whether the installer (admin) account was provisioned with dot files this run
# (used by verify to know whether to check the admin home).
INSTALLER_PROVISIONED=0
INSTALLER_USER="${SUDO_USER:-$USER}"

# ------------------------------------------------------------
# Resilience helpers
# ------------------------------------------------------------
STEP_RESULTS=()   # "PASS|label" / "FAIL|label (rc=N)" / "SKIP|label"

# step "Label" cmd args...   — run a command/function, record result, NEVER abort.
step() {
  local label="$1"; shift
  echo ""
  echo "==> ${label}..."
  if "$@"; then
    STEP_RESULTS+=("PASS|${label}")
  else
    local rc=$?
    STEP_RESULTS+=("FAIL|${label} (rc=${rc})")
    echo "    [WARN] '${label}' failed (rc=${rc}); continuing."
  fi
}

# Download to a file with retries; return non-zero (and leave no partial file)
# if the result is empty. Prevents empty keys/tarballs from poisoning things.
fetch() {  # fetch <url> <dest>
  curl -fsSL --retry 3 --retry-delay 2 -o "$2" "$1" || return 1
  [[ -s "$2" ]] || { rm -f "$2"; return 1; }
}

# ============================================================
# Student account (create if missing)
# ============================================================
setup_student_account() {
  # Prompt for a name only when missing AND we have a terminal; otherwise keep
  # the configured default (so the script is safe to run non-interactively).
  if ! id "$STUDENT_ACCOUNT" &>/dev/null && [ -t 0 ]; then
    read -rp "Account '$STUDENT_ACCOUNT' not found. Username to create [$STUDENT_ACCOUNT]: " input_user
    STUDENT_ACCOUNT="${input_user:-$STUDENT_ACCOUNT}"
  fi

  if ! id "$STUDENT_ACCOUNT" &>/dev/null; then
    echo "    Creating user '$STUDENT_ACCOUNT' (no sudo)..."
    sudo useradd -m -s /bin/bash "$STUDENT_ACCOUNT" || return 1
    local pass="$DEFAULT_PASSWORD"
    [[ -f "$PASSWORD_FILE" ]] && pass="$(cat "$PASSWORD_FILE")"
    echo "${STUDENT_ACCOUNT}:${pass}" | sudo chpasswd
    echo "    Password set for '$STUDENT_ACCOUNT'."
  else
    echo "    User '$STUDENT_ACCOUNT' already exists; leaving password unchanged."
  fi
  STUDENT_HOME="$(getent passwd "$STUDENT_ACCOUNT" | cut -d: -f6)"
  echo "    Student account: $STUDENT_ACCOUNT  (home: $STUDENT_HOME)"
  [[ -n "$STUDENT_HOME" ]]
}

# ============================================================
# System + basic tools
# ============================================================
do_system_update() {
  # apt update may exit non-zero because of unrelated broken third-party repos
  # already on the machine; that must not stop us. upgrade is best-effort.
  sudo apt update || echo "    (apt update reported errors — continuing)"
  sudo apt upgrade -y || echo "    (apt upgrade reported errors — continuing)"
  sudo timedatectl set-timezone Asia/Bangkok 2>/dev/null || true
  return 0
}

do_basic_tools() {
  sudo apt install -y \
    tar zip unzip git build-essential bash-completion xz-utils \
    python3-pip python3-venv pipenv pipx mypy \
    tmux byobu dos2unix xclip fzf scrot \
    emacs-nox vim neovim bat \
    wget curl gnupg ca-certificates \
    kdiff3
}

# ============================================================
# Extra apps — Brave browser + WezTerm (system-wide, all users)
# ============================================================
# Installed via their upstream apt repos. Idempotent.
do_apps() {
  if ! command -v brave-browser >/dev/null 2>&1; then
    sudo install -d -m0755 /usr/share/keyrings
    sudo curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
      -o /usr/share/keyrings/brave-browser-archive-keyring.gpg 2>/dev/null || true
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
      | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
    sudo apt update 2>/dev/null || true
    sudo apt install -y brave-browser 2>/dev/null || echo "    (brave install failed — continuing)"
  fi
  if ! command -v wezterm >/dev/null 2>&1; then
    curl -fsSL https://apt.fury.io/wez/gpg.key 2>/dev/null \
      | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg 2>/dev/null || true
    echo "deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *" \
      | sudo tee /etc/apt/sources.list.d/wezterm.list >/dev/null
    sudo apt update 2>/dev/null || true
    sudo apt install -y wezterm 2>/dev/null || echo "    (wezterm install failed — continuing)"
  fi
}

# Programming fonts (UBUNTU.md §4): FiraCode + IosevkaTerm Nerd Font. The lab
# dot files set the terminal font to Iosevka, so the font must be present.
do_fonts() {
  sudo apt install -y fonts-firacode
  if ! fc-list 2>/dev/null | grep -qi "IosevkaTerm"; then
    local t; t="$(mktemp -d)"
    if fetch "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/IosevkaTerm.zip" "$t/I.zip"; then
      unzip -qo "$t/I.zip" -d "$t/i" && sudo mkdir -p /usr/share/fonts/truetype/iosevka \
        && sudo cp "$t"/i/*.ttf /usr/share/fonts/truetype/iosevka/ && sudo fc-cache -f >/dev/null 2>&1
    else
      echo "    WARNING: IosevkaTerm download failed (FiraCode still installed)."
    fi
    rm -rf "$t"
  fi
}

# uv — fast Python package manager (UBUNTU.md §7). Installed GLOBALLY to
# /usr/local/bin; each managed account gets a ~/.venv (created in install_dotfiles).
do_uv() {
  command -v uv &>/dev/null && { echo "    uv already installed."; return 0; }
  curl -LsSf https://astral.sh/uv/install.sh | sudo env UV_UNMANAGED_INSTALL="/usr/local/bin" sh
}

# lazydocker — terminal UI for Docker (UBUNTU.md §26), global binary.
do_lazydocker() {
  command -v lazydocker &>/dev/null && { echo "    lazydocker already installed."; return 0; }
  local ver t
  ver="$(curl -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep -Po '"tag_name": "v\K[^"]*')"
  [ -n "$ver" ] || { echo "    WARNING: lazydocker version lookup failed."; return 1; }
  t="$(mktemp -d)"
  if fetch "https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_${ver}_Linux_x86_64.tar.gz" "$t/l.tgz"; then
    tar -C "$t" -xzf "$t/l.tgz" lazydocker && sudo install -m755 "$t/lazydocker" /usr/local/bin/
  else
    rm -rf "$t"; return 1
  fi
  rm -rf "$t"
}

# ============================================================
# Dot files (from ubuntu_home) — global toolchain stays shared
# ============================================================
clone_ubuntu_home() {
  sudo rm -rf "$UBUNTU_HOME_TMP"
  git clone --depth 1 -q "$UBUNTU_HOME_REPO" "$UBUNTU_HOME_TMP"
  [[ -d "$UBUNTU_HOME_TMP" ]]
}

install_dotfiles() {  # install_dotfiles <user> <home>
  local user="$1" home="$2"
  [[ -z "$user" || -z "$home" || ! -d "$home" ]] && { echo "    [skip] no home for '$user'"; return 1; }
  echo "    Installing dot files for '$user' ($home)..."
  for item in "${DOTFILE_ITEMS[@]}"; do
    if [[ -e "$UBUNTU_HOME_TMP/$item" ]]; then
      # Remove existing target FIRST so a pre-existing symlink (e.g. a personal
      # dot file linked into Dropbox) is replaced, not written THROUGH.
      sudo rm -rf "$home/$item"
      sudo cp -rf "$UBUNTU_HOME_TMP/$item" "$home"/
    fi
  done
  # Lab ghcup env: points each home's ~/.ghcup/env at the GLOBAL toolchain
  # (/usr/local/.ghcup). The heavy toolchain is shared, never copied per user.
  if [[ -f "$UBUNTU_HOME_TMP/.ghcup/env-lab" ]]; then
    sudo mkdir -p "$home/.ghcup"
    sudo cp -f "$UBUNTU_HOME_TMP/.ghcup/env-lab" "$home/.ghcup/env"
  fi
  # Point per-user GHC default env → global env so plain `ghci` finds HUnit
  # without requiring explicit -package-env flags.
  local ghc_envdir="$home/.ghc/x86_64-linux-${GHC_VER}/environments"
  sudo mkdir -p "$ghc_envdir"
  sudo ln -sf "$GHC_ENV" "$ghc_envdir/default"
  # Ormolu/LSP verification file on the Desktop (see UBUNTU.md "Verify Ormolu
  # and LSP").
  sudo mkdir -p "$home/Desktop"
  sudo tee "$home/Desktop/TestSetup.hs" > /dev/null <<'HSEOF'
-- 1. Test LSP formatting (Ormolu):
--    Try to mess up indentation or remove spaces around '=',
--    then save the file. It should auto-format on save.
x = 1 + 2

-- Intentional type error to test LSP - uncomment
-- badValue :: Int
-- badValue = "this is not an int"

main :: IO ()
main = putStrLn "LSP is working!"
HSEOF
  # Base16 theme (UBUNTU.md §5): the dot files' .bashrc sources tinted-shell
  # when present. Clone it per account so the theme works.
  if [[ ! -d "$home/.config/tinted-shell" ]]; then
    sudo git clone -q --depth 1 https://github.com/tinted-theming/tinted-shell.git \
      "$home/.config/tinted-shell" 2>/dev/null || true
  fi
  # fzf shim: the dot files' .bashrc sources ~/.fzf.bash; point it at the
  # apt-installed fzf keybindings/completion so it works without junegunn's
  # per-user installer.
  printf 'source /usr/share/doc/fzf/examples/key-bindings.bash 2>/dev/null\nsource /usr/share/doc/fzf/examples/completion.bash 2>/dev/null\n' \
    | sudo tee "$home/.fzf.bash" >/dev/null
  # Per-account Python venv via uv (UBUNTU.md §7), if uv is installed.
  if command -v uv &>/dev/null && [[ ! -d "$home/.venv" ]]; then
    sudo -u "$user" /usr/local/bin/uv venv "$home/.venv" 2>/dev/null || true
  fi
  sudo chown -R "$user":"$user" "$home"
}

install_all_dotfiles() {
  clone_ubuntu_home || return 1
  # Student always provisioned.
  install_dotfiles "$STUDENT_ACCOUNT" "$STUDENT_HOME"
  # Installer (admin) provisioned ONLY if it is the designated SUDOER_ACCOUNT,
  # so a personal account running the script keeps its own dot files.
  if [[ "$INSTALLER_USER" == "$SUDOER_ACCOUNT" && "$INSTALLER_USER" != "$STUDENT_ACCOUNT" ]]; then
    local ihome; ihome="$(getent passwd "$INSTALLER_USER" | cut -d: -f6)"
    install_dotfiles "$INSTALLER_USER" "$ihome" && INSTALLER_PROVISIONED=1
  else
    echo "    Installer '$INSTALLER_USER' is not SUDOER_ACCOUNT ('$SUDOER_ACCOUNT'); leaving its dot files untouched."
  fi
  sudo rm -rf "$UBUNTU_HOME_TMP"
  return 0
}

# ============================================================
# XFCE theme (Numix) — apply to the student session
# ============================================================
# The lab image auto-logs the student in, so we set the theme live via
# xfconf-query. We also drop an autostart entry so the theme re-applies on
# every login — idempotent and self-healing (survives first-login races and
# profile resets). GTK/WM = Numix, icons = Numix-Circle.
do_xfce_theme() {
  sudo apt install -y numix-gtk-theme numix-icon-theme numix-icon-theme-circle paper-icon-theme 2>/dev/null || true
  local su shome uid
  su="${STUDENT_ACCOUNT:-student}"
  shome="$(getent passwd "$su" | cut -d: -f6)"
  [ -z "$shome" ] && { echo "    [skip] no home for '$su'"; return 1; }
  uid="$(id -u "$su" 2>/dev/null)" || { echo "    [skip] no user '$su'"; return 1; }

  # Autostart: re-apply the theme on every login.
  sudo mkdir -p "$shome/.config/autostart"
  sudo tee "$shome/.config/autostart/numix-theme.desktop" >/dev/null <<'DESK'
[Desktop Entry]
Type=Application
Name=Apply Numix Theme
Exec=sh -c "xfconf-query -c xsettings -p /Net/ThemeName -s Numix; xfconf-query -c xfwm4 -p /general/theme -s Numix; xfconf-query -c xsettings -p /Net/IconThemeName -s Numix-Circle"
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESK
  sudo chown "$su:$su" "$shome/.config/autostart/numix-theme.desktop"

  # Apply live if a graphical session is up for the student right now.
  if loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | grep -qx "$uid"; then
    sudo -u "$su" DISPLAY=:0 XAUTHORITY="$shome/.Xauthority" \
         DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
         bash -c '
           xfconf-query -c xsettings -p /Net/ThemeName     -s Numix         2>/dev/null || true
           xfconf-query -c xfwm4   -p /general/theme       -s Numix         2>/dev/null || true
           xfconf-query -c xsettings -p /Net/IconThemeName -s Numix-Circle  2>/dev/null || true
         ' && echo "    [ OK ] Numix theme applied live for '$su'"
  else
    echo "    [ OK ] Numix autostart installed for '$su' (applies next login)"
  fi

  # Solid dark-grey desktop background (no wallpaper image). Applies live if a
  # session is up; otherwise the student gets it on next login.
  if loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | grep -qx "$uid"; then
    sudo -u "$su" DISPLAY=:0 XAUTHORITY="$shome/.Xauthority" \
         DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" bash -c '
      ch=xfce4-desktop
      xfconf-query -c "$ch" -l 2>/dev/null | grep -E "/(image-style|color-style|color1)$" | while read -r p; do
        case "$p" in
          *image-style|*color-style) xfconf-query -c "$ch" -p "$p" -s 0 ;;
          *color1)                   xfconf-query -c "$ch" -p "$p" -s "#222222" ;;
        esac
      done
    ' 2>/dev/null && echo "    [ OK ] dark-grey wallpaper for '$su'"
  fi
  return 0
}

# ============================================================
# XFCE panel — apps + launchers (only where XFCE is installed)
# ============================================================
# Installs Brave, Sublime Text, xfce4-terminal, WezTerm and seeds the panel
# for the student: whiskermenu + 4 app launchers + tasklist + tray + clock.
# Disk-seeded into xfconf, so it applies on the next login (the lab image
# auto-logs the student in, so a reboot after install picks it up). Idempotent.
do_xfce_panel() {
  command -v xfce4-panel >/dev/null 2>&1 || { echo "    [skip] no XFCE on this host"; return 0; }
  local su shome
  su="${STUDENT_ACCOUNT:-student}"
  shome="$(getent passwd "$su" | cut -d: -f6)"
  [ -z "$shome" ] && { echo "    [skip] no home for '$su'"; return 1; }

  # --- apps (terminal + editor; Brave/WezTerm installed by do_apps) ---
  command -v xfce4-terminal >/dev/null 2>&1 || sudo apt install -y xfce4-terminal 2>/dev/null || true
  command -v subl >/dev/null 2>&1 || sudo snap install sublime-text --classic 2>/dev/null || true

  # --- panel layout + launchers (seed into xfconf XML) ---
  local pdir="$shome/.config/xfce4/panel"
  local xdir="$shome/.config/xfce4/xfconf/xfce-perchannel-xml"
  sudo mkdir -p "$pdir" "$xdir"
  sudo rm -rf "$pdir"/launcher-{3,4,5,6} 2>/dev/null || true

  _seed_launcher() {  # pid  label  system.desktop
    local pid="$1" label="$2" sys="$3" id
    [ -f "$sys" ] || return 1
    id="${pid}1000000001"
    sudo mkdir -p "$pdir/launcher-$pid"
    sudo cp -f "$sys" "$pdir/launcher-$pid/$id.desktop"
    sudo sed -i "s/^Name=.*/Name=$label/" "$pdir/launcher-$pid/$id.desktop" 2>/dev/null || true
    echo "$id"
  }
  local subl_desk; subl_desk="$(ls /var/lib/snapd/desktop/applications/sublime-text*.desktop /usr/share/applications/sublime_text.desktop 2>/dev/null | head -1)"
  local wez_desk;  wez_desk="$(ls /usr/share/applications/wezterm.desktop /usr/share/applications/org.wezfurl*.desktop 2>/dev/null | head -1)"
  local L3 L4 L5 L6
  L3=$(_seed_launcher 3 Brave        /usr/share/applications/brave-browser.desktop)        || L3=""
  L4=$(_seed_launcher 4 "Sublime Text" "$subl_desk")                                      || L4=""
  L5=$(_seed_launcher 5 Terminal     /usr/share/applications/xfce4-terminal.desktop)      || L5=""
  L6=$(_seed_launcher 6 WezTerm      "$wez_desk")                                         || L6=""

  sudo tee "$xdir/xfce4-panel.xml" >/dev/null <<XML
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="uint" value="1">
    <property name="panel-0" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="length" type="uint" value="100"/>
      <property name="length-adjust" type="bool" value="true"/>
      <property name="size" type="uint" value="26"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/><value type="int" value="2"/><value type="int" value="3"/>
        <value type="int" value="4"/><value type="int" value="5"/><value type="int" value="6"/>
        <value type="int" value="7"/><value type="int" value="8"/><value type="int" value="9"/>
        <value type="int" value="10"/><value type="int" value="11"/><value type="int" value="12"/>
        <value type="int" value="13"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-2" type="string" value="separator"><property name="expand" type="bool" value="false"/><property name="style" type="uint" value="0"/></property>
    <property name="plugin-3" type="string" value="launcher"><property name="items" type="array"><value type="string" value="${L3}.desktop"/></property></property>
    <property name="plugin-4" type="string" value="launcher"><property name="items" type="array"><value type="string" value="${L4}.desktop"/></property></property>
    <property name="plugin-5" type="string" value="launcher"><property name="items" type="array"><value type="string" value="${L5}.desktop"/></property></property>
    <property name="plugin-6" type="string" value="launcher"><property name="items" type="array"><value type="string" value="${L6}.desktop"/></property></property>
    <property name="plugin-7" type="string" value="separator"><property name="expand" type="bool" value="true"/><property name="style" type="uint" value="0"/></property>
    <property name="plugin-8" type="string" value="tasklist"><property name="flat-buttons" type="bool" value="true"/><property name="show-handle" type="bool" value="false"/></property>
    <property name="plugin-9" type="string" value="separator"><property name="expand" type="bool" value="true"/><property name="style" type="uint" value="0"/></property>
    <property name="plugin-10" type="string" value="pulseaudio"/>
    <property name="plugin-11" type="string" value="systray"/>
    <property name="plugin-12" type="string" value="power-manager-plugin"/>
    <property name="plugin-13" type="string" value="clock"><property name="digital-format" type="string" value="%d %b, %H:%M"/><property name="mode" type="uint" value="2"/></property>
  </property>
</channel>
XML
  sudo chown -R "$su:$su" "$shome/.config/xfce4"
  echo "    [ OK ] XFCE panel + launchers seeded for '$su' (applies next login)"
  return 0
}

# ============================================================
# Disable lightdm autologin (students log in manually)
# ============================================================
# Takes effect at the next lightdm restart / reboot. The seeded XFCE theme +
# panel still apply on the student's first manual login.
do_disable_autologin() {
  local f=/etc/lightdm/lightdm.conf
  [ -f "$f" ] || { echo "    [skip] no $f"; return 0; }
  if sudo grep -qE '^autologin-user=' "$f"; then
    sudo sed -i 's/^autologin-user=.*/autologin-user=/' "$f"
    echo "    [ OK ] autologin disabled (next lightdm restart)"
  else
    echo "    [skip] autologin already unset"
  fi
}

# ============================================================
# Python
# ============================================================
do_python() {
  python3 --version
  sudo pip3 install --break-system-packages numpy pandas 2>/dev/null \
    || sudo pip3 install numpy pandas
}

# ============================================================
# Sublime Text
# ============================================================
do_sublime() {
  command -v subl &>/dev/null && { echo "    Sublime already installed."; return 0; }
  sudo apt install -y apt-transport-https
  # Fetch key to temp; install ONLY if non-empty so a failed download can never
  # write an empty key (which would break every later apt update).
  local t; t="$(mktemp)"
  curl -fsSL --retry 3 https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor > "$t" 2>/dev/null
  if [[ -s "$t" ]]; then
    sudo install -m644 "$t" /etc/apt/trusted.gpg.d/sublimehq-archive.gpg
    echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list >/dev/null
    sudo apt update
    sudo apt install -y sublime-text
    rm -f "$t"
  else
    echo "    WARNING: could not download Sublime key; skipping Sublime."
    sudo rm -f /etc/apt/sources.list.d/sublime-text.list
    rm -f "$t"
    return 1
  fi
}

# ============================================================
# Haskell — global install (shared by all users)
# ============================================================
do_haskell_deps() {
  sudo apt install -y build-essential curl libffi-dev libffi8 libgmp-dev \
    libgmp10 libncurses-dev pkg-config
}

do_ghc() {
  # Enforce the pinned version: if ghc is present but a DIFFERENT version,
  # fall through and reinstall the pinned one.
  ghc --version 2>/dev/null | grep -qF "$GHC_VER" && { echo "    ghc ${GHC_VER} present."; return 0; }
  mkdir -p ~/Downloads; cd ~/Downloads || return 1
  sudo rm -rf ~/.ghc* ~/.cabal /usr/local/lib/ghc* 2>/dev/null
  sudo rm -f /usr/local/bin/ghc* 2>/dev/null
  local tb="ghc-${GHC_VER}-x86_64-ubuntu22_04-linux.tar.xz"
  fetch "https://downloads.haskell.org/~ghc/${GHC_VER}/${tb}" "$tb" || {
    echo "    WARNING: GHC download failed."; cd ~; return 1; }
  tar xf "$tb" || { cd ~; return 1; }
  cd "ghc-${GHC_VER}"*/ || { cd ~; return 1; }
  ./configure && sudo make install && sudo ln -sf /usr/local/bin/ghc /usr/bin/ghc
  local rc=$?; cd ~; return $rc
}

do_ghcup() {
  command -v ghcup &>/dev/null && { echo "    ghcup already installed."; return 0; }
  local t; t="$(mktemp)"
  fetch "https://downloads.haskell.org/~ghcup/0.1.50.2/x86_64-linux-ghcup-0.1.50.2" "$t" || {
    echo "    WARNING: ghcup download failed."; rm -f "$t"; return 1; }
  sudo install -m755 "$t" /usr/local/bin/ghcup
  rm -f "$t"
}

do_cabal() {
  cabal --version 2>/dev/null | grep -qF "$CABAL_VER" && { echo "    cabal ${CABAL_VER} present."; return 0; }
  export GHCUP_INSTALL_BASE_PREFIX=/usr/local
  # ghcup install+set enforces the pinned version even if another is installed.
  sudo -E ghcup install cabal "$CABAL_VER" && sudo -E ghcup set cabal "$CABAL_VER" \
    && sudo ln -sf /usr/local/.ghcup/bin/cabal /usr/local/bin/cabal
}

do_stack() {
  stack --version 2>/dev/null | grep -qF "$STACK_VER" && { echo "    stack ${STACK_VER} present."; return 0; }
  export GHCUP_INSTALL_BASE_PREFIX=/usr/local
  sudo -E ghcup install stack "$STACK_VER" && sudo -E ghcup set stack "$STACK_VER" \
    && sudo ln -sf /usr/local/.ghcup/bin/stack /usr/local/bin/stack
}

do_hunit() {
  # Enforce the pinned HUnit version in the global package db.
  if sudo ghc-pkg --package-db="$GHC_PKGDB" list HUnit 2>/dev/null | grep -qF "HUnit-${HUNIT_VER}"; then
    echo "    HUnit ${HUNIT_VER} present."
    return 0
  fi
  cabal update
  sudo -E cabal --store-dir=/usr/local/lib/ghc-${GHC_VER}/cabal-store install \
    --lib "HUnit-${HUNIT_VER}" call-stack \
    --package-db="$GHC_PKGDB" --package-env="$GHC_ENV" \
    --global --overwrite-policy=always --force-reinstalls
}

do_ormolu() {
  # Enforce pinned ormolu — formatting output differs between versions, so the
  # judge version is mandatory. Replace any other version.
  ormolu --version 2>/dev/null | grep -qF "$ORMOLU_VER" && { echo "    ormolu ${ORMOLU_VER} present."; return 0; }
  export GHCUP_INSTALL_BASE_PREFIX=/usr/local
  sudo rm -f /usr/local/bin/ormolu
  sudo -E cabal install "ormolu-${ORMOLU_VER}" --install-method=copy --installdir=/usr/local/bin --overwrite-policy=always
}

do_hls() {
  haskell-language-server-wrapper --version 2>/dev/null | grep -qF "$HLS_VER" && { echo "    HLS ${HLS_VER} present."; return 0; }
  export GHCUP_INSTALL_BASE_PREFIX=/usr/local
  sudo -E ghcup install hls "$HLS_VER" && sudo -E ghcup set hls "$HLS_VER" || return 1
  local f
  for f in /usr/local/.ghcup/bin/haskell-language-server*; do
    sudo ln -sf "$f" /usr/local/bin/"$(basename "$f")"
  done
}

# ============================================================
# Other languages / tools
# ============================================================
do_java() { sudo apt install -y openjdk-21-jdk; }

do_node() {
  command -v node &>/dev/null && node -v | grep -q '^v2[4-9]' && { echo "    node already current."; return 0; }
  curl -fsSL --retry 3 https://deb.nodesource.com/setup_24.x | sudo -E bash - \
    && sudo apt install -y nodejs
}

do_go() {
  command -v go &>/dev/null && { echo "    go already installed."; return 0; }
  mkdir -p ~/Downloads; cd ~/Downloads || return 1
  fetch "https://go.dev/dl/go1.19.13.linux-amd64.tar.gz" go.tgz || {
    echo "    WARNING: Go download failed."; cd ~; return 1; }
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf go.tgz
  echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh >/dev/null
  export PATH="$PATH:/usr/local/go/bin"
  cd ~
}

do_docker() {
  if command -v docker &>/dev/null; then
    echo "    docker already installed; ensuring service."
    sudo systemctl enable --now docker 2>/dev/null || true
    return 0
  fi
  sudo install -m0755 -d /etc/apt/keyrings
  # Temp-file + non-empty guard; install -m644 also avoids gpg's interactive
  # "overwrite?" prompt that bombs out under a non-interactive run.
  local t; t="$(mktemp)"
  curl -fsSL --retry 3 https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor > "$t" 2>/dev/null
  [[ -s "$t" ]] || { echo "    WARNING: docker key download failed."; rm -f "$t"; return 1; }
  sudo install -m644 "$t" /etc/apt/keyrings/docker.gpg; rm -f "$t"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker
}

do_gh() {
  command -v gh &>/dev/null && { echo "    gh already installed."; return 0; }
  sudo mkdir -p -m 755 /etc/apt/keyrings
  local t; t="$(mktemp)"
  curl -fsSL --retry 3 https://cli.github.com/packages/githubcli-archive-keyring.gpg > "$t"
  [[ -s "$t" ]] || { echo "    WARNING: gh key download failed."; rm -f "$t"; return 1; }
  sudo install -m644 "$t" /etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg; rm -f "$t"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt update && sudo apt install -y gh
}

do_ruby()   { command -v ruby  &>/dev/null && return 0; sudo apt install -y ruby; }
do_prolog() {
  command -v swipl &>/dev/null && return 0
  sudo apt-add-repository -y ppa:swi-prolog/stable && sudo apt update && sudo apt install -y swi-prolog
}
do_racket() {
  command -v racket &>/dev/null && return 0
  mkdir -p ~/Downloads; cd ~/Downloads || return 1
  local inst="racket-minimal-8.12-x86_64-linux-bc.sh"
  fetch "https://download.racket-lang.org/releases/8.12/installers/${inst}" "$inst" || {
    echo "    WARNING: Racket download failed."; cd ~; return 1; }
  chmod +x "$inst" && sudo bash "./$inst" && sudo ln -sf /usr/racket/bin/* /usr/local/bin/
  local rc=$?; cd ~; return $rc
}

# ============================================================
# Verification — actually TEST the install; gate the exit code
# ============================================================
VFAIL=0   # critical verification failures
VWARN=0   # optional verification failures

vcrit() {  # vcrit "label" cmd...
  local label="$1"; shift
  if "$@" &>/dev/null; then echo "  [ OK ] $label"; else echo "  [FAIL] $label"; VFAIL=$((VFAIL+1)); fi
}
vopt() {   # vopt "label" cmd...
  local label="$1"; shift
  if "$@" &>/dev/null; then echo "  [ OK ] $label"; else echo "  [warn] $label (optional)"; VWARN=$((VWARN+1)); fi
}
vver() {   # vver "label" "expected-substring" cmd...   — CRITICAL exact-version check
  local label="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1)"
  if echo "$out" | grep -qF "$want"; then
    echo "  [ OK ] $label = $want"
  else
    echo "  [FAIL] $label expected '$want', got: $(echo "$out" | head -1)"
    VFAIL=$((VFAIL+1))
  fi
}

verify_hls_typecheck() {
  local f; f="$(mktemp --suffix=.hs)"
  printf 'main :: IO ()\nmain = putStrLn "ok"\n' > "$f"
  haskell-language-server-wrapper typecheck "$f" &>/dev/null
  local rc=$?; rm -f "$f"; return $rc
}

verify_account() {  # verify_account <user>
  local acct="$1"
  id "$acct" &>/dev/null || { echo "  [skip] account '$acct' absent"; return; }
  local home; home="$(getent passwd "$acct" | cut -d: -f6)"
  echo "  -- $acct ($home) --"
  local item
  for item in "${DOTFILE_ITEMS[@]}"; do
    if sudo test -e "$home/$item"; then echo "    [ OK ] $item"
    else echo "    [FAIL] $item MISSING"; VFAIL=$((VFAIL+1)); fi
  done
  if sudo grep -q "/usr/local/.ghcup/bin" "$home/.ghcup/env" 2>/dev/null; then
    echo "    [ OK ] .ghcup/env -> global toolchain"
  else echo "    [FAIL] .ghcup/env missing/!global"; VFAIL=$((VFAIL+1)); fi
  local ghc_env_link="$home/.ghc/x86_64-linux-${GHC_VER}/environments/default"
  if sudo test -L "$ghc_env_link" && sudo test -e "$ghc_env_link"; then
    echo "    [ OK ] GHC default env -> global (HUnit visible to plain ghci)"
  else echo "    [FAIL] GHC default env symlink missing"; VFAIL=$((VFAIL+1)); fi
  if sudo test -f "$home/.config/sublime-text/Packages/User/LSP.sublime-settings"; then
    echo "    [ OK ] Sublime LSP settings (correct path)"
  else echo "    [FAIL] Sublime LSP.sublime-settings missing/!correct path"; VFAIL=$((VFAIL+1)); fi
  if sudo test -f "$home/Desktop/TestSetup.hs"; then echo "    [ OK ] Desktop/TestSetup.hs"
  else echo "    [FAIL] Desktop/TestSetup.hs missing"; VFAIL=$((VFAIL+1)); fi
  # Optional per-account extras (warn only — present for both student & sudoer).
  local extra
  for extra in ".config/tinted-shell" ".fzf.bash" ".venv"; do
    if sudo test -e "$home/$extra"; then echo "    [ OK ] $extra"
    else echo "    [warn] $extra missing (optional)"; VWARN=$((VWARN+1)); fi
  done
}

verify_install() {
  # Ensure global tool dirs are on PATH for these checks regardless of shell.
  export PATH="/usr/local/bin:/usr/local/.ghcup/bin:/usr/local/go/bin:$PATH"

  echo ""
  echo "============================================================"
  echo " STEP RESULTS"
  echo "============================================================"
  local r
  for r in "${STEP_RESULTS[@]}"; do printf "  %-5s  %s\n" "${r%%|*}" "${r#*|}"; done

  echo ""
  echo "============================================================"
  echo " VERIFICATION (CRITICAL)"
  echo "============================================================"
  # Exact-version checks (judge parity — pinned in UBUNTU.md).
  vver  "ghc"      "$GHC_VER"          ghc --version
  vver  "cabal"    "$CABAL_VER"        cabal --version
  vver  "stack"    "$STACK_VER"        stack --version
  vver  "ormolu"   "$ORMOLU_VER"       ormolu --version
  vver  "HLS"      "$HLS_VER"          haskell-language-server-wrapper --version
  vver  "HUnit"    "HUnit-$HUNIT_VER"  sudo ghc-pkg --package-db="$CABAL_PKGDB" list HUnit
  vcrit "HLS typecheck a .hs file"    verify_hls_typecheck
  vcrit "HUnit importable"            sudo ghc -package-db="$GHC_PKGDB" -package-env="$GHC_ENV" -e "import Test.HUnit"
  vcrit "java"                        java -version
  vcrit "node"                        node -v
  vcrit "python3"                     python3 --version
  vcrit "mypy"                        mypy --version
  vcrit "Sublime (subl)"             command -v subl

  echo ""
  echo " VERIFICATION (OPTIONAL)"
  vopt  "go"                          go version
  vopt  "docker"                      docker --version
  vopt  "lazydocker"                  lazydocker --version
  vopt  "gh"                          gh --version
  vopt  "fzf"                         fzf --version
  vopt  "uv"                          uv --version
  vopt  "bash-completion"             dpkg -s bash-completion
  vopt  "FiraCode font"               bash -c 'fc-list | grep -qi fira'
  vopt  "Iosevka Nerd font"           bash -c 'fc-list | grep -qi iosevka'
  vopt  "ruby"                        ruby --version
  vopt  "swipl (prolog)"             swipl --version
  vopt  "racket"                      racket --version

  echo ""
  echo " DOT FILES / SETTINGS PER ACCOUNT"
  verify_account "$STUDENT_ACCOUNT"
  [[ "$INSTALLER_PROVISIONED" == "1" ]] && verify_account "$INSTALLER_USER"

  echo ""
  echo "============================================================"
  if [[ "$VFAIL" -eq 0 ]]; then
    echo " RESULT: SUCCESS — all critical checks passed (${VWARN} optional warning(s))."
    echo "============================================================"
    return 0
  else
    echo " RESULT: FAILURE — ${VFAIL} critical check(s) failed (${VWARN} optional warning(s))."
    echo " Review the [FAIL] lines and the STEP RESULTS above."
    echo "============================================================"
    return 1
  fi
}

# ============================================================
# Main
# ============================================================
echo "Ubuntu lab setup — resilient run (continues on errors, verifies at end)."

step "Student account"            setup_student_account
step "System update"              do_system_update
step "Basic tools"                do_basic_tools
step "Apps (Brave, WezTerm)"      do_apps
step "Programming fonts"          do_fonts
step "uv (Python pkg mgr)"        do_uv
step "Dot files (ubuntu_home)"    install_all_dotfiles
step "XFCE theme (Numix)"         do_xfce_theme
step "XFCE panel (apps + launchers)" do_xfce_panel
step "Disable lightdm autologin"     do_disable_autologin
step "Python (numpy/pandas)"      do_python
step "Sublime Text"               do_sublime
step "Haskell deps"               do_haskell_deps
step "GHC ${GHC_VER}"             do_ghc
step "GHCup"                      do_ghcup
step "Cabal ${CABAL_VER}"         do_cabal
step "Stack ${STACK_VER}"         do_stack
step "HUnit ${HUNIT_VER} (global)" do_hunit
step "Ormolu"                     do_ormolu
step "Haskell Language Server"    do_hls
step "Java (OpenJDK 21)"          do_java
step "NodeJS 24"                  do_node
step "Go 1.19.13"                 do_go
step "Docker"                     do_docker
step "lazydocker"                 do_lazydocker
step "GitHub CLI"                 do_gh
step "Ruby"                       do_ruby
step "SWI-Prolog"                 do_prolog
step "Racket"                     do_racket

verify_install
exit $?
