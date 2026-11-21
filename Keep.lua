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
    -- The originals of ledgers folded into one (RejoinLedgers below) are kept for a month.
    for key, kept in pairs(self.db and type(self.db.folded) == "table" and self.db.folded or {}) do
        if type(kept) ~= "table" or now - (kept.t or 0) > 30 * DAY then self.db.folded[key] = nil end
    end
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

-- Ledgers split by a realm rename ---------------------------------------------------------------------------
-- A ledger is filed under "guild - realm". On WoW Forever the realm's name has changed under the guild (and has
-- come back empty), and each time Tabard started an empty ledger beside the old one: no history, no join dates and
-- no "since your last visit". When a roster read shows that an older ledger with the same guild name holds mostly
-- the same people, the ledgers are folded into one, oldest first, under the current name. The originals are kept
-- in db.folded for a month.
GL.DeepCopy = function(value) return deepCopy(value) end

local STAMPED = { custom = { "custom", "customBy" }, nick = { "nick", "nickBy" }, birthday = { "birthday" }, safe = { "safe" }, loa = { "loa" } }
local DATED = { joined = "joinedSource", promoted = "promotedSource" }
local STATE = { "left", "leftKind", "leftBy", "leftLive", "joinLive", "missing", "missingLate", "online", "zone", "status", "mobile" }
local OWN = { stamps = true, firstSeen = true, invitedBy = true, group = true, custom = true, customBy = true, nick = true, nickBy = true,
    birthday = true, safe = true, loa = true, joined = true, joinedSource = true, promoted = true, promotedSource = true }

-- One person's record from the older ledger and the newer one, as one record. What the roster shows comes from
-- the newer; what officers set goes by its stamp, newest first; dates go by their source, as between officers.
local function foldMember(old, new)
    local merged = deepCopy(old)
    for key, value in pairs(new) do
        if not OWN[key] then merged[key] = deepCopy(value) end
    end
    for _, key in ipairs(STATE) do merged[key] = deepCopy(new[key]) end
    merged.firstSeen = math.min(old.firstSeen or math.huge, new.firstSeen or math.huge)
    if merged.firstSeen == math.huge then merged.firstSeen = nil end
    merged.invitedBy = old.invitedBy or new.invitedBy
    merged.group = old.group
    merged.stamps = deepCopy(old.stamps) or {}
    local function take(field, names)
        for _, key in ipairs(names) do merged[key] = deepCopy(new[key]) end
        merged.stamps[field] = new.stamps and new.stamps[field] or merged.stamps[field]
    end
    for field, names in pairs(STAMPED) do
        if GL:StampOf(new, field) > GL:StampOf(old, field) then take(field, names) end
    end
    for field, sourceField in pairs(DATED) do
        if new[field] then
            local older, newer = GL.SOURCE_RANK[old[sourceField] or ""] or 0, GL.SOURCE_RANK[new[sourceField] or ""] or 0
            local again = field == "joined" and old.left and new[field] > old.left   -- a new stint
            if not old[field] or again or newer > older or (newer == older and GL:StampOf(new, field) > GL:StampOf(old, field)) then
                take(field, { field, sourceField })
            end
        end
    end
    for field, stamp in pairs(new.stamps or {}) do
        if not STAMPED[field] and not DATED[field] and field ~= "group" and stamp > (merged.stamps[field] or 0) then merged.stamps[field] = stamp end
    end
    if not next(merged.stamps) then merged.stamps = nil end
    return merged
end

-- Folds `newer` into `base` (changed in place; `newer` is only read). `newer` began with a fresh look at the
-- roster at newer.seeded, so it says who is in the guild; `base` says what was known about them before.
-- A `newer` that has not read the roster yet (no seeded) only adds what little it holds.
function GL:FoldLedger(base, newer)
    local started = newer.seeded
    local lastRead = base.lastScan or 0
    local members, former = {}, {}
    local added = {}
    local function known(name) return base.members[name] or base.former[name] end
    if started then
        for name, record in pairs(newer.members) do
            local old = known(name)
            members[name] = old and foldMember(old, record) or deepCopy(record)
            if not old then members[name].group = nil end
            if not base.members[name] then added[#added + 1] = { k = old and "rejoin" or "join", who = name, level = record.level, late = lastRead } end
        end
        for name, record in pairs(newer.former) do
            local old = known(name)
            former[name] = old and foldMember(old, record) or deepCopy(record)
            if not old then former[name].group = nil end
        end
        for name, old in pairs(base.former) do
            if not members[name] and not former[name] then former[name] = old end
        end
        -- In the older ledger and unknown to the newer one: they left between the two.
        for name, old in pairs(base.members) do
            if not members[name] and not former[name] then
                old.left, old.leftKind, old.online, old.missing, old.missingLate = started, "leave", false, nil, nil
                former[name] = old
                added[#added + 1] = { k = "leave", who = name, level = old.level, from = old.rank, since = old.joined, late = old.lastSeen or lastRead }
            end
        end
    else
        members, former = base.members, base.former
    end

    -- Events: everything the older ledger has, and from the newer one what the older does not already say
    -- (the newer read the game's log again from the start).
    local events = base.events
    local byWho = {}
    local function index(event)
        local who = event.who or ""
        byWho[who] = byWho[who] or {}
        table.insert(byWho[who], event)
    end
    for _, event in ipairs(events) do index(event) end
    local function has(kind, who, t, window)
        local class = self.KIND_CLASS[kind] or kind
        for _, other in ipairs(byWho[who or ""] or {}) do
            if (self.KIND_CLASS[other.k] or other.k) == class and math.abs(other.t - t) <= window then return true end
        end
        return false
    end
    local fresh, told = {}, {}   -- told: the joins and leaves the newer ledger has a line for, whenever it was
    for _, event in ipairs(newer.events) do
        if type(event) == "table" and type(event.t) == "number" then
            local class = self.KIND_CLASS[event.k]
            if class and event.who then told[class .. "|" .. event.who] = true end
            if event.t > lastRead or not has(event.k, event.who, event.t, 7200) then fresh[#fresh + 1] = deepCopy(event) end
        end
    end
    for _, event in ipairs(fresh) do
        events[#events + 1] = event
        index(event)
    end
    -- Who came and went between the two ledgers, unless the game's log already said so.
    for i, event in ipairs(added) do
        if not told[self.KIND_CLASS[event.k] .. "|" .. event.who]
            and not has(event.k, event.who, (started + lastRead) / 2, (started - lastRead) / 2 + 7200) then
            event.t, event.src, event.id = started, "scan", string.format("%xf%03d", started, i % 1000)
            events[#events + 1] = event
        end
    end

    -- Game-log fingerprints: both lists, an entry both ledgers read counted once.
    for key, times in pairs(newer.seen or {}) do
        if type(times) == "table" then
            local list = base.seen[key] or {}
            for _, t in ipairs(times) do list[#list + 1] = t end
            table.sort(list)
            local kept = {}
            for _, t in ipairs(list) do
                if #kept == 0 or t - kept[#kept] >= 3600 then kept[#kept + 1] = t end
            end
            base.seen[key] = kept
        end
    end
    for name, ban in pairs(newer.bans or {}) do
        local old = base.bans[name]
        if not old or (ban.stamp or 0) > (old.stamp or 0) then base.bans[name] = deepCopy(ban) end
    end

    -- Everything else: the newer value where there is one; tables are joined (lists end to end, the rest by key).
    local SPECIAL = { members = true, former = true, events = true, seen = true, bans = true, groups = true, nextGroup = true,
        seeded = true, created = true, scans = true, lastVisit = true, visitSince = true }
    for key, value in pairs(newer) do
        if not SPECIAL[key] then
            local old = base[key]
            if type(value) == "table" and type(old) == "table" then
                if value[1] ~= nil or old[1] ~= nil then
                    for _, item in ipairs(value) do old[#old + 1] = deepCopy(item) end
                else
                    for k, v in pairs(value) do old[k] = deepCopy(v) end
                end
            else
                base[key] = deepCopy(value)
            end
        end
    end
    base.members, base.former = members, former
    base.seeded = math.min(base.seeded or math.huge, newer.seeded or math.huge)
    if base.seeded == math.huge then base.seeded = nil end
    base.created = math.min(base.created or math.huge, newer.created or math.huge)
    if base.created == math.huge then base.created = nil end
    base.scans = (base.scans or 0) + (newer.scans or 0)
    -- The last visit is the last time either ledger was written while you were on.
    local visit = math.max(base.lastVisit or 0, newer.lastVisit or 0, lastRead, started and newer.lastScan or 0)
    base.lastVisit = visit > 0 and visit or nil
    base.visitSince = newer.visitSince or base.visitSince
    self:SortEvents(base)

    -- Alt groups set in the newer ledger, where they are newer than what the people in them had.
    local ids = {}
    for id in pairs(newer.groups or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local group = newer.groups[id]
        local main = type(group) == "table" and self:Member(base, group.main)
        if main and type(group.alts) == "table" then
            for _, altName in ipairs(group.alts) do
                local alt = self:Member(base, altName)
                if alt and alt ~= main and (group.t or 0) >= self:StampOf(alt, "group") and (group.t or 0) >= self:StampOf(main, "group") then
                    self:LinkAlt(base, alt, main, "sync", group.t)
                end
            end
        end
    end
    return base
end

-- How much of a saved ledger's membership the live roster still holds (0..1), counted against the smaller of the two.
local function overlap(ledger, roster, total)
    local count, same = 0, 0
    for name, member in pairs(ledger.members or {}) do
        count = count + 1
        local line = roster[name]
        if line and (not line.class or not member.class or line.class == member.class) then same = same + 1 end
    end
    local smaller = math.min(count, total)
    if smaller < 1 then return 0 end
    return same / smaller
end

-- Called with every complete roster read, before anything is compared: folds older ledgers of this guild that
-- were filed under another realm name into `guild` (the table stays the same, its contents change). Returns
-- how many ledgers were joined to it.
local SAME_GUILD = 0.5
local looked = {}
function GL:RejoinLedgers(guild, roster, total)
    local key = self:GuildKey()
    if not (key and guild and self.db and self.db.guilds[key] == guild) then return 0 end
    local found = {}
    for otherKey, other in pairs(self.db.guilds) do
        if other ~= guild and not looked[otherKey] and type(other) == "table" and other.name == guild.name then
            looked[otherKey] = true
            if other.seeded and type(other.members) == "table" and overlap(other, roster, total) >= SAME_GUILD then
                found[#found + 1] = { key = otherKey, guild = other }
            end
        end
    end
    if #found == 0 then return 0 end
    local now = self:Now()
    local folded = type(self.db.folded) == "table" and self.db.folded or {}
    local chain = {}
    for _, item in ipairs(found) do
        for _, field in ipairs({ "members", "former", "events", "seen", "groups", "bans", "ranks", "peers" }) do
            if type(item.guild[field]) ~= "table" then item.guild[field] = {} end
        end
        self:UpgradeSeen(item.guild)
        chain[#chain + 1] = item.guild
    end
    local current = deepCopy(guild)
    chain[#chain + 1] = current
    table.sort(chain, function(a, b) return (a.seeded or math.huge) < (b.seeded or math.huge) end)   -- an unread ledger goes last
    local wasQuiet = self.quiet
    self.quiet = true
    local merged
    local good, err = pcall(function()
        merged = deepCopy(chain[1])
        for i = 2, #chain do self:FoldLedger(merged, chain[i]) end
    end)
    self.quiet = wasQuiet
    if not good then
        self:Print("could not join this guild's older records (" .. tostring(err) .. "); nothing was changed.")
        return 0
    end
    merged.name, merged.realm, merged.repaired = guild.name, guild.realm, 1
    for k in pairs(guild) do guild[k] = nil end
    for k, v in pairs(merged) do guild[k] = v end
    self.db.folded = folded
    if current.seeded then folded[key] = { t = now, guild = current } end
    local mine = type(self.db.mine) == "table" and self.db.mine
    for _, item in ipairs(found) do
        folded[item.key] = { t = now, guild = item.guild }
        self.db.guilds[item.key] = nil
        if mine and type(mine[item.key]) == "table" then
            mine[key] = type(mine[key]) == "table" and mine[key] or {}
            for name, t in pairs(mine[item.key]) do
                mine[key][name] = type(t) == "number" and math.max(type(mine[key][name]) == "number" and mine[key][name] or 0, t) or t
            end
            mine[item.key] = nil
        end
    end
    self:Print(string.format("this guild's records were filed under %s because the realm's name changed; they are one ledger again (%d events since %s).",
        #found == 1 and "another realm name" or (#found .. " other realm names"), #guild.events, self:FormatDate(guild.seeded)))
    return #found
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
    local backedUp, backupErr = pcall(self.Backup, self, guild, "before ledger repair")
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
        local MEMBERSHIP = { join = true, rejoin = true, leave = true, kick = true }
        local RANKS = { promote = true, demote = true }
        -- Two events are not one when an event of the same family about that person lies between them
        -- (a promotion between two promotions, a leave between a join and a rejoin).
        local function blocked(a, b)
            local family = RANKS[a.k] and RANKS or MEMBERSHIP[a.k] and MEMBERSHIP
            if not family then return false end
            local lo, hi = math.min(a.t, b.t), math.max(a.t, b.t)
            for _, other in ipairs(guild.events) do
                if other ~= a and other ~= b and other.who == a.who and family[other.k]
                    and other.t > lo and other.t < hi then return true end
            end
            return false
        end
        -- Nor when they disagree on who did it or the ranks, where both say.
        local function differ(a, b)
            for _, field in ipairs({ "by", "from", "to" }) do
                if a[field] ~= nil and b[field] ~= nil and a[field] ~= b[field] then return true end
            end
            return false
        end
        for _, e in ipairs(guild.events) do
            if e.src == "game" and not done[e] then
                -- The nearest partner that agrees with it; one that disagrees is skipped, not merged.
                local skip = setmetatable({}, { __index = done })
                local partner
                repeat
                    partner = self:MatchEvent(guild, e.k, e.who, e.t, "game", { ignoreClaim = true, exclude = e, claimed = skip })
                    if partner and differ(e, partner) then skip[partner] = true else break end
                until false
                if partner then
                    if not blocked(e, partner) then
                        local keep, drop = partner, e
                        if partner.src == "game" and e.t < partner.t then keep, drop = e, partner end
                        for k, v in pairs(drop) do
                            if keep[k] == nil then keep[k] = v end
                        end
                        -- A removal read as a plain leave on one side is a removal.
                        if drop.k == "kick" and keep.k == "leave" then
                            keep.k = "kick"
                            local former = guild.former[keep.who]
                            if former and (not former.left or math.abs(former.left - keep.t) <= 7200 or math.abs(former.left - drop.t) <= 7200) then
                                former.leftKind, former.leftBy = "kick", keep.by or former.leftBy
                            end
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
