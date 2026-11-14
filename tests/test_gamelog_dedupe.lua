local W = require("wow")
local function fresh()
    local GL = W.load()
    W.setRoster({ { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" } })
    W.scan(GL)
    return GL, GL:Guild()
end
test("reimport after drift adds nothing", function()
    local GL, g = fresh()
    local log = { { kind = "promote", p1 = "Zev Zev", p2 = "Ooh Woo", rank = "Member", hoursAgo = 5 } }
    W.setGameLog(log) W.importLog(GL)
    W.advance(2400) W.importLog(GL)
    W.advance(1800) log[1].hoursAgo = 6 W.importLog(GL)
    eq(#W.events(g, "promote", "Ooh Woo"), 1, "one promote")
    local times = g.seen["promote|Zev Zev|Ooh Woo|Member"]
    eq(type(times) == "table" and #times or -1, 1, "one remembered time, not one per hour bucket")
end)
test("two identical entries in one read both count", function()
    local GL, g = fresh()
    W.setGameLog({
        { kind = "demote", p1 = "Zev Zev", p2 = "Ooh Woo", rank = "Initiate", hoursAgo = 3 },
        { kind = "demote", p1 = "Zev Zev", p2 = "Ooh Woo", rank = "Initiate", hoursAgo = 4 },
    })
    W.importLog(GL)
    eq(#W.events(g, "demote", "Ooh Woo"), 2, "two demotes")
    W.importLog(GL)
    eq(#W.events(g, "demote", "Ooh Woo"), 2, "still two")
end)
test("game entry merges into the scan event", function()
    local GL, g = fresh()
    W.advance(600)
    W.setRoster({ { name = "Ooh Woo", rank = "Officer", rankIndex = 3, level = 20, class = "MAGE" } })
    W.scan(GL)
    eq(#W.events(g, "promote", "Ooh Woo"), 1, "scan recorded it")
    W.setGameLog({ { kind = "promote", p1 = "Zev Zev", p2 = "Ooh Woo", rank = "Officer", hoursAgo = 0 } })
    W.importLog(GL)
    local list = W.events(g, "promote", "Ooh Woo")
    eq(#list, 1, "one promote") eq(list[1].by, "Zev Zev", "actor filled in")
end)
test("two scan events are never merged by the game log", function()
    local GL, g = fresh()
    local function rank(name, index)
        W.setRoster({ { name = "Ooh Woo", rank = name, rankIndex = index, level = 20, class = "MAGE" } })
        W.scan(GL)
    end
    rank("Raider", 5) W.advance(600)
    rank("Initiate", 8) W.advance(5640)       -- first demote
    rank("Raider", 5) W.advance(600)
    rank("Initiate", 8)                        -- second demote, 94 minutes after the first
    eq(#W.events(g, "demote", "Ooh Woo"), 2, "two scan demotes")
    W.setGameLog({
        { kind = "demote", p1 = "Zev Zev", p2 = "Ooh Woo", rank = "Initiate", hoursAgo = 0 },
        { kind = "demote", p1 = "Zev Zev", p2 = "Ooh Woo", rank = "Initiate", hoursAgo = 1 },
    })
    W.importLog(GL)
    local list = W.events(g, "demote", "Ooh Woo")
    eq(#list, 2, "still two") eq(list[1].by, "Zev Zev", "first by") eq(list[2].by, "Zev Zev", "second by")
end)
test("old seen format is upgraded", function()
    local GL, g = fresh()
    local T, T2 = GL:Now() - 90000, GL:Now() - 50000
    g.seen = { ["join|Ooh Woo|||498311"] = T, ["join|Ooh Woo|||498312"] = T + 2160,
        ["demote|Zev Zev|Ooh Woo|Initiate|498400"] = T2, ["demote|Zev Zev|Ooh Woo|Initiate|498402"] = T2 + 5640 }
    GL:Guild()
    eq(#g.seen["join|Ooh Woo||"], 1, "merged")
    eq(#g.seen["demote|Zev Zev|Ooh Woo|Initiate"], 2, "kept apart")
    GL:Guild()
    eq(#g.seen["demote|Zev Zev|Ooh Woo|Initiate"], 2, "idempotent")
end)
test("MatchEvent windows", function()
    local GL, g = fresh()
    local now = GL:Now()
    local e = GL:AddEvent(g, "join", { who = "Ghost One", src = "scan" }, now - 6000)
    ok(GL:MatchEvent(g, "join", "Ghost One", now, "game") == e, "scan event within 7200")
    e.g = true
    ok(GL:MatchEvent(g, "join", "Ghost One", now, "game") == nil, "claimed is skipped")
    ok(GL:MatchEvent(g, "rejoin", "Ghost One", now, "game", { ignoreClaim = true }) == e, "ignoreClaim, same class")
    ok(GL:MatchEvent(g, "join", "Ghost One", now, "game", { ignoreClaim = true, exclude = e }) == nil, "exclude")
    local f = GL:AddEvent(g, "join", { who = "Ghost Two", src = "game" }, now - 6000)
    ok(GL:MatchEvent(g, "join", "Ghost Two", now, "game") == nil, "game event outside 3600")
    local h = GL:AddEvent(g, "join", { who = "Ghost Three", src = "game" }, now - 3000)
    ok(GL:MatchEvent(g, "join", "Ghost Three", now, "game") == h, "game event within 3600")
end)
