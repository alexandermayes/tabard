-- "Since your last visit": the marker does not depend on the logout event (on WoW Forever the guild is already
-- gone when it fires), and the login report waits until everyone who left while you were away is recorded.
local W = require("wow")

local function person(name) return { name = name, rank = "Member", rankIndex = 7, level = 30, class = "WARRIOR" } end
local function roster(without, extra)
    local list = { { name = "Zev Zev", rank = "Officer", rankIndex = 2, level = 60, class = "MAGE" } }
    for i = 1, 10 do
        local name = "Filler" .. string.char(96 + i)
        if name ~= without then list[#list + 1] = person(name) end
    end
    if extra then list[#list + 1] = extra end
    return list
end
local function said(text)
    for _, line in ipairs(W.chat) do
        if string.find(line, text, 1, true) then return true end
    end
    return false
end

-- A first session that ends without a usable logout event, then a login `away` seconds later.
local function secondLogin(away, list)
    local GL = W.load()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.setRoster(roster())
    W.scan(GL)
    W.advance(1800)
    W.scan(GL)
    local lastOn = W.now()
    _G.IsInGuild = function() return false end   -- as at a real logout on Forever
    W.fire("PLAYER_LOGOUT")
    local db = TabardDB
    GL = W.load({ db = db })
    W.advance(lastOn - W.START + away)
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.clearChat()
    W.setRoster(list)
    W.scan(GL)
    return GL, GL:Guild(), lastOn
end

test("last visit: the marker is the last time you were on, without a logout stamp", function()
    local GL, g, lastOn = secondLogin(86400, roster(nil, person("New Guy")))
    eq(g.visitSince, lastOn, "marker")
    local news = GL:WhatsNew(g)
    eq(#news, 1, "one line")
    ok(news[1] and string.find(news[1].text, "New Guy", 1, true), "the join")
end)

test("last visit: a reload keeps the marker of the login", function()
    local GL, g, lastOn = secondLogin(86400, roster())
    W.advance(600)
    W.fire("PLAYER_LOGOUT")
    local db = TabardDB
    local at = W.now()
    GL = W.load({ db = db })
    W.advance(at - W.START + 5)
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    W.setRoster(roster())
    W.scan(GL)
    eq(GL:Guild().visitSince, lastOn, "marker unchanged")
end)

test("login report: waits for the second roster read before it says who left", function()
    local GL, g = secondLogin(86400, roster("Fillerb"))
    ok(not GL:AwaySettled(g), "one read: Fillerb is only missing")
    eq(#W.events(g, "leave", "Fillerb"), 0, "not recorded yet")
    local asked = W.rosterRequests
    -- The follow-up read the first one asked for.
    W.advance(11)
    W.scan(GL)
    ok(GL:AwaySettled(g), "settled")
    W.runTimers()
    ok(W.rosterRequests > asked, "a second read was asked for")
    ok(said("1 left"), "the summary counts the leave")
    ok(said("Fillerb"), "and the report names them")
    ok(not said("nothing has changed"), "not 'nothing has changed'")
    ok(GL.awayReported, "the login card may show")
end)

test("login report: a leave the game's log names is recorded with the first read", function()
    local GL, g = secondLogin(86400, roster("Fillerb"))
    W.setGameLog({ { kind = "quit", p1 = "Fillerb", hoursAgo = 5 } })
    W.importLog(GL)
    local left = W.events(g, "leave", "Fillerb")
    eq(#left, 1, "recorded")
    eq(left[1] and left[1].t, W.now() - 5 * 3600, "at the game's time")
    ok(GL:AwaySettled(g), "settled without a second read")
end)

test("login report: the game's log read first, then the roster", function()
    local GL = W.load()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.setRoster(roster())
    W.scan(GL)
    local g = GL:Guild()
    W.advance(86400)
    GL.sessionReady = false
    W.setGameLog({ { kind = "remove", p1 = "Zev Zev", p2 = "Fillerb", hoursAgo = 3 } })
    W.importLog(GL)
    eq(#W.events(g, "kick", "Fillerb"), 0, "still a member as far as the roster goes")
    W.setRoster(roster("Fillerb"))
    W.scan(GL)
    local kicks = W.events(g, "kick", "Fillerb")
    eq(#kicks, 1, "recorded with the first read")
    eq(kicks[1] and kicks[1].by, "Zev Zev", "with who removed them")
end)
