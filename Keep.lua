-- Tabard: keeping the saved data in shape
-- One backup slot taken before anything that changes a lot at once (imports, mass actions, restores), a
-- housekeeping pass at login that trims old events and long-gone former members, and a size estimate so the
-- saved file never grows the way some guild addons' files do.

local ADDON_NAME, GL = ...

local DAY = 86400

local function setting(key, default)
    local value = GL.settings and GL.settings[key]
    if value == nil then
        if GL.settings then GL.settings[key] = default end
        return default
    end
    return value
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do copy[deepCopy(k, seen)] = deepCopy(v, seen) end
    return copy
end

-- Backup ------------------------------------------------------------------------------------------------------
function GL:Backup(guild, label)
    if not (self.db and guild) then return false end
    local key = self:GuildKey()
    self.db.backup = { t = self:Now(), label = label or "manual", key = key, guild = deepCopy(guild) }
    return true
end

function GL:BackupInfo()
    local backup = self.db and self.db.backup
    if not backup then return nil end
    return backup.t, backup.label, backup.key
end

-- Puts the backup back as the live ledger for its guild. The current data goes into the backup slot, so a
-- second restore undoes the first.
function GL:RestoreBackup()
    local backup = self.db and self.db.backup
    if not backup or not backup.guild then return false, "there is no backup" end
    local live = self.db.guilds[backup.key]
    self.db.guilds[backup.key] = deepCopy(backup.guild)
    self.db.backup = { t = self:Now(), label = "before restore", key = backup.key, guild = live }
    if self.OnLedgerChanged then self:OnLedgerChanged(self:Guild()) end
    return true
end

-- Housekeeping ----------------------------------------------------------------------------------------------
-- keepEventDays: events older than this are dropped (0 = keep everything); maxEvents: hard cap, oldest first.
-- Former members who left more than two years ago and are not banned are forgotten.
function GL:Housekeeping(guild, now)
    now = now or self:Now()
    local report = { events = 0, former = 0, seen = 0 }
    local keepDays = setting("keepEventDays", 365)
    local maxEvents = setting("maxEvents", 20000)
    local events = guild.events
    local cutoff = keepDays > 0 and (now - keepDays * DAY) or 0
    local kept = {}
    for _, event in ipairs(events) do
        if event.t >= cutoff then kept[#kept + 1] = event end
    end
    if maxEvents > 0 and #kept > maxEvents then
        local trimmed = {}
        for i = #kept - maxEvents + 1, #kept do trimmed[#trimmed + 1] = kept[i] end
        kept = trimmed
    end
    report.events = #events - #kept
    if report.events > 0 then guild.events = kept end
    for name, former in pairs(guild.former) do
        if former.left and now - former.left > 2 * 365 * DAY and not (guild.bans[name]) and not self:GroupOf(guild, former) then
            guild.former[name] = nil
            report.former = report.former + 1
        end
    end
    if self.Raids and self.Raids.Prune then self.Raids:Prune(guild, now) end
    return report
end

-- A rough size of the saved data in bytes (what the game will write), without serialising it.
local function sizeOf(value, seen)
    local kind = type(value)
    if kind == "string" then return #value + 3 end
    if kind == "number" then return 10 end
    if kind == "boolean" or kind == "nil" then return 6 end
    if kind ~= "table" then return 0 end
    seen = seen or {}
    if seen[value] then return 0 end
    seen[value] = true
    local total = 4
    for k, v in pairs(value) do total = total + sizeOf(k, seen) + sizeOf(v, seen) + 6 end
    return total
end

function GL:DBSize()
    if not self.db then return 0 end
    return sizeOf(self.db)
end

function GL:DBSizeText()
    local bytes = self:DBSize()
    if bytes > 1024 * 1024 then return string.format("%.1f MB", bytes / (1024 * 1024)) end
    return string.format("%d KB", math.floor(bytes / 1024))
end

-- Wiring --------------------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer.After(20, function()
        local guild = GL.db and IsInGuild() and GL:Guild()
        if not guild then return end
        local ok, report = pcall(GL.Housekeeping, GL, guild)
        if ok and (report.events > 0 or report.former > 0) then
            GL:Print(string.format("housekeeping: dropped %d old events and %d long-gone former members (saved data about %s).", report.events, report.former, GL:DBSizeText()))
        end
    end)
end)

function GL:KeepCommand(rest)
    rest = string.lower(strtrim(rest or ""))
    local guild = self:Guild()
    if rest == "backup" then
        if guild and self:Backup(guild, "manual") then self:Print("backup taken (" .. self:DBSizeText() .. " saved data).") end
    elseif rest == "restore" then
        local ok, err = self:RestoreBackup()
        self:Print(ok and "backup restored; the data from before the restore is now the backup." or ("could not restore: " .. tostring(err)))
    elseif rest == "tidy" then
        if guild then
            local report = self:Housekeeping(guild)
            self:Print(string.format("dropped %d old events and %d former members; saved data about %s.", report.events, report.former, self:DBSizeText()))
        end
    else
        local t, label = self:BackupInfo()
        self:Print(string.format("saved data about %s; backup: %s. Commands: /tabard backup, /tabard restore, /tabard tidy.", self:DBSizeText(), t and (label .. ", " .. self:FormatTime(t)) or "none"))
    end
end

-- One-time ledger repair ------------------------------------------------------------------------------------
-- Runs once per guild (guild.repaired = 1): backup, sort, remove drift duplicates, then rebuild joins, invites and
-- former members from the saved game-log fingerprints through the live import code (replay mode).
-- Returns the report { duplicates, former, joins, invites }. Prints nothing and announces nothing.
local function countKinds(guild)
    local joins, invites = 0, 0
    for _, event in ipairs(guild.events) do
        if event.k == "join" or event.k == "rejoin" then joins = joins + 1
        elseif event.k == "invite" then invites = invites + 1 end
    end
    return joins, invites
end

local SEEN_KINDS = { invite = true, join = true, promote = true, demote = true, remove = true, quit = true }

function GL:RepairLedger(guild)
    local report = { duplicates = 0, former = 0, joins = 0, invites = 0 }
    if not (guild and self.db) then return report end
    guild.events = guild.events or {}
    guild.seen = guild.seen or {}
    guild.former = guild.former or {}
    guild.members = guild.members or {}
    guild.repaired = 1   -- set first: the backup copy carries it (so a restore is not repaired again) and a failure never repeats
    local backedUp, backupErr = pcall(self.Backup, self, guild, "before 1.3.0 repair")
    if not backedUp or backupErr == false then
        report.skipped = true
        return report
    end
    local wasQuiet = self.quiet
    self.quiet = true
    local good, err = pcall(function()
        self:UpgradeSeen(guild)
        -- Events without a usable time cannot be placed: drop them.
        local clean = {}
        for _, event in ipairs(guild.events) do
            if type(event) == "table" and type(event.t) == "number" then clean[#clean + 1] = event
            else report.duplicates = report.duplicates + 1 end
        end
        guild.events = clean
        self:SortEvents(guild)
        for _, event in ipairs(guild.events) do
            if event.src == "game" then event.g = true end
        end
        -- Dedupe: a game event merges into its partner (one-to-one), keeping the scan one or the earlier game one.
        local done, removed = {}, {}
        local function blocked(a, b)
            if a.k ~= "promote" and a.k ~= "demote" then return false end
            local lo, hi = math.min(a.t, b.t), math.max(a.t, b.t)
            for _, other in ipairs(guild.events) do
                if other ~= a and other ~= b and other.who == a.who and (other.k == "promote" or other.k == "demote")
                    and other.t > lo and other.t < hi then return true end
            end
            return false
        end
        for _, e in ipairs(guild.events) do
            if e.src == "game" and not done[e] then
                local partner = self:MatchEvent(guild, e.k, e.who, e.t, "game", { ignoreClaim = true, exclude = e, claimed = done })
                if partner then
                    if not blocked(e, partner) then
                        local keep, drop = partner, e
                        if partner.src == "game" and e.t < partner.t then keep, drop = e, partner end
                        for k, v in pairs(drop) do
                            if keep[k] == nil then keep[k] = v end
                        end
                        keep.g = true
                        done[keep], done[drop] = true, true
                        removed[drop] = true
                        report.duplicates = report.duplicates + 1
                    end
                end
            end
        end
        if next(removed) then
            local kept = {}
            for _, event in ipairs(guild.events) do
                if not removed[event] then kept[#kept + 1] = event end
            end
            guild.events = kept
        end
        -- Rebuild from the saved fingerprints, one entry per remembered time.
        local entries = {}
        for key, times in pairs(guild.seen) do
            local fields = {}
            for part in (key .. "|"):gmatch("([^|]*)|") do fields[#fields + 1] = part end
            if SEEN_KINDS[fields[1]] and fields[2] and fields[2] ~= "" and type(times) == "table" then
                for _, t in ipairs(times) do
                    if type(t) == "number" then
                        entries[#entries + 1] = { kind = fields[1], p1 = fields[2], p2 = fields[3] ~= "" and fields[3] or nil,
                            rank = fields[4] ~= "" and fields[4] or nil, t = t }
                    end
                end
            end
        end
        table.sort(entries, function(a, b)
            if a.t ~= b.t then return a.t < b.t end
            if a.kind ~= b.kind then return a.kind < b.kind end
            return a.p1 < b.p1
        end)
        local joins0, invites0 = countKinds(guild)
        local former0 = self:Count(guild.former)
        self:ImportGameLogEntries(guild, entries, { replay = true })
        local joins1, invites1 = countKinds(guild)
        report.joins = math.max(0, joins1 - joins0)
        report.invites = math.max(0, invites1 - invites0)
        report.former = math.max(0, self:Count(guild.former) - former0)
    end)
    self.quiet = wasQuiet
    if not good then report.failed = tostring(err) end
    return report
end

function GL:RepairLine(report)
    if report.skipped then
        return "the ledger repair was skipped because the backup could not be taken; nothing was changed."
    end
    if report.failed then
        return "the ledger repair failed (" .. report.failed .. "); the backup from before the repair can be restored with /tabard restore."
    end
    if (report.duplicates + report.former + report.joins + report.invites) <= 0 then return nil end
    return string.format("repaired the ledger: removed %d duplicates, added %d former members, %d joins and %d invites; a backup was taken.",
        report.duplicates, report.former, report.joins, report.invites)
end
