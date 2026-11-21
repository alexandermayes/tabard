-- The realm's name changed under the guild (WoW Forever: "Realm 4", "Realm 6", then empty). A ledger is filed
-- under "guild - realm", so each rename used to start an empty ledger beside the old one. The first complete
-- roster read now folds an older ledger of the same guild, with mostly the same people, into the current one.
local W = require("wow")
local OLD_KEY, NEW_KEY = "Test Guild - Test Realm", "Test Guild - "

local function person(name, class) return { name = name, rank = "Member", rankIndex = 7, level = 30, class = class or "WARRIOR" } end
local function roster(without, extra)
    local list = { { name = "Zev Zev", rank = "Officer", rankIndex = 2, level = 60, class = "MAGE" } }
    for i = 1, 10 do
        local name = "Filler" .. string.char(96 + i)
        if name ~= without then list[#list + 1] = person(name) end
    end
    if extra then list[#list + 1] = extra end
    return list
end
local function rename() _G.GetRealmName = function() return "" end end

test("realm rename: the old ledger carries on under the new name", function()
    local GL = W.load()
    W.setRoster(roster())
    W.scan(GL)
    local old = GL:Guild()
    local started = old.seeded
    GL:SetCustomNote(old, old.members["Fillera"], "good tank", "user")
    W.advance(86400)
    rename()
    GL.sessionReady = false
    W.setRoster(roster("Fillerb", person("New Guy", "ROGUE")))
    W.scan(GL)
    local g = GL:Guild()
    ok(TabardDB.guilds[OLD_KEY] == nil, "old name gone")
    ok(TabardDB.guilds[NEW_KEY] == g, "filed under the new name")
    eq(g.seeded, started, "the ledger still starts when it started")
    eq(g.members["Fillera"].custom, "good tank", "ledger note kept")
    eq(#W.events(g, "custom", "Fillera"), 1, "its log line kept")
    eq(#W.events(g, "join", "New Guy"), 1, "the join while away is recorded")
    ok(TabardDB.folded and TabardDB.folded[OLD_KEY], "the original is kept")
    W.scan(GL)
    eq(#W.events(g, "leave", "Fillerb"), 1, "the leave while away is recorded")
    ok(g.former["Fillerb"], "and they are a former member")
end)

test("realm rename: ledgers that were already split become one", function()
    local GL = W.load()
    W.setRoster(roster())
    W.scan(GL)
    local old = GL:Guild()
    local started = old.seeded
    W.advance(600)
    W.setRoster(roster(nil, person("Late Guy", "ROGUE")))
    W.scan(GL) W.runTimers()
    GL:SetCustomNote(old, old.members["Fillera"], "good tank", "user")
    GL:LinkAlt(old, old.members["Fillerc"], old.members["Fillerd"], "user")
    eq(#W.events(old, "join", "Late Guy"), 1, "join seen live")
    local lastOld = W.now()
    -- The rename, with the old copy of Tabard: an empty ledger is started and reads the game's log again.
    W.advance(86400)
    rename()
    local rejoin = GL.RejoinLedgers
    GL.RejoinLedgers = nil
    GL.sessionReady = false
    local now = roster("Fillerb", person("Gap Joiner", "PRIEST"))
    now[#now + 1] = person("Late Guy", "ROGUE")
    W.setRoster(now)
    W.setGameLog({ { kind = "join", p1 = "Late Guy", hoursAgo = 24 } })
    W.scan(GL)
    W.importLog(GL)
    local split = GL:Guild()
    ok(split ~= old and split.seeded and split.seeded > started, "a second ledger was started")
    local splitStarted = split.seeded
    GL:SetCustomNote(split, split.members["Fillere"], "new note", "user")
    W.advance(3600)
    W.scan(GL)
    -- The update.
    GL.RejoinLedgers = rejoin
    W.advance(60)
    W.scan(GL) W.runTimers()
    local g = GL:Guild()
    ok(g == split, "the current table is kept")
    ok(TabardDB.guilds[OLD_KEY] == nil, "one ledger")
    eq(g.seeded, started, "starting when the first one did")
    eq(g.members["Fillera"].custom, "good tank", "note from the old ledger")
    eq(g.members["Fillere"].custom, "new note", "note from the new ledger")
    eq(#W.events(g, "join", "Late Guy"), 1, "the join both ledgers knew is there once")
    eq(g.members["Late Guy"].joinedSource, "scan", "with the date it was seen on")
    local left = W.events(g, "leave", "Fillerb")
    eq(#left, 1, "who left between the two")
    eq(left[1] and left[1].t, splitStarted, "dated when the new ledger first looked")
    ok(g.former["Fillerb"] and not g.members["Fillerb"], "and listed as former")
    eq(#W.events(g, "join", "Gap Joiner"), 1, "who joined between the two")
    ok(GL:IsAlt(g, g.members["Fillerc"]), "alt group kept")
    eq(g.lastVisit, W.now() - 60, "the last visit is the last read before the fold")
    ok(g.scans > 3, "roster reads added up")
    for i = 2, #g.events do ok(g.events[i - 1].t <= g.events[i].t, "events in time order") end
    ok(TabardDB.folded[OLD_KEY] and TabardDB.folded[NEW_KEY], "both originals kept")
    ok(lastOld < splitStarted)
    -- Nothing more to fold, and nothing recorded twice by the next read.
    local count = #g.events
    W.advance(60)
    W.scan(GL) W.runTimers()
    eq(#g.events, count, "the next read adds nothing")
end)

test("realm rename: another guild of the same name is left alone", function()
    local GL = W.load()
    W.setRoster(roster())
    W.scan(GL)
    W.advance(86400)
    rename()
    GL.sessionReady = false
    local others = {}
    for i = 1, 12 do others[#others + 1] = person("Stranger" .. string.char(96 + i), "DRUID") end
    W.setRoster(others)
    W.scan(GL)
    ok(TabardDB.guilds[OLD_KEY], "the other ledger stays")
    eq(GL:Guild().seeded, W.now(), "and this one starts now")
end)
