-- Tabard: roster scanning
-- Compares each roster update with the saved roster to find joins, leaves, promotions, demotions,
-- level-ups, note changes and name changes, and reads the game's own guild event log for who did
-- what (who invited whom, who removed whom) and for the hour it happened.

local ADDON_NAME, GL = ...

local SCAN_INTERVAL = 15          -- seconds between roster requests while the game keeps sending updates
local LEAVE_CONFIRM_SCANS = 2     -- a member must be missing from this many scans in a row before "left" is recorded
local SEEN_WINDOW = 2 * 3600    -- how far apart two readings of the same game-log entry may be (the game only gives the hour)
local SEEN_KEEP = 60 * 86400      -- how long game-log fingerprints are remembered

local frame = CreateFrame("Frame")
local pendingScan, lastRequest, lastGameLogQuery = false, 0, 0
local lastTick                     -- when newcomers were last credited time online

-- Invites this character sent, from the "You have invited X to join your guild." system line: the quickest
-- way to know the inviter when it is you. Keyed by lower-cased name; kept a quarter of an hour.
local INVITE_KEEP = 900
local pendingInvites = {}
-- Turns a game string such as "%s has left the guild." into a Lua pattern that captures each %s.
function GL:PatternFrom(globalString)
    if type(globalString) ~= "string" then return nil end
    return "^" .. string.gsub(string.gsub(globalString, "[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"), "%%%%s", "(.+)") .. "$"
end

local invitePattern = GL:PatternFrom(ERR_GUILD_INVITE_S)
local joinPattern = GL:PatternFrom(ERR_GUILD_JOIN_S)
local leavePattern = GL:PatternFrom(ERR_GUILD_LEAVE_S)
local removePattern = GL:PatternFrom(ERR_GUILD_REMOVE_SS)

local function noteInvite(text)
    if not (invitePattern and type(text) == "string") or (issecretvalue and issecretvalue(text)) then return end
    local name = string.match(text, invitePattern)
    if not name then return end
    pendingInvites[string.lower(GL:ShortName(name))] = { by = GL:PlayerName(), t = GL:Now() }
end

local function inviterFor(name, now)
    local pending = pendingInvites[string.lower(name)]
    if pending and now - pending.t <= INVITE_KEEP then return pending.by end
end

-- Roster ------------------------------------------------------------------------------------------
-- Everything the client tells us about one roster line, keyed by bare name.
local function readRoster()
    local count = GetNumGuildMembers()
    if not count or count == 0 then return nil end
    local now = GL:Now()
    local online = {}
    local roster, total = {}, 0
    for i = 1, count do
        local name, rankName, rankIndex, level, _, zone, note, officerNote, isOnline, status, classFile, _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
        if GL:IsUsable(name) and type(name) == "string" and name ~= "" then
            name = GL:ShortName(name)
            local lastOnline
            if isOnline then
                lastOnline = now
            elseif GetGuildRosterLastOnline then
                local years, months, days, hours = GetGuildRosterLastOnline(i)
                if years or months or days or hours then
                    lastOnline = now - ((((years or 0) * 12 + (months or 0)) * 30.4 + (days or 0)) * 24 + (hours or 0)) * 3600
                end
            end
            roster[name] = {
                name = name,
                rank = GL:IsUsable(rankName) and rankName or nil,
                rankIndex = GL:IsUsable(rankIndex) and rankIndex or nil,
                level = GL:IsUsable(level) and level or nil,
                note = GL:IsUsable(note) and note or "",
                onote = GL:IsUsable(officerNote) and officerNote or "",
                class = GL:IsUsable(classFile) and classFile or nil,
                guid = GL:IsUsable(guid) and guid or nil,
                online = isOnline and true or false,
                lastOnline = lastOnline,
                zone = (isOnline and GL:IsUsable(zone) and type(zone) == "string" and zone ~= "") and zone or nil,
                status = (isOnline and GL:IsUsable(status) and tonumber(status)) or 0,   -- 0 none, 1 AFK, 2 DND
                mobile = (isOnline and isMobile == true) or nil,
            }
            total = total + 1
        end
    end
    if total == 0 then return nil end
    return roster, total, count
end

-- Is this roster only part of the guild? Leaves are never recorded from a partial roster: the guild UI's
-- "show offline" box being off, lines the client hides, or a roster that shrank by more than a tenth
-- since the last complete scan (a server hiccup looks exactly like a mass exodus). A real shrink is
-- accepted once it has held for several scans over ten minutes.
local PARTIAL_ACCEPT_SCANS, PARTIAL_ACCEPT_SECONDS = 3, 600
local shrinkSince, shrinkScans = nil, 0

local function partialReason(guild, total, count, now)
    -- The guild panel's "show offline" flag is not consulted: iterating 1..GetNumGuildMembers() returns every
    -- member whatever the flag says (measured 997/997 with it off), and other addons flip the flag while
    -- building tooltips (Socialite), which made this look partial every time such a window closed. If rows
    -- really were hidden, the readable-lines check below would catch it.
    if total < count then return string.format("%d of %d roster lines readable", total, count) end
    local last = guild.lastCount
    if last and total < last * 0.9 then
        shrinkScans = shrinkScans + 1
        shrinkSince = shrinkSince or now
        if shrinkScans >= PARTIAL_ACCEPT_SCANS and (now - shrinkSince) >= PARTIAL_ACCEPT_SECONDS then
            shrinkSince, shrinkScans = nil, 0
            return nil   -- held long enough: it really happened
        end
        return string.format("roster shrank from %d to %d", last, total)
    end
    shrinkSince, shrinkScans = nil, 0
    return nil
end

local function canSeeOfficerNotes()
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then return C_GuildInfo.CanViewOfficerNote() end
    if CanViewOfficerNote then return CanViewOfficerNote() end
    return false
end

-- Copies the live fields of a roster line into a saved member record.
local function updateMember(member, line, now)
    member.name = line.name
    member.class = line.class or member.class
    member.level = line.level or member.level
    member.rank = line.rank or member.rank
    member.rankIndex = line.rankIndex or member.rankIndex
    member.note = line.note
    if canSeeOfficerNotes() then member.onote = line.onote end
    member.guid = line.guid or member.guid
    member.online = line.online
    member.zone = line.online and line.zone or nil       -- only kept while online
    member.status = line.online and line.status or nil
    member.mobile = line.mobile
    member.lastSeen = now
    if line.lastOnline then member.lastOnline = line.lastOnline end
    member.missing = nil
end

-- Remembers rank names by index (used for the newcomer rank and the Tools page).
local function noteRanks(guild, roster)
    for _, line in pairs(roster) do
        if line.rankIndex and line.rank then guild.ranks[line.rankIndex] = line.rank end
    end
end

-- After a join: shout if the name (or an alt of it) is on the ban list; read the note for an alt link.
local function afterJoin(guild, member, kind)
    local ban, bannedName = GL:BanFor(guild, member)
    if ban then
        GL:Warn(string.format("%s just joined but %s is on the ban list (banned by %s on %s%s).", member.name,
            bannedName == member.name and "this character" or ("their character " .. bannedName), ban.by or "?", GL:FormatDate(ban.t),
            (ban.reason and ban.reason ~= "") and (": " .. ban.reason) or ""))
    end
    if GL.settings.autoAlts then GL:DetectAlt(guild, member) end
    -- Optional, like Guild Roster Manager: write the join date into an empty public or officer note.
    local where = GL.settings.noteJoinDate
    if (where == "public" or where == "officer") and GL.SetNote then
        local current = where == "officer" and member.onote or member.note
        local allowed = where == "officer" and GL.CanEditOfficerNote and GL:CanEditOfficerNote() or (where == "public" and GL.CanEditNote and GL:CanEditNote())
        if allowed and (current == nil or current == "") then
            local text = (kind == "rejoin" and "Rejoined " or "Joined ") .. GL:FormatDate(member.joined or GL:Now())
            pcall(GL.SetNote, GL, member, text, where == "officer")
        end
    end
    -- Welcomes only for joins seen live. The first scan after a login or reload lists everyone who joined
    -- while you were away; whispering them hours later reads as odd, so those are recorded but not welcomed.
    if GL.Welcome then GL.Welcome:OnJoin(guild, member, kind or "join", GL.sessionReady == true) end
end

-- First look at a guild: record everyone, no events. Join dates are unknown; "first seen" is a floor.
local function seedGuild(guild, roster, now)
    for name, line in pairs(roster) do
        local member = { firstSeen = now }
        updateMember(member, line, now)
        guild.members[name] = member
    end
    noteRanks(guild, roster)
    if GL.settings.autoAlts then
        for _, member in pairs(guild.members) do GL:DetectAlt(guild, member) end
    end
    guild.seeded = now
end

-- A member is gone: move them to the former list and log the leave or removal. Shared by the roster diff and
-- the live system-chat lines so both record the same fields.
local function recordLeave(guild, name, member, kind, by, now)
    guild.members[name] = nil
    member.missing = nil
    member.online = false
    member.left, member.leftKind = now, kind
    if kind == "kick" then member.leftBy = by end
    guild.former[name] = member
    return GL:AddEvent(guild, kind, { who = name, by = by, level = member.level, from = member.rank, since = member.joined }, now)
end

-- Compares the saved roster with the live one and records what changed.
local function diffRoster(guild, roster, now, partial)
    local members = guild.members
    local officerNotes = canSeeOfficerNotes()
    local inactiveAfter = (GL.settings.inactiveDays or 30) * 86400
    noteRanks(guild, roster)

    -- Name changes: a new name with the guid of a missing member.
    local guidOf = {}
    for name, member in pairs(members) do
        if member.guid and not roster[name] then guidOf[member.guid] = name end
    end
    for name, line in pairs(roster) do
        local oldName = line.guid and guidOf[line.guid]
        if oldName and not members[name] then
            local member = members[oldName]
            members[oldName] = nil
            members[name] = member
            updateMember(member, line, now)
            GL:AddEvent(guild, "rename", { who = name, from = oldName }, now)
        end
    end

    -- Changes and joins.
    for name, line in pairs(roster) do
        local member = members[name]
        if member then
            if line.level and member.level and line.level > member.level then
                GL:AddEvent(guild, "level", { who = name, from = member.level, level = line.level }, now)
                if GL.Shout then GL.Shout:OnLevel(guild, name, member.level, line.level, line.online) end
            end
            local noteChanged = false
            if line.rankIndex and member.rankIndex and line.rankIndex ~= member.rankIndex then
                local kind = line.rankIndex < member.rankIndex and "promote" or "demote"   -- rank 0 is the guild leader
                GL:AddEvent(guild, kind, { who = name, from = member.rank, to = line.rank }, now)
                member.promoted, member.promotedSource = now, "scan"
                GL:Stamp(member, "promoted", now)
                if kind == "promote" and GL.Shout then GL.Shout:OnPromote(guild, name, line.rank, line.online) end
            elseif line.rank and member.rank and line.rank ~= member.rank and line.rankIndex == member.rankIndex then
                GL:AddEvent(guild, "rank", { who = name, from = member.rank, to = line.rank }, now)
            end
            if member.note ~= nil and line.note ~= member.note then
                GL:AddEvent(guild, "note", { who = name, from = member.note, to = line.note }, now)
                noteChanged = true
            end
            if officerNotes and member.onote ~= nil and line.onote ~= member.onote then
                GL:AddEvent(guild, "onote", { who = name, from = member.onote, to = line.onote }, now)
                noteChanged = true
            end
            local cameOnline = line.online and not member.online
            local cameBack = false
            if cameOnline and member.lastOnline and (now - member.lastOnline) >= inactiveAfter then
                local away = (string.gsub(GL:Ago(member.lastOnline, now), " ago$", ""))
                GL:AddEvent(guild, "back", { who = name, text = away }, now)
                if GL.Shout then GL.Shout:OnBack(guild, name, away) end
                cameBack = GL.settings.announce and GL.settings.announce.back and true or false   -- the "back" line covers the login
            end
            -- The login line (Settings: "comes online"); the Watch line is only needed when it is off.
            local told = cameOnline and not cameBack and GL.AnnounceOnline and GL:AnnounceOnline(guild, member, line, now)
            if member.watch and cameOnline and not told then
                GL:Print(GL:ColoredName(member) .. " is online now (you asked to be told; the Watch button on their card turns this off).")
            end
            if (line.online and true or false) ~= (member.online and true or false) and GL.NoteTransition then GL:NoteTransition(guild, name, line.online, now) end
            updateMember(member, line, now)
            if noteChanged and GL.settings.autoAlts then GL:DetectAlt(guild, member) end
        else
            local former = guild.former[name]
            local kind = former and "rejoin" or "join"
            local leftAt = former and former.left or 0
            member = former or { firstSeen = now }
            guild.former[name] = nil
            updateMember(member, line, now)
            member.left, member.leftKind, member.leftBy = nil, nil, nil
            member.joined, member.joinedSource = now, "scan"
            member.promoted, member.promotedSource = nil, nil
            GL:Stamp(member, "joined", now)
            if GL.StartFirstWeek then GL:StartFirstWeek(member) end
            members[name] = member
            -- Who invited them: your own invite is known at once from the system line; anyone else's comes from
            -- the game's event log, so the chat line waits a few seconds for it (level and inviter, like GRM's line).
            -- The game's log may have been read first and already recorded this joining: reuse that event.
            -- Only one newer than their departure: an earlier join belongs to the stint they just ended.
            local event = GL:MatchEvent(guild, "join", name, now, "scan", { ignoreClaim = true })
            if event and event.t < leftAt then event = nil end
            local by = inviterFor(name, now) or member.invitedBy or (event and event.by)
            if by then member.invitedBy = member.invitedBy or by end
            if event then
                event.k = kind
                event.level = event.level or line.level
                event.by = event.by or by
                event.hold = not by or nil
            else
                event = GL:AddEvent(guild, kind, { who = name, level = line.level, by = by, hold = not by or nil }, now)
            end
            if by then
                GL:Announce(event, guild)
            else
                if QueryGuildEventLog then pcall(QueryGuildEventLog) end
                C_Timer.After(6, function()
                    if event.hold then
                        event.hold = nil
                        if not event.by and member.invitedBy then event.by = member.invitedBy end
                        GL:Announce(event, guild)
                    end
                end)
            end
            afterJoin(guild, member, kind)
        end
    end

    -- Leaves: only from a complete roster, and only after the member has been missing from several scans in a row.
    if partial then return end
    for name, member in pairs(members) do
        if not roster[name] then
            member.missing = (member.missing or 0) + 1
            if member.missing >= LEAVE_CONFIRM_SCANS then
                recordLeave(guild, name, member, "leave", nil, now)
            end
        end
    end
end

-- Game event log -----------------------------------------------------------------------------------
-- The game keeps its own short list (invite, join, promote, demote, remove, quit) with who did it and
-- the hour it happened. Each entry is merged once: it fills in the actor on a scan event, sets a join
-- date for a member seen joining before the ledger existed, or becomes an event of its own.
local function gameLogTime(now, years, months, days, hours)
    return now - ((((years or 0) * 12 + (months or 0)) * 30.4 + (days or 0)) * 24 + (hours or 0)) * 3600
end

-- Merges a list of game-log entries ({ kind, p1, p2, rank, t }, absolute t) into the ledger. Entries already
-- merged on an earlier read are recognised by guild.seen (fingerprint -> list of times) and skipped; the hour
-- the game reports drifts, so times are compared with a tolerance, one-to-one. opts.replay = true skips that
-- check (and does not remember the entries) and instead pairs entries with events one-to-one within the call,
-- ignoring earlier claims; the one-time repair uses it.
function GL:ImportGameLogEntries(guild, entries, opts)
    opts = opts or {}
    local replay = opts.replay
    local now = self:Now()
    local wasQuiet = self.quiet
    self.quiet = true   -- history is never announced
    local held = {}   -- joins whose chat line waited for the inviter
    for _, entry in ipairs(entries) do
        entry.key = table.concat({ entry.kind, entry.p1, entry.p2 or "", entry.rank or "" }, "|")
    end
    -- Entries seen on an earlier read pair one-to-one with the remembered times, nearest first.
    local old = {}
    if not replay then
        local byKey = {}
        for _, entry in ipairs(entries) do
            byKey[entry.key] = byKey[entry.key] or {}
            table.insert(byKey[entry.key], entry)
        end
        for key, list in pairs(byKey) do
            local times = guild.seen[key]
            if times and #times > 0 then
                table.sort(list, function(a, b) return a.t < b.t end)
                local used = {}
                for _, entry in ipairs(list) do
                    local best
                    for j, st in ipairs(times) do
                        if not used[j] and math.abs(st - entry.t) <= SEEN_WINDOW
                            and (not best or math.abs(st - entry.t) < math.abs(times[best] - entry.t)) then best = j end
                    end
                    if best then used[best] = true; old[entry] = true end
                end
            end
        end
    end
    -- Per-call claims. Join and invite entries describe the same joining, so each kind keeps its own set and
    -- ignores the other's claim; everything else is claimed once, for good (or per call when replaying).
    local claimedBy = { invite = {}, join = {}, other = {} }
    local function match(kind, who, t)
        local opt
        if kind == "invite" or kind == "join" then
            opt = { ignoreClaim = true, claimed = claimedBy[kind] }
        elseif replay then
            opt = { ignoreClaim = true, claimed = claimedBy.other }
        end
        return self:MatchEvent(guild, kind == "invite" and "join" or kind, who, t, "game", opt)
    end
    local function claim(kind, event)
        event.g = true
        claimedBy[(kind == "invite" or kind == "join") and kind or "other"][event] = true
    end
    local function create(kind, eventKind, fields, t)
        fields.src = "game"
        local event = self:AddEvent(guild, eventKind, fields, t)
        claim(kind, event)
        return event
    end
    for _, entry in ipairs(entries) do
        if not old[entry] then
            local kind, player1, player2, rank, t = entry.kind, entry.p1, entry.p2, entry.rank, entry.t
            if not replay then
                local times = guild.seen[entry.key]
                if not times then times = {}; guild.seen[entry.key] = times end
                local pos = #times + 1
                while pos > 1 and times[pos - 1] > t do pos = pos - 1 end
                table.insert(times, pos, t)
            end
            if kind == "invite" and player2 then
                -- Looking up the joining is non-exclusive: several invites (two officers, or one remembered at two
                -- times) can describe one join, and none of them may add a second one.
                local event = self:MatchEvent(guild, "join", player2, t, "game", { ignoreClaim = true })
                if event then
                    claim(kind, event)
                    event.by = event.by or player1
                    local joiner = guild.members[player2]
                    if joiner then joiner.invitedBy = joiner.invitedBy or player1 end
                    if event.hold then event.hold = nil; held[#held + 1] = event end
                elseif guild.members[player2] then
                    self:SetJoinDate(guild, player2, t, "game")
                    guild.members[player2].invitedBy = guild.members[player2].invitedBy or player1
                    create(kind, "join", { who = player2, by = player1 }, t)
                else
                    -- Nobody joined (yet): the invite itself is the record. Replaying must not add it twice.
                    local twin = replay and self:MatchEvent(guild, "invite", player2, t, "game", { ignoreClaim = true, claimed = claimedBy.other })
                    if twin then
                        claimedBy.other[twin] = true
                        twin.g = true
                        twin.by = twin.by or player1
                    else
                        create("other", "invite", { who = player2, by = player1 }, t)
                    end
                end
            elseif kind == "join" then
                local event = match("join", player1, t)
                if event then
                    claim(kind, event)
                else
                    local member = guild.members[player1]
                    if member then
                        self:SetJoinDate(guild, player1, t, "game")
                    else
                        local former = guild.former[player1]
                        if former and not former.joined then former.joined, former.joinedSource = t, "game" end
                    end
                    create(kind, "join", { who = player1 }, t)
                end
            elseif (kind == "promote" or kind == "demote") and player2 then
                local event = match(kind, player2, t)
                if event then
                    claim(kind, event)
                    event.by = event.by or player1
                else
                    create(kind, kind, { who = player2, by = player1, to = rank }, t)
                end
                local member = guild.members[player2]
                if member and (not member.promoted or t > member.promoted) then self:SetPromotedDate(guild, player2, t, "game") end
            elseif kind == "remove" and player2 then
                local event = match("leave", player2, t)
                if not guild.members[player2] then self:EnsureFormer(guild, player2, t, "kick", player1, rank) end
                if event then
                    claim(kind, event)
                    event.k, event.by = "kick", event.by or player1
                elseif not guild.members[player2] then
                    local former = guild.former[player2]
                    create(kind, "kick", { who = player2, by = player1, from = rank, since = former and former.joined }, t)
                end
            elseif kind == "quit" then
                local event = match("leave", player1, t)
                if not guild.members[player1] then self:EnsureFormer(guild, player1, t, "leave", nil, rank) end
                if event then
                    claim(kind, event)
                elseif not guild.members[player1] then
                    local former = guild.former[player1]
                    create(kind, "leave", { who = player1, from = rank, since = former and former.joined }, t)
                end
            end
        end
    end
    for _, entry in ipairs(entries) do entry.key = nil end
    self.quiet = wasQuiet
    for _, event in ipairs(held) do self:Announce(event, guild) end
    -- Forget old fingerprints, time by time.
    for key, times in pairs(guild.seen) do
        for i = #times, 1, -1 do
            if now - times[i] > SEEN_KEEP then table.remove(times, i) end
        end
        if #times == 0 then guild.seen[key] = nil end
    end
end

-- Reads the game's event log and merges it into the ledger.
local function importGameLog(guild)
    if not GetNumGuildEvents then return end
    local count = GetNumGuildEvents()
    if not count or count == 0 then return end
    local now = GL:Now()
    local entries = {}
    for i = 1, count do
        local kind, player1, player2, rank, years, months, days, hours = GetGuildEventInfo(i)
        if GL:IsUsable(kind) and GL:IsUsable(player1) and type(player1) == "string" then
            player1 = GL:ShortName(player1)
            player2 = (GL:IsUsable(player2) and type(player2) == "string") and GL:ShortName(player2) or nil
            rank = GL:IsUsable(rank) and rank or nil
            entries[#entries + 1] = { kind = kind, p1 = player1, p2 = player2, rank = rank, t = gameLogTime(now, years, months, days, hours) }
        end
    end
    GL:ImportGameLogEntries(guild, entries)
end

-- Driving it ---------------------------------------------------------------------------------------
function GL:ProcessRoster()
    local guild = self:Guild()
    if not guild then return end
    local roster, total, count = readRoster()
    if not roster then return end
    local now = self:Now()
    local partial = partialReason(guild, total, count, now)
    if partial and not guild.seeded then return end   -- never start from half a roster
    guild.scans = (guild.scans or 0) + 1
    guild.lastScan = now
    -- A partial roster is shown on the To-do tab (Officers.lua), not announced in chat: a transient one is
    -- common (another addon's tooltip, a server hiccup) and the line read as noise.
    guild.partialScan = partial
    if not partial then guild.lastCount = total end
    local wasQuiet = self.quiet
    if not guild.seeded then
        self.quiet = true
        seedGuild(guild, roster, now)
        self.quiet = wasQuiet
        self:Print(string.format("started keeping records for %s with %d members. Joins, leaves, promotions and level-ups are recorded from now on.", guild.name, total))
    else
        diffRoster(guild, roster, now, partial ~= nil)
    end
    if self.ApplySelfGroup then pcall(self.ApplySelfGroup, self, guild) end
    if self.LearnFromGRM then pcall(self.LearnFromGRM, self, guild) end
    if self.TickFirstWeek then
        pcall(self.TickFirstWeek, self, guild, now, lastTick and (now - lastTick) or 0)
        lastTick = now
    end
    if not self.sessionReady then
        self.sessionReady = true
        if self.Shout then self.Shout:AfterScan() end
        if self.settings.anniversaries then pcall(self.CheckAnniversaries, self, guild) end
        if self.Sync then pcall(self.Sync.Hello, self.Sync, false) end
    end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
end

-- Anniversaries -------------------------------------------------------------------------------------
-- Once a day, lists join anniversaries and birthdays falling in the next week.
function GL:Upcoming(guild, days, now)
    now = now or self:Now()
    local list = {}
    for name, member in pairs(guild.members) do
        if member.joined and (now - member.joined) > 300 * 86400 then
            local joined = date("*t", member.joined)
            local until_, year = self:DaysUntil(joined.month, joined.day, now)
            if until_ <= days and year - joined.year >= 1 then
                list[#list + 1] = { member = member, kind = "anniversary", days = until_, years = year - joined.year }
            end
        end
        if member.birthday and member.birthday.m then
            local until_ = self:DaysUntil(member.birthday.m, member.birthday.d, now)
            if until_ <= days then list[#list + 1] = { member = member, kind = "birthday", days = until_ } end
        end
    end
    table.sort(list, function(a, b) if a.days ~= b.days then return a.days < b.days end return a.member.name < b.member.name end)
    return list
end

function GL:CheckAnniversaries(guild)
    local today = date("%Y-%m-%d", self:Now())
    if guild.anniversaryDay == today then return end
    guild.anniversaryDay = today
    local list = self:Upcoming(guild, 7)
    if #list == 0 then return end
    local parts = {}
    for _, item in ipairs(list) do
        local when = item.days == 0 and "today" or item.days == 1 and "tomorrow" or ("in " .. item.days .. " days")
        if item.kind == "anniversary" then
            parts[#parts + 1] = string.format("%s: %d %s in the guild %s", self:ColoredName(item.member), item.years, item.years == 1 and "year" or "years", when)
        else
            parts[#parts + 1] = string.format("%s: birthday %s", self:ColoredName(item.member), when)
        end
    end
    self:Print("coming up: " .. table.concat(parts, "; ") .. ".")
end

-- Asks the game for a fresh roster; the result arrives as GUILD_ROSTER_UPDATE.
function GL:RequestScan(force)
    if not IsInGuild() then return end
    local now = GetTime()
    if not force and now - lastRequest < SCAN_INTERVAL then
        pendingScan = true
        return
    end
    lastRequest = now
    pendingScan = false
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
    if now - lastGameLogQuery > SCAN_INTERVAL and QueryGuildEventLog then
        lastGameLogQuery = now
        QueryGuildEventLog()
    end
end

-- Live join and leave lines: the game prints them the moment they happen, ahead of the roster and event log.
function GL:OnSystemLine(text)
    if not GL.db or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
    if joinPattern and string.match(text, joinPattern) then
        GL:RequestScan(true)   -- the roster read records the join with its level and rank
        return
    end
    local name, by
    local kind = "leave"
    if leavePattern then name = string.match(text, leavePattern) end
    if not name and removePattern then
        name, by = string.match(text, removePattern)
        kind = "kick"
    end
    if not name then return end
    local guild = GL:Guild()
    if not guild or not guild.seeded then return end
    name = GL:ShortName(name)
    local member = guild.members[name]
    if not member then return end   -- not a current member: the game log covers them
    if by then by = GL:ShortName(by) end
    recordLeave(guild, name, member, kind, by, GL:Now())
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("GUILD_EVENT_LOG_UPDATE")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "CHAT_MSG_SYSTEM" then
        noteInvite(arg1)
        GL:OnSystemLine(arg1)
    elseif event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            GL:InitDB()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" then
        C_Timer.After(5, function() GL:RequestScan(true) end)
    elseif event == "GUILD_ROSTER_UPDATE" then
        if GL.db then
            local ok, err = pcall(GL.ProcessRoster, GL)
            if not ok then GL:Print("roster scan failed: " .. tostring(err)) end
        end
    elseif event == "GUILD_EVENT_LOG_UPDATE" then
        local guild = GL.db and GL:Guild()
        if guild and guild.seeded then
            local ok, err = pcall(importGameLog, guild)
            if not ok then GL:Print("event log import failed: " .. tostring(err)) end
            if GL.OnLedgerChanged then GL:OnLedgerChanged(guild) end
        end
    end
end)

-- The roster only changes while someone is online, and the game sends GUILD_ROSTER_UPDATE on its own
-- whenever it does; a slow heartbeat keeps the last-online times fresh and catches anything missed.
local heartbeat = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    heartbeat = heartbeat + elapsed
    if heartbeat < 60 then return end
    heartbeat = 0
    if pendingScan or (GetTime() - lastRequest) > 300 then GL:RequestScan(false) end
end)
