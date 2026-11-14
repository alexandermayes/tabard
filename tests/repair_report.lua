-- Local, read-only tool: prints what GL:RepairLedger would do to each guild in a saved Tabard.lua, working on
-- deep copies. Usage (from the repo root): lua5.1 tests/repair_report.lua <path to SavedVariables/Tabard.lua>
-- It never writes a file.
package.path = "tests/?.lua;" .. package.path
local path = arg and arg[1]
if not path then io.stderr:write("usage: lua5.1 tests/repair_report.lua <SavedVariables/Tabard.lua>\n") os.exit(1) end
local W = require("wow")
local GL = W.load()
TabardDB = nil
local chunk, err = loadfile(path)
if not chunk then io.stderr:write("cannot read " .. tostring(err) .. "\n") os.exit(1) end
chunk()
local db = TabardDB
if type(db) ~= "table" or type(db.guilds) ~= "table" then io.stderr:write("no guilds in that file\n") os.exit(1) end
local function copy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local c = {} seen[v] = c
    for k, x in pairs(v) do c[copy(k, seen)] = copy(x, seen) end
    return c
end
GL.db = copy(db)
GL.settings = GL.db.settings or GL.settings or {}
GL.Backup = function() return true end   -- the copy is thrown away; no backup needed
local names = {}
for key in pairs(GL.db.guilds) do names[#names + 1] = key end
table.sort(names)
for _, key in ipairs(names) do
    local guild = GL.db.guilds[key]
    guild.repaired = nil
    local r = GL:RepairLedger(guild)
    print(string.format("%s: %d duplicates, %d former, %d joins, %d invites", key, r.duplicates, r.former, r.joins, r.invites))
end
