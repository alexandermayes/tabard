# Offline tests

Runs Tabard's logic files (everything in `Tabard.toc` except `Libs\*` and `UI.lua`) against a stub of the WoW API, using plain Lua 5.1.

## Getting Lua 5.1 (no system install)

```
mkdir -p ~/.local/opt/lua51 && cd ~/.local/opt/lua51
apt-get download lua5.1 liblua5.1-0
dpkg -x lua5.1_*.deb root && dpkg -x liblua5.1-0_*.deb root
```

The scripts use `lua5.1` / `luac5.1` from PATH if present, otherwise `~/.local/opt/lua51/root/usr/bin/` with the matching `LD_LIBRARY_PATH`.

## Running

```
tests/run.sh        # every tests/test_*.lua; prints failures and "N passed, M failed"
tests/syntax.sh     # luac5.1 -p on every .lua file in the repo
```

Tests use `test(name, fn)`, `eq(actual, expected, label)` and `ok(cond, label)`, and `local W = require("wow")` for the stub (`W.load`, `W.setRoster`, `W.setGameLog`, `W.scan`, `W.advance`, `W.fire`, `W.runTimers`, `W.chat`, `W.events`, ...). See `tests/wow.lua`.
