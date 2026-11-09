# Windows (Native, no WSL) Setup Guide

> **Who this guide is for:** the Python-only courses **204101 and 204217**.
> **CS111, CS115, CS255 and CS212 must not use this guide** — use
> [Ubuntu](UBUNTU.md) or [macOS](MACOS.md) instead.

This guide sets up a Python environment (Python 3.12, mypy, Sublime Text or VS Code)
directly on Windows 10/11 — **no WSL**.

> **Note:** If you cannot install local tools, use the **[GitHub Codespaces (CS111 Fundamentals of Programming Template)](https://github.com/codespaces/new?hide_repo_select=true&repo=kittipitch/26cs111codespaces)**.

> **Prefer WSL?** The [Windows + WSL guide](WINDOWS.md) runs the tools inside Ubuntu instead.
> This guide is for students who cannot or do not want to use WSL.

All commands below are typed in **PowerShell** (not as Administrator unless the step says so).

## Table of Contents

- [Before You Start](#before-you-start) (winget, coreutils)
- [Basic Tools](#basic-tools)
- [Python](#python)
- [Sublime Text](#sublime-text)
- [VS Code (alternative editor)](#vs-code-alternative-editor)
- [Troubleshooting](#troubleshooting)

---

## Before You Start

### 1. Change language input hotkey

Change to **Win + Space bar** (or anything else). **DO NOT use 'Grave Accent'** to switch languages —
**Alt + `** is used later to open the terminal inside Sublime Text.

### 2. Allow PowerShell scripts

Windows blocks PowerShell scripts by default. Some installers and tools used in this guide
are PowerShell scripts, so they fail with *"running scripts is disabled on this system"* until you run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Answer `Y` if asked.

### 3. winget — the Windows package manager (instead of `apt` / `brew`)

On Windows, **`winget`** does the job of `apt` (Ubuntu) and `brew` (macOS): it installs, upgrades,
and removes programs from the command line. Every install in this guide uses it.

#### 3.1 Check that winget is installed

`winget` is part of **App Installer**, which ships with Windows 11 and Windows 10 (1809 or later):

```powershell
winget --version
```

If you get *"winget is not recognized"*:

1. Ask Windows to register it (common right after a first login):

   ```powershell
   Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
   ```

2. Still missing? Install or update **App Installer** from the Microsoft Store:
   <https://apps.microsoft.com/detail/9nblggh4nns1>

Open a new PowerShell window and run `winget --version` again.

#### 3.2 apt / brew → winget cheat sheet

| Task | Ubuntu (`apt`) | macOS (`brew`) | Windows (`winget`) |
|------|----------------|----------------|--------------------|
| Find a package | `apt search fzf` | `brew search fzf` | `winget search fzf` |
| Install | `sudo apt install fzf` | `brew install fzf` | `winget install -e --id junegunn.fzf` |
| Install a specific version | `sudo apt install pkg=1.2` | `brew install pkg@1.2` | `winget install -e --id Pkg.Id --version 1.2` |
| List installed | `apt list --installed` | `brew list` | `winget list` |
| Upgrade everything | `sudo apt upgrade` | `brew upgrade` | `winget upgrade --all` |
| Uninstall | `sudo apt remove fzf` | `brew uninstall fzf` | `winget uninstall -e --id junegunn.fzf` |
| Hold a version | `sudo apt-mark hold pkg` | `brew pin pkg` | `winget pin add --id Pkg.Id --version 1.2.*` |

- Always install by **`--id`** with **`-e`** (exact match), as this guide does — names can match several packages.
- No `sudo`: winget asks for administrator rights (a Windows prompt) only when an installer needs them.
- The first `winget` command asks you to accept the source agreement — answer `Y`.

> [!IMPORTANT]
> **Open a NEW PowerShell window after every `winget install`.** A window that was already open
> does not see the new program on its `PATH`, so the version checks will say "not recognized".

#### 3.3 Linux commands on Windows (coreutils) and a terminal editor

PowerShell has its own commands (`Get-ChildItem`, ...). To get the same `ls`, `cat`, `cp`, `mv`,
`rm`, `head`, `tail`, `wc`, `sort`, ... that you use on Ubuntu and macOS, install **uutils
coreutils** (the GNU coreutils rewritten in Rust, built for Windows). Also install **Microsoft
Edit** (`edit`), a small terminal text editor from Microsoft, like `nano` (newer Windows 11
builds already include it; installing it again is harmless):

```powershell
winget install -e --id uutils.coreutils
winget install -e --id Microsoft.Edit
```

PowerShell already has built-in *aliases* named `ls`, `cat`, `cp`, ... that would hide the real
commands. Remove them in your PowerShell profile (runs every time PowerShell starts). The second
line makes PowerShell pass text to these commands as plain UTF-8 — without it, an invisible
marker is added to the first line and `sort`, `grep`, ... give wrong results:

```powershell
if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
Add-Content $PROFILE @'
foreach ($a in 'cat','cp','echo','ls','mv','pwd','rm','rmdir','sleep','sort','tee') { Remove-Item "Alias:$a" -Force -ErrorAction SilentlyContinue }
$OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
'@
```

Open a new PowerShell window and check:

```powershell
ls --version      # Should show: ls (uutils coreutils) ...
ls -la
"b","a" | sort    # Should print a, then b
edit --version
```

> **Note:** after this, `ls`/`rm`/`cp` take Linux-style options (`rm -rf dir`, `ls -la`),
> not PowerShell ones (`-Recurse`, `-Force`). Use the full PowerShell names
> (`Get-ChildItem`, `Remove-Item`) when you need the PowerShell behaviour.

---

## Basic Tools

### 4. Install Windows Terminal

Already installed on Windows 11. On Windows 10:

```powershell
winget install -e --id Microsoft.WindowsTerminal
```

### 5. Install Git

```powershell
winget install -e --id Git.Git
```

Open a new window, then set your identity:

```powershell
git --version
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### 6. Install KDiff3

KDiff3 helps you compare files and fix merge conflicts.

```powershell
winget install -e --id KDE.KDiff3
```

winget installs it for your user only, in `%LOCALAPPDATA%\Programs\KDiff3\bin`. Add that folder
to your Path:

```powershell
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ";$env:LOCALAPPDATA\Programs\KDiff3\bin", 'User')
```

Open a new window and check that it is found: `Get-Command kdiff3`

---

## Python

### 7. Install Python 3.12

**Remove any other Python installations first** (Settings → Apps → search "Python").

```powershell
winget install -e --id Python.Python.3.12 --scope user
```

Open a new window and check:

```powershell
python --version   # Should show Python 3.12.x
```

> If `python` opens the Microsoft Store instead, see [Troubleshooting](#python-opens-the-microsoft-store).

### 8. Install mypy and uv

`mypy` checks Python types. `uv` is a fast Python package manager.

```powershell
python -m pip install mypy
winget install -e --id astral-sh.uv
```

Open a new window and check:

```powershell
mypy --version
uv --version
```

Test Python — create `hello.py`:

```python
print("Hello world!!")
```

Run:

```powershell
python hello.py
```

---

## Sublime Text

### 9. Install Sublime Text 4

```powershell
winget install -e --id SublimeHQ.SublimeText.4
```

Add Sublime Text to the Windows Path so `subl` works in the terminal:

1. Windows Key + R
2. Type "sysdm.cpl" and press Enter
3. Click Advanced → Environment Variables

<img src="images/windows/img41_win_adv_env.png" alt="Adv Env" width="600">

4. Click on "Path" then Edit

<img src="images/windows/img36_win_path_edit.png" alt="Path Edit" width="600">

5. Click New

<img src="images/windows/img11_win_new_path.png" alt="New" width="600">

6. Add path: `C:\Program Files\Sublime Text`

<img src="images/windows/img54_win_add_path.png" alt="Add Path" width="600">

### 10. Configure Sublime Text for Python

Make Sublime Text use 4 spaces for Python:

1. Create a `hello.py` file and save it
2. Go to **Preferences → Settings - Syntax Specific**
3. Add:

   ```json
   {
      "tab_size": 4,
      "translate_tabs_to_spaces": true,
   }
   ```

   <img src="images/common/img20_common_sublime_syntax_menu.jpg" alt="JSON 1" width="600">

4. Save (Ctrl+S)

### 11. Install Package Control

- **Ctrl + Shift + P**
- Type "Install Package Control" and hit Enter

If packages are missing later, add the channel:

- **Ctrl + Shift + P** → "Package Control: Add Channel"
- Paste: `https://packages.sublimetext.io/channel.json`

### 12. Installing and Configuring mypy on Sublime Text

#### 12.1 Install SublimeLinter and SublimeLinter-mypy

1. **Ctrl + Shift + P** → "Package Control: Install Package"

   <img src="images/common/img05_common_sublime_install_package_control.png" alt="Sublime Linter 1" width="600">

2. Type "SublimeLinter" and hit Enter.

   <img src="images/common/img32_common_sublime_install_linter.png" alt="Sublime Linter 3" width="600">

3. **Ctrl + Shift + P** → "Package Control: Install Package"
4. Type "SublimeLinter-mypy" and hit Enter.

   <img src="images/common/img33_common_sublime_install_linter_mypy.png" alt="Sublime Linter 4" width="600">

#### 12.2 Configure SublimeLinter

Go to **Preferences → Package Settings → SublimeLinter → Settings** and add to the right panel:

<img src="images/common/img30_common_sublime_linter_menu.png" alt="Sublime Linter Menu" width="600">

```json
{
  "linters": {
    "mypy": {
      "disable": false,
      "executable": ["mypy"],
      "args": ["--ignore-missing-imports"],
      "python": "3.12"
    }
  }
}
```

No bridge script is needed — `mypy` runs natively.

#### 12.3 Verify it works

1. Create a `test_mypy.py` file:

   ```python
   def hello() -> str:
       return 10
   ```

2. **Save the file.** You should see a red dot or error underline.
3. Hover over it: **"Incompatible return value type (got 'int', expected 'str')"**.

   <img src="images/windows/img62_win_mypy_verify.png" alt="mypy Verify" width="600">

4. Change `return 10` to `return "hello"` and save — the error should disappear.

> No error shown? Restart Sublime Text (it only reads `PATH` when it starts).

### 13. Installing Terminus on Sublime Text

Terminus adds a terminal inside Sublime Text.

#### 13.1 Install Terminus

- **Ctrl + Shift + P** → "Package Control: Install Package" → "Terminus"
- **Ctrl + Shift + P** → "**Package Control: Satisfy Dependencies**"

<img src="images/common/img10_common_sublime_install_terminus.png" alt="Terminus" width="600">

#### 13.2 Configure Terminus

Go to **Preferences → Package Settings → Terminus → Settings** and add to the right panel:

<img src="images/common/img55_common_sublime_package_settings_menu.png" alt="Terminus Config 1" width="600">

```json
{
    "default_config": {
        "linux": "Bash",
        "osx": "Zsh",
        "windows": "PowerShell"
    }
}
```

#### 13.3 Set keyboard shortcuts

Go to **Preferences → Key Bindings** and add to the right panel:

<img src="images/common/img53_common_sublime_terminus_keybindings.png" alt="Terminus Keybindings" width="600">

```json
[
  {
    "keys": ["alt+`"],
    "command": "toggle_terminus_panel",
    "args": {
      "config_name": null,
      "cwd": "${file_path:${folder}}"
    }
  }
]
```

Restart Sublime Text. **Alt + `** now opens PowerShell inside Sublime Text.

---
## VS Code (alternative editor)

### 14. Install VS Code

Prefer VS Code over Sublime Text? Install it with winget and add the Python extension
(open VS Code → Extensions → search **Python** → install the Microsoft one):

```powershell
winget install -e --id Microsoft.VisualStudioCode
```

---

### 15. Verify everything

Open a new PowerShell window and run:

```powershell
git --version; python --version; mypy --version; uv --version
ls --version; edit --version
```

Every line should print a version. A "not recognized" error means that step's install did not
finish, or the window was opened before the install — open a new one and try again.

## Troubleshooting

### Python opens the Microsoft Store

Settings → Apps → Advanced app settings → **App execution aliases** → turn **off**
`python.exe` and `python3.exe`. Open a new window.

### A command is "not recognized" right after installing it

Open a **new** PowerShell window. If Sublime Text cannot find a tool (mypy), restart
Sublime Text — or sign out and back in.

### Exit Editors (Misc)

If you are stuck in a terminal editor:

- **edit** (Microsoft Edit): Press **Ctrl + S** to save, **Ctrl + Q** to exit.
- **nano**: Press **Ctrl + X**, then **Y**, then **Enter** to save and exit.
- **vim**: Press **Esc**, then type `:q!` and press **Enter** to exit without saving.

---

*For issues or questions, refer to your course-specific instructions or wiki.*
