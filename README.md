# CS111: Fundamentals of Programming Development Environment Setup

## Table of Contents

- [Course Coverage](#course-coverage)
- [Platform Guides](#platform-guides)
  - [Windows + WSL](#windows--wsl)
  - [Ubuntu 24.04](#ubuntu-2404)
  - [macOS](#macos)
- [Browser-based Options](#browser-based-options)
- [Class-Specific Instructions](#class-specific-instructions)

## Course Coverage

| Level | Content | Platform |
|-------|---------|----------|
| **100-level** (CS111/CS115) | Python, Haskell | Windows + WSL, macOS, Ubuntu, or **[GitHub Codespaces](#browser-based-options)** |
| **200-level** (CS203/CS212/CS252) | C/C++, Go, NodeJS, Docker | **macOS or Ubuntu only** |

## Platform Guides

Choose your platform below:

### [Windows + WSL](WINDOWS.md)

**For CS111 (Python) and CS115 (Haskell) only.**

Complete setup for Windows using Sublime Text with WSL (Ubuntu 24.04) backend.

**Covers:**

- Windows/WSL installation and configuration
- Sublime Text with WSL integration (mypy via WSL, Terminus)
- Python and Haskell setup

### [Ubuntu 24.04](UBUNTU.md)

Native Ubuntu setup (dual-boot or native Linux). Supports all courses.

**Covers:**

- System update and basic tools
- All programming languages (Python, Haskell, C/C++, Go, NodeJS)
- Docker, fzf, GitHub CLI
- Sublime Text and VSCode

### [macOS](MACOS.md)

Setup for macOS users. Supports all courses.

**Covers:**

- Python 3.12 and Haskell setup
- All programming languages (C/C++, Go, NodeJS)
- Sublime Text with mypy and Terminus

---

## Browser-based Options

> **Important:** Avoid using AI-assisted coding features. Complete exercises on your own to build foundational skills.

If you cannot install local tools:

1. **GitHub Codespaces (CS111 - Fundamentals of Programming Template)** - [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&repo=kittipitch/26cs111codespaces)
   - [Log in with your GitHub account](https://github.com/login).
   - Wait for the environment to build (includes Python 3.12, **Microsoft Python**, and **mypy**).
   - The environment is pre-configured for static type checking.
   - Use the built-in VS Code editor in your browser.
   - **To resume work:** Go to [github.com/codespaces](https://github.com/codespaces) to open your existing one.
   - **Note:** Free accounts get 60 core-hours per month. For more hours, apply for the [GitHub Student Developer Pack](https://education.github.com/pack).
2. **GitHub Codespaces (CS115 - Principles of Functional Programming)** - [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&repo=kittipitch/26cs115codespaces)
   - Select **"Manually via PATH"** when prompted, as shown below.
   <img src="images/nix/img60_nix_haskell_codespace_prompt.png" alt="Haskell Codespace Prompt" width="600">
3. **Haskell Playground** - <https://play.haskell.org/> - Quick Haskell testing in browser

---

## Class-Specific Instructions

| Course | Content | Guide |
|--------|---------|-------|
| CS111 | Python | **[GitHub Codespaces (CS111 Template)](#browser-based-options)**, [WINDOWS.md](WINDOWS.md#basic-tools), [UBUNTU.md](UBUNTU.md#python), [MACOS.md](MACOS.md#python-312) |
| CS115 | Haskell | **[GitHub Codespaces (CS115 Template)](#browser-based-options)**, [WINDOWS.md](WINDOWS.md#haskell-setup), [UBUNTU.md](UBUNTU.md#haskell), [MACOS.md](MACOS.md#haskell) |
| CS203 | Go, Docker | [UBUNTU.md](UBUNTU.md#nodejs--go), [MACOS.md](MACOS.md#nodejs--go) |
| CS212 | NodeJS, Bun, Docker | [UBUNTU.md](UBUNTU.md#nodejs--go), [MACOS.md](MACOS.md#nodejs--go) |
| CS252 | C/C++ | [UBUNTU.md](UBUNTU.md#cc), [MACOS.md](MACOS.md#cc) |
