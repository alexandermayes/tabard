local W = require("wow")
local function fresh()
    local GL = W.load()
    W.setRoster({ { name = "Ooh Woo", rank = "Member", rankIndex = 3, level = 20, class = "MAGE" } })
    W.scan(GL)
    local g = GL:Guild()
    GL:AddEvent(g, "level", { who = "Ooh Woo", level = 21, from = 20 }, W.START - 5 * 86400)
    return GL, g
end
test("recording-since line names the first event and the default keep period", function()
    local GL, g = fresh()
    eq(GL:RecordingSinceText(g), "Recording since " .. GL:FormatDate(W.START - 5 * 86400) .. ", keeping 365 days", "text")
end)
test("recording-since line says everything when nothing is trimmed", function()
    local GL, g = fresh()
    GL.settings.keepEventDays = 0
    local text = GL:RecordingSinceText(g)
    ok(string.sub(text, -#", keeping everything") == ", keeping everything", "ends with keeping everything")
end)
