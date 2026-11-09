#!/usr/bin/env bash
# macOS setup for CS courses. Follows MACOS.md.
#
# Runs on Apple's stock bash 3.2, so students do not need to upgrade bash first. Keep it
# that way: no declare -A, mapfile, ${x,,}, &>> or negative array indices. Avoid sed -i too,
# because BSD and GNU sed disagree on it. Everything the shell needs goes in ~/.zshrc,
# because zsh is the login shell on a Mac and never reads ~/.bash_profile.
#
# RESILIENT BY DESIGN: no `set -e`. A failing step never stops the run, every step is safe
# to re-run, and the final checks open a new zsh, so they see what a student's terminal
# will see. The exit code is non-zero if a critical check fails.
#
# What is already on the machine is left alone: installed packages are not upgraded, and
# existing dot files are not overwritten.
#
#   MAC_DRY_RUN=1            list the steps, change nothing
#   MAC_VERIFY_ONLY=1        run the checks only, change nothing
#   MAC_SKIP_DOCKER_ENGINE=1 skip starting the Docker engine and its checks (CI runners)

GHC_VER="9.6.7"
CABAL_VER="3.16.1.0"
STACK_VER="3.7.1"
HLS_VER="2.14.0.0"
HUNIT_VER="1.6.2.0"
ORMOLU_VER="0.7.2.0"
ORMOLU_RESOLVER="lts-22.44"
BUN_VER="1.3.14"
UBUNTU_HOME_REPO="https://github.com/kittipitch/ubuntu_home.git"
MAC_APPS="${MAC_APPS:-/Applications}"
export HOMEBREW_NO_INSTALL_UPGRADE=1  # brew install must not upgrade what is already there

STEP_RESULTS=()
VFAIL=0
VWARN=0

step() {
  local label="$1"; shift
  echo ""
  echo "==> ${label}..."
  [[ -n "${MAC_DRY_RUN:-}" ]] && return 0
  if "$@"; then
    STEP_RESULTS+=("PASS|${label}")
  else
    local rc=$?
    STEP_RESULTS+=("FAIL|${label} (rc=${rc})")
    echo "    [WARN] '${label}' failed (rc=${rc}); continuing."
  fi
}

# ------------------------------------------------------------
# Installers
# ------------------------------------------------------------
formula() {
  brew list --formula "$1" >/dev/null 2>&1 && return 0
  brew install "$1"
}

# Try every package, so one bad package does not stop the rest, then report.
formulas() {
  local p rc=0
  for p in "$@"; do
    formula "$p" || { echo "    [WARN] brew could not install $p"; rc=1; }
  done
  return "$rc"
}

# cask <token> [App.app]: an app installed by hand makes `brew install --cask` fail.
cask() {
  [[ -n "${2:-}" && -d "$MAC_APPS/$2" ]] && { echo "    $2 already in $MAC_APPS."; return 0; }
  brew list --cask "$1" >/dev/null 2>&1 && return 0
  brew install --cask "$1"
}

# ------------------------------------------------------------
# Shell setup
# ------------------------------------------------------------
do_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    local b
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [[ -x "$b" ]] && eval "$("$b" shellenv)"
    done
  fi
  if ! command -v brew >/dev/null 2>&1; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [[ -x "$b" ]] && eval "$("$b" shellenv)"
    done
  fi
  command -v brew >/dev/null 2>&1
}

# The lines every new terminal needs. brew's prefix differs on Apple Silicon and Intel.
zshrc_block_text() {
  local prefix gccbin
  prefix="$(brew --prefix)"
  echo "eval \"\$($prefix/bin/brew shellenv)\""
  echo "export PATH=\"$prefix/opt/python@3.12/libexec/bin:\$PATH\""
  echo "export PATH=\"$prefix/opt/openjdk@21/bin:\$PATH\""
  echo "export PATH=\"$prefix/opt/node@24/bin:\$PATH\""
  echo 'export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"'
  echo '[ -f "$HOME/.ghcup/env" ] && . "$HOME/.ghcup/env"'
  # Aliases, not symlinks: GHC needs plain `gcc` to stay Apple's clang, and aliases only
  # apply where a student types.
  gccbin="$(ls "$prefix/opt/gcc/bin" 2>/dev/null | grep -E '^gcc-[0-9]+$' | head -1)"
  if [[ -n "$gccbin" ]]; then
    echo "alias gcc=$gccbin"
    echo "alias g++=g++-${gccbin#gcc-}"
  fi
}

# Replace our marked block, keep everything else. `cat >` writes through a symlinked ~/.zshrc.
write_zshrc_block() {
  local rc="$HOME/.zshrc" tmp
  tmp="$(mktemp)"
  if [[ -e "$rc" ]]; then
    ls -a "$HOME" | grep -q '^\.zshrc\.bak_' || cp -a "$rc" "$rc.bak_$(date +%s)"
    awk '/^# >>> cs111env >>>/{skip=1; next} /^# <<< cs111env <<</{skip=0; next} !skip' "$rc" > "$tmp"
  fi
  {
    echo "# >>> cs111env >>> (managed by macos_user_install.sh, edits here are replaced)"
    zshrc_block_text
    echo "# <<< cs111env <<<"
  } >> "$tmp"
  cat "$tmp" > "$rc"
  rm -f "$tmp"
}

# Load the same lines into this script, so later steps find what earlier steps installed.
load_env_now() {
  local line
  while IFS= read -r line; do
    case "$line" in alias*) ;; *) eval "$line" ;; esac
  done < <(zshrc_block_text)
  hash -r
}

do_zshrc() { write_zshrc_block && load_env_now; }

# ------------------------------------------------------------
# Tools
# ------------------------------------------------------------
# Course dot files only where the student has none. Not .bash_profile (zsh never reads it)
# and not .config (it holds only the Linux path for Sublime Text).
copy_dotfiles() {  # copy_dotfiles <repo dir>
  local f
  for f in .dircolors .gitconfig .emacs.d; do
    if [[ -e "$HOME/$f" ]]; then echo "    Keeping your $f."
    else cp -R "$1/$f" "$HOME/$f" || return 1; fi
  done
}

do_dotfiles() {
  local t rc=0
  t="$(mktemp -d)"
  git clone --depth 1 "$UBUNTU_HOME_REPO" "$t/h" && copy_dotfiles "$t/h" || rc=1
  rm -rf "$t"
  mkdir -p "$HOME/.config"
  [[ -d "$HOME/.config/tinted-shell" ]] || \
    git clone https://github.com/tinted-theming/tinted-shell.git "$HOME/.config/tinted-shell" || rc=1
  return "$rc"
}

do_fonts() { cask font-fira-code && cask font-iosevka-nerd-font; }

# Intel Macs keep brew in /usr/local, so an existing python.org install there blocks
# `brew link`. Those links are the student's, so explain the fix instead of replacing them.
do_python() {
  formula python@3.12 && return 0
  echo "    [FAIL] brew could not finish python@3.12, usually because Python from python.org"
  echo "           is already in /usr/local/bin. To replace those links with Homebrew's:"
  echo "             brew link --overwrite python@3.12"
  return 1
}

do_haskell() {
  if [[ ! -x "$HOME/.ghcup/bin/ghcup" ]]; then
    export BOOTSTRAP_HASKELL_NONINTERACTIVE=1
    export BOOTSTRAP_HASKELL_NO_UPGRADE=1
    export BOOTSTRAP_HASKELL_GHC_VERSION="$GHC_VER"
    export BOOTSTRAP_HASKELL_CABAL_VERSION="$CABAL_VER"
    export BOOTSTRAP_HASKELL_ADJUST_BASHRC=0  # ~/.zshrc block loads ~/.ghcup/env
    curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh || return 1
  fi
  . "$HOME/.ghcup/env" || return 1
  ghcup install ghc "$GHC_VER" && ghcup set ghc "$GHC_VER" || return 1
  ghcup install cabal "$CABAL_VER" && ghcup set cabal "$CABAL_VER" || return 1
  ghcup install stack "$STACK_VER" && ghcup set stack "$STACK_VER" || return 1
  ghcup install hls "$HLS_VER" && ghcup set hls "$HLS_VER" || return 1
  cabal update || return 1
  cabal install --lib "HUnit-${HUNIT_VER}" --force-reinstalls
}

do_ormolu() {
  ormolu --version 2>/dev/null | grep -qF "$ORMOLU_VER" && { echo "    ormolu ${ORMOLU_VER} already installed."; return 0; }
  stack install "ormolu-${ORMOLU_VER}" --resolver "$ORMOLU_RESOLVER"
}

# macOS ships no GNU gcc — /usr/bin/gcc is Apple's clang, which GHC expects. If an
# unversioned GNU gcc (not brew's versioned gcc-16) sits earlier on PATH, ghc fails to
# link with "unrecognized command-line option '--target'". Fix: point GHC's own settings
# back at clang. Idempotent; safe with no GHC on the machine.
do_gcc_fix() {
  local gccid settings
  gccid="$(gcc --version 2>/dev/null | head -1)"
  [[ -z "$gccid" ]] && { echo "    no gcc on PATH yet; nothing to check."; return 0; }
  [[ "$gccid" == *"Apple clang"* ]] && { echo "    plain gcc is Apple clang; nothing to fix."; return 0; }
  echo "    PATH shadows clang with: $gccid — patching GHC settings."
  . "$HOME/.ghcup/env" 2>/dev/null
  settings="$(ghc --print-libdir 2>/dev/null)/lib/settings"
  [[ -f "$settings" ]] || { echo "    [FAIL] GHC settings file not found: $settings"; return 1; }
  sed 's/, "gcc")/, "clang")/g; s/, "g++")/, "clang++")/g' "$settings" > "$settings.tmp" || return 1
  cp -a "$settings" "$settings.bak_$(date +%s)"
  cat "$settings.tmp" > "$settings" && rm -f "$settings.tmp"
  echo "    GHC now links with clang (backup saved beside the settings file)."
}

do_bun() {
  [[ "$(bun --version 2>/dev/null)" == "$BUN_VER" ]] && { echo "    bun ${BUN_VER} already installed."; return 0; }
  curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VER}"
}

# One Docker daemon only: OrbStack. This is the student's own laptop, so report Docker
# Desktop and let them remove it; its images would be lost with it.
do_orbstack() {
  if [[ -d "$MAC_APPS/Docker.app" ]]; then
    echo "    [FAIL] Docker Desktop is installed. Quit and uninstall it, then re-run this script."
    echo "           OrbStack beside it would mean two Docker daemons."
    return 1
  fi
  cask orbstack OrbStack.app || return 1
  [[ -n "${MAC_SKIP_DOCKER_ENGINE:-}" ]] && { echo "    [skip] Docker engine start"; return 0; }
  open -ga OrbStack || return 1
  echo "    Waiting for OrbStack. On the first launch, finish its setup window..."
  local i
  for i in $(seq 1 60); do
    docker info >/dev/null 2>&1 && return 0
    sleep 5
  done
  echo "    [FAIL] Docker did not answer after 5 minutes. Open OrbStack, then re-run this script."
  return 1
}

do_fzf() {
  formula fzf || return 1
  "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --update-rc --no-bash --no-fish
}

# ------------------------------------------------------------
# Verify, in a new zsh, because that is what a student gets
# ------------------------------------------------------------
in_zsh() { zsh -lic "$1" 2>&1 </dev/null; }

vcrit() {  # vcrit "label" 'shell command'
  if in_zsh "$2" >/dev/null; then echo "  [ OK ] $1"
  else echo "  [FAIL] $1"; VFAIL=$((VFAIL+1)); fi
}

vopt() {
  if in_zsh "$2" >/dev/null; then echo "  [ OK ] $1"
  else echo "  [warn] $1"; VWARN=$((VWARN+1)); fi
}

vver() {  # vver "label" "expected text" 'shell command'
  local out; out="$(in_zsh "$3")"
  if grep -qF -- "$2" <<<"$out"; then echo "  [ OK ] $1 ($2)"
  else echo "  [FAIL] $1: wanted $2, got: $(tail -1 <<<"$out" | cut -c1-70)"; VFAIL=$((VFAIL+1)); fi
}

verify_install() {
  local r t
  echo ""
  echo "============================================================"
  echo " STEP RESULTS"
  echo "============================================================"
  for r in ${STEP_RESULTS[@]+"${STEP_RESULTS[@]}"}; do printf "  %-5s  %s\n" "${r%%|*}" "${r#*|}"; done

  echo ""
  echo " VERIFICATION (CRITICAL, in a new zsh)"
  vcrit "brew"                 'brew --version'
  vver  "python3"  "Python 3.12."      'python3 --version'
  vver  "pip3"     "python 3.12"       'pip3 --version'
  vcrit "mypy"                 'mypy --version'
  vcrit "uv"                   'uv --version'
  vver  "java"     'version "21.'      'java -version'
  vver  "ghc"      "$GHC_VER"          'ghc --version'
  vver  "cabal"    "$CABAL_VER"        'cabal --version'
  vver  "stack"    "$STACK_VER"        'stack --version'
  vver  "HLS"      "$HLS_VER"          'haskell-language-server-wrapper --version'
  vver  "ormolu"   "$ORMOLU_VER"       'ormolu --version'
  vcrit "HUnit importable"     'ghc -e "import Test.HUnit"'
  # A real compile and link: this is what fails when a GNU gcc shadows Apple's clang.
  t="$(mktemp -d)"; printf 'main :: IO ()\nmain = putStrLn "ok"\n' > "$t/Hello.hs"
  vver  "ghc compiles and links" "ok"  "ghc -outputdir '$t' -o '$t/hello' '$t/Hello.hs' && '$t/hello'"
  rm -rf "$t"
  vver  "g++ alias is GNU"     "GCC"   'g++ --version'
  vver  "node"     "v24."              'node -v'
  vcrit "npm"                  'npm -v'
  vcrit "npx"                  'npx -v'
  vver  "bun"      "$BUN_VER"          'bun --version'
  vcrit "go"                   'go version'
  vcrit "subl"                 'command -v subl'
  vcrit "lazydocker"           'lazydocker --version'
  if [[ -n "${MAC_SKIP_DOCKER_ENGINE:-}" ]]; then
    echo "  [skip] Docker engine checks"
  else
    vcrit "docker hello-world"   'docker run --rm hello-world'
    vcrit "docker compose"       'docker compose version'
    if [[ -d "$MAC_APPS/Docker.app" ]]; then
      echo "  [FAIL] Docker Desktop installed beside OrbStack"; VFAIL=$((VFAIL+1))
    else echo "  [ OK ] no Docker Desktop (one daemon)"; fi
  fi

  echo ""
  echo " VERIFICATION (OPTIONAL)"
  vopt "fzf"          'command -v fzf'
  vopt "gh"           'gh --version'
  vopt "kdiff3"       "test -d '$MAC_APPS/kdiff3.app'"
  vopt "FiraCode font" 'ls ~/Library/Fonts | grep -qi fira'

  echo ""
  if [[ "$VFAIL" -eq 0 ]]; then
    echo " RESULT: SUCCESS (${VWARN} optional warning(s))"
  else
    echo " RESULT: FAILURE, ${VFAIL} critical check(s) failed (${VWARN} optional warning(s))"
    echo " If 'ghc compiles and links' failed, re-run this script (its GHC gcc shadow fix"
    echo " step patches GHC's settings), or see MACOS.md step 17."
  fi
  echo ""
  echo "Next steps:"
  echo "  1. Open a new terminal so the PATH changes apply."
  echo "  2. git config --global user.name \"Your Name\""
  echo "     git config --global user.email \"your.email@example.com\""
  echo "  3. Sublime Text packages are set up by hand: MACOS.md steps 9, 13, 14 and 16."
  [[ "$VFAIL" -eq 0 ]]
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
if [[ "$(uname)" != "Darwin" ]]; then echo "ERROR: this script is for macOS." >&2; exit 2; fi
if [[ "$(id -u)" == "0" ]]; then echo "ERROR: run as your normal user, not with sudo." >&2; exit 2; fi

if [[ -n "${MAC_VERIFY_ONLY:-}" ]]; then
  verify_install
  exit $?
fi

echo "macOS setup: resilient run (continues on errors, verifies at the end)."
echo "bash ${BASH_VERSION}"

step "Homebrew"          do_homebrew
step "Basic tools"       formulas git bash-completion tmux byobu coreutils pipx pipenv wget curl gnupg mypy bat vim neovim emacs dos2unix
step "kdiff3"            cask kdiff3 kdiff3.app
step "Dot files"         do_dotfiles
step "Fonts"             do_fonts
step "Python 3.12"       do_python
step "uv"                formula uv
step "Java 21"           formula openjdk@21
step "C/C++ (GNU gcc)"   formula gcc
step "Node 24"           formula node@24
step "Go"                formula go
step "zshrc PATH block"  do_zshrc
step "Sublime Text"      cask sublime-text "Sublime Text.app"
step "Haskell (GHC ${GHC_VER}, cabal, stack, HLS ${HLS_VER}, HUnit)" do_haskell
step "Ormolu"            do_ormolu
step "GHC gcc shadow fix" do_gcc_fix
step "Bun ${BUN_VER}"    do_bun
step "VS Code"           cask visual-studio-code "Visual Studio Code.app"
step "OrbStack (Docker)" do_orbstack
step "lazydocker"        formula jesseduffield/lazydocker/lazydocker
step "fzf"               do_fzf
step "GitHub CLI"        formula gh

[[ -n "${MAC_DRY_RUN:-}" ]] && exit 0
verify_install
