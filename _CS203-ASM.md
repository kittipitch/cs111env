# CS203 Assembly Setup Guide

> **Note:** This guide is for CS203 Assembly. For CS231 ASM, see `wiki-cs231/en`.

## Course Overview

CS203 covers low-level assembly programming. This guide is for students who need to set up an assembly development environment.

---

## Platform Requirements

**For CS203 Assembly, use one of:**
- **Ubuntu 24.04** (native or dual-boot) - **Recommended**
- **macOS** - with some limitations
- **Windows + WSL** - Not recommended for assembly (possible but may have issues)

---

## Ubuntu Setup (Recommended)

### 1. Install NASM (Netwide Assembler)

```bash
sudo apt update
sudo apt install nasm
```

Verify installation:

```bash
nasm --version
```

### 2. Install GCC (for linking)

```bash
sudo apt install build-essential
```

### 3. Install GDB (debugger)

```bash
sudo apt install gdb
```

### 4. Create your first assembly program

Create `hello.asm`:

```nasm
section .data
    msg db "Hello, Assembly!", 0xA
    len equ $ - msg

section .text
    global _start

_start:
    ; Write to stdout
    mov eax, 4          ; syscall number for write
    mov ebx, 1          ; file descriptor (stdout)
    mov ecx, msg        ; message to write
    mov edx, len        ; message length
    int 0x80            ; call kernel

    ; Exit
    mov eax, 1          ; syscall number for exit
    mov ebx, 0          ; exit code
    int 0x80            ; call kernel
```

### 5. Assemble, link, and run

```bash
# Assemble
nasm -f elf32 hello.asm -o hello.o

# Link
ld -m elf_i386 hello.o -o hello

# Run
./hello
```

### 6. Debug with GDB

```bash
# Start GDB
gdb ./hello

# Common GDB commands
(gdb) break _start     # Set breakpoint at _start
(gdb) run              # Run program
(gdb) stepi            # Step instruction
(gdb) info registers   # Show registers
(gdb) x/10x $eip       # Examine memory at EIP
(gdb) quit             # Quit GDB
```

---

## macOS Setup

macOS can run assembly but uses different tools and formats.

### 1. Install NASM

```bash
brew install nasm
```

### 2. macOS-specific hello.asm

macOS uses Mach-O format, not ELF:

```nasm
section .data
    msg db "Hello, Assembly!", 0xA
    len equ $ - msg

section .text
    global start

start:
    ; Write to stdout
    mov eax, 4          ; syscall number for write (may differ)
    mov ebx, 1          ; file descriptor (stdout)
    mov ecx, msg        ; message to write
    mov edx, len        ; message length
    int 0x80            ; system call

    ; Exit
    mov eax, 1          ; syscall number for exit
    mov ebx, 0          ; exit code
    int 0x80            ; system call
```

### 3. Assemble and run

```bash
# Assemble
nasm -f macho hello.asm -o hello.o

# Link
ld hello.o -o hello

# Run
./hello
```

> **Note:** macOS system calls differ from Linux. Your course may use Linux-specific syscalls. Consider using Ubuntu for consistency with course materials.

---

## Common Issues

### 64-bit vs 32-bit

Most assembly courses start with 32-bit x86. On a 64-bit system:

```bash
# Assemble as 32-bit
nasm -f elf32 hello.asm -o hello.o

# Link as 32-bit
ld -m elf_i386 hello.o -o hello
```

If you get "invalid machine" errors, install 32-bit libraries:

```bash
sudo apt install gcc-multilib
```

### "Operation not permitted" on macOS

macOS has System Integrity Protection (SIP) that may interfere with low-level operations. This is one reason **Ubuntu is recommended** for assembly.

---

## Editor Setup

### Sublime Text Assembly Syntax

1. Install Package Control
2. Install **Assembly** package for syntax highlighting

### VSCode Assembly Extension

Install **x86 and x86_64 Assembly** extension from the marketplace.

---

## Resources

- [NASM Documentation](https://www.nasm.us/docs.php)
- [x86 Assembly Reference](https://www.felixcloutier.com/x86/)
- [GDB Documentation](https://www.gnu.org/software/gdb/documentation/)

---

*For course-specific assignments and requirements, refer to your CS203 course materials.*
