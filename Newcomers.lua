-- Tabard: the first week, and who to play with right now
--
-- Most people who leave a new guild go in the first two weeks, usually because nobody talked to them. So for
-- seven days after a join a member is "new": Tabard counts their time online, notices whether they spoke in
-- guild chat, were named in it, grouped with a guildie or answered a whisper, and raises a To-do item when
-- someone has been on for half an hour and none of that has happened. Only flags and minutes are kept, never
-- message text.
--
-- The play-now finder is the other half: guildies online within a few levels of you, by zone, with the
-- dungeons that fit the band. Roster data only, so it works for every member, not just officers.

local ADDON_NAME, GL = ...

local NEW_DAYS = 7                 -- "new" for this long after the join
local KEEP_DAYS = 14               -- the first-week record is dropped after this
local ATTENTION_SECONDS = 30 * 60  -- online this long with nobody talking to them -> To-do
local LEVELS_GOAL = 3              -- "+3 levels" on the checklist
local MAX_STEP = 600               -- seconds credited per scan at most (scans are ~15 s apart, the heartbeat slower)

GL.PLAY_BAND = 4                   -- "near my level": within this many levels

-- Vanilla dungeons by the levels they suit. A dungeon "fits" when your level is inside its range.
GL.DUNGEONS = {
    { "Ragefire Chasm", 13, 18 }, { "Wailing Caverns", 17, 24 }, { "The Deadmines", 17, 26 }, { "Shadowfang Keep", 22, 30 },
    { "The Stockade", 22, 30 }, { "Blackfathom Deeps", 24, 32 }, { "Gnomeregan", 29, 38 }, { "Razorfen Kraul", 29, 38 },
    { "Scarlet Monastery", 30, 45 }, { "Razorfen Downs", 37, 46 }, { "Uldaman", 41, 51 }, { "Zul'Farrak", 44, 54 },
    { "Maraudon", 46, 55 }, { "Sunken Temple", 50, 60 }, { "Blackrock Depths", 52, 60 }, { "Dire Maul", 55, 60 },
    { "Lower Blackrock Spire", 55, 60 }, { "Scholomance", 58, 60 }, { "Stratholme", 58, 60 }, { "Upper Blackrock Spire", 58, 60 },
}

-- Newcomers ---------------------------------------------------------------------------------------------------
function GL:IsNewcomer(member, now)
    if not (member and type(member.joined) == "number") then return false end
    now = now or self:Now()
    return now - member.joined >= 0 and now - member.joined < NEW_DAYS * 86400
end

-- The first-week record: { on = seconds online, level0 = level at join, spoke, named, grouped, replied = times }
local function weekOf(member, create)
    local week = member.week
    if type(week) ~= "table" and create then
        week = { on = 0, level0 = member.level }
        member.week = week
    end
    return type(week) == "table" and week or nil
end

-- Called on a join: starts the record.
function GL:StartFirstWeek(member)
    if not member then return end
    member.week = { on = 0, level0 = member.level }
end

local function firstWord(name)
    return string.lower(string.match(name or "", "^(%S+)") or "")
end

local function escapePattern(text)
    return (string.gsub(text, "%W", "%%%0"))
end

-- After each roster read: credits time online to newcomers, drops old records.
function GL:TickFirstWeek(guild, now, sinceLast)
    if not guild then return end
    now = now or self:Now()
    local step = math.max(0, math.min(sinceLast or 0, MAX_STEP))
    for _, member in pairs(guild.members) do
        local week = weekOf(member)
        if week then
            if type(member.joined) ~= "number" or now - member.joined > KEEP_DAYS * 86400 then
                member.week = nil
            elseif member.online and step > 0 and self:IsNewcomer(member, now) then
                week.on = (week.on or 0) + step
            end
        end
    end
end

-- Flags ---------------------------------------------------------------------------------------------------------
local function flag(self, guild, member, key, now, by)
    local week = weekOf(member, true)
    if not week then return false end
    now = now or self:Now()
    local changed = week[key] == nil
    if changed then
        week[key] = now
        if by then week[key .. "By"] = by end
        if self.Sync and self.Sync.Share then pcall(self.Sync.Share, self.Sync, guild, "N", member) end
        if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    end
    return changed
end

-- A guild chat line: the sender spoke; any newcomer named in it was talked to.
function GL:NoteGuildChat(guild, sender, text, now)
    if not (guild and type(sender) == "string" and type(text) == "string") then return end
    if not (self:IsUsable(sender) and self:IsUsable(text)) then return end
    now = now or self:Now()
    local short = self:ShortName(sender)
    local speaker = guild.members[short]
    if speaker and self:IsNewcomer(speaker, now) then flag(self, guild, speaker, "spoke", now) end
    local lower = string.lower(text)
    for name, member in pairs(guild.members) do
        if name ~= short and member.week and self:IsNewcomer(member, now) and not member.week.named then
            local stem = firstWord(name)
            if #stem >= 3 and string.find(lower, "%f[%a]" .. escapePattern(stem) .. "%f[%A]") then
                flag(self, guild, member, "named", now, short)
            end
        end
    end
end

-- A whisper from a newcomer: they answered.
function GL:NoteWhisperFrom(guild, sender, now)
    if not (guild and type(sender) == "string" and self:IsUsable(sender)) then return end
    local member = guild.members[self:ShortName(sender)]
    if member and self:IsNewcomer(member, now) then flag(self, guild, member, "replied", now) end
end

-- Our party or raid changed: any newcomer in it has grouped with a guildie.
function GL:NoteGroup(guild, now)
    if not (guild and IsInGroup and IsInGroup()) then return end
    now = now or self:Now()
    local prefix, count = "party", GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
    if IsInRaid and IsInRaid() then prefix, count = "raid", GetNumGroupMembers and GetNumGroupMembers() or 0 end
    for i = 1, count do
        local name = self:UnitRosterName(prefix .. i)
        if name then
            local member = guild.members[name]
            if member and self:IsNewcomer(member, now) then flag(self, guild, member, "grouped", now, self:PlayerName()) end
        end
    end
end

-- Another Tabard user's flags for a newcomer, merged by "earliest wins" for times and "most" for minutes.
function GL:ApplyFirstWeek(guild, name, on, spoke, named, grouped, replied)
    local member = guild and guild.members[name]
    if not member then return false end
    local week = weekOf(member, true)
    local changed = false
    if (tonumber(on) or 0) > (week.on or 0) then week.on = tonumber(on) changed = true end
    for key, value in pairs({ spoke = spoke, named = named, grouped = grouped, replied = replied }) do
        local t = tonumber(value)
        if t and t > 0 and (week[key] == nil or t < week[key]) then week[key] = t changed = true end
    end
    return changed
end

-- Reading it back -----------------------------------------------------------------------------------------------
-- Has anyone talked to them (chat, whisper, group)?
function GL:NewcomerContacted(member)
    local week = weekOf(member)
    return week ~= nil and (week.spoke or week.named or week.grouped or week.replied) ~= nil
end

-- The checklist for a card or tooltip: { { label, done }, ... }
function GL:NewcomerChecklist(guild, member)
    local week = weekOf(member) or {}
    local welcomed = guild and type(guild.welcomed) == "table" and guild.welcomed[member.name] ~= nil
    local levels = (member.level or 0) - (week.level0 or member.level or 0)
    return {
        { "welcomed", welcomed }, { "spoke in guild chat", week.spoke ~= nil }, { "named in guild chat", week.named ~= nil },
        { "grouped with a guildie", week.grouped ~= nil }, { "answered a whisper", week.replied ~= nil },
        { "+" .. LEVELS_GOAL .. " levels", levels >= LEVELS_GOAL },
    }
end

function GL:NewcomerSummary(guild, member)
    local done, total, parts = 0, 0, {}
    for _, item in ipairs(self:NewcomerChecklist(guild, member)) do
        total = total + 1
        if item[2] then done = done + 1 parts[#parts + 1] = item[1] end
    end
    local week = weekOf(member)
    local minutes = week and math.floor((week.on or 0) / 60) or 0
    return done, total, parts, minutes
end

-- Newcomers, newest first. Each: { member, minutes, contacted, needsAttention }
function GL:Newcomers(guild, now)
    local list = {}
    if not guild then return list end
    now = now or self:Now()
    for _, member in pairs(guild.members) do
        if self:IsNewcomer(member, now) then
            local week = weekOf(member)
            local on = week and week.on or 0
            local contacted = self:NewcomerContacted(member)
            list[#list + 1] = { member = member, minutes = math.floor(on / 60), contacted = contacted, needsAttention = (not contacted) and on >= ATTENTION_SECONDS }
        end
    end
    table.sort(list, function(a, b) return (a.member.joined or 0) > (b.member.joined or 0) end)
    return list
end

-- Play now -------------------------------------------------------------------------------------------------------
-- Online members near a level, grouped by zone. AFK and DND players and anyone who asked not to be invited are
-- left out. around = { level, zone, name } (defaults to you); band = levels either side (nil = everyone online).
-- Returns groups { { zone, members = { member... } }, ... } sorted by size, then zone; members by level distance.
function GL:PlayNow(guild, around, band)
    local groups, byZone = {}, {}
    if not guild then return groups end
    around = around or {}
    local me = around.name or self:PlayerName()
    local level = around.level or (UnitLevel and UnitLevel("player")) or 0
    for name, member in pairs(guild.members) do
        if member.online and name ~= me and (member.status or 0) == 0 and not member.mobile and not member.noInvites
            and (not band or math.abs((member.level or 0) - level) <= band) then
            local zone = member.zone or "Somewhere"
            local group = byZone[zone]
            if not group then group = { zone = zone, members = {} } byZone[zone] = group groups[#groups + 1] = group end
            group.members[#group.members + 1] = member
        end
    end
    for _, group in ipairs(groups) do
        table.sort(group.members, function(a, b)
            local da, db = math.abs((a.level or 0) - level), math.abs((b.level or 0) - level)
            if da ~= db then return da < db end
            return a.name < b.name
        end)
    end
    local myZone = around.zone or (GetRealZoneText and GetRealZoneText()) or nil
    table.sort(groups, function(a, b)
        if myZone and (a.zone == myZone) ~= (b.zone == myZone) then return a.zone == myZone end
        if #a.members ~= #b.members then return #a.members > #b.members end
        return a.zone < b.zone
    end)
    return groups
end

-- Dungeons that fit a level (names, in order).
function GL:DungeonsFor(level)
    local names = {}
    level = tonumber(level) or 0
    for _, dungeon in ipairs(self.DUNGEONS) do
        if level >= dungeon[2] and level <= dungeon[3] then names[#names + 1] = dungeon[1] end
    end
    return names
end

-- The best online match for a member (a buddy for a newcomer): closest level, same zone first. nil when none.
function GL:BuddyFor(guild, member)
    if not (guild and member) then return nil end
    local groups = self:PlayNow(guild, { level = member.level, zone = member.zone, name = member.name }, self.PLAY_BAND)
    local best
    for _, group in ipairs(groups) do
        for _, other in ipairs(group.members) do
            if not self:IsNewcomer(other) and other.name ~= self:PlayerName() then
                local sameZone = member.zone ~= nil and other.zone == member.zone
                local distance = math.abs((other.level or 0) - (member.level or 0))
                local score = distance - (sameZone and 10 or 0)
                if not best or score < best.score then best = { member = other, score = score } end
            end
        end
    end
    return best and best.member or nil
end

-- How many guildies are online within the band of your level (for the minimap tooltip).
function GL:PlayNowCount(guild, band)
    local count = 0
    for _, group in ipairs(self:PlayNow(guild, nil, band or self.PLAY_BAND)) do count = count + #group.members end
    return count
end

-- Events --------------------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_GUILD")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(_, event, text, sender)
    if not GL.db or (GL.settings and GL.settings.firstWeek == false) then return end
    local guild = GL:Guild()
    if not guild then return end
    if event == "CHAT_MSG_GUILD" then
        pcall(GL.NoteGuildChat, GL, guild, sender, text)
    elseif event == "CHAT_MSG_WHISPER" then
        pcall(GL.NoteWhisperFrom, GL, guild, sender)
    elseif event == "GROUP_ROSTER_UPDATE" then
        pcall(GL.NoteGroup, GL, guild)
    end
end)
