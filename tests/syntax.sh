#!/usr/bin/env bash
# Compiles every .lua file in the repo (outside .git) with luac5.1 -p; non-zero exit on a syntax error.
cd "$(dirname "$0")/.." || exit 1
if command -v luac5.1 >/dev/null 2>&1; then
    LUAC=luac5.1
else
    LUAC="$HOME/.local/opt/lua51/root/usr/bin/luac5.1"
    export LD_LIBRARY_PATH="$HOME/.local/opt/lua51/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
status=0
while IFS= read -r f; do
    "$LUAC" -p "$f" || { echo "syntax error: $f"; status=1; }
done < <(find . -name .git -prune -o -name '*.lua' -print | sort)
exit $status
