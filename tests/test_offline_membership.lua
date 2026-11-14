-- Joins and leaves that happened while nobody was online: the first roster read of a session sees them late,
-- and the game's event log, read before or after it, supplies the real time (and who invited or removed them).
local W = require("wow")
local officer = { name = "Ooh Woo", rank = "Officer", rankIndex = 2, level = 60, class = "MAGE" }
local newb = { name = "Late Guy", rank = "Initiate", rankIndex = 8, level = 10, class = "ROGUE" }
local function others()
    local list = { officer }
    for i = 1, 10 do list[#list + 1] = { name = "Filler" .. string.char(96 + i), rank = "Member", rankIndex = 7, level = 30, class = "WARRIOR" } end
    return list
end
local function with(extra)
    local list = others()
    list[#list + 1] = extra
    return list
end
-- A guild seen yesterday; then a day passes with nobody online and a new session starts.
local function nextDay(list)
    local GL = W.load()
    W.setRoster(list or others())
    W.scan(GL)
    W.advance(86400)
    GL.sessionReady = false   -- a new login: the next roster read is the first of the session
    return GL, GL:Guild()
end
local function joinLog(hours)
    return { { kind = "invite", p1 = "Ooh Woo", p2 = "Late Guy", hoursAgo = hours }, { kind = "join", p1 = "Late Guy", hoursAgo = hours } }
end

test("offline join: event log read before the first roster read", function()
    local GL, g = nextDay()
    local T = W.now() - 5 * 3600
    W.setGameLog(joinLog(5))
    W.importLog(GL)
    W.setRoster(with(newb))
    W.scan(GL) W.runTimers()
    local joins = W.events(g, "join", "Late Guy")
    eq(#joins, 1, "one join")
    eq(joins[1] and joins[1].t, T, "at the game's time")
    eq(joins[1] and joins[1].by, "Ooh Woo", "inviter")
    eq(joins[1] and joins[1].late, nil, "not left late")
    eq(g.members["Late Guy"].joined, T, "join date")
    eq(g.members["Late Guy"].joinedSource, "game", "join date source")
end)

test("offline join: first roster read before the event log", function()
    local GL, g = nextDay()
    local T = W.now() - 5 * 3600
    W.setRoster(with(newb))
    W.scan(GL)
    local first = W.events(g, "join", "Late Guy")[1]
    ok(first and first.late, "marked late")
    W.setGameLog(joinLog(5))
    W.importLog(GL) W.runTimers()
    local joins = W.events(g, "join", "Late Guy")
    eq(#joins, 1, "one join")
    eq(joins[1] and joins[1].t, T, "at the game's time")
    eq(joins[1] and joins[1].by, "Ooh Woo", "inviter")
    eq(joins[1] and joins[1].late, nil, "late cleared")
    eq(joins[1] and joins[1].g, true, "claimed")
    eq(g.members["Late Guy"].joined, T, "join date")
    eq(g.members["Late Guy"].joinedSource, "game", "join date source")
    -- in time order: nothing after it is older
    for i = 2, #g.events do ok(g.events[i - 1].t <= g.events[i].t, "sorted " .. i) end
    -- later reads of the same log (the hour drifts) add nothing
    W.advance(3600)
    W.setGameLog(joinLog(6))
    W.importLog(GL)
    eq(#W.events(g, "join", "Late Guy"), 1, "still one join")
end)

test("offline removal: event log read while the roster cache still lists them", function()
    local GL, g = nextDay(with(newb))
    local T = W.now() - 5 * 3600
    W.setGameLog({ { kind = "remove", p1 = "Ooh Woo", p2 = "Late Guy", hoursAgo = 5 } })
    W.importLog(GL)
    ok(g.members["Late Guy"], "still a member until the roster drops them")
    W.setRoster(others())
    W.scan(GL) W.advance(20) W.scan(GL)
    local kicks = W.events(g, "kick", "Late Guy")
    eq(#kicks, 1, "one kick")
    eq(#W.events(g, "leave", "Late Guy"), 0, "no plain leave")
    eq(kicks[1] and kicks[1].t, T, "at the game's time")
    eq(kicks[1] and kicks[1].by, "Ooh Woo", "remover")
    local f = g.former["Late Guy"]
    eq(f and f.leftKind, "kick", "leftKind")
    eq(f and f.leftBy, "Ooh Woo", "leftBy")
    eq(f and f.left, T, "left")
    eq(g.pendingLeave and g.pendingLeave["Late Guy"], nil, "pending cleared")
end)

test("offline removal: roster reads before the event log", function()
    local GL, g = nextDay(with(newb))
    W.setRoster(others())
    W.scan(GL) W.advance(20) W.scan(GL)
    local T = W.now() - 5 * 3600
    local first = W.events(g, "leave", "Late Guy")[1]
    ok(first and first.late, "marked late")
    W.setGameLog({ { kind = "remove", p1 = "Ooh Woo", p2 = "Late Guy", hoursAgo = 5 } })
    W.importLog(GL)
    local kicks = W.events(g, "kick", "Late Guy")
    eq(#kicks, 1, "one kick")
    eq(#W.events(g, "leave", "Late Guy"), 0, "no plain leave")
    eq(kicks[1] and kicks[1].t, T, "at the game's time")
    eq(kicks[1] and kicks[1].by, "Ooh Woo", "remover")
    eq(kicks[1] and kicks[1].late, nil, "late cleared")
    local f = g.former["Late Guy"]
    eq(f and f.leftKind, "kick", "leftKind") eq(f and f.leftBy, "Ooh Woo", "leftBy") eq(f and f.left, T, "left")
end)

test("offline quit: either order gives one leave at the game's time", function()
    for _, logFirst in ipairs({ true, false }) do
        local GL, g = nextDay(with(newb))
        local T = W.now() - 5 * 3600
        W.setGameLog({ { kind = "quit", p1 = "Late Guy", hoursAgo = 5 } })
        if logFirst then W.importLog(GL) end
        W.setRoster(others())
        W.scan(GL) W.advance(20) W.scan(GL)
        if not logFirst then T = W.now() - 5 * 3600 W.importLog(GL) end
        local leaves = W.events(g, "leave", "Late Guy")
        local tag = logFirst and " (log first)" or " (roster first)"
        eq(#leaves, 1, "one leave" .. tag)
        eq(#W.events(g, "kick", "Late Guy"), 0, "no kick" .. tag)
        eq(leaves[1] and leaves[1].t, T, "at the game's time" .. tag)
        eq(g.former["Late Guy"] and g.former["Late Guy"].left, T, "left" .. tag)
    end
end)

test("a live join and leave while online are not late and keep their times", function()
    local GL = W.load()
    W.setRoster(others())
    W.scan(GL)
    local g = GL:Guild()
    W.advance(60)
    W.setRoster(with(newb))
    W.scan(GL) W.runTimers()
    local now = W.now()
    local join = W.events(g, "join", "Late Guy")[1]
    ok(join, "join recorded")
    eq(join and join.late, nil, "join not late")
    eq(join and join.t, now, "join time")
    eq(g.members["Late Guy"].joined, now, "join date")
    eq(g.members["Late Guy"].joinedSource, "scan", "join date source")
    W.setGameLog(joinLog(0))
    W.importLog(GL)
    eq(#W.events(g, "join", "Late Guy"), 1, "one join after the log")
    eq(W.events(g, "join", "Late Guy")[1].t, now, "time kept")
    eq(g.members["Late Guy"].joinedSource, "scan", "scan date kept")
    W.advance(60)
    W.setRoster(others())
    W.scan(GL) W.advance(20) W.scan(GL)
    local leave = W.events(g, "leave", "Late Guy")[1]
    ok(leave, "leave recorded")
    eq(leave and leave.late, nil, "leave not late")
    eq(leave and leave.t, W.now(), "leave time")
end)

test("a promotion by someone who left late does not date their leave", function()
    local GL, g = nextDay(with(newb))
    W.setRoster(others())
    W.scan(GL) W.advance(20) W.scan(GL)
    local before = W.events(g, "leave", "Late Guy")[1]
    local t0 = before and before.t
    W.setGameLog({ { kind = "promote", p1 = "Late Guy", p2 = "Fillera", rank = "Member", hoursAgo = 5 } })
    W.importLog(GL)
    local leave = W.events(g, "leave", "Late Guy")[1]
    eq(leave and leave.t, t0, "leave time unchanged")
    ok(leave and leave.late, "still late")
    eq(#W.events(g, "promote", "Fillera"), 1, "the promotion is its own event")
end)

test("a /reload a minute later is not late: the join keeps its scan time", function()
    local GL = W.load()
    W.setRoster(others())
    W.scan(GL)
    local db, clock = TabardDB, W.now()
    GL = W.load({ db = db })   -- a /reload: saved data kept, a new session
    W.advance(clock - W.START + 60)
    ok(not GL.sessionReady, "first read of the new session")
    local g = GL:Guild()
    W.setRoster(with(newb))
    W.scan(GL) W.runTimers()
    local now = W.now()
    local join = W.events(g, "join", "Late Guy")[1]
    ok(join, "join recorded")
    eq(join and join.late, nil, "not late")
    eq(join and join.t, now, "scan time")
    W.advance(30)
    W.setGameLog(joinLog(0))
    W.importLog(GL)
    eq(#W.events(g, "join", "Late Guy"), 1, "one join after the log")
    eq(W.events(g, "join", "Late Guy")[1].t, now, "scan time kept")
    eq(g.members["Late Guy"].joined, now, "join date kept")
    eq(g.members["Late Guy"].joinedSource, "scan", "scan source kept")
end)
