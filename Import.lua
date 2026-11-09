-- Tabard: import from Guild Roster Manager's saved data
-- Reads the join dates, promotion dates, alt groups, ledger notes, birthdays and bans that this account's copy
-- of Guild Roster Manager recorded for the current guild, so nothing is lost when switching. Only the saved
-- data on this computer is read; nothing of the other addon's code is used or needed, and it does not have to
-- be loaded (saved variables of disabled addons are not available, so it must still be installed and enabled
-- for the one import).

local ADDON_NAME, GL = ...

local function epochOf(entry, dayIndex)
    -- entries look like { day, month, year, "YYYYMMDD", time the entry was written, verified, source }; the
    -- day/month/year is the date, the fifth field is only when it was recorded.
    if type(entry) ~= "table" then return nil end
    local day, month, year, written = entry[dayIndex], entry[dayIndex + 1], entry[dayIndex + 2], entry[dayIndex + 4]
    if type(day) == "number" and day > 0 and type(month) == "number" and month >= 1 and month <= 12 and type(year) == "number" and year > 2000 then
        return time({ year = year, month = month, day = day, hour = 12 })
    end
    if type(written) == "number" and written > 0 then return written end
    return nil
end

local function grmKey(guild)
    return guild.name .. "-" .. string.gsub(guild.realm or "", "%s", "")
end

-- GRM's alt groups for this guild, from its loaded saved data (nil when GRM is not running).
local function grmAltGroups(guild)
    local altGroups = rawget(_G, "GRM_Alts")
    if type(altGroups) ~= "table" then return nil end
    local key = grmKey(guild)
    if type(altGroups[key]) == "table" then return altGroups[key] end
    for k, v in pairs(altGroups) do
        if type(v) == "table" and string.sub(k, 1, #guild.name + 1) == guild.name .. "-" then return v end
    end
    return nil
end

-- Every few minutes while GRM is installed: any GRM group with two or more current members becomes a Tabard
-- group too, with GRM's main. Groups Tabard already has are left as they are; nothing is ever unlinked.
local lastLearn, lastLearnSignature = 0, nil
function GL:LearnFromGRM(guild, force)
    if not guild or (self.settings and self.settings.learnFromGRM == false) then return 0 end
    local now = self:Now()
    if not force and now - lastLearn < 300 then return 0 end
    lastLearn = now
    local groups = grmAltGroups(guild)
    if not groups then return 0 end
    local signature, sets = 0, {}
    for _, group in pairs(groups) do
        if type(group) == "table" then
            local names, main = {}, nil
            if type(group.main) == "string" then
                local mainName = self:ShortName(group.main)
                if guild.members[mainName] then main = mainName names[#names + 1] = mainName end
            end
            for _, entry in ipairs(group) do
                if type(entry) == "table" and type(entry.name) == "string" then
                    local name = self:ShortName(entry.name)
                    if guild.members[name] and name ~= main then names[#names + 1] = name end
                end
            end
            if #names >= 2 then sets[#sets + 1] = { names = names, main = main } signature = signature + #names end
        end
    end
    if not force and signature == lastLearnSignature then return 0 end
    lastLearnSignature = signature
    local wasQuiet = self.quiet
    self.quiet = true
    local stamp = now - 1
    local learned = 0
    for _, set in ipairs(sets) do
        local ok, changed = pcall(self.GroupTogether, self, guild, set.names, "import", stamp, set.main)
        if ok and changed then learned = learned + 1 end
    end
    self.quiet = wasQuiet
    if learned > 0 and self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return learned
end

-- Gathers what can be imported. Returns a plan table and a summary, or nil and a reason.
function GL:PlanGRMImport(guild)
    local history = rawget(_G, "GRM_GuildMemberHistory_Save")
    if type(history) ~= "table" then return nil, "no Guild Roster Manager data is loaded (it must be installed and enabled for the import)." end
    local key = grmKey(guild)
    local players = history[key]
    if type(players) ~= "table" then
        -- try any key starting with the guild name
        for k, v in pairs(history) do
            if type(v) == "table" and string.sub(k, 1, #guild.name + 1) == guild.name .. "-" then players, key = v, k end
        end
    end
    if type(players) ~= "table" then return nil, "Guild Roster Manager has no data for " .. guild.name .. "." end
    local leftPlayers = rawget(_G, "GRM_PlayersThatLeftHistory_Save")
    leftPlayers = type(leftPlayers) == "table" and leftPlayers[key] or {}
    local altGroups = rawget(_G, "GRM_Alts")
    altGroups = type(altGroups) == "table" and altGroups[key] or {}

    local plan = { joins = {}, promos = {}, notes = {}, birthdays = {}, bans = {}, groups = {}, unknown = {} }
    local function readPlayer(fullName, record, former)
        if type(record) ~= "table" or type(fullName) ~= "string" then return end
        local name = GL:ShortName(fullName)
        local member = former and guild.former[name] or guild.members[name]
        if not member then
            if not former then plan.unknown[#plan.unknown + 1] = name end
            return
        end
        local joinHist = record.joinDateHist
        if type(joinHist) == "table" and type(joinHist[1]) == "table" and joinHist[1][1] ~= 0 then
            local t = epochOf(joinHist[1], 1)
            if t and (not member.joined or (GL.SOURCE_RANK[member.joinedSource or ""] or 0) < GL.SOURCE_RANK.import) then
                plan.joins[#plan.joins + 1] = { name = name, t = t, former = former }
            end
        end
        local rankHist = record.rankHist
        if type(rankHist) == "table" and type(rankHist[1]) == "table" and rankHist[1][2] ~= 0 and (member.rankIndex or 0) > 0 then
            local t = epochOf(rankHist[1], 2)
            if t and not member.promoted then plan.promos[#plan.promos + 1] = { name = name, t = t, former = former } end
        end
        local custom = record.customNote
        if type(custom) == "table" and type(custom[4]) == "string" and custom[4] ~= "" and not member.custom then
            plan.notes[#plan.notes + 1] = { name = name, text = custom[4], by = type(custom[3]) == "string" and custom[3] ~= "" and GL:ShortName(custom[3]) or nil, former = former }
        end
        local birthday = record.birthdayInfo
        if type(birthday) == "table" and type(birthday.date) == "table" and not birthday.unknown and (birthday.date[1] or 0) > 0 and not member.birthday then
            plan.birthdays[#plan.birthdays + 1] = { name = name, d = birthday.date[1], m = birthday.date[2], former = former }
        end
        local ban = record.bannedInfo
        if type(ban) == "table" and ban[1] == true and not GL:IsBanned(guild, name) then
            plan.bans[#plan.bans + 1] = { name = name, t = type(ban[2]) == "number" and ban[2] > 0 and ban[2] or nil, reason = type(record.reasonBanned) == "string" and record.reasonBanned or "" }
        end
    end
    for fullName, record in pairs(players) do readPlayer(fullName, record, false) end
    for fullName, record in pairs(leftPlayers) do readPlayer(fullName, record, true) end
    for _, group in pairs(altGroups) do
        if type(group) == "table" then
            local main = type(group.main) == "string" and GL:Member(guild, GL:ShortName(group.main))
            local alts = {}
            for _, entry in ipairs(group) do
                if type(entry) == "table" and type(entry.name) == "string" then
                    local alt = GL:Member(guild, GL:ShortName(entry.name))
                    if alt and alt ~= main then alts[#alts + 1] = alt end
                end
            end
            if not main and #alts > 1 then main = table.remove(alts, 1) end
            if main and #alts > 0 then plan.groups[#plan.groups + 1] = { main = main, alts = alts } end
        end
    end
    local summary = string.format("%d join dates, %d promotion dates, %d alt groups, %d notes, %d birthdays, %d bans", #plan.joins, #plan.promos, #plan.groups, #plan.notes, #plan.birthdays, #plan.bans)
    return plan, summary
end

-- Applies the plan. Everything imported is stamped "import" so later game-log or typed-in dates still win.
function GL:ApplyGRMImport(guild, plan)
    if self.Backup then self:Backup(guild, "before GRM import") end
    local wasQuiet = self.quiet
    self.quiet = true
    local stamp = self:Now() - 1   -- older than anything set by hand from now on
    for _, item in ipairs(plan.joins) do self:SetJoinDate(guild, item.name, item.t, "import", false, stamp) end
    for _, item in ipairs(plan.promos) do self:SetPromotedDate(guild, item.name, item.t, "import", false, stamp) end
    for _, item in ipairs(plan.notes) do
        local member = self:Member(guild, item.name)
        if member then self:SetCustomNote(guild, member, item.text, "import", item.by or "import", stamp) end
    end
    for _, item in ipairs(plan.birthdays) do
        local member = self:Member(guild, item.name)
        if member then self:SetBirthday(guild, member, item.m, item.d, "import", stamp) end
    end
    for _, item in ipairs(plan.bans) do self:Ban(guild, item.name, item.reason, "import", "import", item.t, stamp) end
    for _, group in ipairs(plan.groups) do
        if not self:GroupOf(guild, group.main) then self:SetMain(guild, group.main, "import", stamp) end
        for _, alt in ipairs(group.alts) do self:LinkAlt(guild, alt, group.main, "import", stamp) end
    end
    self.quiet = wasQuiet
    guild.importedFromGRM = self:Now()
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
end

-- /tabard import [apply]
function GL:ImportFromGRM(apply)
    local guild = self:Guild()
    if not guild then self:Print("you are not in a guild.") return end
    if not guild.seeded then self:Print("the roster has not been read yet; try again in a few seconds.") return end
    local plan, summary = self:PlanGRMImport(guild)
    if not plan then self:Print(summary) return end
    if not apply then
        self:Print("Guild Roster Manager has " .. summary .. " that Tabard does not. Type |cffffffff/tabard import apply|r to bring them over.")
        if #plan.unknown > 0 then self:Print(#plan.unknown .. " names in its data are not in the current roster and are skipped.") end
        return
    end
    self:ApplyGRMImport(guild, plan)
    self:Print("imported " .. summary .. ".")
end
