#!/usr/bin/env bash
# Sourced by run_tests.sh and session_start.sh. Prints a usable interpreter/binary path, or nothing.

find_python() {
  local c
  # On Windows `python3` is often the Microsoft Store alias stub: it exists but cannot run code.
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys" >/dev/null 2>&1; then command -v "$c"; return; fi
  done
  if command -v py >/dev/null 2>&1 && py -3 -c "import sys" >/dev/null 2>&1; then echo "py"; fi
}

find_godot() {
  local c
  for c in godot /c/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return; fi
  done
}

# SAVE22: point Godot's user:// at a fresh per-run directory so tests never read or write the PC's real saves
# (a checkpoint from an older content revision fails unrelated tests with CONTENT_MISMATCH). Godot reads APPDATA
# on Windows and XDG_DATA_HOME on Linux at startup; tests/run_tests.gd refuses to run unless user:// lands inside
# LBO_TEST_USER_ROOT. Exports the three variables in the calling shell; the caller removes the directory.
isolate_godot_user_dir() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/lbo_test_user.XXXXXX")" || return 1
  # Git Bash: hand Godot a Windows path (C:/Users/...), which it also prints back from OS.get_user_data_dir().
  if command -v cygpath >/dev/null 2>&1; then root="$(cygpath -m "$root")"; fi
  export LBO_TEST_USER_ROOT="$root" APPDATA="$root" XDG_DATA_HOME="$root"
}
