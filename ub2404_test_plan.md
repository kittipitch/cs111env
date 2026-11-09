
### 2026-11-09 CMS-doc Haskell section: tested on a clean machine

Ready_base snapshot restored (no ghc/gcc/make/curl), then the languages doc's Haskell
script executed verbatim except noted. Result: ghc 9.6.7, cabal 3.16.1.0, runghc
compiles Hello World, Part 5 prints "Verification Success: HUnit is globally
available." Four doc fixes applied and verified via Docs API read-back (tables
descended — export cache lagged twice):
1. prereq line `sudo apt install -y curl libgmp-dev libffi-dev libncurses-dev` before
   Part 1 (clean 24.04 has none of these; CMS-install doc covers build-essential +
   pkg-config only)
2. `cabal 3.16.1[1].0` footnote artifact → `3.16.1.0`
3. `/usr/localcheck /bin/ghc` typo → `/usr/local/bin/ghc`
4. `sudo -E cabal update` before Part 4 (root cabal has no Hackage index; docs UI
   find&replace cannot insert newlines — final edits via Docs API replaceAllText,
   which DOES insert them).
user/lab scripts need NO change: both already install build-essential/curl/xz +
libffi/gmp/ncurses before their Haskell steps; xfce room shares the lab script.
Traps hit: snapshot restore resets VM clock (apt "Release file not valid yet" — set
date from host epoch); sudo credentials don't survive into nohup sessions (silent
sudo failures — run such scripts under `sudo -S env HOME=<user> bash`).
