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
STUDENT_ACCOUNT="${STUDENT_ACCOUNT:-csmajor}"

# Password used when this script has to CREATE the student account.
# Public repo rule: never store the lab password here. Pass STUDENT_PASSWORD
# from the private deployment flow or provide a private student_password.txt.
STUDENT_PASSWORD="${STUDENT_PASSWORD:-}"

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
INSTALLER_HOME="$(getent passwd "$INSTALLER_USER" | cut -d: -f6)"

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

is_lab_cscmu_machine() {
  # "cscmu" marks the slow CS major room machines that must not run Docker.
  # Other account policy must continue to use SUDOER_ACCOUNT/STUDENT_ACCOUNT.
  id cscmu &>/dev/null
}

is_veriton_machine() {
  hostname | grep -qi 'veriton' && return 0
  hostnamectl 2>/dev/null | grep -qi 'veriton'
}

disable_unit_if_present() {  # disable_unit_if_present <unit>
  local unit="$1"
  if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q "^${unit}[[:space:]]"; then
    sudo systemctl disable --now "$unit" 2>/dev/null || true
  else
    echo "    [skip] $unit not installed"
  fi
}

do_disable_veriton_slow_boot_services() {
  if ! is_veriton_machine; then
    echo "    [skip] not a Veriton host"
    return 0
  fi

  echo "    Disabling slow boot services on Veriton host..."
  local unit
  for unit in \
    NetworkManager-wait-online.service \
    apport.service \
    snapd.service \
    snapd.seeded.service \
    snapd.socket \
    snapd.apparmor.service \
    bluetooth.service \
    avahi-daemon.service \
    avahi-daemon.socket \
    cups.service \
    cups.socket \
    cups.path \
    cups-browsed.service \
    e2scrub_reap.service \
    e2scrub_all.service \
    e2scrub_all.timer \
    apt-daily.service \
    apt-daily.timer \
    apt-daily-upgrade.service \
    apt-daily-upgrade.timer
  do
    disable_unit_if_present "$unit"
  done
  return 0
}

# ============================================================
# Student account (create if missing)
# ============================================================
setup_student_account() {
  # Remove the image-default account before creating/fixing csmajor. On the
  # Veritons it owned UID 1001, which prevented a consistent csmajor UID.
  if [[ "$STUDENT_ACCOUNT" != "student" ]] && id student &>/dev/null; then
    echo "    Removing legacy 'student' account..."
    sudo loginctl terminate-user student 2>/dev/null || true
    sudo pkill -KILL -u student 2>/dev/null || true
    sleep 2
    sudo userdel -f -r student 2>/dev/null || sudo userdel -f student 2>/dev/null || true
    sudo groupdel student 2>/dev/null || true
  fi

  if ! getent group "$STUDENT_ACCOUNT" &>/dev/null; then
    if getent group 1001 &>/dev/null; then
      sudo groupadd "$STUDENT_ACCOUNT" || true
    else
      sudo groupadd -g 1001 "$STUDENT_ACCOUNT" || true
    fi
  elif [[ "$(getent group "$STUDENT_ACCOUNT" | cut -d: -f3)" != "1001" ]] \
       && ! getent group 1001 &>/dev/null; then
    sudo groupmod -g 1001 "$STUDENT_ACCOUNT" || true
  fi

  # Prompt for a name only when missing AND we have a terminal; otherwise keep
  # the configured default (so the script is safe to run non-interactively).
  if ! id "$STUDENT_ACCOUNT" &>/dev/null && [ -t 0 ]; then
    read -rp "Account '$STUDENT_ACCOUNT' not found. Username to create [$STUDENT_ACCOUNT]: " input_user
    STUDENT_ACCOUNT="${input_user:-$STUDENT_ACCOUNT}"
  fi

  if ! id "$STUDENT_ACCOUNT" &>/dev/null; then
    echo "    Creating user '$STUDENT_ACCOUNT' (no sudo) with fixed UID 1001..."
    # IMPORTANT: Fixed UID 1001 ensures consistency across all lab boxes
    sudo useradd -m -s /bin/bash -u 1001 -g "$STUDENT_ACCOUNT" "$STUDENT_ACCOUNT" || return 1
    local pass="$STUDENT_PASSWORD"
    [[ -f "$PASSWORD_FILE" ]] && pass="$(cat "$PASSWORD_FILE")"
    if [[ -n "$pass" ]]; then
      echo "${STUDENT_ACCOUNT}:${pass}" | sudo chpasswd
      echo "    Password set for '$STUDENT_ACCOUNT'."
    else
      sudo passwd -l "$STUDENT_ACCOUNT" >/dev/null 2>&1 || true
      echo "    No student password provided; '$STUDENT_ACCOUNT' password login locked."
    fi
  else
    # Check if existing account has wrong UID and fix it
    local current_uid
    current_uid=$(id -u "$STUDENT_ACCOUNT" 2>/dev/null)
    if [[ "$current_uid" != "1001" ]]; then
      echo "    WARNING: '$STUDENT_ACCOUNT' has UID $current_uid (should be 1001)"
      echo "    Fixing UID to 1001 for consistency..."
      sudo usermod -u 1001 "$STUDENT_ACCOUNT"
      # Fix file ownership for the new UID
      sudo find /home -user "$current_uid" -exec chown -h "$STUDENT_ACCOUNT:$STUDENT_ACCOUNT" {} \; 2>/dev/null || true
      sudo find / -xdev -user "$current_uid" -exec chown -h "$STUDENT_ACCOUNT:$STUDENT_ACCOUNT" {} \; 2>/dev/null || true
      echo "    UID fixed to 1001"
    fi
    sudo usermod -g "$STUDENT_ACCOUNT" "$STUDENT_ACCOUNT" 2>/dev/null || true
    echo "    User '$STUDENT_ACCOUNT' already exists; leaving password unchanged."
  fi
  sudo usermod -G "" "$STUDENT_ACCOUNT" 2>/dev/null || true
  STUDENT_HOME="$(getent passwd "$STUDENT_ACCOUNT" | cut -d: -f6)"
  echo "    Student account: $STUDENT_ACCOUNT  (home: $STUDENT_HOME)"
  [[ -n "$STUDENT_HOME" ]]
}

do_student_policy() {
  echo "    Enforcing restricted student account policy..."
  id "$STUDENT_ACCOUNT" &>/dev/null || { echo "    [skip] '$STUDENT_ACCOUNT' missing"; return 1; }
  for grp in sudo admin wheel docker lxd; do
    if getent group "$grp" >/dev/null && id -nG "$STUDENT_ACCOUNT" | tr ' ' '\n' | grep -qx "$grp"; then
      sudo gpasswd -d "$STUDENT_ACCOUNT" "$grp" >/dev/null 2>&1 || true
      echo "      Removed '$STUDENT_ACCOUNT' from $grp."
    fi
  done
  return 0
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
    tmux byobu dos2unix xclip fzf \
    emacs-nox vim neovim bat \
    wget curl gnupg ca-certificates \
    kdiff3
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
  if is_lab_cscmu_machine; then
    echo "    [skip] cscmu lab machine: Docker tooling is intentionally not installed."
    return 0
  fi
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

  # GOLDEN RULE: Preserve ntfy callback mechanism before wiping .config
  local ntfy_backup=""
  if [[ -d "$home/.config/major-room" ]]; then
    ntfy_backup=$(mktemp -d)
    echo "      [GOLDEN RULE] Backing up ntfy callback config..."
    sudo cp -a "$home/.config/major-room" "$ntfy_backup/"
    sudo cp -a "$home/bin/major-room-report.sh" "$ntfy_backup/" 2>/dev/null || true
  fi

  for item in "${DOTFILE_ITEMS[@]}"; do
    if [[ -e "$UBUNTU_HOME_TMP/$item" ]]; then
      # Remove existing target FIRST so a pre-existing symlink (e.g. a personal
      # dot file linked into Dropbox) is replaced, not written THROUGH.
      sudo rm -rf "$home/$item"
      sudo cp -rf "$UBUNTU_HOME_TMP/$item" "$home"/
    fi
  done

  # GOLDEN RULE: Restore ntfy callback mechanism after dotfiles install
  if [[ -n "$ntfy_backup" ]]; then
    echo "      [GOLDEN RULE] Restoring ntfy callback config..."
    sudo mkdir -p "$home/.config"
    sudo cp -a "$ntfy_backup/major-room" "$home/.config/"
    sudo mkdir -p "$home/bin"
    sudo cp -a "$ntfy_backup/major-room-report.sh" "$home/bin/" 2>/dev/null || true
    sudo chown -R "$user:$user" "$home/.config/major-room" "$home/bin/major-room-report.sh" 2>/dev/null || true
    sudo rm -rf "$ntfy_backup"
  fi
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
# ntfy Callback Mechanism (Discovery)
# ============================================================
# GOLDEN RULE: This function MUST preserve ~/.config/major-room/ntfy.conf
# and ~/bin/major-room-report.sh at ALL TIMES. The callback mechanism
# is critical for fleet discovery and must never be removed or broken.
# This step runs AFTER install_all_dotfiles which wipes ~/.config,
# so it MUST be called after that step in the main sequence.
do_ntfy_report() {
  # Check for required environment variables (credentials should be passed in)
  [[ -z "${NTFY_URL:-}" ]] && { echo "    [skip] NTFY_URL not set"; return 0; }
  [[ -z "${NTFY_TOPIC:-}" ]] && { echo "    [skip] NTFY_TOPIC not set"; return 0; }
  [[ -z "${NTFY_USER:-}" ]] && { echo "    [skip] NTFY_USER not set"; return 0; }
  [[ -z "${NTFY_PASS:-}" ]] && { echo "    [skip] NTFY_PASS not set"; return 0; }

  echo "    Installing ntfy callback mechanism (GOLDEN RULE - always preserved)..."
  # ntfy config for both csmajor and cscmu
  for user_home in "$STUDENT_HOME" "$INSTALLER_HOME"; do
    [[ ! -d "$user_home" ]] && continue
    local user; user="$(basename "$user_home")"
    echo "      Setting up ntfy for '$user' ($user_home)..."

    # Create ntfy config directory and config file using env vars
    # GOLDEN RULE: Always preserve this config - never remove during any installation
    sudo mkdir -p "$user_home/.config/major-room"
    sudo tee "$user_home/.config/major-room/ntfy.conf" > /dev/null <<NTFYEOF
NTFY_URL=$NTFY_URL
NTFY_TOPIC=$NTFY_TOPIC
NTFY_USER=$NTFY_USER
NTFY_PASS=$NTFY_PASS
NTFYEOF
    sudo chmod 600 "$user_home/.config/major-room/ntfy.conf"
    sudo chown -R "$user:$user" "$user_home/.config/major-room"

    # Deploy reporter script - GOLDEN RULE: Always preserve this script
    sudo mkdir -p "$user_home/bin"
    sudo tee "$user_home/bin/major-room-report.sh" > /dev/null <<'REPORTEOF'
#!/usr/bin/env bash
# Phone home at boot and every 15 minutes: publish this box's current network
# identity to the self-hosted ntfy server on score_cron (private topic, basic auth).
set -u
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/major-room/ntfy.conf"
[ -r "$CONF" ] || exit 0
. "$CONF"
[ -z "${NTFY_URL:-}" ] || [ -z "${NTFY_TOPIC:-}" ] && exit 0

for _ in $(seq 1 6); do
  if=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
  [ -z "$if" ] && { sleep 15; continue; }
  mac=$(cat "/sys/class/net/$if/address" 2>/dev/null)
  [ -z "$mac" ] && { sleep 15; continue; }
  ip4=$(ip -4 -o addr show "$if" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
  [ -z "$ip4" ] && { sleep 15; continue; }
  hn=$(hostname)
  ts=$(date -u +%FT%TZ)
  msg="mac=$mac ip=$ip4 iface=$if host=$hn ts=$ts"
  code=$(curl -s -m 6 -o /dev/null -w '%{http_code}' \
    -u "${NTFY_USER:-}:${NTFY_PASS:-}" \
    -H "Title: $hn" -H "Tags: $mac" \
    -d "$msg" "${NTFY_URL%/}/${NTFY_TOPIC}" 2>/dev/null || echo 000)
  [ "$code" = "200" ] && exit 0
  sleep 15
done
exit 0
REPORTEOF
    sudo chmod +x "$user_home/bin/major-room-report.sh"
    sudo chown "$user:$user" "$user_home/bin/major-room-report.sh"

    # Create symlink for old crontab path compatibility
    sudo ln -sf "$user_home/bin/major-room-report.sh" "$user_home/major-room-report.sh" 2>/dev/null || true

    # Keep callback frequent. DHCP IPs change, so registry must refresh
    # even when a box did not reboot cleanly.
    local reboot_cron="@reboot $user_home/bin/major-room-report.sh"
    local interval_cron="*/15 * * * * $user_home/bin/major-room-report.sh"
    (
      sudo -u "$user" crontab -l 2>/dev/null | grep -v 'major-room-report.sh' || true
      echo "$reboot_cron"
      echo "$interval_cron"
    ) | sudo -u "$user" crontab -
    echo "        Installed @reboot + */15 callback crontab for '$user'"
  done

  # Test reporter once
  echo "      Testing reporter (csmajor)..."
  sudo -u "$STUDENT_ACCOUNT" "$STUDENT_HOME/bin/major-room-report.sh" && \
    echo "        ✓ Test report successful" || echo "        ⚠ Test report failed (may work on reboot)"
  return 0
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
# XFCE Desktop Environment (Apps, Theme, Panel)
# ============================================================
# GOLDEN RULE: All functions MUST preserve ~/.config/major-room/ntfy.conf
# and ~/bin/major-room-report.sh to maintain callback mechanism.

do_xfce_apps() {
  echo "    Installing desktop applications..."
  # Brave browser
  command -v brave-browser &>/dev/null && \
    echo "      Brave browser already installed." || {
    sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave.com/brave-browser-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | \
      sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
    sudo apt update
    sudo apt install -y brave-browser
  }

  # WezTerm terminal
  command -v wezterm &>/dev/null && \
    echo "      WezTerm already installed." || {
    sudo apt install -y wezterm
  }
  return 0
}

do_xfce_theme() {
  echo "    Installing XFCE desktop theme..."
  # Install Numix theme and icons
  sudo apt install -y numix-gtk-theme numix-icon-theme-circle

  # Apply theme for both csmajor and cscmu
  for user_home in "$STUDENT_HOME" "$INSTALLER_HOME"; do
    [[ ! -d "$user_home" ]] && continue
    local user; user="$(basename "$user_home")"
    echo "      Setting up theme for '$user'..."

    # Set Numix GTK and window manager theme via xfconf
    sudo -u "$user" xfconf-query -c xsettings -p /Net/ThemeName -s "Numix" -t string 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xsettings -p /Net/IconThemeName -s "Numix-Circle" -t string 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfwm4 -p /general/theme -s "Numix" -t string 2>/dev/null || true

    # Set SOLID dark grey background (#222222) - NO wallpaper image
    # This creates a solid color background instead of using an image
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/color-shading-type -s "solid" -t string 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/color1 -r -t uint8 34 -t uint8 34 -t uint8 34 -t uint8 255 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/color2 -r -t uint8 34 -t uint8 34 -t uint8 34 -t uint8 255 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-style -s 0 -t int 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/last-image -s "" -t string 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s "" -t string 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor1/color-shading-type -s "solid" -t string 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor1/color1 -r -t uint8 34 -t uint8 34 -t uint8 34 -t uint8 255 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor1/color2 -r -t uint8 34 -t uint8 34 -t uint8 34 -t uint8 255 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor1/image-style -s 0 -t int 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor1/last-image -s "" -t string 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor1/image-path -s "" -t string 2>/dev/null || true

    # Set dark GTK theme preferences
    sudo -u "$user" xfconf-query -c xsettings -p /Gtk/ThemeName -s "Numix" -t string 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xsettings -p /Gtk/IconThemeName -s "Numix-Circle" -t string 2>/dev/null || true
    sudo -u "$user" xfconf-query -c xsettings -p /Gtk/FontName -s "Sans 10" -t string 2>/dev/null || true

    # Add xfce4-settings-autostart to ensure theme persists
    sudo mkdir -p "$user_home/.config/autostart"
    sudo tee "$user_home/.config/autostart/xfce4-settings-autostart.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Type=Application
Name=XFCE Settings Autostart
Exec=xfce4-settings-manager
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
    sudo chown "$user:$user" "$user_home/.config/autostart/xfce4-settings-autostart.desktop"
  done
  return 0
}

do_xfce_panel() {
  echo "    Setting up XFCE panel..."
  # Install xfce4-panel if not present
  sudo apt install -y xfce4-panel xfce4-whiskermenu-plugin

  for user_home in "$STUDENT_HOME" "$INSTALLER_HOME"; do
    [[ ! -d "$user_home" ]] && continue
    local user; user="$(basename "$user_home")"
    echo "      Configuring panel for '$user'..."

    # Create panel config directory
    sudo mkdir -p "$user_home/.config/xfce4/panel"

    # Create launcher .desktop files
    local launcher_dir="$user_home/.local/share/applications"
    sudo mkdir -p "$launcher_dir"

    # Brave launcher
    sudo tee "$launcher_dir/brave-browser.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Name=Brave Web Browser
GenericName=Web Browser
Comment=Browse the World Wide Web
Exec=brave-browser %U
Terminal=false
X-MultipleArgs=false
Type=Application
Icon=brave-browser
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;
EOF

    # Sublime launcher
    sudo tee "$launcher_dir/sublime-text.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Name=Sublime Text
GenericName=Text Editor
Comment=Sophisticated text editor
Exec=subl %F
Terminal=false
Type=Application
Icon=sublime-text
Categories=TextEditor;Development;
EOF

    # WezTerm launcher
    sudo tee "$launcher_dir/wezterm.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Name=WezTerm
GenericName=Terminal
Comment=GPU-accelerated terminal emulator
Exec=wezterm
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
EOF

    sudo chown -R "$user:$user" "$launcher_dir"

    # Create panel configuration with launchers
    sudo tee "$user_home/.config/xfce4/panel/panels-1.rc" > /dev/null << 'PANELEOF'
panels=toc9hv1:1:57
toc9hv1:1:57=config
config=toc9hv1:1:57
toc9hv1:1:1=whiskermenu-button-1
toc9hv1:1:2=launcher-2
toc9hv1:1:3=launcher-3
toc9hv1:1:4=launcher-4
toc9hv1:1:5=tasklist-5
toc9hv1:1:6=systray-6
toc9hv1:1:7=clock-7

whiskermenu-button-1=plugin
plugin-2=plugin
plugin-3=plugin
plugin-4=plugin
plugin-5=plugin
plugin-6=plugin
plugin-7=plugin

plugin-2=launcher
plugin-3=launcher
plugin-4=launcher

clear=toc9hv1:1:57;3;4;5;6;7
PANELEOF

    # Create launcher plugin configs
    sudo mkdir -p "$user_home/.config/xfce4/panel/plugin-2"
    sudo tee "$user_home/.config/xfce4/panel/plugin-2/launcher-2.rc" > /dev/null << 'EOF'
[Entry]
Name=Brave Browser
Comment=Web Browser
Icon=brave-browser
Exec=brave-browser
EOF

    sudo mkdir -p "$user_home/.config/xfce4/panel/plugin-3"
    sudo tee "$user_home/.config/xfce4/panel/plugin-3/launcher-3.rc" > /dev/null << 'EOF'
[Entry]
Name=Sublime Text
Comment=Text Editor
Icon=sublime-text
Exec=subl
EOF

    sudo mkdir -p "$user_home/.config/xfce4/panel/plugin-4"
    sudo tee "$user_home/.config/xfce4/panel/plugin-4/launcher-4.rc" > /dev/null << 'EOF'
[Entry]
Name=WezTerm
Comment=Terminal
Icon=terminal
Exec=wezterm
EOF

    sudo chown -R "$user:$user" "$user_home/.config/xfce4"
  done
  return 0
}

set_lightdm_autologin_file() {  # set_lightdm_autologin_file <path>
  local cfg="$1" tmp
  tmp="$(mktemp)"
  if [[ -f "$cfg" ]]; then
    sudo cp "$cfg" "$tmp"
    sudo chown "$(id -u):$(id -g)" "$tmp"
    if grep -q '^autologin-user=' "$tmp"; then
      sed -i "s/^autologin-user=.*/autologin-user=${STUDENT_ACCOUNT}/" "$tmp"
    else
      printf '\nautologin-user=%s\n' "$STUDENT_ACCOUNT" >> "$tmp"
    fi
  else
    printf '[Seat:*]\nautologin-user=%s\n' "$STUDENT_ACCOUNT" > "$tmp"
  fi
  sudo install -m 644 "$tmp" "$cfg"
  rm -f "$tmp"
}

do_enable_student_autologin() {
  echo "    Enabling LightDM autologin for '$STUDENT_ACCOUNT'..."
  id "$STUDENT_ACCOUNT" &>/dev/null || { echo "    [skip] '$STUDENT_ACCOUNT' missing"; return 1; }
  sudo mkdir -p /etc/lightdm/lightdm.conf.d
  # iMacs and Veritons read different LightDM layouts. Keep both explicit.
  set_lightdm_autologin_file /etc/lightdm/lightdm.conf
  set_lightdm_autologin_file /etc/lightdm/lightdm.conf.d/lightdm.conf
  return 0
}

do_ip_screensaver() {
  # XScreenSaver (phosphor) showing hostname + CURRENT IP, but ONLY when the box
  # can actually reach the internet (so a stale DHCP IP is never displayed).
  # v6.08 reads ~/.xscreensaver (NOT ~/.config/xscreensaver/XScreenSaver).
  # Saver appears at 5 min; the monitor powers off (DPMS) at 35 min. Also
  # disables xfce4-screensaver (conflicts). Applied to both managed accounts.
  echo "    Configuring IP screensaver (phosphor) for managed users..."
  command -v xscreensaver &>/dev/null || \
    sudo apt install -y xscreensaver xscreensaver-data xscreensaver-data-extra xscreensaver-gl

  local user_home user
  for user_home in "$STUDENT_HOME" "$INSTALLER_HOME"; do
    [[ ! -d "$user_home" ]] && continue
    user="$(basename "$user_home")"
    echo "      Screensaver for '$user'..."

    sudo install -d -o "$user" -g "$user" -m 755 "$user_home/.local/bin"
    sudo tee "$user_home/.local/bin/major-room-saver-text.sh" >/dev/null <<'STXT'
#!/bin/bash
# Shown on the screensaver. Prints hostname + current IP only when the box can
# reach the internet (ping out); otherwise an offline notice (never a stale IP).
export LC_ALL=C
hn=$(hostname)
ifc=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
ip4=$(ip -4 -o addr show "$ifc" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
if ping -c1 -W2 google.com >/dev/null 2>&1; then
  printf '%s\nIP: %s\nonline\n' "$hn" "${ip4:-unknown}"
else
  printf '%s\noffline\n' "$hn"
fi
STXT
    sudo chmod 755 "$user_home/.local/bin/major-room-saver-text.sh"
    sudo chown "$user:$user" "$user_home/.local/bin/major-room-saver-text.sh"

    sudo tee "$user_home/.xscreensaver" >/dev/null <<XSS
timeout:        0:05:00
cycle:          0:05:00
lockTimeout:    0:00:00
lock:           False
mode:           one
selected:       0
dpmsEnabled:    True
dpmsStandby:    0:35:00
dpmsSuspend:    0:35:00
dpmsOff:        0:35:00
textMode:       program
textProgram:    $user_home/.local/bin/major-room-saver-text.sh
programs:       phosphor -scale 4 -root
XSS
    sudo chown "$user:$user" "$user_home/.xscreensaver"

    sudo install -d -o "$user" -g "$user" -m 755 "$user_home/.config/autostart"
    sudo tee "$user_home/.config/autostart/xfce4-screensaver.desktop" >/dev/null <<'D'
[Desktop Entry]
Type=Application
Name=Screensaver
Exec=xfce4-screensaver
Hidden=true
X-GNOME-Autostart-enabled=false
D
    sudo tee "$user_home/.config/autostart/xscreensaver.desktop" >/dev/null <<'D'
[Desktop Entry]
Type=Application
Name=XScreenSaver
Exec=xscreensaver -nosplash
X-GNOME-Autostart-enabled=true
D
    sudo chown "$user:$user" \
      "$user_home/.config/autostart/xfce4-screensaver.desktop" \
      "$user_home/.config/autostart/xscreensaver.desktop"
  done
  return 0
}

# Apple keyboards (iMacs): make F1-F12 real function keys (fnmode=2) instead of
# media/brightness keys, so they reach byobu/tmux without holding Fn.
do_imac_fnkeys() {
  [[ -e /sys/module/hid_apple/parameters/fnmode ]] || { echo "    [skip] not an Apple keyboard"; return 0; }
  echo "    Setting Apple keyboard fnmode=2 (F-keys are function keys)..."
  echo "options hid_apple fnmode=2" | sudo tee /etc/modprobe.d/hid_apple.conf >/dev/null
  echo 2 | sudo tee /sys/module/hid_apple/parameters/fnmode >/dev/null 2>&1 || true
  sudo update-initramfs -u >/dev/null 2>&1 || true
  return 0
}

# Free F1/F11 in xfce4-terminal so byobu/tmux receive them (empty accel = pass-through).
do_terminal_accels() {
  echo "    Freeing xfce4-terminal F-keys for byobu/tmux..."
  local user_home user
  for user_home in "$STUDENT_HOME" "$INSTALLER_HOME"; do
    [[ ! -d "$user_home" ]] && continue
    user="$(basename "$user_home")"
    sudo install -d -o "$user" -g "$user" -m 700 "$user_home/.config/xfce4/terminal"
    sudo tee "$user_home/.config/xfce4/terminal/accels.scm" >/dev/null <<'D'
(gtk_accel_path "<Actions>/terminal-window/contents" "")
(gtk_accel_path "<Actions>/terminal-window/fullscreen" "")
D
    sudo chown "$user:$user" "$user_home/.config/xfce4/terminal/accels.scm"
  done
  return 0
}

# Thai keyboard layout: us,th with CapsLock toggle (tap=switch, Shift+Caps=CapsLock).
do_keyboard_thai() {
  echo "    Adding Thai keyboard layout (us,th; CapsLock toggle)..."
  local user_home user
  for user_home in "$STUDENT_HOME" "$INSTALLER_HOME"; do
    [[ ! -d "$user_home" ]] && continue
    user="$(basename "$user_home")"
    sudo -u "$user" xfconf-query -c keyboard-layout -p /Default/XkbDisable -n -t bool -s false 2>/dev/null || true
    sudo -u "$user" xfconf-query -c keyboard-layout -p /Default/XkbLayout  -n -t string -s "us,th" 2>/dev/null \
      || sudo -u "$user" xfconf-query -c keyboard-layout -p /Default/XkbLayout -s "us,th" 2>/dev/null || true
    sudo -u "$user" xfconf-query -c keyboard-layout -p /Default/XkbVariant -n -t string -s "," 2>/dev/null || true
    sudo -u "$user" xfconf-query -c keyboard-layout -p /Default/XkbOptions/Group -n -t string -s "grp:caps_toggle" 2>/dev/null \
      || sudo -u "$user" xfconf-query -c keyboard-layout -p /Default/XkbOptions/Group -s "grp:caps_toggle" 2>/dev/null || true
  done
  if [[ -f /etc/default/keyboard ]]; then
    sudo sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="us,th"/' /etc/default/keyboard
    if grep -q '^XKBOPTIONS=' /etc/default/keyboard; then
      sudo sed -i 's/^XKBOPTIONS=.*/XKBOPTIONS="grp:caps_toggle"/' /etc/default/keyboard
    else
      echo 'XKBOPTIONS="grp:caps_toggle"' | sudo tee -a /etc/default/keyboard >/dev/null
    fi
  fi
  return 0
}

# Panel keyboard-layout indicator that follows the X group (so CapsLock layout
# switching updates it). The default "EN" comes from ibus (tracks its own engine,
# not the xkb group), so disable ibus and add the xfce4-xkb-plugin.
do_panel_language_indicator() {
  echo "    Panel keyboard-layout indicator (xfce4-xkb-plugin); disabling ibus..."
  sudo apt install -y xfce4-xkb-plugin >/dev/null 2>&1 || true
  local user_home user uid local_panel mx new i
  for user_home in "$STUDENT_HOME" "$INSTALLER_HOME"; do
    [[ ! -d "$user_home" ]] && continue
    user="$(basename "$user_home")"; uid="$(id -u "$user")"
    printf 'run_im none\n' | sudo tee "$user_home/.xinputrc" >/dev/null
    sudo chown "$user:$user" "$user_home/.xinputrc"
    local R=(sudo -u "$user" env DISPLAY=:0 XAUTHORITY="$user_home/.Xauthority" \
      XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" HOME="$user_home")
    "${R[@]}" bash -c 'pkill -u "$(id -u)" ibus-daemon 2>/dev/null; true'
    if "${R[@]}" xfconf-query -c xfce4-panel -p /plugins -lv 2>/dev/null | awk '{print $2}' | grep -qx xkb; then
      continue
    fi
    local_panel=$("${R[@]}" xfconf-query -c xfce4-panel -p /panels 2>/dev/null | sed -n 's/^[[:space:]]*\([0-9]\+\).*/\1/p' | head -1)
    local_panel=${local_panel:-1}
    mx=$("${R[@]}" xfconf-query -c xfce4-panel -p /plugins -lv 2>/dev/null | grep -oE 'plugin-[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)
    new=$(( ${mx:-0} + 1 ))
    "${R[@]}" xfconf-query -c xfce4-panel -p "/plugins/plugin-$new" --create -t string -s xkb
    "${R[@]}" xfconf-query -c xfce4-panel -p "/plugins/plugin-$new/display-type" --create -t uint -s 1 2>/dev/null || true
    "${R[@]}" xfconf-query -c xfce4-panel -p "/plugins/plugin-$new/group-policy" --create -t uint -s 0 2>/dev/null || true
    local ids; mapfile -t ids < <("${R[@]}" xfconf-query -c xfce4-panel -p "/panels/panel-$local_panel/plugin-ids" 2>/dev/null \
                                    | sed -n 's/^[[:space:]]*\([0-9]\+\)[[:space:]]*$/\1/p')
    local args=(); for i in "${ids[@]}"; do args+=(-t int -s "$i"); done; args+=(-t int -s "$new")
    "${R[@]}" xfconf-query -c xfce4-panel -p "/panels/panel-$local_panel/plugin-ids" --create --force-array "${args[@]}"
    "${R[@]}" bash -c 'xfce4-panel -r >/dev/null 2>&1 &' || true
  done
  return 0
}

# ulauncher app launcher: autostart for managed users, Ctrl+Space to toggle.
do_ulauncher() {
  echo "    Installing ulauncher (Ctrl+Space launcher)..."
  if ! command -v ulauncher &>/dev/null; then
    local ver t
    ver="$(curl -s https://api.github.com/repos/Ulauncher/Ulauncher/releases/latest | grep -Po '"tag_name": "\K[^"]*')"
    if [[ -n "$ver" ]]; then
      t="$(mktemp --suffix=.deb)"
      if fetch "https://github.com/Ulauncher/Ulauncher/releases/download/${ver}/ulauncher_${ver}_all.deb" "$t"; then
        sudo apt install -y "$t" || { sudo dpkg -i "$t"; sudo apt-get -y -f install; }
      fi
      rm -f "$t"
    fi
  fi
  command -v ulauncher &>/dev/null || { echo "    WARNING: ulauncher install failed."; return 1; }
  local user_home user
  for user_home in "$STUDENT_HOME" "$INSTALLER_HOME"; do
    [[ ! -d "$user_home" ]] && continue
    user="$(basename "$user_home")"
    sudo install -d -o "$user" -g "$user" -m 755 "$user_home/.config/autostart"
    sudo tee "$user_home/.config/autostart/ulauncher.desktop" >/dev/null <<'D'
[Desktop Entry]
Type=Application
Name=Ulauncher
Comment=Application launcher
Exec=ulauncher --hide-window --no-window-shadow
Icon=ulauncher
Terminal=false
X-GNOME-Autostart-enabled=true
D
    sudo chown "$user:$user" "$user_home/.config/autostart/ulauncher.desktop"
    # Ctrl+Space toggles ulauncher (XFCE global shortcut).
    sudo -u "$user" xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary>space" -n -t string -s "ulauncher-toggle" 2>/dev/null \
      || sudo -u "$user" xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary>space" -s "ulauncher-toggle" 2>/dev/null || true
  done
  return 0
}

# Restrict SSH logins to the maintenance sudoer only (students never SSH in).
# sshd UNIONS all AllowUsers lines, so make the main config authoritative.
do_ssh_restrict() {
  echo "    Restricting SSH to '$SUDOER_ACCOUNT' only..."
  local main=/etc/ssh/sshd_config
  sudo cp -a "$main" "${main}.major.bak" 2>/dev/null || true
  if sudo grep -qiE '^[[:space:]]*AllowUsers' "$main"; then
    sudo sed -ri "s/^[[:space:]]*AllowUsers.*/AllowUsers ${SUDOER_ACCOUNT}/I" "$main"
  else
    printf '\n# major-room: restrict SSH to the maintenance sudoer only\nAllowUsers %s\n' \
      "$SUDOER_ACCOUNT" | sudo tee -a "$main" >/dev/null
  fi
  sudo mkdir -p /etc/ssh/sshd_config.d
  printf '# major-room: restrict SSH to the maintenance sudoer only\nAllowUsers %s\n' \
    "$SUDOER_ACCOUNT" | sudo tee /etc/ssh/sshd_config.d/10-major-room.conf >/dev/null
  if sudo sshd -t 2>/dev/null; then
    sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true
  else
    echo "    WARNING: sshd config invalid; reverting."; sudo cp -a "${main}.major.bak" "$main"
    return 1
  fi
  return 0
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
  if is_lab_cscmu_machine; then
    echo "    [skip] cscmu lab machine: Docker is intentionally not installed."
    return 0
  fi
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
  if id -nG "$acct" | tr ' ' '\n' | grep -Eq '^(sudo|admin|wheel|docker|lxd)$'; then
    echo "    [FAIL] $acct has privileged supplementary group(s): $(id -nG "$acct")"
    VFAIL=$((VFAIL+1))
  else echo "    [ OK ] no privileged supplementary groups"; fi
  if sudo grep -q 'major-room-saver-text' "$home/.xscreensaver" 2>/dev/null; then
    echo "    [ OK ] IP screensaver (phosphor + online-only IP)"
  else echo "    [FAIL] IP screensaver missing"; VFAIL=$((VFAIL+1)); fi
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
  if is_lab_cscmu_machine; then
    echo "  [skip] Skipping Docker verification on cscmu lab machine"
    echo "  [skip] Skipping lazydocker verification on cscmu lab machine"
  else
    vopt  "docker"                    docker --version
    vopt  "lazydocker"                lazydocker --version
  fi
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
  if id student &>/dev/null; then
    echo "  [FAIL] legacy student account still exists"
    VFAIL=$((VFAIL+1))
  else echo "  [ OK ] legacy student account absent"; fi
  if grep -hE '^autologin-user=' /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.d/lightdm.conf 2>/dev/null \
      | grep -qv "^autologin-user=${STUDENT_ACCOUNT}$"; then
    echo "  [FAIL] LightDM autologin is not consistently ${STUDENT_ACCOUNT}"
    VFAIL=$((VFAIL+1))
  else echo "  [ OK ] LightDM autologin -> ${STUDENT_ACCOUNT}"; fi
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
step "Restricted student policy"  do_student_policy
step "System update"              do_system_update
step "Basic tools"                do_basic_tools
step "Programming fonts"          do_fonts
step "uv (Python pkg mgr)"        do_uv
step "Dot files (ubuntu_home)"    install_all_dotfiles
step "ntfy callback mechanism"    do_ntfy_report
step "Python (numpy/pandas)"      do_python
step "Sublime Text"               do_sublime
step "Desktop apps (Brave/WezTerm)" do_xfce_apps
step "XFCE theme (Numix + dark bg)" do_xfce_theme
step "XFCE panel"                 do_xfce_panel
step "Student autologin"          do_enable_student_autologin
step "IP screensaver (phosphor)"  do_ip_screensaver
step "iMac function keys"         do_imac_fnkeys
step "Terminal F-keys (byobu)"    do_terminal_accels
step "Thai keyboard layout"       do_keyboard_thai
step "Panel language indicator"   do_panel_language_indicator
step "ulauncher (Ctrl+Space)"     do_ulauncher
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
step "Veriton slow boot services" do_disable_veriton_slow_boot_services
step "GitHub CLI"                 do_gh
step "Ruby"                       do_ruby
step "SWI-Prolog"                 do_prolog
step "Racket"                     do_racket
step "Restrict SSH to sudoer"     do_ssh_restrict

verify_install
exit $?

# ============================================================
# Profile Synchronization (ensure all boxes identical)
# ============================================================
# Runs after all setup to ensure csmajor profile is consistent
sync_csmajor_profile() {
  echo "    Skipping profile sync (manual step for maintenance)"
  return 0
}
