local W = require("wow")
local function fresh()
    local GL = W.load()
    W.setRoster({ { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" } })
    W.scan(GL)
    GL.settings.announce = GL.settings.announce or {}
    GL.settings.announce.leave = true
    GL.settings.announce.kick = true
    W.clearChat()
    return GL, GL:Guild()
end
local function count(pattern)
    local n = 0
    for _, line in ipairs(W.chat) do if string.find(line, pattern) then n = n + 1 end end
    return n
end
test("leave line records once", function()
    local GL, g = fresh()
    W.advance(60)
    W.fire("CHAT_MSG_SYSTEM", "Ooh Woo has left the guild.")
    local f = g.former["Ooh Woo"]
    ok(f, "former set")
    eq(f.leftKind, "leave", "leftKind") eq(f.online, false, "offline") ok(f.left, "left time")
    eq(g.members["Ooh Woo"], nil, "no longer a member")
    W.setRoster({})
    W.scan(GL) W.scan(GL)
    eq(#W.events(g, "leave", "Ooh Woo"), 1, "still one leave after scans")
    W.setGameLog({ { kind = "quit", p1 = "Ooh Woo", hoursAgo = 0 } })
    W.importLog(GL)
    eq(#W.events(g, "leave", "Ooh Woo"), 1, "still one after game log")
    local e = W.events(g, "leave", "Ooh Woo")[1]
    eq(e.level, 20, "level") eq(e.from, "Initiate", "rank")
    eq(count("left the guild"), 1, "announced once")
end)
test("kick line names the remover", function()
    local GL, g = fresh()
    W.fire("CHAT_MSG_SYSTEM", "Ooh Woo has been kicked out of the guild by Zev Zev.")
    local list = W.events(g, "kick", "Ooh Woo")
    eq(#list, 1, "one kick") eq(list[1].by, "Zev Zev", "by")
    eq(g.former["Ooh Woo"].leftKind, "kick", "leftKind") eq(g.former["Ooh Woo"].leftBy, "Zev Zev", "leftBy")
end)
test("join line asks for a scan", function()
    local GL = fresh()
    local before = W.rosterRequests
    W.fire("CHAT_MSG_SYSTEM", "Newbie Nine has joined the guild.")
    eq(W.rosterRequests, before + 1, "one roster request")
end)
-- A guild big enough that one leaver does not make the roster look partial (a >10% shrink does).
local leaver = { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" }
local function others()
    local list = {}
    for i = 1, 10 do list[i] = { name = "Filler" .. string.char(96 + i), rank = "Member", rankIndex = 7, level = 30, class = "WARRIOR" } end
    return list
end
local function bigGuild()
    local GL = W.load()
    local list = others()
    list[#list + 1] = leaver
    W.setRoster(list)
    W.scan(GL)
    GL.settings.announce = GL.settings.announce or {}
    GL.settings.announce.leave = true
    GL.settings.announce.kick = true
    W.clearChat()
    return GL, GL:Guild()
end
test("stale roster right after a leave line is not a rejoin", function()
    local GL, g = bigGuild()
    GL.settings.announce.rejoin = true
    GL.settings.announce.join = true
    W.advance(600)
    W.fire("CHAT_MSG_SYSTEM", "Ooh Woo has left the guild.")
    W.advance(2)
    W.scan(GL)   -- the roster cache still lists the leaver
    W.runTimers()
    eq(g.members["Ooh Woo"], nil, "still not a member")
    ok(g.former["Ooh Woo"], "still former")
    W.advance(30)
    W.setRoster(others())
    W.scan(GL) W.scan(GL) W.runTimers()
    eq(g.lastCount, 10, "complete roster read")
    eq(#W.events(g, "leave", "Ooh Woo"), 1, "one leave")
    eq(#W.events(g, "rejoin", "Ooh Woo"), 0, "no rejoin")
    eq(count("left the guild"), 1, "one leave line")
    eq(count("rejoined"), 0, "no rejoin line")
    eq(g.former["Ooh Woo"].leftLive, nil, "leftLive cleared once the roster drops them")
end)
test("leave line then join line then roster: a real rejoin", function()
    local GL, g = bigGuild()
    W.advance(600)
    W.fire("CHAT_MSG_SYSTEM", "Ooh Woo has left the guild.")
    W.advance(20)
    W.fire("CHAT_MSG_SYSTEM", "Ooh Woo has joined the guild.")
    W.advance(2)
    W.scan(GL) W.runTimers()
    eq(#W.events(g, "rejoin", "Ooh Woo"), 1, "one rejoin")
    ok(g.members["Ooh Woo"], "member again")
    eq(g.members["Ooh Woo"].leftLive, nil, "leftLive cleared")
end)
test("stale-roster guard ends after two minutes", function()
    local GL, g = bigGuild()
    W.advance(600)
    W.fire("CHAT_MSG_SYSTEM", "Ooh Woo has left the guild.")
    W.advance(2)
    W.scan(GL)
    eq(#W.events(g, "rejoin", "Ooh Woo"), 0, "guarded")
    W.advance(200)
    W.scan(GL)   -- still listed well past the window: they really are back
    eq(#W.events(g, "rejoin", "Ooh Woo"), 1, "rejoin after the window")
end)
