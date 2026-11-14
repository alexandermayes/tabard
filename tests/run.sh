#!/usr/bin/env bash
# Runs every tests/test_*.lua offline against the WoW API stub. Exits non-zero on any failure.
cd "$(dirname "$0")/.." || exit 1
if command -v lua5.1 >/dev/null 2>&1; then
    LUA=lua5.1
else
    LUA="$HOME/.local/opt/lua51/root/usr/bin/lua5.1"
    export LD_LIBRARY_PATH="$HOME/.local/opt/lua51/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
exec "$LUA" tests/runner.lua "$@"
