-- Tabard: "since you were last here"
-- Stamps the guild with the time you were last on and, at the next real login, keeps that stamp as the
-- "last visit" marker for the session. Everything recorded after the marker is what changed while you were
-- away: a one-line chat summary, the "Since your last visit" block on the Overview and the divider in the Log,
-- like Guild Roster Manager's login report. The marker is captured once per login, not per /reload.

local ADDON_NAME, GL = ...

-- Counts of events after `since`. Returns nil when there is nothing to compare against.
function GL:AwaySummary(guild, since)
    if not (guild and type(since) == "number" and since > 0) then return nil end
    local counts = { since = since, joins = 0, leaves = 0, ranks = 0, levels = 0, notes = 0, other = 0, total = 0 }
    for i = #guild.events, 1, -1 do
        local event = guild.events[i]
        if event.t <= since then break end
        counts.total = counts.total + 1
        if event.k == "join" or event.k == "rejoin" then counts.joins = counts.joins + 1
        elseif event.k == "leave" or event.k == "kick" then counts.leaves = counts.leaves + 1
        elseif event.k == "promote" or event.k == "demote" then counts.ranks = counts.ranks + 1
        elseif event.k == "level" then counts.levels = counts.levels + 1
        elseif event.k == "note" or event.k == "onote" or event.k == "custom" then counts.notes = counts.notes + 1
        else counts.other = counts.other + 1 end
    end
    return counts
end

-- "3 joined, 1 left, 2 rank changes, 12 level-ups" (empty string when nothing happened).
function GL:AwayText(counts)
    if not counts or counts.total == 0 then return "" end
    local parts = {}
    local function add(n, one, many) if n > 0 then parts[#parts + 1] = n .. " " .. (n == 1 and one or many) end end
    add(counts.joins, "joined", "joined")
    add(counts.leaves, "left", "left")
    add(counts.ranks, "rank change", "rank changes")
    add(counts.levels, "level-up", "level-ups")
    add(counts.notes, "note change", "note changes")
    add(counts.other, "other change", "other changes")
    return table.concat(parts, ", ")
end

-- The summary since the last-visit marker, or nil before the first login with the addon.
function GL:SinceLastVisit(guild)
    guild = guild or self:Guild()
    if not guild then return nil end
    return self:AwaySummary(guild, guild.visitSince)
end

-- The lines for the Overview: nil when there is no marker yet; otherwise joins, leaves, rank changes and note
-- changes as their own lines (newest first), then the level-ups on one line and everything else on another.
-- item = { text, accent = "green" | "red" | "gold" | "blue" | "purple" | "grey", member (when still in the guild), kinds }
function GL:WhatsNew(guild)
    guild = guild or self:Guild()
    local since = guild and guild.visitSince
    if not (type(since) == "number" and since > 0) then return nil end
    local items, levels, other, otherKinds = {}, {}, 0, {}
    for i = #guild.events, 1, -1 do
        local event = guild.events[i]
        if event.t <= since then break end
        local k = event.k
        if k == "join" or k == "rejoin" then
            items[#items + 1] = { text = self:Describe(event, guild), accent = "green", member = self:Member(guild, event.who), kinds = { join = true, rejoin = true } }
        elseif k == "leave" or k == "kick" then
            items[#items + 1] = { text = self:Describe(event, guild), accent = "red", member = self:Member(guild, event.who), kinds = { leave = true, kick = true } }
        elseif k == "promote" or k == "demote" then
            items[#items + 1] = { text = self:Describe(event, guild), accent = "gold", member = self:Member(guild, event.who), kinds = { promote = true, demote = true } }
        elseif k == "level" then
            levels[#levels + 1] = event
        elseif k == "note" or k == "onote" or k == "custom" then
            items[#items + 1] = { text = self:Describe(event, guild), accent = "purple", member = self:Member(guild, event.who), kinds = { [k] = true } }
        else
            other = other + 1
            otherKinds[k] = true
        end
    end
    if #levels > 0 then
        local names = {}   -- every one of them; the line below names four, the login card more
        for _, event in ipairs(levels) do
            local member = self:Member(guild, event.who)
            names[#names + 1] = (member and self:ColoredName(member) or ("|cffffffff" .. tostring(event.who or "?") .. "|r")) .. " " .. tostring(event.level or "")
        end
        local text
        if #levels == 1 then
            text = "1 level-up: " .. names[1]
        else
            text = #levels .. " level-ups: " .. table.concat(names, ", ", 1, math.min(4, #names)) .. (#levels > 4 and (" and " .. (#levels - 4) .. " more") or "")
        end
        items[#items + 1] = { text = text, accent = "blue", kinds = { level = true }, names = names }
    end
    if other > 0 then
        items[#items + 1] = { text = other .. (other == 1 and " other change" or " other changes") .. " (alts, bans, dates)", accent = "grey", kinds = otherKinds }
    end
    return items
end

-- The lines themselves, like Guild Roster Manager's login report: each join, leave and rank change on its own
-- coloured line, newest first, level-ups together on one, the rest counted. Long absences are cut short.
local REPORT_LINES = 12
local ACCENT_COLOR = { green = "ff33dd33", red = "ffff5555", gold = "ffffd100", blue = "ff66aaff", purple = "ffdd99ff", grey = "ff9d9d9d" }
function GL:PrintLoginReport(guild)
    local items = self:WhatsNew(guild)
    if not items or #items == 0 then return end
    local shown = 0
    for _, item in ipairs(items) do
        if shown >= REPORT_LINES then
            self:Print("|cff9d9d9d... and " .. (#items - shown) .. " more. |cffffffff/tabard|r|cff9d9d9d for the log.|r")
            break
        end
        local color = ACCENT_COLOR[item.accent] or "ffffffff"
        self:Print("  |c" .. color .. string.gsub(item.text, "|r", "|r|c" .. color) .. "|r")
        shown = shown + 1
    end
end

-- The marker. It is taken with the first roster read of a login, not at the loading screen: only then is it
-- certain which ledger is this guild's (Keep.lua folds ledgers a realm rename split). And it does not depend on
-- the logout: on WoW Forever the guild is already gone when PLAYER_LOGOUT fires on a real logout, so the stamp
-- written there only ever landed on a /reload. Every roster read stamps the visit instead (they come at least
-- every five minutes), and the marker is the later of that stamp and the last roster read before this login.
local entered, wasLogin = false, false   -- has the loading screen told us whether this is a login or a reload?
local captured = false
local sawRead, readBefore = false, nil   -- the last roster read before this session
local visitGuild

-- Called after every roster read (Scan.lua). prevScan: the read before this one.
function GL:NoteVisit(guild, prevScan)
    if not guild then return end
    if not sawRead then sawRead, readBefore = true, prevScan end
    if not entered then return end
    if not captured then
        captured = true
        if wasLogin then
            local since = math.max(type(guild.lastVisit) == "number" and guild.lastVisit or 0, type(readBefore) == "number" and readBefore or 0)
            guild.visitSince = since > 0 and since or nil
        end
    end
    visitGuild = guild
    guild.lastVisit = self:Now()
end

-- Is everything that changed while you were away recorded? Someone missing from the first roster read is only
-- recorded as gone once a second read (or the game's log) agrees, a few seconds later.
function GL:AwaySettled(guild)
    if not (captured and self.sessionReady and guild) then return false end
    for _, member in pairs(guild.members) do
        if member.missing then return false end
    end
    return true
end

local REPORT_WAIT = 40   -- seconds after login the report waits, at most, for the roster to settle

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, isLogin, isReload)
    if event == "PLAYER_LOGOUT" then
        if captured and visitGuild then visitGuild.lastVisit = GL:Now() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        entered, wasLogin = true, isLogin and true or false
        if isLogin then
            -- One line at login like other addons print, and what changed when the CurseForge app updated us.
            local db = GL.db
            local previous = db and db.loadedVersion
            if db then db.loadedVersion = GL.version end
            if previous and previous ~= GL.version then
                GL:Print("updated to " .. GL.version .. " (from " .. previous .. "): " .. (GL.whatsNew or "see the changelog on CurseForge") .. ". |cffffffff/tabard|r opens the window.")
            else
                GL:Print(GL.version .. " loaded. |cffffffff/tabard|r opens the window.")
            end
        end
        -- Wait for the roster so joins and leaves since the logout are recorded first: at login until it has
        -- settled (see AwaySettled), with a limit. After a reload the marker is the one from login, so the
        -- summary line repeats; the long report does not.
        local waited = isLogin and 12 or 6
        local function report()
            local guild = GL.db and IsInGuild() and GL:Guild()
            if isLogin and waited < REPORT_WAIT and not (guild and GL:AwaySettled(guild)) then
                waited = waited + 2
                C_Timer.After(2, report)
                return
            end
            GL.awayReported = true   -- the login card waits for this (UI.lua)
            if not guild then return end
            local counts = GL:SinceLastVisit(guild)
            local text = GL:AwayText(counts)
            if text ~= "" then
                GL:Print("since you were last here (" .. GL:Ago(counts.since) .. "): " .. text .. ". |cffffffff/tabard|r for the log.")
                if isLogin and GL.settings.loginReport ~= false then pcall(GL.PrintLoginReport, GL, guild) end
            elseif counts then
                GL:Print("nothing has changed since you were last here (" .. GL:Ago(counts.since) .. ").")
            end
        end
        C_Timer.After(waited, report)
    end
end)
