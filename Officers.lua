-- Tabard: officer work
-- Leaves of absence, the trial workflow, strikes (a dated case file that expires), the officer to-do list
-- with "handled by", requests members send by whisper ("!main Zevya", "!bday 3/14", "!loa 12/1 holidays"),
-- and cohort / recruiter numbers. Everything an officer sets is stamped and shared like the other records.

local ADDON_NAME, GL = ...

local Officers = { replies = {} }
GL.Officers = Officers

local DAY = 86400
local HANDLED_KEEP = 30 * DAY     -- how long "handled" marks are remembered
local REQUEST_KEEP = 14 * DAY     -- how long an unanswered request waits

local function recordable(source)
    return source == nil or source == "user" or source == "scan"
end

local function shareable(self, source)
    return source == "user" and not self.remote and self.Sync ~= nil
end

local function setting(key, default)
    local value = GL.settings and GL.settings[key]
    if value == nil then
        if GL.settings then GL.settings[key] = default end
        return default
    end
    return value
end

-- Leave of absence ------------------------------------------------------------------------------------------
-- member.loa = { till, reason, by, t }. A member on leave is left off the removal list until the date passes;
-- after that they appear in the to-do list until someone clears the leave or they come back.
function GL:SetLOA(guild, member, till, reason, source, by, stamp)
    if not member then return false end
    if source == "sync" and (stamp or 0) <= self:StampOf(member, "loa") then return false end
    till = tonumber(till) or 0
    reason = type(reason) == "string" and strtrim(reason) or ""
    if till > 0 then
        member.loa = { till = till, reason = reason ~= "" and reason or nil, by = by or self:PlayerName(), t = stamp or self:Now() }
    else
        if not member.loa and source == "sync" then self:Stamp(member, "loa", stamp) return false end
        member.loa = nil
    end
    self:Stamp(member, "loa", stamp)
    if recordable(source) then
        local text = till > 0 and ("is on leave until " .. self:FormatDate(till) .. (reason ~= "" and (" (" .. reason .. ")") or ""))
            or "is back from leave"
        self:AddEvent(guild, "loa", { who = member.name, to = till > 0 and till or nil, text = text, by = by or self:PlayerName(), src = source or "user" }, stamp)
    end
    if shareable(self, source) then self.Sync:Share(guild, "L", member) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

function GL:OnLeave(member, now)
    if not (member and member.loa) then return false end
    return member.loa.till > (now or self:Now())
end

function GL:LeaveExpired(member, now)
    if not (member and member.loa) then return false end
    return member.loa.till <= (now or self:Now())
end

-- Trials ----------------------------------------------------------------------------------------------------
-- Members in the trial rank (settings.trialRank, else the newcomer rank) are reviewed after settings.trialDays.
-- Officers leave a vote (+1 / 0 / -1 with a few words); the outcome is whatever happens next (promotion or removal).
function GL:TrialRank(guild)
    local rank = self.settings.trialRank
    if rank and guild.ranks[rank] then return rank end
    return self:NewcomerRank(guild)
end

function GL:TrialRows(guild, now)
    now = now or self:Now()
    local rank = self:TrialRank(guild)
    local days = setting("trialDays", 14)
    local list = {}
    if not rank then return list end
    for _, member in pairs(guild.members) do
        if member.rankIndex == rank then
            local since = member.promoted or member.joined or member.firstSeen or now
            local votes, plus, minus, count = member.trial and member.trial.votes or {}, 0, 0, 0
            for _, vote in pairs(votes) do
                count = count + 1
                if vote.v > 0 then plus = plus + 1 elseif vote.v < 0 then minus = minus + 1 end
            end
            local elapsed = math.floor((now - since) / DAY)
            list[#list + 1] = { member = member, since = since, days = elapsed, due = elapsed >= days, votes = votes, plus = plus, minus = minus, count = count }
        end
    end
    table.sort(list, function(a, b) if a.due ~= b.due then return a.due end return a.since < b.since end)
    return list
end

-- vote: 1, 0, -1 or nil to withdraw. by: the voting officer (defaults to the player).
function GL:SetTrialVote(guild, member, vote, text, source, by, stamp)
    if not member then return false end
    by = by or self:PlayerName()
    local field = "trial." .. by
    if source == "sync" and (stamp or 0) <= self:StampOf(member, field) then return false end
    member.trial = member.trial or { votes = {} }
    text = type(text) == "string" and strtrim(text) or ""
    if vote == nil then
        member.trial.votes[by] = nil
        if not next(member.trial.votes) then member.trial = nil end
    else
        member.trial.votes[by] = { v = tonumber(vote) or 0, text = text ~= "" and text or nil, t = stamp or self:Now() }
    end
    self:Stamp(member, field, stamp)
    if recordable(source) then
        local label = vote == nil and "withdrew their trial vote" or ((vote > 0 and "+1" or vote < 0 and "-1" or "0") .. " on the trial" .. (text ~= "" and (": " .. text) or ""))
        self:AddEvent(guild, "trial", { who = member.name, text = label, by = by, src = source or "user" }, stamp)
    end
    if shareable(self, source) then self.Sync:Share(guild, "T", member, by) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

-- Strikes ---------------------------------------------------------------------------------------------------
-- member.strikes = { { id, t, by, text, gone }, ... }. A strike counts for settings.strikeDays (90) unless removed.
local function strikeById(member, id)
    for _, strike in ipairs(member.strikes or {}) do if strike.id == id then return strike end end
    return nil
end

function GL:AddStrike(guild, member, text, source, by, t, stamp, id)
    if not member then return false end
    text = type(text) == "string" and strtrim(text) or ""
    if text == "" then return false end
    by = by or self:PlayerName()
    t = t or stamp or self:Now()
    id = id or string.format("%x", t) .. string.sub(by, 1, 3)
    if strikeById(member, id) then return false end
    member.strikes = member.strikes or {}
    member.strikes[#member.strikes + 1] = { id = id, t = t, by = by, text = text }
    self:Stamp(member, "strike." .. id, stamp)
    if recordable(source) then self:AddEvent(guild, "strike", { who = member.name, text = "got a strike: " .. text, by = by, src = source or "user" }, t) end
    if shareable(self, source) then self.Sync:Share(guild, "W", member, id) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

function GL:RemoveStrike(guild, member, id, source, by, stamp)
    local strike = member and strikeById(member, id)
    if not strike then return false end
    if source == "sync" and (stamp or 0) <= self:StampOf(member, "strike." .. id) then return false end
    if strike.gone then return false end
    strike.gone, strike.goneBy = stamp or self:Now(), by or self:PlayerName()
    self:Stamp(member, "strike." .. id, stamp)
    if recordable(source) then self:AddEvent(guild, "strike", { who = member.name, text = "had a strike removed: " .. strike.text, by = strike.goneBy, src = source or "user" }, stamp) end
    if shareable(self, source) then self.Sync:Share(guild, "W", member, id) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

-- Strikes that still count, newest first.
function GL:Strikes(member, now)
    now = now or self:Now()
    local keep = setting("strikeDays", 90) * DAY
    local list = {}
    for _, strike in ipairs(member and member.strikes or {}) do
        if not strike.gone and (keep == 0 or now - strike.t < keep) then list[#list + 1] = strike end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

-- Requests sent by whisper ----------------------------------------------------------------------------------
-- A member whispers any officer running Tabard: "!main Zevya", "!bday 3/14", "!loa 12/1 holidays",
-- "!loa off". The request waits in guild.requests[name] until an officer approves or declines it; approving
-- applies it as if the officer had typed it. The reply whisper goes out on the officer's next click.
local HELP = "Tabard requests: !main <character> (link this character to your main), !bday <month/day>, !loa <date> [reason], !loa off."

function Officers:Parse(guild, name, text)
    local command, rest = string.match(text or "", "^%s*!(%a+)%s*(.-)%s*$")
    if not command then return nil end
    command = string.lower(command)
    if command == "main" then
        local main = rest ~= "" and GL:FindMember(guild, rest, false, guild.members[name])
        if not main then return { kind = "main", error = "no guild member called \"" .. rest .. "\"" } end
        return { kind = "main", value = main.name, text = "main " .. main.name }
    elseif command == "bday" or command == "birthday" then
        local m, d = GL:ParseMonthDay(rest)
        if not m then return { kind = "bday", error = "say the birthday as month/day, like !bday 3/14" } end
        return { kind = "bday", value = m .. "/" .. d, text = "birthday " .. GL:FormatMonthDay(m, d) }
    elseif command == "loa" or command == "away" then
        if string.lower(rest) == "off" or string.lower(rest) == "back" then return { kind = "loa", value = "0", text = "back from leave" } end
        local when, reason = string.match(rest, "^(%S+)%s*(.-)$")
        local t = when and GL:ParseDate(when)
        if not t then return { kind = "loa", error = "say the date you are back, like !loa 12/1 holidays" } end
        return { kind = "loa", value = tostring(t) .. (reason ~= "" and ("|" .. reason) or ""), text = "leave until " .. GL:FormatDate(t) .. (reason ~= "" and (" (" .. reason .. ")") or "") }
    elseif command == "help" or command == "ledger" then
        return { kind = "help" }
    end
    return nil
end

local function requestKey(name) return "request:" .. name end

function GL:SetRequest(guild, name, kind, value, text, t, source, stamp)
    guild.requests = guild.requests or {}
    local existing = guild.requests[name]
    if source == "sync" and existing and (existing.stamp or 0) >= (stamp or 0) then return false end
    if kind == nil or kind == "" then
        if not existing then return false end
        guild.requests[name] = nil
    else
        guild.requests[name] = { kind = kind, value = value, text = text, t = t or self:Now(), stamp = stamp or self:Now() }
        if guild.handled then guild.handled[requestKey(name)] = nil end
        if recordable(source) then self:AddEvent(guild, "request", { who = name, text = "asked for " .. tostring(text), src = source or "user" }, t) end
    end
    if source ~= "sync" and self.Sync then self.Sync:Share(guild, "R", nil, name) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

function GL:ApproveRequest(guild, name)
    local request = guild.requests and guild.requests[name]
    local member = self:Member(guild, name)
    if not (request and member) then return false end
    if request.kind == "main" then
        local main = self:Member(guild, request.value)
        if not main then return false end
        self:LinkAlt(guild, member, main, "user")
    elseif request.kind == "bday" then
        local m, d = string.match(request.value or "", "^(%d+)/(%d+)$")
        self:SetBirthday(guild, member, tonumber(m), tonumber(d), "user")
    elseif request.kind == "loa" then
        local till, reason = string.match(request.value or "0", "^(%d+)|?(.*)$")
        self:SetLOA(guild, member, tonumber(till), reason, "user", nil)
    end
    self:SetRequest(guild, name, nil, nil, nil, nil, "user")
    Officers:Reply(name, "Done: " .. tostring(request.text) .. ". (Tabard)")
    return true
end

function GL:DeclineRequest(guild, name, why)
    local request = guild.requests and guild.requests[name]
    if not request then return false end
    self:SetRequest(guild, name, nil, nil, nil, nil, "user")
    Officers:Reply(name, "Your request (" .. tostring(request.text) .. ") was not applied" .. (why and why ~= "" and (": " .. why) or "") .. ". (Tabard)")
    return true
end

-- Replies are chat, which this client only accepts from a click; they wait for the next one.
function Officers:Reply(name, text)
    if not (name and text) then return end
    self.replies[#self.replies + 1] = { name = name, text = string.sub(text, 1, 255) }
end

function Officers:Pump()
    if #self.replies == 0 then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local item = table.remove(self.replies, 1)
    pcall(GL.SendChat, GL, item.text, "WHISPER", item.name)
    return true
end

local function onWhisper(text, sender)
    if not setting("requests", true) then return end
    if not (GL:IsUsable(text) and GL:IsUsable(sender) and type(text) == "string") then return end
    if string.sub(text, 1, 1) ~= "!" then return end
    local guild = GL.db and GL:Guild()
    if not guild then return end
    local name = GL:ShortName(sender)
    if not name or not guild.members[name] then return end
    local request = Officers:Parse(guild, name, text)
    if not request then return end
    if request.kind == "help" then Officers:Reply(name, HELP) return end
    if request.error then Officers:Reply(name, "Sorry, " .. request.error .. ". " .. HELP) return end
    GL:SetRequest(guild, name, request.kind, request.value, request.text, GL:Now(), "user")
    Officers:Reply(name, "Got it: " .. request.text .. ". An officer will confirm it. (Tabard)")
    GL:Print(string.format("%s asked for %s (whisper); approve or decline it in the to-do list.", GL:ColoredName(guild.members[name]), request.text))
end

-- The to-do list ---------------------------------------------------------------------------------------------
-- Everything that wants an officer's eyes, with a stable key so one officer can mark it handled for everyone.
function GL:MarkHandled(guild, key, source, by, stamp)
    guild.handled = guild.handled or {}
    local existing = guild.handled[key]
    if source == "sync" and existing and (existing.t or 0) >= (stamp or 0) then return false end
    guild.handled[key] = { by = by or self:PlayerName(), t = stamp or self:Now() }
    if source ~= "sync" and self.Sync then self.Sync:Share(guild, "K", nil, key) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

function GL:ClearHandled(guild, key)
    if not (guild.handled and guild.handled[key]) then return false end
    guild.handled[key] = nil
    if self.Sync then self.Sync:Share(guild, "K", nil, key) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

function GL:TodoItems(guild, now)
    now = now or self:Now()
    local items = {}
    local handled = guild.handled or {}
    for key, mark in pairs(handled) do
        if now - (mark.t or 0) > HANDLED_KEEP then handled[key] = nil end
    end
    local function add(key, kind, member, text, since)
        items[#items + 1] = { key = key, kind = kind, member = member, text = text, since = since or now, handled = handled[key] }
    end
    if guild.partialScan then add("partial", "roster", nil, "Roster incomplete (" .. tostring(guild.partialScan) .. "); leaves are not being recorded", guild.lastScan) end
    for _, row in ipairs(self:TrialRows(guild, now)) do
        if row.due then add("trial:" .. row.member.name .. ":" .. math.floor(row.since), "trial", row.member, string.format("Trial review due (%d days, %d votes: +%d / -%d)", row.days, row.count, row.plus, row.minus), row.since) end
    end
    for _, member in pairs(guild.members) do
        if self:LeaveExpired(member, now) then
            add("loa:" .. member.name .. ":" .. member.loa.till, "loa", member, "Leave ended " .. self:FormatDate(member.loa.till) .. (member.online and ", online now" or (member.lastOnline and (", last seen " .. self:Ago(member.lastOnline, now)) or "")), member.loa.till)
        end
        local ban, bannedName = self:BanFor(guild, member)
        if ban then
            add("banned:" .. member.name, "banned", member, "On the ban list" .. (bannedName ~= member.name and (" (as " .. bannedName .. ")") or "") .. (ban.reason and ban.reason ~= "" and (": " .. ban.reason) or ""), member.joined or member.firstSeen)
        end
        if self:IsAlt(guild, member) then
            local main = self:MainOf(guild, member)
            if main and not guild.members[main.name] then add("orphan:" .. member.name, "orphan", member, "Alt of " .. main.name .. ", who is no longer in the guild", main.left) end
        end
    end
    local okAlts, suggestions = pcall(function() return self.AltSuggestions and self:AltSuggestions(guild, now) or {} end)
    if okAlts and type(suggestions) == "table" then
        for i, s in ipairs(suggestions) do
            if i > 25 then break end
            add("alts:" .. s.key, "altpair", s.member, "Probably an alt of " .. self:ColoredName(s.other) .. " (" .. s.reason .. ")", s.since)
            items[#items].other = s.other
        end
    end
    -- New members nobody has talked to after half an hour online, with a buddy near their level when one is on.
    if self.Newcomers then
        for _, row in ipairs(self:Newcomers(guild, now)) do
            if row.needsAttention then
                local text = "New this week, online " .. row.minutes .. " min and nobody has talked to them yet"
                local buddy = self.BuddyFor and self:BuddyFor(guild, row.member)
                if buddy then
                    text = text .. "; " .. self:ColoredName(buddy) .. " (" .. tostring(buddy.level or "?") .. (buddy.zone and (", " .. buddy.zone) or "") .. ") is on near their level"
                end
                add("new:" .. row.member.name, "newcomer", row.member, text, row.member.joined)
            end
        end
    end
    for name, request in pairs(guild.requests or {}) do
        if now - (request.t or 0) > REQUEST_KEEP then
            guild.requests[name] = nil
        else
            add(requestKey(name), "request", self:Member(guild, name), "Asked by whisper for " .. tostring(request.text), request.t)
        end
    end
    for _, row in ipairs(self:PromoteCandidates(guild, now)) do
        add("promote:" .. row.member.name .. ":" .. math.floor(now - row.waiting), "promote", row.member, "Promotion due (" .. self:Span(row.waiting) .. " in " .. tostring(row.member.rank) .. ")", now - row.waiting)
    end
    for i = #guild.events, math.max(1, #guild.events - 200), -1 do
        local event = guild.events[i]
        if now - event.t > 7 * DAY then break end
        if event.k == "back" and guild.members[event.who] then
            add("back:" .. event.who .. ":" .. event.t, "back", guild.members[event.who], "Back after " .. tostring(event.text or "a break") .. "; say hello", event.t)
        end
    end
    table.sort(items, function(a, b)
        if (a.handled ~= nil) ~= (b.handled ~= nil) then return a.handled == nil end
        return a.since < b.since
    end)
    return items
end

-- Cohorts and recruiters ------------------------------------------------------------------------------------------
local function leftAt(guild, name)
    local former = guild.former[name]
    return former and former.left or nil
end

-- Joins grouped by week, with how many were still in the guild 7, 14 and 30 days after joining.
-- Only joins old enough to judge count toward each column.
function GL:Cohorts(guild, now, weeks)
    now = now or self:Now()
    weeks = weeks or 8
    local since = now - weeks * 7 * DAY
    local byWeek = {}
    for _, event in ipairs(guild.events) do
        if (event.k == "join" or event.k == "rejoin") and event.t >= since and event.who then
            local week = date("%Y-%m-%d", event.t - ((tonumber(date("%w", event.t)) + 6) % 7) * DAY)   -- Monday
            local row = byWeek[week]
            if not row then row = { week = week, joined = 0, kept = { [7] = 0, [14] = 0, [30] = 0 }, judged = { [7] = 0, [14] = 0, [30] = 0 } }; byWeek[week] = row end
            row.joined = row.joined + 1
            local gone = guild.members[event.who] and nil or leftAt(guild, event.who)
            for _, d in ipairs({ 7, 14, 30 }) do
                if now - event.t >= d * DAY then
                    row.judged[d] = row.judged[d] + 1
                    if not gone or gone > event.t + d * DAY then row.kept[d] = row.kept[d] + 1 end
                end
            end
        end
    end
    local list = {}
    for _, row in pairs(byWeek) do list[#list + 1] = row end
    table.sort(list, function(a, b) return a.week > b.week end)
    return list
end

-- Who invites people who stay: invites in the last `days`, how many of those are still here after 14 days.
function GL:Recruiters(guild, now, days)
    now = now or self:Now()
    local since = now - (days or 90) * DAY
    local byName = {}
    for _, event in ipairs(guild.events) do
        if (event.k == "join" or event.k == "rejoin") and event.t >= since and event.who then
            local member = self:Member(guild, event.who)
            local by = event.by or (member and member.invitedBy)
            if by then
                local row = byName[by]
                if not row then row = { name = by, invites = 0, judged = 0, kept = 0, here = 0 }; byName[by] = row end
                row.invites = row.invites + 1
                if guild.members[event.who] then row.here = row.here + 1 end
                if now - event.t >= 14 * DAY then
                    row.judged = row.judged + 1
                    local gone = guild.members[event.who] and nil or leftAt(guild, event.who)
                    if not gone or gone > event.t + 14 * DAY then row.kept = row.kept + 1 end
                end
            end
        end
    end
    local list = {}
    for _, row in pairs(byName) do
        row.rate = row.judged > 0 and (row.kept / row.judged) or nil
        row.member = self:Member(guild, row.name)
        list[#list + 1] = row
    end
    table.sort(list, function(a, b) if a.invites ~= b.invites then return a.invites > b.invites end return a.name < b.name end)
    return list
end

-- Alt groups at odds with the rank ladder: an alt ranked above its main, or alts whose main is gone.
function GL:AltAudit(guild)
    local list = {}
    for _, member in pairs(guild.members) do
        if self:IsAlt(guild, member) then
            local main = self:MainOf(guild, member)
            if main and not guild.members[main.name] then
                list[#list + 1] = { member = member, main = main, problem = "main left the guild" }
            elseif main and member.rankIndex and main.rankIndex and member.rankIndex < main.rankIndex then
                list[#list + 1] = { member = member, main = main, problem = "ranked above their main (" .. tostring(main.rank) .. ")" }
            end
        end
    end
    table.sort(list, function(a, b) return a.member.name < b.member.name end)
    return list
end

-- Wiring ------------------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:SetScript("OnEvent", function(_, event, text, sender)
    if event == "CHAT_MSG_WHISPER" then
        local ok, err = pcall(onWhisper, text, sender)
        if not ok then GL:Print("could not read a whispered request: " .. tostring(err)) end
    end
end)
if WorldFrame and WorldFrame.HookScript then WorldFrame:HookScript("OnMouseDown", function() Officers:Pump() end) end
if ChatEdit_SendText and hooksecurefunc then hooksecurefunc("ChatEdit_SendText", function() Officers:Pump() end) end
for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local box = _G["ChatFrame" .. i .. "EditBox"]
    if box and box.HookScript then box:HookScript("OnEnterPressed", function() Officers:Pump() end) end
end

function Officers:Command(rest)
    rest = string.lower(strtrim(rest or ""))
    local guild = GL:Guild()
    if not guild then GL:Print("you are not in a guild.") return end
    if rest == "on" or rest == "off" then
        GL.settings.requests = rest == "on"
        GL:Print("whispered requests are " .. rest .. ".")
        return
    end
    local items = GL:TodoItems(guild)
    if #items == 0 then GL:Print("nothing on the to-do list.") return end
    GL:Print(#items .. " on the to-do list:")
    for i = 1, math.min(#items, 15) do
        local item = items[i]
        GL:Print(string.format("  %s%s: %s%s", item.member and GL:ColoredName(item.member) .. " - " or "", item.kind, item.text,
            item.handled and (" |cff888888(handled by " .. tostring(item.handled.by) .. ")|r") or ""))
    end
end
