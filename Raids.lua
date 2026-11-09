-- Tabard: raid sessions and attendance
-- A session opens when the player is in a raid group inside a raid instance (or the first boss pull) and
-- closes when the group breaks up, the player leaves the instance for half an hour, or logs out. While it is
-- open, every roster change and every pull records who is there; each person is credited to their main.
-- Officers can mark people as benched or excused, which counts as attendance. Loot that the client reports
-- per boss is kept with the session. Attendance over 30/60/90 days feeds the promotion and removal lists.
--
-- guild.raids[id] = { id, start, stop, zone, size, pulls = { { t, name, id, kill, present = {names} } },
--   members = { [name] = { first, last, pulls, kills, main, bench, excused, reason } }, loot = { { t, who, link, boss } } }

local ADDON_NAME, GL = ...

local Raids = {}
GL.Raids = Raids

local DAY = 86400
local IDLE_CLOSE = 30 * 60        -- seconds outside the instance / group before the session closes
local MIN_PLAYERS = 5             -- smaller groups are not raids
local LATE_AFTER = 15 * 60        -- joining this long after the first pull counts as late
local KEEP_DAYS = 180             -- sessions older than this are dropped at login

local current, lastInside, pendingCheck = nil, nil, false

local function setting(key, default)
    local value = GL.settings and GL.settings[key]
    if value == nil then
        if GL.settings then GL.settings[key] = default end
        return default
    end
    return value
end

local function raids(guild)
    if type(guild.raids) ~= "table" then guild.raids = {} end
    return guild.raids
end

-- Where we are: in a raid group, and in a raid instance?
local function inRaidGroup()
    if IsInRaid and IsInRaid() then return true end
    return (GetNumGroupMembers and GetNumGroupMembers() or 0) >= MIN_PLAYERS
end

local function inRaidInstance()
    if not IsInInstance then return false, nil end
    local inside, kind = IsInInstance()
    return inside and kind == "raid", kind
end

-- Names in the group right now (bare names), with class when known.
local function groupNames()
    local names = {}
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    if count == 0 then return names end
    if GetRaidRosterInfo then
        for i = 1, count do
            local name, _, _, _, _, class, _, online = GetRaidRosterInfo(i)
            if GL:IsUsable(name) and type(name) == "string" then
                names[#names + 1] = { name = GL:ShortName(name), class = GL:IsUsable(class) and class or nil, online = online }
            end
        end
    end
    if #names == 0 and UnitName then
        local me = GL:PlayerName()
        names[#names + 1] = { name = me, online = true }
    end
    return names
end

-- Session lifecycle --------------------------------------------------------------------------------------
local function newSession(guild, now)
    local zone = GetInstanceInfo and select(1, GetInstanceInfo()) or (GetZoneText and GetZoneText()) or "?"
    if not GL:IsUsable(zone) then zone = "?" end
    local id = string.format("%d", now)
    local session = { id = id, start = now, zone = zone, size = 0, pulls = {}, members = {}, loot = {} }
    raids(guild)[id] = session
    guild.lastRaid = id
    return session
end

function Raids:Current(guild)
    if current and guild and raids(guild)[current.id] == current then return current end
    return nil
end

-- Records who is present; `pull` is the pull record to attach the list to, if any.
function Raids:Snapshot(guild, session, now, pull)
    local present = {}
    for _, entry in ipairs(groupNames()) do
        if entry.online ~= false then
            present[#present + 1] = entry.name
            local record = session.members[entry.name]
            if not record then
                local member = guild.members[entry.name]
                local main = member and GL:MainOf(guild, member)
                record = { first = now, last = now, pulls = 0, kills = 0, main = main and main.name or nil, class = entry.class or (member and member.class) }
                session.members[entry.name] = record
                if #session.pulls > 0 and now - session.pulls[1].t > LATE_AFTER then record.late = now - session.pulls[1].t end
            end
            record.last = now
            if pull then
                record.pulls = record.pulls + 1
                if pull.kill then record.kills = record.kills + 1 end
            end
        end
    end
    if pull then pull.present = present end
    session.size = math.max(session.size or 0, #present)
    return present
end

function Raids:Open(guild, now)
    if current then return current end
    local session = newSession(guild, now)
    current = session
    self:Snapshot(guild, session, now)
    GL:Print(string.format("raid session started in %s with %d in the group.", session.zone, session.size))
    if GL.OnLedgerChanged then GL:OnLedgerChanged(guild) end
    return session
end

function Raids:Close(guild, now, why)
    local session = current
    if not session then return end
    current = nil
    session.stop = now
    if session.size < MIN_PLAYERS and #session.pulls == 0 then
        raids(guild)[session.id] = nil   -- never became a raid
        return
    end
    local kills = 0
    for _, pull in ipairs(session.pulls) do if pull.kill then kills = kills + 1 end end
    GL:Print(string.format("raid session in %s closed (%s): %d people, %d pulls, %d kills.", session.zone, why or "ended", GL:Count(session.members), #session.pulls, kills))
    if GL.OnLedgerChanged then GL:OnLedgerChanged(guild) end
end

-- Called on every group/instance change and on a slow timer.
function Raids:Check(guild, now)
    if not guild then return end
    local insideRaid = inRaidInstance()
    local grouped = inRaidGroup()
    if insideRaid and grouped then lastInside = now end
    if current then
        if not grouped then
            self:Close(guild, now, "group ended")
        elseif not insideRaid and lastInside and now - lastInside > IDLE_CLOSE then
            self:Close(guild, now, "left the instance")
        else
            self:Snapshot(guild, current, now)
        end
    elseif insideRaid and grouped and setting("raidTracking", true) then
        self:Open(guild, now)
    end
end

-- Encounters ------------------------------------------------------------------------------------------------
function Raids:OnEncounterStart(guild, now, encounterID, name, difficulty, size)
    if not setting("raidTracking", true) then return end
    if not current then
        if not inRaidGroup() then return end
        self:Open(guild, now)
    end
    local pull = { t = now, id = encounterID, name = GL:IsUsable(name) and name or "?", size = size }
    current.pulls[#current.pulls + 1] = pull
    current.openPull = pull
    self:Snapshot(guild, current, now, pull)
end

function Raids:OnEncounterEnd(guild, now, encounterID, name, difficulty, size, success)
    if not current then return end
    local pull = current.openPull
    if pull and pull.id == encounterID then
        pull.stop, pull.kill = now, (success == 1 or success == true)
        if pull.kill then
            for _, who in ipairs(pull.present or {}) do
                local record = current.members[who]
                if record then record.kills = record.kills + 1 end
            end
        end
    end
    current.openPull = nil
    if GL.OnLedgerChanged then GL:OnLedgerChanged(guild) end
end

function Raids:OnLoot(guild, now, encounterID, itemID, itemLink, quantity, who)
    if not current or not GL:IsUsable(who) or type(who) ~= "string" then return end
    local boss
    for i = #current.pulls, 1, -1 do if current.pulls[i].id == encounterID then boss = current.pulls[i].name break end end
    current.loot[#current.loot + 1] = { t = now, who = GL:ShortName(who), link = GL:IsUsable(itemLink) and itemLink or ("item:" .. tostring(itemID)), boss = boss, n = quantity }
end

-- Bench and excused ------------------------------------------------------------------------------------------
-- kind: "bench" (ready but not in the group) or "excused" (told us beforehand); nil clears both.
function GL:SetRaidCredit(guild, session, name, kind, reason)
    if not (session and name) then return false end
    local record = session.members[name]
    if not record then
        local member = guild.members[name]
        local main = member and self:MainOf(guild, member)
        record = { first = self:Now(), last = self:Now(), pulls = 0, kills = 0, main = main and main.name or nil, class = member and member.class }
        session.members[name] = record
    end
    record.bench, record.excused = kind == "bench" or nil, kind == "excused" or nil
    record.reason = (kind and reason and reason ~= "") and reason or nil
    if not kind and record.pulls == 0 and not record.first then session.members[name] = nil end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

-- Attendance ------------------------------------------------------------------------------------------------
-- Sessions that count as a raid: enough people and at least one pull.
function GL:RaidSessions(guild, now, days)
    now = now or self:Now()
    local since = days and (now - days * DAY) or 0
    local list = {}
    for _, session in pairs(raids(guild)) do
        if session.start >= since and (session.size or 0) >= MIN_PLAYERS and #session.pulls > 0 then list[#list + 1] = session end
    end
    table.sort(list, function(a, b) return a.start > b.start end)
    return list
end

-- One row per main (or ungrouped character) with raids attended / held in the window.
-- bench and excused count as attended; "late" is counted separately.
function GL:Attendance(guild, now, days)
    now = now or self:Now()
    local sessions = self:RaidSessions(guild, now, days or 30)
    local held = #sessions
    local rows = {}
    local function rowFor(name)
        local row = rows[name]
        if not row then row = { name = name, member = self:Member(guild, name), attended = 0, benched = 0, late = 0, pulls = 0, kills = 0, chars = {} }; rows[name] = row end
        return row
    end
    for _, session in ipairs(sessions) do
        local credited = {}
        for charName, record in pairs(session.members) do
            local key = record.main or charName
            local row = rowFor(key)
            row.chars[charName] = true
            row.pulls = row.pulls + (record.pulls or 0)
            row.kills = row.kills + (record.kills or 0)
            if not credited[key] then
                credited[key] = true
                row.attended = row.attended + 1
                if record.bench or record.excused then row.benched = row.benched + 1 end
                if record.late then row.late = row.late + 1 end
            end
        end
    end
    local list = {}
    for _, row in pairs(rows) do
        row.held = held
        row.rate = held > 0 and (row.attended / held) or 0
        list[#list + 1] = row
    end
    table.sort(list, function(a, b) if a.attended ~= b.attended then return a.attended > b.attended end return a.name < b.name end)
    return list, held
end

-- Attendance of one member's group in the last `days` (0..1), or nil when no raids were held.
function GL:AttendanceOf(guild, member, now, days)
    local list, held = self:Attendance(guild, now, days)
    if held == 0 then return nil, 0 end
    local main = self:MainOf(guild, member)
    local key = main and main.name or member.name
    for _, row in ipairs(list) do if row.name == key then return row.rate, held, row end end
    return 0, held
end

-- Plain-text digest of one session (for the export page and the Discord outbox).
function GL:RaidDigest(guild, session)
    if not session then return "" end
    local lines = {}
    local kills, wipes = {}, 0
    for _, pull in ipairs(session.pulls) do
        if pull.kill then kills[#kills + 1] = pull.name else wipes = wipes + 1 end
    end
    lines[#lines + 1] = string.format("%s, %s (%s)", session.zone, self:FormatDate(session.start), session.stop and self:Span(session.stop - session.start) or "open")
    lines[#lines + 1] = string.format("%d pulls, %d kills, %d wipes", #session.pulls, #kills, wipes)
    if #kills > 0 then lines[#lines + 1] = "Killed: " .. table.concat(kills, ", ") end
    local present, bench, late = {}, {}, {}
    for name, record in pairs(session.members) do
        if record.bench or record.excused then bench[#bench + 1] = name .. (record.reason and (" (" .. record.reason .. ")") or "")
        else
            present[#present + 1] = name .. (record.main and record.main ~= name and (" (" .. record.main .. ")") or "")
            if record.late then late[#late + 1] = name end
        end
    end
    table.sort(present); table.sort(bench); table.sort(late)
    lines[#lines + 1] = string.format("Present (%d): %s", #present, table.concat(present, ", "))
    if #bench > 0 then lines[#lines + 1] = string.format("Bench/excused (%d): %s", #bench, table.concat(bench, ", ")) end
    if #late > 0 then lines[#lines + 1] = "Late: " .. table.concat(late, ", ") end
    if #session.loot > 0 then
        local items = {}
        for _, drop in ipairs(session.loot) do items[#items + 1] = drop.who .. ": " .. tostring(drop.link) .. (drop.boss and (" (" .. drop.boss .. ")") or "") end
        lines[#lines + 1] = "Loot: " .. table.concat(items, "; ")
    end
    return table.concat(lines, "\n")
end

-- Housekeeping ---------------------------------------------------------------------------------------------------
function Raids:Prune(guild, now)
    for id, session in pairs(raids(guild)) do
        if now - session.start > KEEP_DAYS * DAY or (session.stop and (session.size or 0) < MIN_PLAYERS and #session.pulls == 0) then guild.raids[id] = nil end
    end
end

-- Wiring --------------------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
for _, event in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "ENCOUNTER_LOOT_RECEIVED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_LOGIN" }) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
    local guild = GL.db and IsInGuild() and GL:Guild()
    if not guild then return end
    local now = GL:Now()
    local ok, err = pcall(function(...)
        if event == "ENCOUNTER_START" then Raids:OnEncounterStart(guild, now, ...)
        elseif event == "ENCOUNTER_END" then Raids:OnEncounterEnd(guild, now, ...)
        elseif event == "ENCOUNTER_LOOT_RECEIVED" then Raids:OnLoot(guild, now, ...)
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then pendingCheck = true
        elseif event == "PLAYER_LOGOUT" then Raids:Close(guild, now, "logged out")
        elseif event == "PLAYER_LOGIN" then Raids:Prune(guild, now) end
    end, ...)
    if not ok then GL:Print("raid tracking error: " .. tostring(err)) end
end)

local tick = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    tick = tick + elapsed
    if tick < 5 and not pendingCheck then return end
    if tick < 1 then return end
    tick, pendingCheck = 0, false
    local guild = GL.db and IsInGuild() and GL:Guild()
    if guild then
        local ok, err = pcall(Raids.Check, Raids, guild, GL:Now())
        if not ok then GL:Print("raid tracking error: " .. tostring(err)) end
    end
end)

function Raids:Command(rest)
    rest = string.lower(strtrim(rest or ""))
    local guild = GL:Guild()
    if not guild then GL:Print("you are not in a guild.") return end
    if rest == "on" or rest == "off" then
        GL.settings.raidTracking = rest == "on"
        GL:Print("raid tracking is " .. rest .. ".")
        return
    end
    if rest == "start" then self:Open(guild, GL:Now()) return end
    if rest == "stop" then self:Close(guild, GL:Now(), "stopped") return end
    local session = self:Current(guild) or (guild.lastRaid and raids(guild)[guild.lastRaid])
    if not session then GL:Print("no raid session recorded yet.") return end
    for line in string.gmatch(GL:RaidDigest(guild, session), "[^\n]+") do GL:Print(line) end
    local list, held = GL:Attendance(guild, nil, 30)
    GL:Print(string.format("attendance, last 30 days (%d raids): %s", held, (function()
        local parts = {}
        for i = 1, math.min(#list, 10) do parts[#parts + 1] = list[i].name .. " " .. list[i].attended .. "/" .. held end
        return table.concat(parts, ", ")
    end)()))
end
