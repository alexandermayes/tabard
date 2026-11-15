-- The sync queue must actually send. On WoW Forever, C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() answers
-- true in the open world while guild and whisper addon messages still go through; holding the queue on it left
-- every copy stuck at "queue N, lockdown" and nobody ever heard anybody's hello.
local W = require("wow")
local roster = {
    { name = "Zev Zev", rank = "Guild Master", rankIndex = 0, level = 60, class = "MAGE" },
    { name = "Ooh Woo", rank = "Officer", rankIndex = 1, level = 60, class = "PRIEST", online = true },
}
local function setup(restricted, lockdown)
    local GL = W.load()
    W.setRoster(roster)
    W.scan(GL)
    local sent = {}
    C_ChatInfo.SendAddonMessage = function(prefix, message, channel, target)
        sent[#sent + 1] = { prefix = prefix, message = message, channel = channel, target = target }
        return 0
    end
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return restricted end
    C_ChatInfo.InChatMessagingLockdown = function() return lockdown end
    return GL, sent
end
test("the queue drains while the realm's outgoing-addon-chat flag says restricted", function()
    local GL, sent = setup(true, false)
    GL.Sync:Hello(true)
    W.tick(10)
    ok(#sent > 0, "messages were sent")
    eq(sent[1] and string.sub(sent[1].message, 1, 1), "H", "the hello went out first")
    eq(#GL.Sync.queue, 0, "queue empty")
    eq(GL.Sync:Status(), "queue 0", "status shows no lockdown")
end)
test("a real chat messaging lockdown still holds the queue", function()
    local GL, sent = setup(false, true)
    GL.Sync:Hello(true)
    W.tick(10)
    eq(#sent, 0, "nothing sent during lockdown")
    ok(#GL.Sync.queue > 0, "messages wait in the queue")
    ok(string.find(GL.Sync:Status(), "lockdown", 1, true) ~= nil, "status says lockdown")
end)
test("a lockdown result from the send itself waits and retries", function()
    local GL, sent = setup(false, false)
    local refuse = true
    C_ChatInfo.SendAddonMessage = function(prefix, message, channel, target)
        if refuse then return 11 end   -- Enum.SendAddonMessageResult.AddOnMessageLockdown
        sent[#sent + 1] = { message = message }
        return 0
    end
    GL.Sync:Hello(true)
    W.tick(5)
    eq(#sent, 0, "refused while the game says lockdown")
    ok(#GL.Sync.queue > 0, "kept for a retry")
    ok(string.find(GL.Sync:Status(), "lockdown", 1, true) ~= nil, "status says lockdown")
    refuse = false
    W.tick(10)
    ok(#sent > 0, "sent once the game accepts it")
    eq(#GL.Sync.queue, 0, "queue empty")
end)
test("a message the game refuses outright is dropped and counted in the status", function()
    local GL = setup(false, false)
    C_ChatInfo.SendAddonMessage = function() return 9 end   -- Enum.SendAddonMessageResult.GeneralError
    GL.Sync:Hello(true)
    local queued = #GL.Sync.queue
    ok(queued > 0, "something to send")
    W.tick(10)
    eq(#GL.Sync.queue, 0, "not retried forever")
    eq(GL.Sync.dropped, queued, "every refused message counted")
    ok(string.find(GL.Sync:Status(), queued .. " dropped", 1, true) ~= nil, "status shows the drops")
end)
test("a send call that errors is dropped and counted", function()
    local GL = setup(false, false)
    C_ChatInfo.SendAddonMessage = function() error("boom") end
    GL.Sync:Hello(true)
    local queued = #GL.Sync.queue
    W.tick(10)
    eq(#GL.Sync.queue, 0, "queue empty")
    eq(GL.Sync.dropped, queued, "counted")
end)
test("successful sends are not counted as dropped", function()
    local GL, sent = setup(false, false)
    GL.Sync:Hello(true)
    W.tick(10)
    ok(#sent > 0, "sent")
    eq(GL.Sync.dropped, 0, "nothing dropped")
end)
test("result codes come from the client's Enum.SendAddonMessageResult when it has one", function()
    local GL, sent = setup(false, false)
    -- a client that numbers the codes differently from the built-in fallback
    _G.Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 30, ChannelThrottle = 31, AddOnMessageLockdown = 42, NotInGuild = 40, TargetOffline = 41 } }
    local refuse = true
    C_ChatInfo.SendAddonMessage = function(_, message)
        if refuse then return 42 end
        sent[#sent + 1] = { message = message }
        return 0
    end
    GL.Sync:Hello(true)
    W.tick(5)
    ok(#GL.Sync.queue > 0, "the client's lockdown code holds the queue")
    eq(GL.Sync.dropped, 0, "nothing dropped")
    ok(string.find(GL.Sync:Status(), "lockdown", 1, true) ~= nil, "status says lockdown")
    refuse = false
    W.tick(10)
    eq(#GL.Sync.queue, 0, "sent once accepted")
end)
