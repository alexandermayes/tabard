-- Tabard: usage counts
-- Counts how this copy of Tabard is used, so the parts people rely on can get the attention: on how many days
-- the window was opened, which pages, how many member cards, which slash commands, and which features are
-- switched on. Only counts and switches: never names, notes or chat. Kept in TabardDB.usage.
--
-- An addon cannot reach the internet, so none of this goes anywhere by itself. The counts travel with the
-- sharing hello to other Tabard users in the same guild (settings.shareUsage, on by default, Settings >
-- Sharing and tooltips), where /tabard users lists them; /tabard usage shows this copy's line ready to copy,
-- for a Discord post or a CurseForge comment.
--
-- Wire format (Sync.lua, message "U  version  usage"): "key=value" pairs joined by ";"
--   s  days since counting started      d  days the window was used      o  opened by hand    a  opened at login
--   p  page views, "ov12,mb7"           c  member cards opened           k  slash commands, "sy2,nk1"
--   f  features on, "wl,sh,hi"          l  open at login (always/todo/never)   b  background
--   g  guild size (to the nearest 10)   r  own rank index (0 = guild leader)  n  other Tabard users in the guild

local ADDON_NAME, GL = ...

local Usage = { auto = false }
GL.Usage = Usage

local WIRE_LIMIT = 230   -- the usage part of a "U" message; Sync messages stop at 250 bytes

-- Pages of the window: key, wire code, name in the readable line.
local PAGES = {
    { "overview", "ov", "Overview" }, { "todo", "td", "To-do" }, { "log", "lg", "Log" }, { "members", "mb", "Members" },
    { "play", "pl", "Play" }, { "former", "fm", "Former" }, { "bans", "bn", "Bans" }, { "tools", "tl", "Tools" },
    { "export", "ex", "Export" }, { "settings", "st", "Settings" },
}
-- Slash commands that are counted (opening the window is counted as an open, not a command), with aliases.
local COMMANDS = {
    { "scan", "sc" }, { "sync", "sy" }, { "import", "im" }, { "minimap", "mm" }, { "welcome", "wl" }, { "shout", "sh" },
    { "hints", "hi" }, { "nick", "nk" }, { "todo", "td" }, { "raid", "rd" }, { "backup", "bk" }, { "restore", "rs" },
    { "tidy", "ti" }, { "size", "sz" }, { "art", "ar" }, { "status", "su" }, { "usage", "us" }, { "users", "ur" },
}
local ALIASES = { nickname = "nick", requests = "todo", background = "art", theme = "art" }
-- Features: wire code, name, whether it is on.
local function on(value, default) if value == nil then return default end return value and true or false end
local FEATURES = {
    { "wl", "welcome whispers", function(s) return type(s.welcome) == "table" and s.welcome.enabled == true end },
    { "sh", "shoutouts", function(s) return type(s.shout) == "table" and s.shout.enabled == true end },
    { "on", "online lines", function(s) return type(s.announce) == "table" and s.announce.online ~= false end },
    { "hi", "chat hints", function(s) return on(s.hints, true) end },
    { "tt", "tooltips", function(s) return on(s.tooltip, true) end },
    { "aa", "alts from notes", function(s) return on(s.autoAlts, true) end },
    { "fw", "first week", function(s) return on(s.firstWeek, true) end },
    { "an", "anniversaries", function(s) return on(s.anniversaries, true) end },
    { "lr", "login report", function(s) return on(s.loginReport, true) end },
    { "rq", "whispered requests", function(s) return on(s.requests, true) end },
    { "rt", "raid tracking", function(s) return on(s.raidTracking, true) end },
    { "mm", "minimap button", function(s) return type(s.minimap) ~= "table" or s.minimap.shown ~= false end },
}

local PAGE_BY_KEY, PAGE_BY_CODE, COMMAND_CODE, COMMAND_BY_CODE, FEATURE_BY_CODE = {}, {}, {}, {}, {}
for _, page in ipairs(PAGES) do PAGE_BY_KEY[page[1]] = page PAGE_BY_CODE[page[2]] = page end
for _, command in ipairs(COMMANDS) do COMMAND_CODE[command[1]] = command[2] COMMAND_BY_CODE[command[2]] = command[1] end
for _, feature in ipairs(FEATURES) do FEATURE_BY_CODE[feature[1]] = feature end

local function now() return GL.Now and GL:Now() or (GetServerTime and GetServerTime()) or 0 end
local function today() return math.floor(now() / 86400) end

-- The saved counts, created on first use.
function Usage:Data()
    local db = GL.db
    if type(db) ~= "table" then return nil end
    local u = db.usage
    if type(u) ~= "table" then u = { since = now() } db.usage = u end
    if type(u.pages) ~= "table" then u.pages = {} end
    if type(u.commands) ~= "table" then u.commands = {} end
    u.since = u.since or now()
    return u
end

local function touch(u)
    local day = today()
    if u.lastDay ~= day then u.lastDay = day u.days = (u.days or 0) + 1 end
end

local function bump(key, sub)
    local u = Usage:Data()
    if not u then return end
    if sub then u[key][sub] = (u[key][sub] or 0) + 1 else u[key] = (u[key] or 0) + 1 end
    touch(u)
end

-- Called by the window: opened (by hand or at login), a page shown, a member card opened.
function Usage:Opened()
    if self.auto then
        local u = self:Data()
        if u then u.auto = (u.auto or 0) + 1 end
    else
        bump("opens")
    end
end

function Usage:Page(key)
    if self.auto or not PAGE_BY_KEY[key] then return end
    bump("pages", key)
end

function Usage:Card()
    bump("cards")
end

function Usage:Command(command)
    command = ALIASES[command] or command
    if COMMAND_CODE[command] then bump("commands", command) end
end

-- Encoding ------------------------------------------------------------------------------------------------
local function sortedCounts(counts, codeOf)
    local list = {}
    for key, n in pairs(counts or {}) do
        local code = codeOf(key)
        if code and type(n) == "number" and n > 0 then list[#list + 1] = { code = code, n = n } end
    end
    table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.code < b.code end)
    local parts = {}
    for _, item in ipairs(list) do parts[#parts + 1] = item.code .. item.n end
    return table.concat(parts, ",")
end

local function clean(value)
    return (string.gsub(tostring(value or ""), "[^%w%-_]", ""))
end

-- This copy's counts as the compact wire string.
function Usage:Wire()
    local u = self:Data()
    if not u then return nil end
    local s = GL.settings or {}
    local parts = {
        "s=" .. math.max(0, math.floor((now() - (u.since or now())) / 86400)),
        "d=" .. (u.days or 0), "o=" .. (u.opens or 0), "a=" .. (u.auto or 0),
        "p=" .. sortedCounts(u.pages, function(key) return PAGE_BY_KEY[key] and PAGE_BY_KEY[key][2] end),
        "c=" .. (u.cards or 0),
    }
    local features = {}
    for _, feature in ipairs(FEATURES) do
        local ok, isOn = pcall(feature[3], s)
        if ok and isOn then features[#features + 1] = feature[1] end
    end
    parts[#parts + 1] = "f=" .. table.concat(features, ",")
    parts[#parts + 1] = "l=" .. clean(s.openOnLogin or "always")
    parts[#parts + 1] = "b=" .. clean(s.backgroundArt or "default")
    local guild = IsInGuild and IsInGuild() and GL.Guild and GL:Guild()
    if guild then
        local size, others = 0, 0
        for _ in pairs(guild.members or {}) do size = size + 1 end
        for name in pairs(guild.peers or {}) do if name ~= (GL.PlayerName and GL:PlayerName()) then others = others + 1 end end
        parts[#parts + 1] = "g=" .. (size > 0 and math.max(10, math.floor((size + 5) / 10) * 10) or 0)
        local me = GL.PlayerName and guild.members[GL:PlayerName()]
        if me and me.rankIndex then parts[#parts + 1] = "r=" .. me.rankIndex end
        parts[#parts + 1] = "n=" .. others
    end
    -- Commands last: they are the first thing dropped when the line would not fit in one message.
    local commands = sortedCounts(u.commands, function(key) return COMMAND_CODE[key] end)
    local wire = table.concat(parts, ";")
    if commands ~= "" then
        local full = wire .. ";k=" .. commands
        while #full > WIRE_LIMIT and string.find(commands, ",") do
            commands = string.match(commands, "^(.*),[^,]*$")
            full = wire .. ";k=" .. commands
        end
        if #full <= WIRE_LIMIT then wire = full end
    end
    if #wire > WIRE_LIMIT then wire = string.sub(wire, 1, WIRE_LIMIT) end
    return wire
end

-- A wire string back into a table (unknown keys are kept as text so newer copies can add fields).
function Usage:Decode(wire)
    local t = {}
    for pair in string.gmatch(tostring(wire or "") .. ";", "([^;]*);") do
        local key, value = string.match(pair, "^(%a+)=(.*)$")
        if key then t[key] = value end
    end
    return t
end

local function countList(text, nameOf)
    local list = {}
    for code, n in string.gmatch(tostring(text or ""), "(%a+)(%d+)") do
        list[#list + 1] = (nameOf(code) or code) .. " " .. n
    end
    return list
end

-- The readable line, the same for this copy and for what other users sent.
function Usage:Format(wire, version)
    local t = self:Decode(wire)
    local function n(key) return tonumber(t[key]) or 0 end
    local parts = {}
    local span = n("s") + 1
    parts[#parts + 1] = "Tabard " .. tostring(version or "?") .. ": used on " .. n("d") .. " of " .. span .. (span == 1 and " day" or " days")
    parts[#parts + 1] = "opened " .. n("o") .. " by hand, " .. n("a") .. " at login"
    local pages = countList(t.p, function(code) return PAGE_BY_CODE[code] and PAGE_BY_CODE[code][3] end)
    parts[#parts + 1] = "pages: " .. (#pages > 0 and table.concat(pages, ", ") or "none")
    parts[#parts + 1] = n("c") .. " member cards"
    local commands = countList(t.k, function(code) return COMMAND_BY_CODE[code] and ("/" .. COMMAND_BY_CODE[code]) end)
    if #commands > 0 then parts[#parts + 1] = "commands: " .. table.concat(commands, ", ") end
    local features = {}
    for code in string.gmatch(tostring(t.f or ""), "[^,]+") do features[#features + 1] = FEATURE_BY_CODE[code] and FEATURE_BY_CODE[code][2] or code end
    parts[#parts + 1] = "on: " .. (#features > 0 and table.concat(features, ", ") or "nothing optional")
    parts[#parts + 1] = "opens at login: " .. tostring(t.l or "?") .. ", background: " .. tostring(t.b or "?")
    if t.g then
        local rank = tonumber(t.r)
        parts[#parts + 1] = "guild of about " .. n("g") .. (rank and (rank == 0 and ", guild leader" or (", rank " .. rank)) or "")
            .. ", " .. n("n") .. " other Tabard " .. (n("n") == 1 and "user" or "users")
    end
    return table.concat(parts, "; ")
end

-- Sharing ---------------------------------------------------------------------------------------------------
function Usage:Sharing()
    return GL.settings and GL.settings.shareUsage ~= false
end

-- A "U" message from another Tabard user in the guild (Sync.lua). Kept apart from guild.peers, which every
-- hello rewrites.
function Usage:Receive(guild, sender, version, wire)
    if not (guild and sender and wire) then return end
    guild.peerUsage = type(guild.peerUsage) == "table" and guild.peerUsage or {}
    guild.peerUsage[sender] = { v = string.sub(tostring(version or "?"), 1, 20), u = string.sub(tostring(wire), 1, 250), t = now() }
end

-- Commands --------------------------------------------------------------------------------------------------
local function copyBox(text)
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    StaticPopupDialogs["TABARD_COPY"] = StaticPopupDialogs["TABARD_COPY"] or {
        text = "%s",
        button1 = CLOSE or "Close",
        hasEditBox = true,
        editBoxWidth = 360,
        maxLetters = 1000,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(self, data)
            local box = (self.GetEditBox and self:GetEditBox()) or self.EditBox or self.editBox
            if box and data then box:SetText(data.text or "") box:SetFocus() box:HighlightText() end
        end,
        EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    }
    StaticPopup_Show("TABARD_COPY", "Your Tabard usage. Ctrl+C to copy, then paste it in the Tabard thread on Discord or a CurseForge comment.", nil, { text = text })
end

-- /tabard usage: this copy's line, printed and in a box to copy.
function Usage:ShowOwn()
    local line = self:Format(self:Wire(), GL.version)
    GL:Print(line)
    GL:Print(self:Sharing() and "shared with other Tabard users in your guild (Settings > Sharing and tooltips turns that off)."
        or "not shared: usage sharing is off in Settings > Sharing and tooltips.")
    copyBox(line)
end

-- /tabard users: every other Tabard user in the guild, their version and what they use.
function Usage:ShowUsers()
    local guild = IsInGuild() and GL:Guild()
    if not guild then GL:Print("you are not in a guild.") return end
    local names, seen = {}, {}
    for name in pairs(guild.peers or {}) do if not seen[name] then seen[name] = true names[#names + 1] = name end end
    for name in pairs(guild.peerUsage or {}) do if not seen[name] then seen[name] = true names[#names + 1] = name end end
    table.sort(names)
    if #names == 0 then
        GL:Print("nobody else in the guild has said hello from Tabard yet. |cffffffff/tabard sync|r asks everyone online.")
        return
    end
    GL:Print(#names .. " other Tabard " .. (#names == 1 and "user" or "users") .. " in " .. tostring(guild.name) .. ":")
    for _, name in ipairs(names) do
        local peer, usage = guild.peers and guild.peers[name], guild.peerUsage and guild.peerUsage[name]
        local member = GL:Member(guild, name)
        local who = GL.ColoredName and GL:ColoredName(member, name) or name
        local seenAt = math.max(peer and peer.t or 0, usage and usage.t or 0)
        local ago = GL.Ago and seenAt > 0 and (" (" .. GL:Ago(seenAt, now()) .. ")") or ""
        if usage then
            GL:Print(who .. ago .. " " .. self:Format(usage.u, usage.v))
        else
            GL:Print(who .. ago .. " Tabard " .. tostring(peer and peer.version or "?") .. ": no usage shared (an older Tabard, or sharing is off).")
        end
    end
end
