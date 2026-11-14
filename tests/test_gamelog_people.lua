local W = require("wow")
local function fresh()
    local GL = W.load()
    W.setRoster({ { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" } })
    W.scan(GL)
    return GL, GL:Guild()
end
test("joined and left while away", function()
    local GL, g = fresh()
    W.setGameLog({
        { kind = "join", p1 = "Tessa Zethrel", hoursAgo = 6 },
        { kind = "quit", p1 = "Tessa Zethrel", rank = "Initiate", hoursAgo = 3 },
    })
    W.importLog(GL)
    eq(#W.events(g, "join", "Tessa Zethrel"), 1, "one join")
    eq(#W.events(g, "leave", "Tessa Zethrel"), 1, "one leave")
    local f = g.former["Tessa Zethrel"]
    ok(f ~= nil, "former record")
    eq(f.leftKind, "leave", "left kind")
    ok(math.abs(f.joined - (W.now() - 6 * 3600)) <= 3600, "joined about six hours ago")
    ok(math.abs(f.left - (W.now() - 3 * 3600)) <= 3600, "left about three hours ago")
    W.importLog(GL)
    eq(#W.events(g, "leave", "Tessa Zethrel"), 1, "still one leave")
end)
test("removal makes a former member", function()
    local GL, g = fresh()
    W.setGameLog({ { kind = "remove", p1 = "Zev Zev", p2 = "Obi Wan", rank = "Initiate", hoursAgo = 2 } })
    W.importLog(GL)
    eq(#W.events(g, "kick", "Obi Wan"), 1, "one kick")
    local f = g.former["Obi Wan"]
    ok(f ~= nil, "former record")
    eq(f.leftKind, "kick", "left kind")
    eq(f.leftBy, "Zev Zev", "removed by")
end)
test("invite nobody accepted", function()
    local GL, g = fresh()
    W.setGameLog({ { kind = "invite", p1 = "Zev Zev", p2 = "Shy Guy", hoursAgo = 1 } })
    W.importLog(GL)
    eq(#W.events(g, "invite", "Shy Guy"), 1, "one invite")
    eq(#W.events(g, "join", "Shy Guy"), 0, "no join")
    W.importLog(GL)
    eq(#W.events(g, "invite", "Shy Guy"), 1, "still one invite")
end)
test("invite and join in one read", function()
    for _, inviteFirst in ipairs({ true, false }) do
        local GL, g = fresh()
        local invite = { kind = "invite", p1 = "Zev Zev", p2 = "Glad Guy", hoursAgo = 1 }
        local join = { kind = "join", p1 = "Glad Guy", hoursAgo = 1 }
        W.setGameLog(inviteFirst and { invite, join } or { join, invite })
        W.importLog(GL)
        local joins = W.events(g, "join", "Glad Guy")
        eq(#joins, 1, "one join")
        eq(joins[1] and joins[1].by, "Zev Zev", "inviter filled in")
        eq(#W.events(g, "invite", "Glad Guy"), 0, "no invite left")
    end
end)
test("invite first, join later", function()
    local GL, g = fresh()
    W.setGameLog({ { kind = "invite", p1 = "Zev Zev", p2 = "Late Guy", hoursAgo = 1 } })
    W.importLog(GL)
    eq(#W.events(g, "invite", "Late Guy"), 1, "invite read")
    W.advance(600)
    W.setRoster({
        { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" },
        { name = "Late Guy", rank = "Initiate", rankIndex = 8, level = 10, class = "ROGUE" },
    })
    W.scan(GL)
    local joins = W.events(g, "join", "Late Guy")
    eq(#joins, 1, "one join")
    eq(joins[1] and joins[1].by, "Zev Zev", "inviter copied")
    eq(#W.events(g, "invite", "Late Guy"), 0, "invite folded away")
end)
test("game join first, then the scan sees the person", function()
    local GL, g = fresh()
    W.setGameLog({ { kind = "join", p1 = "Quick Guy", hoursAgo = 0 } })
    W.importLog(GL)
    eq(#W.events(g, "join", "Quick Guy"), 1, "join from the log")
    W.setRoster({
        { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" },
        { name = "Quick Guy", rank = "Initiate", rankIndex = 8, level = 10, class = "ROGUE" },
    })
    W.scan(GL)
    eq(#W.events(g, "join", "Quick Guy"), 1, "still one join")
    eq(#W.events(g, "rejoin", "Quick Guy"), 0, "no rejoin")
end)
test("game join of a former member first, then the scan", function()
    local GL, g = fresh()
    local function roster(withBack)
        local list = { { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" } }
        if withBack then list[2] = { name = "Back Guy", rank = "Initiate", rankIndex = 8, level = 10, class = "ROGUE" } end
        W.setRoster(list)
    end
    roster(true) W.scan(GL)
    roster(false)
    for _ = 1, 4 do W.advance(600) W.scan(GL) end
    ok(g.former["Back Guy"] ~= nil, "became former")
    W.advance(7200)
    W.setGameLog({ { kind = "join", p1 = "Back Guy", hoursAgo = 0 } })
    W.importLog(GL)
    roster(true) W.scan(GL)
    eq(#W.events(g, "rejoin", "Back Guy"), 1, "one rejoin")
    eq(#W.events(g, "join", "Back Guy"), 1, "only the original join")
    ok(g.members["Back Guy"] and g.members["Back Guy"].leftBy == nil, "leftBy cleared")
end)
test("a real rejoin is not swallowed by the earlier join", function()
    local GL, g = fresh()
    local function roster(withGuy)
        local list = { { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" } }
        if withGuy then list[2] = { name = "Flip Guy", rank = "Initiate", rankIndex = 8, level = 10, class = "ROGUE" } end
        W.setRoster(list)
    end
    W.advance(60)
    roster(true) W.scan(GL)
    roster(false)
    for _ = 1, 4 do W.advance(300) W.scan(GL) end
    ok(g.former["Flip Guy"] ~= nil, "became former")
    W.advance(300)
    roster(true) W.scan(GL)
    local all = {}
    for _, e in ipairs(g.events) do if e.who == "Flip Guy" then all[#all + 1] = e.k end end
    eq(table.concat(all, ","), "join,leave,rejoin", "events in order")
end)
