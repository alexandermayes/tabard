-- Tabard: records officers keep by hand
-- Alt groups (one main, any number of alts), the ban list, ledger notes (private to Tabard users),
-- birthdays and "leave alone" flags for the recommendation lists. Every setter stamps the field so that
-- officers syncing with each other keep the newest value.

local ADDON_NAME, GL = ...

-- Only changes made here or seen on the roster become log lines; records arriving from another officer or
-- an import are applied silently (the other officer's ledger already has the line).
local function recordable(source)
    return source == nil or source == "user" or source == "scan"
end

-- Alt groups ------------------------------------------------------------------------------------------
function GL:GroupOf(guild, member)
    if not (guild and member and member.group) then return nil end
    local group = guild.groups[member.group]
    if not group then member.group = nil end
    return group
end

-- The main of a member's group (nil when the member is not in a group).
function GL:MainOf(guild, member)
    local group = self:GroupOf(guild, member)
    if not group then return nil end
    return self:Member(guild, group.main), group
end

-- The other characters in a member's group, mains first.
function GL:AltsOf(guild, member)
    local group = self:GroupOf(guild, member)
    local list = {}
    if not group then return list end
    for _, name in ipairs(group.alts) do
        if name ~= member.name then
            local other = self:Member(guild, name)
            if other then list[#list + 1] = other end
        end
    end
    if group.main ~= member.name then
        local main = self:Member(guild, group.main)
        if main then table.insert(list, 1, main) end
    end
    return list
end

function GL:IsMain(guild, member)
    local group = self:GroupOf(guild, member)
    return group ~= nil and group.main == member.name
end

function GL:IsAlt(guild, member)
    local group = self:GroupOf(guild, member)
    return group ~= nil and group.main ~= member.name
end

local function removeName(list, name)
    for i = #list, 1, -1 do
        if list[i] == name then table.remove(list, i) end
    end
end

local function newGroup(guild, mainName, t)
    guild.nextGroup = (guild.nextGroup or 0) + 1
    local id = tostring(guild.nextGroup)
    guild.groups[id] = { main = mainName, alts = {}, t = t }
    return id, guild.groups[id]
end

-- Takes a member out of their group; a group left with one character is dissolved.
function GL:Unlink(guild, member, source, stamp)
    local group = self:GroupOf(guild, member)
    if not group then return false end
    local id = member.group
    member.group = nil
    self:Stamp(member, "group", stamp)
    removeName(group.alts, member.name)
    if group.main == member.name then
        group.main = group.alts[1]
        if group.main then table.remove(group.alts, 1) end
    end
    if not group.main or (#group.alts == 0) then
        local last = group.main and self:Member(guild, group.main)
        if last then last.group = nil; self:Stamp(last, "group", stamp) end
        guild.groups[id] = nil
    else
        group.t = stamp or self:Now()
    end
    if source == "user" and self.Sync then self.Sync:Share(guild, "G", member) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

-- Makes `member` an alt of `mainMember`. If either is already grouped, the groups merge.
function GL:LinkAlt(guild, member, mainMember, source, stamp)
    if not (member and mainMember) or member == mainMember then return false end
    local now = stamp or self:Now()
    local mainGroup = self:GroupOf(guild, mainMember)
    local altGroup = self:GroupOf(guild, member)
    if mainGroup and altGroup == mainGroup then
        if mainGroup.main == member.name then return self:SetMain(guild, mainMember, source, stamp) end
        return false   -- already linked
    end
    if not mainGroup then
        local id
        id, mainGroup = newGroup(guild, mainMember.name, now)
        mainMember.group = id
        self:Stamp(mainMember, "group", stamp)
    end
    if altGroup then
        -- merge the alt's old group into the main's
        for _, name in ipairs(altGroup.alts) do
            local other = self:Member(guild, name)
            if other and other ~= member then
                other.group = mainMember.group
                self:Stamp(other, "group", stamp)
                mainGroup.alts[#mainGroup.alts + 1] = name
            end
        end
        local oldMain = altGroup.main ~= member.name and self:Member(guild, altGroup.main)
        if oldMain then
            oldMain.group = mainMember.group
            self:Stamp(oldMain, "group", stamp)
            mainGroup.alts[#mainGroup.alts + 1] = oldMain.name
        end
        for id, group in pairs(guild.groups) do if group == altGroup then guild.groups[id] = nil end end
    end
    member.group = mainMember.group
    self:Stamp(member, "group", stamp)
    removeName(mainGroup.alts, member.name)
    mainGroup.alts[#mainGroup.alts + 1] = member.name
    mainGroup.t = now
    if recordable(source) then self:AddEvent(guild, "alt", { who = member.name, to = mainMember.name, by = source == "user" and self:PlayerName() or nil, src = source or "user" }, now) end
    if source == "user" and self.Sync then self.Sync:Share(guild, "G", member) end
    return true
end

-- Makes a grouped character the main of its group.
function GL:SetMain(guild, member, source, stamp)
    local group = self:GroupOf(guild, member)
    if not group then
        local id
        id, group = newGroup(guild, member.name, stamp or self:Now())
        member.group = id
        self:Stamp(member, "group", stamp)
        return true
    end
    if group.main == member.name then return false end
    local oldMain = group.main
    removeName(group.alts, member.name)
    table.insert(group.alts, 1, oldMain)   -- first in line if the new main is ever unlinked
    group.main = member.name
    group.t = stamp or self:Now()
    for _, name in ipairs(group.alts) do
        local other = self:Member(guild, name)
        if other then self:Stamp(other, "group", stamp) end
    end
    self:Stamp(member, "group", stamp)
    if recordable(source) then self:AddEvent(guild, "main", { who = member.name, from = oldMain, by = source == "user" and self:PlayerName() or nil, src = source or "user" }, stamp) end
    if source == "user" and self.Sync then self.Sync:Share(guild, "G", member) end
    return true
end

-- Reads a public or officer note for "alt of Ooh", "Ooh's alt", "Ooh alt", "main: Ooh", "main Ooh", "(Ooh)" and links the
-- member to that main when the main is a known member. Returns the main when something was linked.
local ALT_PATTERNS = {
    "^alt of (.-)$", "^(.-)'s alt$", "^(.-) alt$", "^alt (.-)$", "^main:%s*(.-)$", "^main[%s%-=]+(.-)$", "^(.-)'s$", "^%((.-)%)$",
}

function GL:DetectAlt(guild, member)
    if self:GroupOf(guild, member) then return nil end
    for _, text in ipairs({ member.onote, member.note }) do
        if type(text) == "string" and text ~= "" then
            local lower = string.lower(strtrim(text))
            for _, pattern in ipairs(ALT_PATTERNS) do
                local who = string.match(lower, pattern)
                if who and who ~= "" and who ~= "alt" then
                    who = string.gsub(who, "[%.,;:!]+$", "")
                    local main = self:FindMember(guild, who, false, member)
                    if main and main ~= member and not (self:IsAlt(guild, main)) then
                        if self:LinkAlt(guild, member, main, "scan") then return main end
                    elseif main and main ~= member then
                        local realMain = self:MainOf(guild, main)
                        if realMain and self:LinkAlt(guild, member, realMain, "scan") then return realMain end
                    end
                end
            end
        end
    end
    return nil
end

-- Bans ---------------------------------------------------------------------------------------------------
function GL:IsBanned(guild, name)
    local ban = guild and guild.bans[name]
    if ban and not ban.lifted then return ban end
    return nil
end

-- Any ban that applies to this member: their own name, or one of their alts.
function GL:BanFor(guild, member)
    if not member then return nil end
    local own = self:IsBanned(guild, member.name)
    if own then return own, member.name end
    for _, other in ipairs(self:AltsOf(guild, member)) do
        local ban = self:IsBanned(guild, other.name)
        if ban then return ban, other.name end
    end
    return nil
end

function GL:Ban(guild, name, reason, source, by, t, stamp)
    local now = stamp or self:Now()
    local existing = guild.bans[name]
    if existing and not existing.lifted and source == "sync" and (existing.stamp or 0) >= now then return false end
    local member = self:Member(guild, name)
    guild.bans[name] = { t = t or now, by = by or self:PlayerName(), reason = reason or "", class = member and member.class or (existing and existing.class), guid = member and member.guid or (existing and existing.guid), stamp = now }
    self:AddEvent(guild, "ban", { who = name, by = guild.bans[name].by, text = reason, src = source or "user" }, t or now)
    if source == "user" and self.Sync then self.Sync:Share(guild, "B", nil, name) end
    return true
end

function GL:Unban(guild, name, source, by, stamp)
    local ban = guild.bans[name]
    if not ban or ban.lifted then return false end
    local now = stamp or self:Now()
    if source == "sync" and (ban.stamp or 0) >= now then return false end
    ban.lifted, ban.liftedBy, ban.stamp = now, by or self:PlayerName(), now
    self:AddEvent(guild, "unban", { who = name, by = ban.liftedBy, src = source or "user" }, now)
    if source == "user" and self.Sync then self.Sync:Share(guild, "B", nil, name) end
    return true
end

-- Ledger notes, birthdays, leave-alone flags ----------------------------------------------------------------
function GL:SetCustomNote(guild, member, text, source, by, stamp)
    text = type(text) == "string" and strtrim(text) or ""
    if source == "sync" and (stamp or 0) <= self:StampOf(member, "custom") then return false end
    if (member.custom or "") == text and source ~= "sync" then return false end
    member.custom, member.customBy = text ~= "" and text or nil, by or self:PlayerName()
    self:Stamp(member, "custom", stamp)
    if recordable(source) then self:AddEvent(guild, "custom", { who = member.name, to = text, by = member.customBy, src = source or "user" }, stamp) end
    if source == "user" and self.Sync then self.Sync:Share(guild, "C", member) end
    return true
end

-- A nickname belongs to the person, so it is kept on their main and shown after every character of theirs
-- (Hints.lua puts it after names in guild chat). Empty text clears it. Shared with the other officers.
function GL:SetNickname(guild, member, text, source, by, stamp)
    text = type(text) == "string" and strtrim(text) or ""
    if #text > 31 then text = string.sub(text, 1, 31) end
    if source ~= "sync" then
        local main = self.MainOf and self:MainOf(guild, member)
        if main then member = main end
    end
    if source == "sync" and (stamp or 0) <= self:StampOf(member, "nick") then return false end
    if (member.nick or "") == text and source ~= "sync" then return false end
    member.nick, member.nickBy = text ~= "" and text or nil, by or self:PlayerName()
    self:Stamp(member, "nick", stamp)
    if recordable(source) then self:AddEvent(guild, "nick", { who = member.name, to = text, by = member.nickBy, src = source or "user" }, stamp) end
    if source == "user" and self.Sync then self.Sync:Share(guild, "I", member) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

function GL:SetBirthday(guild, member, month, day, source, stamp)
    if source == "sync" and (stamp or 0) <= self:StampOf(member, "birthday") then return false end
    if month and day then member.birthday = { m = month, d = day } else member.birthday = nil end
    self:Stamp(member, "birthday", stamp)
    if recordable(source) then self:AddEvent(guild, "birthday", { who = member.name, text = month and self:FormatMonthDay(month, day) or "unknown", by = source == "user" and self:PlayerName() or nil, src = source or "user" }, stamp) end
    if source == "user" and self.Sync then self.Sync:Share(guild, "D", member) end
    return true
end

-- flag: "kick" | "promote"; leaves the member off that recommendation list.
function GL:SetSafe(guild, member, flag, value, source, stamp)
    if source == "sync" and (stamp or 0) <= self:StampOf(member, "safe") then return false end
    member.safe = member.safe or {}
    member.safe[flag] = value and true or nil
    if not next(member.safe) then member.safe = nil end
    self:Stamp(member, "safe", stamp)
    if source == "user" and self.Sync then self.Sync:Share(guild, "S", member) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

function GL:IsSafe(member, flag)
    return member and member.safe and member.safe[flag] == true
end
