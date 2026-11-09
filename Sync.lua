-- Tabard: sharing between officers
-- Tabard users in the same guild exchange the records that cannot be read from the game: join and
-- promotion dates, alt groups, bans, ledger notes, birthdays and leave-alone flags. Each record carries the
-- time it was set; the newest wins. Data is only accepted from guild members at or above the rank chosen
-- in settings, and only from characters that are actually in the roster.
--
-- Delivery: messages wait in a queue that drains a few times a second, stops while the game forbids addon
-- messages (boss fights), backs off when the client throttles, and drops messages to people who went
-- offline. Full exchanges are held back inside dungeons and raids and sent once outside.
--
-- Exchanges are incremental: a hello carries the time this character's ledger last ran, and every peer
-- answers with only the records set since then. "Ask officers" sends a hello with time 0 and gets everything.
--
-- Wire format: fields separated by the unit separator (\031); several records in one message are separated
-- by the record separator (\030). Messages:
--   H  version  ask  since  proto     hello; peers answer with records newer than `since` (ask = 1 forces it)
--   J  name  joined  source  stamp
--   P  name  promoted  source  stamp
--   G  main  alt1,alt2,...  stamp     a whole alt group
--   X  name  stamp                    name has no group (tombstone)
--   B  name  t  by  reason  class  stamp  lifted  liftedBy
--   C  name  text  by  stamp          ledger note (empty text clears it)
--   D  name  month  day  stamp        birthday (month 0 clears it)
--   S  name  flags  stamp             leave-alone flags, "k" and/or "p"
--   E  count                          end of an exchange

local ADDON_NAME, GL = ...

local PREFIX = "Tabard"
local PROTO = "2"               -- wire format; records from peers speaking another version are ignored
local SEP = "\031"
local RSEP = "\030"
local MAX_MESSAGE = 250
local SEND_GAP = 0.2            -- seconds between messages
local THROTTLE_WAIT = 1.5       -- seconds to wait after the client throttles us
local LOCKDOWN_WAIT = 1.0       -- seconds between checks while addon messages are forbidden
local HELLO_GAP = 120           -- do not answer the same person's hello more often than this
local SINCE_SLACK = 300         -- records this many seconds older than "since" are still sent
local QUEUE_LIMIT = 600         -- messages; beyond this the oldest bulk messages are dropped

local Sync = { queue = {}, lastHello = {}, answered = {}, held = {}, dropped = 0, state = "idle" }
GL.Sync = Sync

local frame = CreateFrame("Frame")
local registered = false

local RESULT = {
    Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3, InvalidChatType = 4, NotInGroup = 5,
    TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9, NotInGuild = 10, AddOnMessageLockdown = 11,
    TargetOffline = 12,
}

local function clean(text)
    text = tostring(text or "")
    text = string.gsub(text, "[\030\031\r\n]", " ")
    return text
end

local function split(message)
    local fields = {}
    for field in string.gmatch(message .. SEP, "(.-)" .. SEP) do fields[#fields + 1] = field end
    return fields
end

local function enabled()
    return GL.settings and GL.settings.sync and IsInGuild()
end

-- Is this sender allowed to change our records? They must be in the roster at a high enough rank.
local function trusted(guild, sender)
    local member = guild.members[sender]
    if not member or member.rankIndex == nil then return false end
    return member.rankIndex <= (GL.settings.syncMinRank or 1)
end

-- Are addon messages forbidden right now (boss encounters and similar)?
local function lockedDown()
    if C_ChatInfo then
        if C_ChatInfo.InChatMessagingLockdown then
            local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
            if ok and locked then return true end
        end
        if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then
            local ok, locked = pcall(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
            if ok and locked then return true end
        end
    end
    return false
end

-- Inside a dungeon, raid or battleground? Full exchanges wait until outside.
local function inInstance()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and kind ~= "none" and kind ~= nil
end

-- Sending ----------------------------------------------------------------------------------------------
local function ensureRegistered()
    if registered then return true end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        registered = true
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, PREFIX)
        registered = true
    end
    return registered
end

-- bulk: part of a full exchange (dropped first when the queue overflows)
function Sync:Push(message, channel, target, bulk)
    if not ensureRegistered() then return end
    if #message > 255 then message = string.sub(message, 1, 255) end
    if #self.queue >= QUEUE_LIMIT then
        for i = 1, #self.queue do
            if self.queue[i].bulk then table.remove(self.queue, i); self.dropped = self.dropped + 1; break end
        end
        if #self.queue >= QUEUE_LIMIT then self.dropped = self.dropped + 1; return end
    end
    self.queue[#self.queue + 1] = { message = message, channel = channel or "GUILD", target = target, bulk = bulk }
end

local function dropWhere(test)
    local queue, n = Sync.queue, 0
    for i = #queue, 1, -1 do
        if test(queue[i]) then table.remove(queue, i); n = n + 1 end
    end
    Sync.dropped = Sync.dropped + n
    return n
end

-- Sends one queued message. Returns how long to wait before the next attempt and whether the item was handled.
local function sendNow(item)
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if not send then return SEND_GAP, true end
    local ok, result = pcall(send, PREFIX, item.message, item.channel, item.target)
    if not ok then return SEND_GAP, true end                                     -- bad call; nothing to retry
    if result == nil or result == true or result == RESULT.Success then return SEND_GAP, true end
    if result == RESULT.AddonMessageThrottle or result == RESULT.ChannelThrottle then
        Sync.state = "throttled"
        return THROTTLE_WAIT, false
    end
    if result == RESULT.AddOnMessageLockdown then
        Sync.state = "lockdown"
        return LOCKDOWN_WAIT, false
    end
    if result == RESULT.TargetOffline then
        local target = item.target
        dropWhere(function(other) return other.channel == "WHISPER" and other.target == target end)
        return SEND_GAP, true
    end
    if result == RESULT.NotInGuild then
        dropWhere(function(other) return other.channel == "GUILD" end)
        return SEND_GAP, true
    end
    return SEND_GAP, true                                                        -- malformed or impossible; drop it
end

local wait, runTimer = 0, 0
local noteRunning   -- defined below
frame:SetScript("OnUpdate", function(self, elapsed)
    runTimer = runTimer + elapsed
    if runTimer >= 60 then runTimer = 0; pcall(noteRunning) end
    wait = wait - elapsed
    if wait > 0 then return end
    wait = SEND_GAP
    local item = Sync.queue[1]
    if not item then Sync.state = "idle"; return end
    if lockedDown() then Sync.state = "lockdown"; wait = LOCKDOWN_WAIT; return end
    local delay, handled = sendNow(item)
    if handled then
        Sync.state = "sending"
        if Sync.queue[1] == item then table.remove(Sync.queue, 1) end
    end
    wait = delay
end)

-- Called when a lockdown is likely over: send right away instead of waiting out the check interval.
function Sync:Resume()
    if #self.queue > 0 then wait = 0 end
end

-- Record encoders -----------------------------------------------------------------------------------------
local function joinRecord(member)
    if not (member.joined and member.joinedSource ~= "first") then return nil end
    return table.concat({ "J", member.name, member.joined, member.joinedSource or "scan", GL:StampOf(member, "joined") }, SEP), GL:StampOf(member, "joined")
end

local function promoRecord(member)
    if not member.promoted then return nil end
    return table.concat({ "P", member.name, member.promoted, member.promotedSource or "scan", GL:StampOf(member, "promoted") }, SEP), GL:StampOf(member, "promoted")
end

local function groupRecord(guild, member)
    local group = GL:GroupOf(guild, member)
    if not group then
        local stamp = GL:StampOf(member, "group")
        if stamp == 0 then return nil end
        return table.concat({ "X", member.name, stamp }, SEP), stamp
    end
    return table.concat({ "G", group.main, table.concat(group.alts, ","), group.t or 0 }, SEP), group.t or 0
end

local function mineRecord(guild)
    local names = GL.MyCharacters and GL:MyCharacters(guild) or {}
    if #names < 2 then return nil end
    return table.concat({ "M", table.concat(names, ","), GL:Now() }, SEP)
end

local function weekRecord(member)
    local week = member and member.week
    if type(week) ~= "table" then return nil end
    return table.concat({ "N", member.name, math.floor(week.on or 0), week.spoke or 0, week.named or 0, week.grouped or 0, week.replied or 0 }, SEP)
end

local function banRecord(guild, name)
    local ban = guild.bans[name]
    if not ban then return nil end
    return table.concat({ "B", name, ban.t or 0, clean(ban.by), string.sub(clean(ban.reason), 1, 120), ban.class or "", ban.stamp or 0, ban.lifted or 0, clean(ban.liftedBy) }, SEP), ban.stamp or 0
end

local function noteRecord(member)
    local stamp = GL:StampOf(member, "custom")
    if stamp == 0 then return nil end
    return table.concat({ "C", member.name, string.sub(clean(member.custom), 1, 160), clean(member.customBy), stamp }, SEP), stamp
end

local function birthdayRecord(member)
    local stamp = GL:StampOf(member, "birthday")
    if stamp == 0 then return nil end
    local b = member.birthday
    return table.concat({ "D", member.name, b and b.m or 0, b and b.d or 0, stamp }, SEP), stamp
end

local function safeRecord(member)
    local stamp = GL:StampOf(member, "safe")
    if stamp == 0 then return nil end
    local flags = (GL:IsSafe(member, "kick") and "k" or "") .. (GL:IsSafe(member, "promote") and "p" or "")
    return table.concat({ "S", member.name, flags, stamp }, SEP), stamp
end

-- Officer records (Officers.lua): leave, trial votes, strikes, whispered requests, handled marks.
local function loaRecord(member)
    local stamp = GL:StampOf(member, "loa")
    if stamp == 0 then return nil end
    local loa = member.loa
    return table.concat({ "L", member.name, loa and loa.till or 0, string.sub(clean(loa and loa.reason), 1, 80), clean(loa and loa.by), stamp }, SEP), stamp
end

local function trialRecord(member, officer)
    local stamp = GL:StampOf(member, "trial." .. officer)
    if stamp == 0 then return nil end
    local vote = member.trial and member.trial.votes and member.trial.votes[officer]
    return table.concat({ "T", member.name, officer, vote and vote.v or "", string.sub(clean(vote and vote.text), 1, 100), stamp }, SEP), stamp
end

local function strikeRecord(member, id)
    local strike
    for _, s in ipairs(member.strikes or {}) do if s.id == id then strike = s end end
    if not strike then return nil end
    local stamp = GL:StampOf(member, "strike." .. id)
    return table.concat({ "W", member.name, id, strike.t, clean(strike.by), string.sub(clean(strike.text), 1, 120), strike.gone or 0, clean(strike.goneBy), stamp }, SEP), stamp
end

local function requestRecord(guild, name, tomb)
    local request = guild.requests and guild.requests[name]
    if not request then
        local stamp = tomb or GL:Now()
        return table.concat({ "R", name, "", "", "", 0, stamp }, SEP), stamp
    end
    return table.concat({ "R", name, request.kind, clean(request.value), string.sub(clean(request.text), 1, 100), request.t or 0, request.stamp or 0 }, SEP), request.stamp or 0
end

local function handledRecord(guild, key)
    local mark = guild.handled and guild.handled[key]
    if not mark then return table.concat({ "K", clean(key), "", 0 }, SEP), 0 end
    return table.concat({ "K", clean(key), clean(mark.by), mark.t or 0 }, SEP), mark.t or 0
end

-- Shares one changed record with everyone online right away. kind: J P G B C D S L T W R K
function Sync:Share(guild, kind, member, name)
    if not enabled() then return end
    local message
    if kind == "J" then message = member and joinRecord(member)
    elseif kind == "P" then message = member and promoRecord(member)
    elseif kind == "G" then message = member and groupRecord(guild, member)
    elseif kind == "M" then message = mineRecord(guild)
    elseif kind == "N" then message = member and weekRecord(member)
    elseif kind == "B" then message = banRecord(guild, name)
    elseif kind == "C" then message = member and noteRecord(member)
    elseif kind == "D" then message = member and birthdayRecord(member)
    elseif kind == "S" then message = member and safeRecord(member)
    elseif kind == "L" then message = member and loaRecord(member)
    elseif kind == "T" then message = member and name and trialRecord(member, name)
    elseif kind == "W" then message = member and name and strikeRecord(member, name)
    elseif kind == "R" then message = name and requestRecord(guild, name)
    elseif kind == "K" then message = name and handledRecord(guild, name) end
    if message then self:Push(message, "GUILD") end
end

-- Sends what we know to one person (whisper) or to the guild: everything when `since` is nil or 0, otherwise
-- only records set after `since`. Several records travel in one message, up to the message size limit.
-- Inside an instance the exchange is held and sent on the way out.
function Sync:SendAll(guild, target, since)
    if inInstance() and target then
        self.held[target] = math.min(self.held[target] or math.huge, since or 0)
        return 0, true
    end
    since = (since or 0) > 0 and (since - SINCE_SLACK) or 0
    local channel = target and "WHISPER" or "GUILD"
    local count, buffer = 0, {}
    local function flush()
        if #buffer > 0 then self:Push(table.concat(buffer, RSEP), channel, target, true) buffer = {} end
    end
    local function add(message, stamp)
        if not message or (stamp or 0) <= since and since > 0 then return end
        count = count + 1
        local size = #message
        for _, part in ipairs(buffer) do size = size + #part + 1 end
        if size > MAX_MESSAGE then flush() end
        buffer[#buffer + 1] = message
    end
    local sentGroups = {}
    for _, set in ipairs({ guild.members, guild.former }) do
        for _, member in pairs(set) do
            add(joinRecord(member))
            add(promoRecord(member))
            add(noteRecord(member))
            add(birthdayRecord(member))
            add(safeRecord(member))
            add(loaRecord(member))
            if member.trial and member.trial.votes then
                for officer in pairs(member.trial.votes) do add(trialRecord(member, officer)) end
            end
            for _, strike in ipairs(member.strikes or {}) do add(strikeRecord(member, strike.id)) end
            local group = GL:GroupOf(guild, member)
            if not group then
                add(groupRecord(guild, member))                    -- tombstone, if the member was ever grouped
            elseif not sentGroups[group] then
                sentGroups[group] = true
                add(groupRecord(guild, member))
            end
        end
    end
    for name in pairs(guild.bans) do add(banRecord(guild, name)) end
    for name in pairs(guild.requests or {}) do add(requestRecord(guild, name)) end
    for key in pairs(guild.handled or {}) do add(handledRecord(guild, key)) end
    if count > 0 then
        local total = count
        add(table.concat({ "E", total }, SEP), math.huge)
        count = total
        flush()
    end
    return count, false
end

-- Sends the exchanges held back while inside an instance.
function Sync:ReleaseHeld()
    if inInstance() or not next(self.held) then return end
    local guild = GL:Guild()
    local held = self.held
    self.held = {}
    if not guild then return end
    for target, since in pairs(held) do
        if guild.members[target] and guild.members[target].online ~= false then self:SendAll(guild, target, since) end
    end
end

-- The time this character's ledger last ran before this session; records newer than this are what we may
-- have missed. Captured once, before this session starts updating it.
function Sync:Since(guild)
    if self.since == nil then self.since = guild and guild.lastRun or 0 end
    return self.since
end

-- Hello: announces this user and asks everyone for the records newer than our last run (`ask` asks for all).
function Sync:Hello(ask, target)
    if not enabled() then return end
    local guild = GL:Guild()
    if not guild then return end
    local since = ask and 0 or self:Since(guild)
    self:Push(table.concat({ "H", GL.version, ask and 1 or 0, since, PROTO }, SEP), target and "WHISPER" or "GUILD", target)
end

-- Receiving -------------------------------------------------------------------------------------------------
local function number(text) return tonumber(text) or 0 end

local function apply(guild, fields, sender)
    local kind = fields[1]
    local wasQuiet, wasRemote = GL.quiet, GL.remote
    GL.quiet, GL.remote = true, true   -- shared records are never announced in chat nor shared again
    local ok, err = pcall(function()
        if kind == "J" then
            local name, t, source, stamp = fields[2], number(fields[3]), fields[4], number(fields[5])
            if not GL.SOURCE_RANK[source or ""] or source == "first" then source = "sync" end
            local member = GL:Member(guild, name)
            if member and t > 0 and GL:SetJoinDate(guild, name, t, source, false, stamp) then member.joinedVia = sender end
        elseif kind == "P" then
            local name, t, source, stamp = fields[2], number(fields[3]), fields[4], number(fields[5])
            if not GL.SOURCE_RANK[source or ""] or source == "first" then source = "sync" end
            local member = GL:Member(guild, name)
            if member and t > 0 and GL:SetPromotedDate(guild, name, t, source, false, stamp) then member.promotedVia = sender end
        elseif kind == "G" then
            local mainName, altText, stamp = fields[2], fields[3] or "", number(fields[4])
            local main = GL:Member(guild, mainName)
            if main then
                -- accept when newer than everything we have about the characters involved
                local newest = GL:StampOf(main, "group")
                local alts = {}
                for altName in string.gmatch(altText, "[^,]+") do
                    local alt = GL:Member(guild, altName)
                    if alt then alts[#alts + 1] = alt; newest = math.max(newest, GL:StampOf(alt, "group")) end
                end
                if stamp > newest then
                    if GL:IsAlt(guild, main) then GL:Unlink(guild, main, "sync", stamp) end
                    GL:SetMain(guild, main, "sync", stamp)
                    for _, alt in ipairs(alts) do
                        if alt ~= main then
                            local group = GL:GroupOf(guild, alt)
                            if group and group ~= GL:GroupOf(guild, main) then GL:Unlink(guild, alt, "sync", stamp) end
                            GL:LinkAlt(guild, alt, main, "sync", stamp)
                        end
                    end
                end
            end
        elseif kind == "X" then
            local member, stamp = GL:Member(guild, fields[2]), number(fields[3])
            if member and stamp > GL:StampOf(member, "group") then
                if GL:GroupOf(guild, member) then GL:Unlink(guild, member, "sync", stamp) else GL:Stamp(member, "group", stamp) end
            end
        elseif kind == "B" then
            local name, t, by, reason, class, stamp, lifted, liftedBy = fields[2], number(fields[3]), fields[4], fields[5], fields[6], number(fields[7]), number(fields[8]), fields[9]
            local ban = guild.bans[name]
            if not ban or (ban.stamp or 0) < stamp then
                if lifted > 0 then
                    if not ban then guild.bans[name] = { t = t, by = by, reason = reason, class = class ~= "" and class or nil, stamp = stamp } end
                    if not guild.bans[name].lifted then GL:Unban(guild, name, "sync", liftedBy, stamp) end
                    guild.bans[name].lifted = lifted
                else
                    if ban and ban.lifted then ban.lifted, ban.liftedBy = nil, nil end
                    GL:Ban(guild, name, reason, "sync", by, t, stamp)
                    if guild.bans[name] and class ~= "" then guild.bans[name].class = guild.bans[name].class or class end
                end
                if guild.bans[name] then guild.bans[name].via = sender end
            end
        elseif kind == "C" then
            local member, text, by, stamp = GL:Member(guild, fields[2]), fields[3], fields[4], number(fields[5])
            if member then GL:SetCustomNote(guild, member, text, "sync", by, stamp) end
        elseif kind == "D" then
            local member, m, d, stamp = GL:Member(guild, fields[2]), number(fields[3]), number(fields[4]), number(fields[5])
            if member then GL:SetBirthday(guild, member, m > 0 and m or nil, d > 0 and d or nil, "sync", stamp) end
        elseif kind == "S" then
            local member, flags, stamp = GL:Member(guild, fields[2]), fields[3] or "", number(fields[4])
            if member and stamp > GL:StampOf(member, "safe") then
                GL:SetSafe(guild, member, "kick", string.find(flags, "k", 1, true) ~= nil, "sync", stamp)
                GL:SetSafe(guild, member, "promote", string.find(flags, "p", 1, true) ~= nil, "sync", stamp)
            end
        elseif kind == "L" then
            local member, till, reason, by, stamp = GL:Member(guild, fields[2]), number(fields[3]), fields[4], fields[5], number(fields[6])
            if member and GL.SetLOA then GL:SetLOA(guild, member, till, reason, "sync", by ~= "" and by or nil, stamp) end
        elseif kind == "T" then
            local member, officer, vote, text, stamp = GL:Member(guild, fields[2]), fields[3], fields[4], fields[5], number(fields[6])
            if member and officer and officer ~= "" and GL.SetTrialVote then GL:SetTrialVote(guild, member, vote ~= "" and tonumber(vote) or nil, text, "sync", officer, stamp) end
        elseif kind == "W" then
            local member, id, t, by, text, gone, goneBy, stamp = GL:Member(guild, fields[2]), fields[3], number(fields[4]), fields[5], fields[6], number(fields[7]), fields[8], number(fields[9])
            if member and id and id ~= "" and GL.AddStrike then
                local have = GL:StampOf(member, "strike." .. id)
                if have == 0 or stamp > have then
                    GL:AddStrike(guild, member, text, "sync", by, t, stamp, id)   -- no-op when we already have it
                    local strike
                    for _, s in ipairs(member.strikes or {}) do if s.id == id then strike = s end end
                    if strike then
                        if gone > 0 and not strike.gone then strike.gone, strike.goneBy = gone, goneBy ~= "" and goneBy or nil end
                        GL:Stamp(member, "strike." .. id, stamp)
                    end
                end
            end
        elseif kind == "R" then
            local name, rkind, value, text, t, stamp = fields[2], fields[3], fields[4], fields[5], number(fields[6]), number(fields[7])
            if name and GL:Member(guild, name) and GL.SetRequest then GL:SetRequest(guild, name, rkind ~= "" and rkind or nil, value, text, t > 0 and t or nil, "sync", stamp) end
        elseif kind == "K" then
            local key, by, t = fields[2], fields[3], number(fields[4])
            if key and key ~= "" and GL.MarkHandled then
                if t > 0 then GL:MarkHandled(guild, key, "sync", by, t)
                elseif guild.handled then guild.handled[key] = nil end
            end
        elseif kind == "E" then
            local count = number(fields[2])
            guild.lastSync = { from = sender, t = GL:Now(), count = count }
            if count > 0 and GL.settings.syncReport ~= false then GL:Print(string.format("received %d %s from %s.", count, count == 1 and "record" or "records", sender)) end
        end
    end)
    GL.quiet, GL.remote = wasQuiet, wasRemote
    if not ok then GL:Print("could not apply a shared record from " .. tostring(sender) .. ": " .. tostring(err)) end
end

local function onMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or not enabled() then return end
    if channel ~= "GUILD" and channel ~= "WHISPER" then return end
    sender = GL:ShortName(sender)
    if not sender or sender == GL:PlayerName() then return end
    local guild = GL:Guild()
    if not guild or not guild.seeded then return end
    if not guild.members[sender] then return end   -- not one of ours
    local records = {}
    for record in string.gmatch(message .. RSEP, "(.-)" .. RSEP) do if record ~= "" then records[#records + 1] = record end end
    local first = split(records[1] or "")
    local peer = guild.peers[sender]
    if first[1] == "H" then
        local version, asked, since, proto = first[2] or "?", first[3] == "1", number(first[4]), first[5] or "1"
        local now = GetTime()
        guild.peers[sender] = { version = version, proto = proto, t = GL:Now() }
        if proto == PROTO and (asked or (now - (Sync.answered[sender] or -HELLO_GAP)) >= HELLO_GAP) then
            Sync.answered[sender] = now
            -- introduce ourselves back: always to a guild-wide hello, once to a whispered one
            if channel == "GUILD" or not peer then Sync:Hello(false, sender) end
            if trusted(guild, GL:PlayerName()) then Sync:SendAll(guild, sender, asked and 0 or since) end
        end
        if GL.OnLedgerChanged then GL:OnLedgerChanged(guild) end
        return
    end
    if first[1] == "N" then
        -- a newcomer's first-week flags: harmless, so taken from any Tabard user
        if peer and peer.proto ~= PROTO then return end
        if GL.ApplyFirstWeek then pcall(GL.ApplyFirstWeek, GL, guild, first[2], first[3], first[4], first[5], first[6], first[7]) end
        if GL.OnLedgerChanged then GL:OnLedgerChanged(guild) end
        return
    end
    if first[1] == "M" then
        -- "these characters are mine": taken from any member, it only concerns the sender's own characters
        if peer and peer.proto ~= PROTO then return end
        if GL.ApplyClaimedCharacters then pcall(GL.ApplyClaimedCharacters, GL, guild, sender, first[2] or "", number(first[3])) end
        if GL.OnLedgerChanged then GL:OnLedgerChanged(guild) end
        return
    end
    if not trusted(guild, sender) then return end                       -- rank is re-checked on every message
    if peer and peer.proto ~= PROTO then return end                      -- another wire format
    if not peer then Sync:Hello(false, sender) end                       -- never met: say hello so both sides learn versions
    for _, record in ipairs(records) do apply(guild, split(record), sender) end
    if GL.OnLedgerChanged then GL:OnLedgerChanged(guild) end
end

-- Last-run bookkeeping: the guild record remembers when this character's ledger was last running so that the
-- next session can ask only for what happened since.
noteRunning = function()
    local guild = GL.db and IsInGuild() and GL:Guild()
    if not guild then return end
    Sync:Since(guild)                 -- capture the previous value before overwriting it
    guild.lastRun = GL:Now()
end

frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        ensureRegistered()
    elseif event == "PLAYER_LOGOUT" then
        pcall(noteRunning)
    elseif event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_END" then
        Sync:Resume()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Sync:Resume()
        C_Timer.After(10, function() pcall(Sync.ReleaseHeld, Sync) end)
    elseif event == "CHAT_MSG_ADDON" then
        local ok, err = pcall(onMessage, ...)
        if not ok then GL:Print("sync error: " .. tostring(err)) end
    end
end)

-- Who else in the guild runs Tabard (seen this session or saved from earlier).
function Sync:Peers(guild)
    local list = {}
    for name, info in pairs(guild.peers or {}) do
        list[#list + 1] = { name = name, version = info.version, t = info.t, member = GL:Member(guild, name) }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- One line for the status command and the Overview page.
function Sync:Status()
    local parts = { string.format("queue %d", #self.queue) }
    if self.state ~= "idle" and self.state ~= "sending" then parts[#parts + 1] = self.state end
    if next(self.held) then parts[#parts + 1] = string.format("%d exchange%s held until outside", GL:Count(self.held), GL:Count(self.held) == 1 and "" or "s") end
    if self.dropped > 0 then parts[#parts + 1] = string.format("%d dropped", self.dropped) end
    return table.concat(parts, ", ")
end
