-- Tabard: core
-- Data model, saved variables, time helpers, chat announcements and the slash command.
-- Written from scratch for WoW Forever; the only outside pieces used are the game's own API and templates.

local ADDON_NAME, GL = ...

-- The version from the toc, so the sharing hello carries the real one (other Tabard users learn from it
-- whether a newer release is out). "0.0.0" only when the client cannot read addon metadata.
local function tocVersion()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if not get then return nil end
    local ok, value = pcall(get, ADDON_NAME, "Version")
    if ok and type(value) == "string" and string.match(value, "^%d+%.%d+") then return value end
    return nil
end
GL.version = tocVersion() or "0.0.0"
-- One line for the "updated to" message at the first login after an update (an addon cannot read CHANGELOG.md).
GL.whatsNew = "smarter alt suggestions, a login line, Promote and Demote that pick a rank"

-- "1.2.10" -> 1002010, so versions compare as numbers; nil when the text is not a version.
function GL:VersionNumber(text)
    if type(text) ~= "string" then return nil end
    local a, b, c = string.match(text, "^(%d+)%.(%d+)%.?(%d*)")
    if not a then return nil end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + (tonumber(c) or 0)
end
GL.prefix = "|TInterface\\AddOns\\Tabard\\logo:14:14:0:0|t |cffffd100Tabard:|r "

-- Event kinds -------------------------------------------------------------------------------
-- Every record in a guild's history has one of these kinds. Kept short because they are saved.
-- `color` is the badge colour in the log; `verb` is the short badge text.
GL.KINDS = {
    join = { order = 1, label = "Joined", color = "ff33dd33" },
    rejoin = { order = 2, label = "Rejoined", color = "ff33dd33" },
    leave = { order = 3, label = "Left", color = "ffff5555" },
    kick = { order = 4, label = "Removed", color = "ffff5555" },
    promote = { order = 5, label = "Promoted", color = "ffffd100" },
    demote = { order = 6, label = "Demoted", color = "ffff9933" },
    level = { order = 7, label = "Leveled", color = "ff66aaff" },
    note = { order = 8, label = "Note", color = "ffdddddd" },
    onote = { order = 9, label = "Officer note", color = "ffdd99ff" },
    custom = { order = 10, label = "Tabard note", color = "ffdd99ff" },
    rename = { order = 11, label = "Name change", color = "ff99eeff" },
    rank = { order = 12, label = "Rank renamed", color = "ffffd100" },
    back = { order = 13, label = "Back", color = "ff33ddcc" },
    alt = { order = 14, label = "Alt linked", color = "ffc0a0ff" },
    main = { order = 15, label = "Main set", color = "ffc0a0ff" },
    ban = { order = 16, label = "Banned", color = "ffff3333" },
    unban = { order = 17, label = "Ban lifted", color = "ffff8866" },
    joindate = { order = 18, label = "Join date set", color = "ffbbbbbb" },
    promodate = { order = 19, label = "Promotion date set", color = "ffbbbbbb" },
    birthday = { order = 20, label = "Birthday set", color = "ffbbbbbb" },
    loa = { order = 21, label = "Leave", color = "ff8fb8ff" },
    trial = { order = 22, label = "Trial", color = "ffd6a85c" },
    strike = { order = 23, label = "Strike", color = "ffff8c5a" },
    request = { order = 24, label = "Request", color = "ffb48cff" },
    nick = { order = 25, label = "Nickname set", color = "ffbbbbbb" },
}

GL.KIND_ORDER = {}
for kind in pairs(GL.KINDS) do GL.KIND_ORDER[#GL.KIND_ORDER + 1] = kind end
table.sort(GL.KIND_ORDER, function(a, b) return GL.KINDS[a].order < GL.KINDS[b].order end)

-- Defaults ---------------------------------------------------------------------------------
local DEFAULT_SETTINGS = {
    announce = { join = true, rejoin = true, leave = true, kick = true, promote = true, demote = true, level = true, note = false, onote = false,
        custom = false, rename = true, back = true, alt = false, main = false, ban = true, unban = true, nick = false,
        online = true },  -- online is not an event kind: a line when a guild member logs in, nothing is recorded
    showFilters = {},        -- kind -> false hides it in the log; absent/true shows it
    inactiveDays = 30,       -- "back after a break" threshold
    kickDays = 60,           -- recommend removing members offline this long
    kickMaxLevel = 0,        -- only recommend removal below this level (0 = any level)
    promoteDays = 14,        -- recommend promotion after this long in the newcomer rank
    promoteFromRank = nil,   -- rank index that counts as "newcomer"; nil = the lowest rank
    sync = true,             -- exchange join dates, alts, bans and notes with other Tabard users in the guild
    syncMinRank = 1,         -- accept shared data from members at this rank index or higher (0 = guild leader)
    shareUsage = true,       -- send this copy's usage counts (pages opened, features on; no names) to Tabard users in the guild
    tooltip = true,          -- add Tabard lines to unit tooltips of guild members
    autoAlts = true,         -- read "alt of X" style notes to link alts
    learnFromGRM = true,     -- keep taking alt groups from Guild Roster Manager's data while it is installed
    mainTags = true,         -- "(main)" / "(alt of X)" after names on event lines
    firstWeek = true,        -- track new members' first week: time online, whether anyone talked to them
    anniversaries = true,    -- mention join anniversaries and birthdays at login
    inviteBar = true,        -- offer the secure Invite button when someone outside the guild whispers you
    loginReport = true,      -- list who joined, left and changed rank while you were away, at login
    minimap = { shown = true, angle = 220 },
    windowPoint = nil,       -- saved window position { point, x, y }
}

local function copyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            copyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

-- Saved data ---------------------------------------------------------------------------------
-- TabardDB = { version, settings, guilds = { [key] = guild } }
-- guild = {
--   name, realm, created (first scan), scans (count), seeded, lastScan,
--   members = { [name] = member }, former = { [name] = member }, events = { event, ... }, seen = { [fingerprint] = t },
--   groups = { [id] = { main = name, alts = { name, ... }, t } }, nextGroup,
--   bans = { [name] = { t, by, reason, class, guid, stamp } }, ranks = { [index] = name }, peers = { [name] = { version, t } }
-- }
-- member = { name, class, level, rank, rankIndex, note, onote, guid, firstSeen, lastSeen, lastOnline, online, missing,
--   joined, joinedSource, invitedBy, promoted, promotedSource, group, custom, customBy, birthday = { m, d },
--   safe = { kick, promote }, stamps = { field = when it was last set, for syncing }, left, leftKind }
-- event = { t, k, who, by, from, to, level, text, src, id }
function GL:InitDB()
    if type(TabardDB) ~= "table" and type(GuildLedgerDB) == "table" then TabardDB = GuildLedgerDB end   -- migrated from GuildLedger
    if type(TabardDB) ~= "table" then TabardDB = {} end
    local db = TabardDB
    db.version = 2
    if type(db.guilds) ~= "table" then db.guilds = {} end
    if type(db.settings) ~= "table" then db.settings = {} end
    copyDefaults(db.settings, DEFAULT_SETTINGS)
    -- Level-ups in chat became the default in 1.0.0; settings saved before that had it off.
    if not db.levelLinesOn then db.levelLinesOn = true db.settings.announce.level = true end
    self.db = db
    self.settings = db.settings
end

function GL:GuildKey()
    if not IsInGuild() then return nil end
    local guildName = GetGuildInfo("player")
    if not guildName or guildName == "" then return nil end
    local realm = GetRealmName() or ""
    return guildName .. " - " .. realm, guildName, realm
end

-- The ledger of the guild the player is in (created on first use), or nil when not in a guild.
function GL:Guild()
    local key, guildName, realm = self:GuildKey()
    if not key then return nil end
    local guild = self.db.guilds[key]
    if not guild then
        guild = { name = guildName, realm = realm, created = GetServerTime(), scans = 0 }
        self.db.guilds[key] = guild
    end
    for _, field in ipairs({ "members", "former", "events", "seen", "groups", "bans", "ranks", "peers" }) do
        if type(guild[field]) ~= "table" then guild[field] = {} end
    end
    return guild
end

function GL:Member(guild, name)
    if not (guild and name) then return nil end
    return guild.members[name] or guild.former[name]
end

function GL:Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- Names ----------------------------------------------------------------------------------------
-- Forever returns bare names from the roster ("Ooh Woo"); other clients may add "-Realm". Members are
-- keyed by the bare name. Values the client marks secret are ignored.
function GL:IsUsable(value)
    if value == nil then return false end
    if issecretvalue and issecretvalue(value) then return false end
    return true
end

function GL:ShortName(name)
    if type(name) ~= "string" then return nil end
    local dash = string.find(name, "-", 1, true)
    if dash then return string.sub(name, 1, dash - 1) end
    return name
end

-- The player's name as the guild roster writes it. On Forever, UnitName("player") returns the first name and the
-- surname as two values ("Zev", "Zev") while the roster says "Zev Zev"; other clients return name and realm.
function GL:PlayerName()
    local full = GetUnitName and GetUnitName("player", false)
    if type(full) == "string" and string.find(full, " ", 1, true) and not (issecretvalue and issecretvalue(full)) then
        return self:ShortName(full)
    end
    local name, second = UnitName("player")
    if type(name) ~= "string" then return "?" end
    name = self:ShortName(name)
    if type(second) == "string" and second ~= "" and not string.find(second, "-", 1, true) then
        local realm = string.gsub(GetRealmName() or "", "%s+", "")
        if string.gsub(second, "%s+", "") ~= realm then name = name .. " " .. second end
    end
    return name
end

-- Just the first name ("Zev"), for lines written in the first person.
function GL:PlayerFirstName()
    local name = self:PlayerName()
    return string.match(name, "^(%S+)") or name
end

function GL:ClassColor(classFile)
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then return color.r, color.g, color.b, color.colorStr end
    return 1, 1, 1, "ffffffff"
end

function GL:ColoredName(member, name)
    local _, _, _, hex = self:ClassColor(member and member.class)
    return "|c" .. hex .. (member and member.name or name or "?") .. "|r"
end

-- " (main)" or " (alt of Zev)" for a member; empty when main tags are off.
function GL:MainTag(guild, member)
    if not (guild and member) or (self.settings and self.settings.mainTags == false) then return "" end
    if self.IsAlt and self:IsAlt(guild, member) then
        local main = self:MainOf(guild, member)
        return " |cff9d9d9d(alt of " .. (main and main.name or "?") .. ")|r"
    end
    return " |cffffd100(main)|r"
end

-- The nickname people know a member by: their own, or their main's (a nickname belongs to the person, so it
-- is kept on the main and shown after every character of theirs).
function GL:Nickname(guild, member)
    if not (guild and member) then return nil end
    if member.nick then return member.nick end
    local main, group = self.MainOf and self:MainOf(guild, member)
    if main and main ~= member and main.nick then return main.nick end
    if group and group.nick then return group.nick end
    return nil
end

function GL:ClassName(classFile)
    local names = LOCALIZED_CLASS_NAMES_MALE
    if names and classFile and names[classFile] then return names[classFile] end
    if type(classFile) ~= "string" then return "" end
    return string.upper(string.sub(classFile, 1, 1)) .. string.lower(string.sub(classFile, 2))
end

-- Finds a member by a typed name: exact, then case-insensitive, then a unique first word ("Ooh" -> "Ooh Woo").
function GL:FindMember(guild, text, includeFormer, exclude)
    if not (guild and type(text) == "string") then return nil end
    text = strtrim(text)
    if text == "" then return nil end
    local pool = guild.members
    if pool[text] and pool[text] ~= exclude then return pool[text] end
    if includeFormer and guild.former[text] and guild.former[text] ~= exclude then return guild.former[text] end
    local needle, found, count = string.lower(text), nil, 0
    local pattern = "^" .. string.gsub(needle, "%p", "%%%0") .. "%f[%s%z]"
    local function look(set)
        for name, member in pairs(set) do
            if member ~= exclude then
                local lower = string.lower(name)
                if lower == needle then return member end
                if string.match(lower, pattern) then found, count = member, count + 1 end
            end
        end
    end
    local exact = look(pool)
    if exact then return exact end
    if includeFormer then
        exact = look(guild.former)
        if exact then return exact end
    end
    if count == 1 then return found end
    return nil
end

-- Time -------------------------------------------------------------------------------------------
function GL:Now()
    return GetServerTime()
end

function GL:FormatTime(t)
    if type(t) ~= "number" or t <= 0 then return "" end
    return date("%d %b %Y %H:%M", t)
end

function GL:FormatDate(t)
    if type(t) ~= "number" or t <= 0 then return "" end
    return date("%d %b %Y", t)
end

-- "3 days ago", "2 hours ago", "just now"
function GL:Ago(t, now)
    if type(t) ~= "number" or t <= 0 then return "" end
    local seconds = (now or self:Now()) - t
    if seconds < 60 then return "just now" end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return minutes .. (minutes == 1 and " minute ago" or " minutes ago") end
    local hours = math.floor(minutes / 60)
    if hours < 48 then return hours .. (hours == 1 and " hour ago" or " hours ago") end
    local days = math.floor(hours / 24)
    if days < 60 then return days .. " days ago" end
    local months = math.floor(days / 30.4)
    if months < 24 then return months .. " months ago" end
    return math.floor(months / 12) .. " years ago"
end

-- "1 year, 2 months" style span for anniversaries and time in rank.
function GL:Span(seconds)
    if type(seconds) ~= "number" or seconds < 0 then return "" end
    local days = math.floor(seconds / 86400)
    if days < 1 then return "less than a day" end
    if days < 30 then return days .. (days == 1 and " day" or " days") end
    local months = math.floor(days / 30.4)
    if months < 12 then return months .. (months == 1 and " month" or " months") end
    local years, rest = math.floor(months / 12), months % 12
    local text = years .. (years == 1 and " year" or " years")
    if rest > 0 then text = text .. ", " .. rest .. (rest == 1 and " month" or " months") end
    return text
end

-- Parses "2026-11-04", "11/04/2026", "4 Nov 2026" or "04.11.2026" into an epoch at noon server time; nil if not a date.
local MONTHS = { jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12 }

function GL:ParseDate(text)
    if type(text) ~= "string" then return nil end
    text = strtrim(text)
    local y, m, d = string.match(text, "^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
    if not y then m, d, y = string.match(text, "^(%d%d?)/(%d%d?)/(%d%d%d%d)$") end
    if not y then d, m, y = string.match(text, "^(%d%d?)%.(%d%d?)%.(%d%d%d%d)$") end
    if not y then
        local day, monthName, year = string.match(text, "^(%d%d?)%s+(%a+)%s+(%d%d%d%d)$")
        if day then
            m = MONTHS[string.lower(string.sub(monthName, 1, 3))]
            d, y = day, year
        end
    end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not (y and m and d) or m < 1 or m > 12 or d < 1 or d > 31 or y < 2000 or y > 2100 then return nil end
    return time({ year = y, month = m, day = d, hour = 12, min = 0, sec = 0 })
end

-- Parses a birthday without a year: "11/04", "4 Nov", "Nov 4", "11-04". Returns month, day.
function GL:ParseMonthDay(text)
    if type(text) ~= "string" then return nil end
    text = strtrim(text)
    local m, d = string.match(text, "^(%d%d?)[/%-%.](%d%d?)$")
    if not m then
        local day, monthName = string.match(text, "^(%d%d?)%s+(%a+)$")
        if not day then monthName, day = string.match(text, "^(%a+)%s+(%d%d?)$") end
        if day then m, d = MONTHS[string.lower(string.sub(monthName, 1, 3))], day end
    end
    m, d = tonumber(m), tonumber(d)
    if not (m and d) or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return m, d
end

local MONTH_NAMES = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
function GL:FormatMonthDay(m, d)
    if not (m and d) then return "" end
    return tostring(d) .. " " .. (MONTH_NAMES[m] or "?")
end

-- Days until the next occurrence of month/day from `now` (0 = today).
function GL:DaysUntil(m, d, now)
    now = now or self:Now()
    local today = date("*t", now)
    local this = time({ year = today.year, month = m, day = d, hour = 12 })
    local midday = time({ year = today.year, month = today.month, day = today.day, hour = 12 })
    local diff, year = math.floor((this - midday) / 86400 + 0.5), today.year
    if diff < 0 then
        year = today.year + 1
        this = time({ year = year, month = m, day = d, hour = 12 })
        diff = math.floor((this - midday) / 86400 + 0.5)
    end
    return diff, year
end

-- Events -------------------------------------------------------------------------------------------
local nextId = 0

-- Adds a record to the guild's ledger. fields: who, by, from, to, level, text, src ("scan" | "game" | "user" | "sync" | "import").
function GL:AddEvent(guild, kind, fields, t)
    nextId = nextId + 1
    local event = { t = t or self:Now(), k = kind, src = fields.src or "scan", id = string.format("%x%03d", self:Now(), nextId % 1000) }
    for key, value in pairs(fields) do
        if key ~= "src" then event[key] = value end
    end
    guild.events[#guild.events + 1] = event
    self:Announce(event, guild)
    if self.OnLedgerChanged then self:OnLedgerChanged(guild, event) end
    return event
end

-- The most recent event of a kind about a member within `window` seconds of `t`, or nil.
function GL:FindEvent(guild, kind, who, t, window)
    local best
    for i = #guild.events, 1, -1 do
        local event = guild.events[i]
        if event.k == kind and event.who == who and math.abs(event.t - t) <= window then
            if not best or math.abs(event.t - t) < math.abs(best.t - t) then best = event end
        end
        if event.t < t - window - 86400 then break end   -- events are roughly in time order
    end
    return best
end

-- All events about one member, newest first.
function GL:EventsFor(guild, name)
    local list = {}
    for i = #guild.events, 1, -1 do
        local event = guild.events[i]
        if event.who == name or event.from == name or event.by == name then list[#list + 1] = event end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

-- One readable line for an event, with class colours when the member is known.
function GL:Describe(event, guild)
    local who = event.who or "?"
    local member = guild and self:Member(guild, who)
    local name = member and self:ColoredName(member) or ("|cffffffff" .. who .. "|r")
    local by = event.by and ("|cffffffff" .. event.by .. "|r")
    local kind = event.k
    -- Main or alt after the name, like Guild Roster Manager's (M): a character that is nobody's alt is a main.
    -- Not on joins (nobody knows yet) or on the lines that are about the link itself.
    if member and kind ~= "join" and kind ~= "rejoin" and kind ~= "alt" and kind ~= "main" and kind ~= "rename" then
        name = name .. self:MainTag(guild, member)
    end
    if kind == "join" or kind == "rejoin" then
        local text = name .. (kind == "rejoin" and " rejoined the guild" or " joined the guild")
        if event.level then text = text .. " at level " .. event.level end
        if by then text = text .. ", invited by " .. by end
        return text .. "."
    elseif kind == "leave" or kind == "kick" then
        local text = name .. (kind == "kick" and " was removed from the guild" or " left the guild")
        if by and kind == "kick" then text = text .. " by " .. by end
        if event.level then text = text .. " at level " .. tostring(event.level) end
        local since = event.since or (member and member.joined)
        if since and event.t and event.t > since then text = text .. " after " .. self:Span(event.t - since) .. " as a member" end
        if event.from then text = text .. " (" .. tostring(event.from) .. ")" end
        return text .. "."
    elseif kind == "promote" or kind == "demote" then
        local text = name .. (kind == "promote" and " was promoted" or " was demoted")
        if event.from and event.to then text = text .. " from " .. event.from .. " to " .. event.to
        elseif event.to then text = text .. " to " .. event.to end
        if by then text = text .. " by " .. by end
        return text .. "."
    elseif kind == "level" then
        local level, from = tonumber(event.level), tonumber(event.from)
        local gained = (level and from) and (level - from) or nil
        return name .. " reached level " .. tostring(event.level) .. (gained and gained > 1 and (" (+" .. gained .. ")") or "") .. "."
    elseif kind == "note" then
        return name .. "'s note is now \"" .. tostring(event.to or "") .. "\"."
    elseif kind == "onote" then
        return name .. "'s officer note is now \"" .. tostring(event.to or "") .. "\"."
    elseif kind == "custom" then
        return name .. "'s Tabard note is now \"" .. tostring(event.to or "") .. "\"" .. (by and (" (" .. by .. ")") or "") .. "."
    elseif kind == "rename" then
        return "|cffffffff" .. tostring(event.from) .. "|r is now known as " .. name .. "."
    elseif kind == "rank" then
        return "Rank \"" .. tostring(event.from) .. "\" was renamed to \"" .. tostring(event.to) .. "\"."
    elseif kind == "back" then
        return name .. " is back after " .. tostring(event.text or "a break") .. "."
    elseif kind == "alt" then
        return name .. " is now an alt of |cffffffff" .. tostring(event.to) .. "|r" .. (by and (" (" .. by .. ")") or "") .. "."
    elseif kind == "main" then
        return name .. " is now the main of their group" .. (by and (" (" .. by .. ")") or "") .. "."
    elseif kind == "ban" then
        return name .. " was banned" .. (by and (" by " .. by) or "") .. (event.text and event.text ~= "" and (": " .. event.text) or "") .. "."
    elseif kind == "unban" then
        return name .. "'s ban was lifted" .. (by and (" by " .. by) or "") .. "."
    elseif kind == "joindate" then
        return name .. "'s join date was set to " .. self:FormatDate(event.to) .. (by and (" by " .. by) or "") .. "."
    elseif kind == "promodate" then
        return name .. "'s promotion date was set to " .. self:FormatDate(event.to) .. (by and (" by " .. by) or "") .. "."
    elseif kind == "birthday" then
        return name .. "'s birthday was set to " .. tostring(event.text or "") .. (by and (" by " .. by) or "") .. "."
    elseif kind == "nick" then
        if event.to and event.to ~= "" then return name .. " goes by \"" .. tostring(event.to) .. "\" now" .. (by and (" (" .. by .. ")") or "") .. "." end
        return name .. "'s nickname was cleared" .. (by and (" (" .. by .. ")") or "") .. "."
    end
    return name .. ": " .. tostring(event.text or kind)
end

-- Chat ---------------------------------------------------------------------------------------------
-- Sends a chat line. C_ChatInfo.SendChatMessage always exists on Forever; the bare SendChatMessage global is an
-- alias that the client only loads when the "loadDeprecationFallbacks" CVar is on. Raises the same blocked /
-- forbidden errors as the game call would, so callers keep their ADDON_ACTION_BLOCKED handling.
function GL:SendChat(text, kind, target)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    send(text, kind, nil, target)
    return true
end

function GL:Print(text)
    local frame = DEFAULT_CHAT_FRAME or ChatFrame1
    frame:AddMessage(self.prefix .. tostring(text))
end

function GL:Warn(text)
    local frame = DEFAULT_CHAT_FRAME or ChatFrame1
    frame:AddMessage("|cffff4444Tabard:|r " .. tostring(text))
    local plainText = "Tabard: " .. (string.gsub(tostring(text), "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    local color = ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.3, b = 0.3 }
    if RaidWarningUtil and RaidWarningUtil.AddMessage then
        pcall(RaidWarningUtil.AddMessage, plainText, color)
    elseif RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, plainText, color)
    end
end

function GL:Announce(event, guild)
    if self.quiet then return end   -- while importing history or applying shared data
    if event.hold then return end    -- a join waiting a moment for the game's event log to name the inviter
    local announce = self.settings and self.settings.announce
    if announce and announce[event.k] then
        -- The whole line takes the kind's colour (green joins, red leaves, blue level-ups...) so it stands out in
        -- a busy chat frame; names keep their class colour and the line colour resumes after each |r.
        local kind = self.KINDS[event.k]
        local color = kind and kind.color or "ffffffff"
        local text = self:Describe(event, guild)
        text = "|c" .. color .. string.gsub(text, "|r", "|r|c" .. color) .. "|r"
        self:Print(text)
    end
end

-- A guild member logged in: one line in the chat frame, like the level-up lines, with who they are and when
-- they were last on. Only once the first roster read of the session is done (everyone online at login is not
-- "logging in"), never for your own characters. `line` is the fresh roster line; `member` still holds the
-- previous last-online time. Returns true when a line was printed.
local ONLINE_COLOR = "ff33ccaa"
function GL:AnnounceOnline(guild, member, line, now)
    if self.quiet or not self.sessionReady then return false end
    local announce = self.settings and self.settings.announce
    if not (announce and announce.online) then return false end
    if not (guild and member and member.name) or member.name == self:PlayerName() then return false end
    if self.db and self.db.mine then
        local key = self:GuildKey()
        local mine = key and self.db.mine[key]
        if mine and mine[member.name] then return false end
    end
    local name = self:ColoredName(member) .. self:MainTag(guild, member)
    local nick = self:Nickname(guild, member)
    local facts = {}
    local level = line and line.level or member.level
    if level and level > 0 then facts[#facts + 1] = "level " .. level .. (member.class and (" " .. self:ClassName(member.class)) or "") end
    if member.lastOnline and now and now - member.lastOnline >= 3600 then facts[#facts + 1] = "last on " .. self:Ago(member.lastOnline, now) end
    local text = name .. (nick and (" |cffffffff\"" .. nick .. "\"|r") or "") .. " is online" .. (#facts > 0 and (" (" .. table.concat(facts, ", ") .. ")") or "") .. "."
    text = "|c" .. ONLINE_COLOR .. string.gsub(text, "|r", "|r|c" .. ONLINE_COLOR) .. "|r"
    self:Print(text)
    return true
end

-- Stamps -------------------------------------------------------------------------------------------
-- Every shareable field remembers when it was last set so that the newest value wins between officers.
function GL:Stamp(member, field, t)
    member.stamps = member.stamps or {}
    member.stamps[field] = t or self:Now()
end

function GL:StampOf(member, field)
    return member and member.stamps and member.stamps[field] or 0
end

-- Join and promotion dates -----------------------------------------------------------------------------
-- source: "game" (guild event log), "scan" (seen joining), "user" (typed in), "import" (from another addon's data),
-- "sync" (from another officer), "first" (first time seen; a floor, not the date)
local SOURCE_RANK = { first = 1, import = 2, game = 3, scan = 4, sync = 5, user = 5 }
GL.SOURCE_RANK = SOURCE_RANK
GL.SOURCE_LABEL = { game = "from the game's event log", scan = "seen joining", user = "typed in", import = "imported", sync = "shared by an officer", first = "first seen" }

-- A better source replaces a worse one; between equal sources the newer stamp wins. A date typed in here
-- always wins. GL.remote is set while another officer's records are being applied: those carry their
-- original source but are never re-shared.
local function acceptsDate(self, member, field, sourceField, source, stamp)
    local typed = source == "user" and not self.remote
    if typed or not member[field] then return true end
    local current, incoming = SOURCE_RANK[member[sourceField] or ""] or 0, SOURCE_RANK[source] or 0
    if current < incoming then return true end
    if current > incoming then return false end
    return (stamp or 0) > self:StampOf(member, field)
end

function GL:SetJoinDate(guild, name, t, source, record, stamp)
    local member = self:Member(guild, name)
    if not member or type(t) ~= "number" then return false end
    if not acceptsDate(self, member, "joined", "joinedSource", source, stamp) then return false end
    member.joined, member.joinedSource = t, source
    self:Stamp(member, "joined", stamp)
    if record then
        self:AddEvent(guild, "joindate", { who = name, to = t, by = self:PlayerName(), src = "user" })
    end
    if source == "user" and not self.remote and self.Sync then self.Sync:Share(guild, "J", member) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

function GL:SetPromotedDate(guild, name, t, source, record, stamp)
    local member = self:Member(guild, name)
    if not member or type(t) ~= "number" then return false end
    if not acceptsDate(self, member, "promoted", "promotedSource", source, stamp) then return false end
    member.promoted, member.promotedSource = t, source
    self:Stamp(member, "promoted", stamp)
    if record then
        self:AddEvent(guild, "promodate", { who = name, to = t, by = self:PlayerName(), src = "user" })
    end
    if source == "user" and not self.remote and self.Sync then self.Sync:Share(guild, "P", member) end
    if self.OnLedgerChanged then self:OnLedgerChanged(guild) end
    return true
end

-- Slash command -------------------------------------------------------------------------------------
SLASH_TABARD1 = "/tabard"
SlashCmdList["TABARD"] = function(message)
    local command, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    if command ~= "" and GL.Usage then pcall(GL.Usage.Command, GL.Usage, command) end
    if command == "" or command == "show" or command == "toggle" then
        if GL.ToggleWindow then GL:ToggleWindow() end
    elseif command == "scan" then
        GL:RequestScan(true)
        GL:Print("scanning the roster...")
    elseif command == "sync" then
        if GL.Sync then GL.Sync:Hello(true) GL:Print("asked other Tabard users in the guild for their data.") end
    elseif command == "import" then
        if GL.ImportFromGRM then GL:ImportFromGRM(rest == "apply") end
    elseif command == "minimap" then
        GL.settings.minimap.shown = not GL.settings.minimap.shown
        if GL.UpdateMinimapButton then GL:UpdateMinimapButton() end
        GL:Print("minimap button " .. (GL.settings.minimap.shown and "shown" or "hidden") .. ".")
    elseif command == "welcome" then
        if GL.Welcome then GL.Welcome:Command(rest) end
    elseif command == "shout" then
        if GL.Shout then GL.Shout:Command(rest) end
    elseif command == "hints" then
        if GL.Hints then GL.Hints:Command(rest) end
    elseif command == "invite" or command == "ginvite" then
        if GL.Invite then GL.Invite:Command(rest) end
    elseif command == "nick" or command == "nickname" then
        -- /tabard nick Check Myspeed = Checky   (nothing after "=" clears it)
        local guild = GL:Guild()
        local who, nick = string.match(rest or "", "^(.-)%s*=%s*(.-)$")
        if not guild then GL:Print("you are not in a guild.")
        elseif not who or who == "" then GL:Print("usage: |cffffffff/tabard nick NAME = NICKNAME|r sets what someone goes by (shown after their name in guild chat); |cffffffff/tabard nick NAME =|r clears it.")
        else
            local member = GL:FindMember(guild, who, true)
            if not member then GL:Print("no member called \"" .. who .. "\".")
            else
                GL:SetNickname(guild, member, nick, "user")
                local target = GL:MainOf(guild, member) or member
                GL:Print(GL:ColoredName(target) .. (target.nick and (" goes by \"" .. target.nick .. "\" now.") or " has no nickname now."))
                if GL.RefreshWindow then GL:RefreshWindow() end
            end
        end
    elseif command == "todo" or command == "requests" then
        if GL.Officers then GL.Officers:Command(rest) end
    elseif command == "raid" then
        if GL.Raids then GL.Raids:Command(rest) end
    elseif command == "backup" or command == "restore" or command == "tidy" or command == "size" then
        if GL.KeepCommand then GL:KeepCommand(command == "size" and "" or command) end
    elseif command == "art" or command == "background" or command == "theme" then
        if GL.ArtCommand then GL:ArtCommand(rest) end
    elseif command == "usage" then
        if GL.Usage then GL.Usage:ShowOwn() end
    elseif command == "users" then
        if GL.Usage then GL.Usage:ShowUsers() end
    elseif command == "status" then
        local guild = GL:Guild()
        if not guild then GL:Print("you are not in a guild.") return end
        local members, dated = 0, 0
        for _, member in pairs(guild.members) do
            members = members + 1
            if member.joined then dated = dated + 1 end
        end
        GL:Print(string.format("%s: %d members, %d with a join date, %d alt groups, %d bans, %d events recorded, %d scans.",
            guild.name, members, dated, GL:Count(guild.groups), GL:Count(guild.bans), #guild.events, guild.scans or 0))
    else
        GL:Print("commands: |cffffffff/tabard|r opens the window, |cffffffff/tabard scan|r rescans the roster, |cffffffff/tabard sync|r asks other officers for their data, |cffffffff/tabard import|r previews a GRM import (|cffffffff/tabard import apply|r applies it), |cffffffff/tabard minimap|r toggles the button, |cffffffff/tabard status|r shows what is recorded, |cffffffff/tabard art next|r changes the background, |cffffffff/tabard welcome|r sets up welcome whispers for new members, |cffffffff/tabard shout|r sets up guild chat shoutouts for level milestones, |cffffffff/tabard nick NAME = NICKNAME|r sets what someone goes by in chat, |cffffffff/tabard users|r lists the other Tabard users in the guild and what they use, |cffffffff/tabard usage|r shows your own usage line to copy, |cffffffff/tabard invite NAME|r puts up the Invite button.")
    end
end
