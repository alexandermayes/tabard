-- An error inside a pcall'd import or scan must not leave GL.quiet on (that silences every chat line).
local W = require("wow")
local member = { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" }
local function count(pattern)
    local n = 0
    for _, line in ipairs(W.chat) do if string.find(line, pattern) then n = n + 1 end end
    return n
end
test("an event log import error does not silence announcements", function()
    local GL = W.load()
    W.setRoster({ member })
    W.scan(GL)
    local g = GL:Guild()
    GL.settings.announce = GL.settings.announce or {}
    GL.settings.announce.leave = true
    local real = GL.EnsureFormer
    GL.EnsureFormer = function(self, guild, name, ...)
        if name == "Boom Boom" then error("boom") end
        return real(self, guild, name, ...)
    end
    W.setGameLog({ { kind = "quit", p1 = "Boom Boom", hoursAgo = 3 } })
    W.importLog(GL)
    ok(count("event log import failed") == 1, "the failure is reported")
    ok(not GL.quiet, "quiet restored")
    W.clearChat()
    W.advance(60)
    W.fire("CHAT_MSG_SYSTEM", "Ooh Woo has left the guild.")
    eq(#W.events(g, "leave", "Ooh Woo"), 1, "leave recorded")
    eq(count("left the guild"), 1, "leave announced")
end)
test("a roster scan error does not silence announcements", function()
    local GL = W.load()
    W.setRoster({ member })
    GL.settings.autoAlts = true
    local real = GL.DetectAlt
    GL.DetectAlt = function() error("boom") end   -- fails inside the quiet first-look seeding
    W.scan(GL)
    ok(count("roster scan failed") == 1, "the failure is reported")
    ok(not GL.quiet, "quiet restored")
    GL.DetectAlt = real
    W.advance(30)
    W.scan(GL)
    local g = GL:Guild()
    ok(g.seeded, "seeded on the next scan")
    GL.settings.announce = GL.settings.announce or {}
    GL.settings.announce.leave = true
    W.clearChat()
    W.advance(60)
    W.fire("CHAT_MSG_SYSTEM", "Ooh Woo has left the guild.")
    eq(count("left the guild"), 1, "leave announced")
end)
