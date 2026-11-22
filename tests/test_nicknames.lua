-- A nickname belongs to the person. It is written on their main, and it used to be read from the main only, so
-- it vanished for the whole group whenever the main changed: by hand, from another officer's records, or when
-- ledgers split by a realm rename were folded and the newer one had grouped the same characters under another main.
local W = require("wow")

local function person(name, level) return { name = name, rank = "Member", rankIndex = 7, level = level or 30, class = "WARRIOR" } end
local function roster()
    local list = { { name = "Zev Zev", rank = "Officer", rankIndex = 2, level = 60, class = "MAGE" } }
    for i = 1, 10 do list[#list + 1] = person("Filler" .. string.char(96 + i)) end
    return list
end
local function start()
    local GL = W.load()
    W.setRoster(roster())
    W.scan(GL)
    local g = GL:Guild()
    return GL, g, g.members
end

test("nickname: kept when another character becomes the main", function()
    local GL, g, m = start()
    GL:LinkAlt(g, m["Fillerb"], m["Fillera"], "user")
    GL:LinkAlt(g, m["Fillerc"], m["Fillera"], "user")
    GL:SetNickname(g, m["Fillerb"], "Checky", "user")
    eq(m["Fillera"].nick, "Checky", "written on the main")
    eq(GL:Nickname(g, m["Fillerc"]), "Checky", "shown on an alt")
    W.advance(60)
    GL:SetMain(g, m["Fillerb"], "user")
    eq(GL:Nickname(g, m["Fillerb"]), "Checky", "the new main")
    eq(GL:Nickname(g, m["Fillerc"]), "Checky", "an alt")
    eq(GL:Nickname(g, m["Fillera"]), "Checky", "the old main")
end)

test("nickname: changed and cleared after the main changed", function()
    local GL, g, m = start()
    GL:LinkAlt(g, m["Fillerb"], m["Fillera"], "user")
    GL:SetNickname(g, m["Fillera"], "Checky", "user")
    W.advance(60)
    GL:SetMain(g, m["Fillerb"], "user")
    W.advance(60)
    ok(GL:SetNickname(g, m["Fillera"], "Chex", "user"), "changed")
    eq(GL:Nickname(g, m["Fillera"]), "Chex", "new name on the old main")
    eq(GL:Nickname(g, m["Fillerb"]), "Chex", "and on the new one")
    W.advance(60)
    ok(GL:SetNickname(g, m["Fillerb"], "", "user"), "cleared")
    eq(GL:Nickname(g, m["Fillera"]), nil, "nothing on the old main")
    eq(GL:Nickname(g, m["Fillerb"]), nil, "nothing on the new one")
    ok(not GL:SetNickname(g, m["Fillerb"], "", "user"), "clearing nothing changes nothing")
end)

test("nickname: one without a group is its own", function()
    local GL, g, m = start()
    GL:SetNickname(g, m["Fillera"], "Solo", "user")
    eq(GL:Nickname(g, m["Fillera"]), "Solo")
    eq(GL:Nickname(g, m["Fillerb"]), nil)
end)

test("nickname: an officer's record for a character that is an alt here still shows", function()
    local GL, g, m = start()
    GL:LinkAlt(g, m["Fillerb"], m["Fillera"], "user")   -- here Fillera is the main
    W.advance(60)
    -- The other officer has Fillerb as the main and set the nickname there.
    ok(GL:SetNickname(g, m["Fillerb"], "Checky", "sync", "Other Officer", W.now()), "taken")
    eq(GL:Nickname(g, m["Fillera"]), "Checky", "on the main")
    eq(GL:Nickname(g, m["Fillerb"]), "Checky", "on the alt")
    -- They clear it later.
    W.advance(60)
    GL:SetNickname(g, m["Fillerb"], "", "sync", "Other Officer", W.now())
    eq(GL:Nickname(g, m["Fillera"]), nil, "cleared for the person")
end)

test("nickname: survives folding ledgers that grouped the same people under another main", function()
    local GL, old, m = start()
    GL:LinkAlt(old, m["Fillera"], m["Zev Zev"], "user")
    GL:SetNickname(old, m["Zev Zev"], "Boss", "user")
    GL:SetNickname(old, m["Fillerc"], "Sea", "user")
    -- The rename, with a copy of Tabard that started an empty ledger; there the alt was grouped as the main.
    W.advance(86400)
    _G.GetRealmName = function() return "" end
    local rejoin = GL.RejoinLedgers
    GL.RejoinLedgers = nil
    GL.sessionReady = false
    W.scan(GL)
    local split = GL:Guild()
    ok(split ~= old, "a second ledger was started")
    GL:LinkAlt(split, split.members["Zev Zev"], split.members["Fillera"], "scan")
    eq(GL:Nickname(split, split.members["Zev Zev"]), nil, "no nicknames in the empty ledger")
    -- The update folds them.
    GL.RejoinLedgers = rejoin
    W.advance(3600)
    W.scan(GL) W.runTimers()
    local g = GL:Guild()
    ok(GL:IsMain(g, g.members["Fillera"]), "the newer ledger's main")
    eq(GL:Nickname(g, g.members["Fillera"]), "Boss", "nickname on the new main")
    eq(GL:Nickname(g, g.members["Zev Zev"]), "Boss", "and on the old one")
    eq(GL:Nickname(g, g.members["Fillerc"]), "Sea", "an ungrouped member's nickname")
end)
