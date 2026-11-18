local W = require("wow")
local function fresh()
    local GL = W.load()
    W.setRoster({ { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" } })
    W.scan(GL)
    local g = GL:Guild()
    g.events, g.seen, g.former, g.repaired = {}, {}, {}, nil
    return GL, g
end
test("drift duplicates go, real repeats stay", function()
    local GL, g = fresh()
    local T, T2 = GL:Now() - 90000, GL:Now() - 50000
    g.events = {
        { k = "demote", who = "Oh No", t = T2 + 5640, src = "scan", from = "Raider", to = "Initiate" },
        { k = "join", who = "Nu Guy", t = T + 2160, src = "game" },
        { k = "promote", who = "Oh No", t = T2 + 2800, src = "scan", to = "Raider" },
        { k = "join", who = "Nu Guy", t = T, src = "game" },
        { k = "promote", who = "Nu Guy", t = T + 1000, src = "game", to = "Member", by = "Zev Zev" },
        { k = "demote", who = "Oh No", t = T2, src = "scan", from = "Raider", to = "Initiate" },
    }
    local report = GL:RepairLedger(g)
    eq(#W.events(g, "join", "Nu Guy"), 1, "one join")
    eq(#W.events(g, "demote", "Oh No"), 2, "two demotes")
    eq(report.duplicates, 1, "one duplicate")
    for i = 2, #g.events do ok(g.events[i - 1].t <= g.events[i].t, "sorted") end
end)
test("former and joins come back from seen", function()
    local GL, g = fresh()
    local T = GL:Now() - 90000
    g.seen = { ["join|Gone Guy||"] = { T }, ["quit|Gone Guy||Initiate"] = { T + 40000 } }
    local report = GL:RepairLedger(g)
    local f = g.former["Gone Guy"]
    ok(f and f.joined and f.left, "former with joined and left")
    eq(#W.events(g, "join", "Gone Guy"), 1, "one join")
    eq(#W.events(g, "leave", "Gone Guy"), 1, "one leave")
    eq(report.former, 1, "former counted") eq(report.joins, 1, "join counted")
end)
test("unaccepted invites become invite events", function()
    local GL, g = fresh()
    g.seen = { ["invite|Zev Zev|Shy Guy|"] = { GL:Now() - 5000 } }
    local report = GL:RepairLedger(g)
    eq(#W.events(g, "invite", "Shy Guy"), 1, "one invite")
    eq(report.invites, 1, "counted")
end)
test("runs once", function()
    local GL, g = fresh()
    g.seen = { ["invite|Zev Zev|Shy Guy|"] = { GL:Now() - 5000 } }
    g.events = { { k = "join", who = "Bad", src = "scan" } }   -- no time: dropped, no crash
    W.clearChat()
    GL:ProcessRoster()
    local lines = 0
    for _, m in ipairs(W.chat) do if tostring(m):find("repaired the ledger", 1, true) then lines = lines + 1 end end
    eq(lines, 1, "printed once")
    eq(g.repaired, 1, "marked")
    eq(select(2, GL:BackupInfo()), "before ledger repair", "backup label")
    W.clearChat()
    GL:ProcessRoster()
    for _, m in ipairs(W.chat) do ok(not tostring(m):find("repaired the ledger", 1, true), "not again") end
    eq(#W.events(g, "invite", "Shy Guy"), 1, "no second invite")
end)
local function chatHas(text)
    for _, m in ipairs(W.chat) do if tostring(m):find(text, 1, true) then return true end end
    return false
end
test("a failing repair never repeats and never reports success", function()
    local GL, g = fresh()
    g.seen = { ["invite|Zev Zev|Shy Guy|"] = { GL:Now() - 5000 } }
    local real = GL.SortEvents
    GL.SortEvents = function() error("boom") end
    W.clearChat()
    local good = pcall(GL.ProcessRoster, GL)
    GL.SortEvents = real
    ok(good, "ProcessRoster did not error")
    eq(g.repaired, 1, "marked") eq(GL.quiet and true or false, false, "quiet restored")
    ok(not chatHas("repaired the ledger"), "no success line")
    ok(chatHas("/tabard restore"), "failure line says how to undo")
    W.clearChat()
    GL.SortEvents = function() error("boom again") end
    pcall(GL.ProcessRoster, GL)
    GL.SortEvents = real
    ok(not chatHas("failed"), "no retry")
end)
test("a failing backup skips the repair but sets the marker", function()
    local GL, g = fresh()
    g.seen = { ["invite|Zev Zev|Shy Guy|"] = { GL:Now() - 5000 } }
    local real = GL.Backup
    GL.Backup = function() error("no copy") end
    W.clearChat()
    local good = pcall(GL.ProcessRoster, GL)
    GL.Backup = real
    ok(good, "no error") eq(g.repaired, 1, "marked")
    eq(#W.events(g, "invite", "Shy Guy"), 0, "not repaired without a backup")
    ok(chatHas("skipped"), "skipped line")
end)
test("the backup carries the marker", function()
    local GL, g = fresh()
    GL:RepairLedger(g)
    ok(GL.db.backup and GL.db.backup.guild.repaired == 1, "backup has marker")
end)
test("a leave between a join and a rejoin keeps all three", function()
    local GL, g = fresh()
    local T = GL:Now() - 90000
    g.events = {
        { k = "join", who = "Yo Yo", t = T, src = "game" },
        { k = "leave", who = "Yo Yo", t = T + 1800, src = "scan" },
        { k = "rejoin", who = "Yo Yo", t = T + 3000, src = "scan" },
    }
    local report = GL:RepairLedger(g)
    eq(#W.events(g, "join", "Yo Yo"), 1, "join kept")
    eq(#W.events(g, "leave", "Yo Yo"), 1, "leave kept")
    eq(#W.events(g, "rejoin", "Yo Yo"), 1, "rejoin kept")
    eq(report.duplicates, 0, "no duplicates")
end)
test("promotions to different ranks, or by different officers, are not duplicates", function()
    local GL, g = fresh()
    local T = GL:Now() - 90000
    g.events = {
        { k = "promote", who = "Fast Guy", t = T, src = "game", to = "Member", by = "Zev Zev" },
        { k = "promote", who = "Fast Guy", t = T + 2400, src = "game", to = "Lucky", by = "Zev Zev" },
        { k = "promote", who = "Two Bosses", t = T, src = "game", to = "Member", by = "Zev Zev" },
        { k = "promote", who = "Two Bosses", t = T + 2400, src = "game", to = "Member", by = "Ann Officer" },
    }
    local report = GL:RepairLedger(g)
    eq(#W.events(g, "promote", "Fast Guy"), 2, "both ranks kept")
    eq(#W.events(g, "promote", "Two Bosses"), 2, "both officers kept")
    eq(report.duplicates, 0, "no duplicates")
end)
test("same promotion read twice is still one", function()
    local GL, g = fresh()
    local T = GL:Now() - 90000
    g.events = {
        { k = "promote", who = "Fast Guy", t = T, src = "game", to = "Member", by = "Zev Zev" },
        { k = "promote", who = "Fast Guy", t = T + 2400, src = "game", to = "Member" },
    }
    local report = GL:RepairLedger(g)
    eq(#W.events(g, "promote", "Fast Guy"), 1, "one promotion")
    eq(report.duplicates, 1, "one duplicate")
end)
test("a removal merged into a plain leave makes it a kick", function()
    local GL, g = fresh()
    local T = GL:Now() - 90000
    g.former["Gone Guy"] = { name = "Gone Guy", left = T, leftKind = "leave" }
    g.events = {
        { k = "leave", who = "Gone Guy", t = T, src = "scan", from = "Initiate" },
        { k = "kick", who = "Gone Guy", t = T + 1800, src = "game", by = "Zev Zev" },
    }
    local report = GL:RepairLedger(g)
    eq(#W.events(g, "leave", "Gone Guy"), 0, "no plain leave")
    local kicks = W.events(g, "kick", "Gone Guy")
    eq(#kicks, 1, "one kick")
    eq(kicks[1] and kicks[1].by, "Zev Zev", "remover")
    eq(report.duplicates, 1, "one duplicate")
    eq(g.former["Gone Guy"].leftKind, "kick", "leftKind")
    eq(g.former["Gone Guy"].leftBy, "Zev Zev", "leftBy")
end)
