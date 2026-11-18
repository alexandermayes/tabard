-- The member card is built with secure buttons, which the game blocks in combat. UI.lua is not part of the
-- harness load, so it is loaded here by hand; the main window is stubbed (it cannot be built offline).
local W = require("wow")
local function count(pattern)
    local n = 0
    for _, line in ipairs(W.chat) do if string.find(line, pattern, 1, true) then n = n + 1 end end
    return n
end
local function withUI()
    local GL = W.load()
    W.setRoster({ { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" } })
    W.scan(GL)
    assert(loadfile("UI.lua"))("Tabard", GL)
    GL.ToggleWindow = function() return true end
    W.clearChat()
    return GL
end
test("asking for the card in combat waits for the end of combat", function()
    local GL = withUI()
    local fighting = true
    _G.InCombatLockdown = function() return fighting end
    GL:OpenMember("Ooh Woo")
    GL:OpenMember("Ooh Woo")
    eq(_G.TabardUIMemberFrame, nil, "not built in combat")
    eq(count("the member card opens after combat"), 1, "told once")
    fighting = false
    W.fire("PLAYER_REGEN_ENABLED")
    ok(_G.TabardUIMemberFrame ~= nil, "built after combat")
    local before = #W.chat
    W.fire("PLAYER_REGEN_ENABLED")   -- the watcher let go after the first one
    eq(#W.chat, before, "nothing more happens on the next combat end")
end)
test("out of combat the card is built at once", function()
    local GL = withUI()
    _G.InCombatLockdown = function() return false end
    GL:OpenMember("Ooh Woo")
    ok(_G.TabardUIMemberFrame ~= nil, "built")
    eq(count("opens after combat"), 0, "no combat line")
end)
