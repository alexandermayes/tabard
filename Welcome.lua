-- Tabard: welcome whispers
-- Whispers every new member a personalized welcome, rotating through a list of lines so no two
-- joiners in a row get the same one. Lines read like a short text from the officer, not a form letter.
--
-- Delivery: the client may refuse chat sent from a timer (reported on WoW Forever), so by default a
-- welcome is queued and goes out on your next click or chat line ("click" mode). "auto" mode tries the
-- timer first and falls back to click mode for the session if the game blocks it.
--
-- /tabard welcome              status
-- /tabard welcome on|off       enable or disable
-- /tabard welcome test         whisper yourself the next line (proves the whole path)
-- /tabard welcome preview NAME show what NAME would get, without sending
-- /tabard welcome list         show the rotation
-- /tabard welcome add TEXT     add a line ({name} {class} {level} {me} are replaced)
-- /tabard welcome remove N     remove line N
-- /tabard welcome reset        restore the stock lines
-- /tabard welcome delay N      seconds to wait after the join (default 8)
-- /tabard welcome mode click|auto
-- /tabard welcome rank N       only send when my rank index is N or better (0 = guild leader; default 1)

local ADDON_NAME, GL = ...
local Welcome = {}
GL.Welcome = Welcome

-- Stock lines: first person, statements only, no questions, nothing guild-specific. Every one must stay under
-- 255 bytes after the placeholders are filled in; the composer trims if a long name pushes it over.
-- Guilds add their own lines (Discord link, raid nights) in Settings.
local DEFAULT_LINES = {
    "Hey {name}, welcome to the guild. I'm {me}, say hi in guild chat whenever.",
    "Welcome in {name}. If you need anything, ask in guild chat or whisper me, I'm {me}.",
    "Hey {name}, glad you joined. People are usually around for dungeons, just ask.",
    "Welcome {name}. Level {level} {class}, nice. Shout in guild chat when you want a group.",
    "Hey {name}, {me} here. Welcome aboard, ask in guild chat whenever you want a group.",
    "{name}, welcome to the guild. Nothing you have to do, just hang out and play.",
    "Welcome in {name}. Guild chat is the easy way to find people to play with.",
    "Hey {name}, good to have you. Ask in guild chat if you have questions, someone will help.",
}

local DEFAULT_BACK_LINES = {
    "Welcome back {name}. Good to have you in the guild again.",
    "Hey {name}, welcome back. Say hi in guild chat when you're on.",
    "{name}, welcome back in. I'm {me} if you need anything.",
}

local CLASS_NAMES = {
    WARRIOR = "warrior", PALADIN = "paladin", HUNTER = "hunter", ROGUE = "rogue", PRIEST = "priest",
    SHAMAN = "shaman", MAGE = "mage", WARLOCK = "warlock", DRUID = "druid", DEATHKNIGHT = "death knight",
    MONK = "monk", DEMONHUNTER = "demon hunter", EVOKER = "evoker",
}

local DEFAULTS = {
    enabled = false,      -- opt in: off until an officer turns it on in Settings
    delay = 8,            -- seconds after the join before the whisper is due
    mode = "click",       -- "click": send on the next click/chat line; "auto": try a timer first
    minRank = 1,          -- send only when my rank index is this or better (0 = guild leader)
    repeatDays = 14,      -- do not welcome the same name twice within this many days
    maxWait = 900,        -- drop a queued welcome that could not be sent after this many seconds
    lines = nil,          -- custom rotation; nil = DEFAULT_LINES
    cursor = 1,           -- rotation position
    backCursor = 1,
}

local MAX_BYTES = 255

-- Settings -------------------------------------------------------------------------------------
local function settings()
    if not GL.settings then return nil end
    local s = GL.settings.welcome
    if type(s) ~= "table" then s = {}; GL.settings.welcome = s end
    for key, value in pairs(DEFAULTS) do
        if s[key] == nil and value ~= nil then s[key] = value end
    end
    return s
end

local function lines()
    local s = settings()
    local list = s and s.lines
    if type(list) == "table" and #list > 0 then return list, true end
    return DEFAULT_LINES, false
end

-- Composition ----------------------------------------------------------------------------------
local function tidy(text)
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

-- Fills a template for one member. ctx = { name, class (classFile), level, me }
function Welcome:Compose(template, ctx)
    local classFile = ctx.class and string.upper(ctx.class) or nil
    local className = classFile and CLASS_NAMES[classFile] or "adventurer"
    local text = template
    text = string.gsub(text, "{name}", ctx.name or "there")
    text = string.gsub(text, "{class}", className)
    text = string.gsub(text, "{level}", tostring(ctx.level or "?"))
    text = string.gsub(text, "{me}", ctx.me or GL:PlayerFirstName())
    -- 1.0.0 added a sentence per class here ("Rogues are handy for us..."). It read oddly, so it is gone;
    -- saved lines that still carry the placeholder get nothing in its place.
    text = string.gsub(text, "{classbit}", "")
    text = tidy(text)
    if #text > MAX_BYTES then text = string.sub(text, 1, MAX_BYTES - 1) end
    return text
end

-- The next template in the rotation (advances the cursor when `take` is true).
function Welcome:NextTemplate(kind, take)
    local s = settings()
    local list = (kind == "rejoin") and DEFAULT_BACK_LINES or lines()
    local key = (kind == "rejoin") and "backCursor" or "cursor"
    local i = tonumber(s and s[key]) or 1
    if i < 1 or i > #list then i = 1 end
    if take and s then s[key] = (i % #list) + 1 end
    return list[i], i
end

-- Looks the member up in the ledger, then the live roster, for class and level.
local function contextFor(name)
    local ctx = { name = name, me = GL:PlayerFirstName() }
    local guild = GL:Guild()
    local member = guild and GL:Member(guild, name)
    if member then ctx.class, ctx.level, ctx.online = member.class, member.level, member.online end
    if (not ctx.class or ctx.online == nil) and GetNumGuildMembers then
        for i = 1, (GetNumGuildMembers() or 0) do
            local rosterName, _, _, level, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
            if rosterName and GL:ShortName(rosterName) == name then
                ctx.class = ctx.class or classFile
                ctx.level = ctx.level or level
                ctx.online = isOnline and true or false
                break
            end
        end
    end
    return ctx
end

-- Queue -----------------------------------------------------------------------------------------
local queue = {}            -- { name, kind, queuedAt, dueAt }
local clickOnly = false     -- set for the session once the game blocks an auto send
local lastAuto = nil        -- the item last sent from the timer, in case the game blocks it

local function myRankOk()
    local s = settings()
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex == nil then return false end
    return rankIndex <= (s.minRank or 1)
end

local function welcomedRecently(guild, name)
    local s = settings()
    local list = guild.welcomed
    if type(list) ~= "table" then return false end
    local t = list[name]
    return t and (GL:Now() - t) < (s.repeatDays or 14) * 86400
end

local function markWelcomed(guild, name)
    if type(guild.welcomed) ~= "table" then guild.welcomed = {} end
    guild.welcomed[name] = GL:Now()
end

local function queued(name)
    for _, item in ipairs(queue) do if item.name == name then return item end end
    return nil
end

-- live: the join happened just now while you were online (the system line, or a scan after the first one).
function Welcome:OnJoin(guild, member, kind, live)
    local s = settings()
    if not (s and s.enabled) or not live then return end
    local name = type(member) == "table" and member.name or member
    if not name or name == GL:PlayerName() then return end
    if not myRankOk() then return end
    if welcomedRecently(guild, name) or queued(name) then return end
    local now = GetTime()
    queue[#queue + 1] = { name = name, kind = kind or "join", queuedAt = now, dueAt = now + (s.delay or 8) }
    if s.mode == "auto" and not clickOnly then
        C_Timer.After((s.delay or 8) + 0.5, function() Welcome:Pump(true) end)
    else
        GL:Print("welcome for |cffffffff" .. name .. "|r is ready; it goes out on your next click or chat line.")
    end
end

-- Sends one due welcome. Called from click hooks (auto = false) and the auto timer (auto = true).
function Welcome:Pump(auto)
    if #queue == 0 then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local s = settings()
    local now = GetTime()
    local guild = GL:Guild()
    if not guild then return false end
    for i, item in ipairs(queue) do
        if now - item.queuedAt > (s.maxWait or 900) then
            table.remove(queue, i)
            GL:Print("dropped the welcome for " .. item.name .. " (could not send it in time).")
            return false
        end
        if now >= item.dueAt then
            local ctx = contextFor(item.name)
            if ctx.online == false then
                -- not online yet or already gone: try again on the next pump
                item.dueAt = now + 5
            else
                local template = self:NextTemplate(item.kind, true)
                local text = self:Compose(template, ctx)
                table.remove(queue, i)
                markWelcomed(guild, item.name)
                if auto then lastAuto = { item = item, at = now } end
                GL:SendChat(text, "WHISPER", item.name)
                return true
            end
        end
    end
    return false
end

-- Click delivery: any of these is a hardware event the client accepts chat from.
local function pumpClick()
    if #queue > 0 then Welcome:Pump(false) end
    if GL.Shout then GL.Shout:Pump(false) end
end
if WorldFrame and WorldFrame.HookScript then WorldFrame:HookScript("OnMouseDown", pumpClick) end
if ChatEdit_SendText then hooksecurefunc("ChatEdit_SendText", pumpClick) end
-- Enter in a chat box calls the box's own method, not the ChatEdit_SendText global (that is only an alias the
-- client loads with deprecation fallbacks), so hook every chat window's edit box as well.
for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local box = _G["ChatFrame" .. i .. "EditBox"]
    if box and box.HookScript then box:HookScript("OnEnterPressed", pumpClick) end
end
if ActionButtonDown then hooksecurefunc("ActionButtonDown", pumpClick) end
if ToggleGameMenu then hooksecurefunc("ToggleGameMenu", pumpClick) end

-- Join detection: the system line arrives the moment someone joins, before the roster updates.
local joinPattern
if ERR_GUILD_JOIN_S then
    joinPattern = "^" .. string.gsub(string.gsub(ERR_GUILD_JOIN_S, "[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"), "%%%%s", "(.+)") .. "$"
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "CHAT_MSG_SYSTEM" then
        if not (joinPattern and GL.db and type(arg1) == "string") or (issecretvalue and issecretvalue(arg1)) then return end
        local name = string.match(arg1, joinPattern)
        if not name then return end
        name = GL:ShortName(name)
        local guild = GL:Guild()
        if not guild then return end
        local former = guild.former and guild.former[name]
        Welcome:OnJoin(guild, name, former and "rejoin" or "join", true)
        if GL.RequestScan then GL:RequestScan(true) end
    elseif event == "ADDON_ACTION_BLOCKED" then
        if arg1 ~= ADDON_NAME or not (type(arg2) == "string" and string.find(arg2, "SendChatMessage")) then return end
        clickOnly = true
        if lastAuto and (GetTime() - lastAuto.at) < 2 then
            local item = lastAuto.item
            lastAuto = nil
            local guild = GL:Guild()
            if guild and guild.welcomed then guild.welcomed[item.name] = nil end
            item.dueAt = GetTime()
            queue[#queue + 1] = item
            GL:Print("the game blocked the timed welcome for " .. item.name .. "; it goes out on your next click instead. Welcomes use click mode for the rest of this session.")
        end
    end
end)

-- Slash ------------------------------------------------------------------------------------------
local function describeMode(s)
    if s.mode == "auto" and not clickOnly then return "auto (timer first, click if the game blocks it)" end
    return "click (goes out on your next click or chat line)"
end

function Welcome:Command(rest)
    local s = settings()
    if not s then GL:Print("not loaded yet.") return end
    local sub, arg = string.match(rest or "", "^(%S*)%s*(.-)%s*$")
    sub = string.lower(sub or "")
    if sub == "" or sub == "status" then
        local list, custom = lines()
        GL:Print(string.format("welcome whispers are %s. %d lines%s, next is #%d. Delay %ds, %s, rank %d or better. %d queued.",
            s.enabled and "|cff33dd33on|r" or "|cffff5555off|r", #list, custom and " (custom)" or "", s.cursor or 1, s.delay or 8, describeMode(s), s.minRank or 1, #queue))
        if not myRankOk() then GL:Print("|cffff9933this character's rank is below the sender rank, so it will not send welcomes.|r") end
    elseif sub == "on" or sub == "off" then
        s.enabled = (sub == "on")
        GL:Print("welcome whispers " .. (s.enabled and "on" or "off") .. ".")
    elseif sub == "test" then
        local me = GL:PlayerName()
        local ctx = contextFor(me)
        ctx.class = ctx.class or select(2, UnitClass("player"))
        ctx.level = ctx.level or UnitLevel("player")
        local template = self:NextTemplate("join", true)
        GL:SendChat(self:Compose(template, ctx), "WHISPER", me)
    elseif sub == "preview" then
        local name = arg ~= "" and arg or GL:PlayerName()
        local ctx = contextFor(name)
        if name == GL:PlayerName() then ctx.class = ctx.class or select(2, UnitClass("player")); ctx.level = ctx.level or UnitLevel("player") end
        local template, i = self:NextTemplate("join", false)
        GL:Print("next line (#" .. i .. ") for " .. name .. ":")
        GL:Print("|cffffffff" .. self:Compose(template, ctx) .. "|r")
    elseif sub == "list" then
        local list, custom = lines()
        GL:Print((custom and "custom" or "stock") .. " rotation (" .. #list .. " lines):")
        for i, line in ipairs(list) do GL:Print(string.format("%s%d.|r %s", i == (s.cursor or 1) and "|cff33dd33" or "|cff808080", i, line)) end
    elseif sub == "add" then
        if arg == "" then GL:Print("usage: /tabard welcome add TEXT") return end
        if #arg > 230 then GL:Print("that line is too long; keep it under 230 characters so the name fits.") return end
        local list, custom = lines()
        if not custom then
            s.lines = {}
            for _, line in ipairs(list) do s.lines[#s.lines + 1] = line end
        end
        s.lines[#s.lines + 1] = arg
        GL:Print("added line #" .. #s.lines .. ".")
    elseif sub == "remove" then
        local n = tonumber(arg)
        local list, custom = lines()
        if not n or not list[n] then GL:Print("usage: /tabard welcome remove N") return end
        if not custom then
            s.lines = {}
            for _, line in ipairs(list) do s.lines[#s.lines + 1] = line end
        end
        table.remove(s.lines, n)
        if #s.lines == 0 then s.lines = nil end
        s.cursor = 1
        GL:Print("removed line #" .. n .. ".")
    elseif sub == "reset" then
        s.lines, s.cursor, s.backCursor = nil, 1, 1
        GL:Print("stock lines restored.")
    elseif sub == "delay" then
        local n = tonumber(arg)
        if not n then GL:Print("usage: /tabard welcome delay SECONDS") return end
        s.delay = math.max(2, math.min(120, n))
        GL:Print("delay set to " .. s.delay .. "s.")
    elseif sub == "mode" then
        if arg ~= "click" and arg ~= "auto" then GL:Print("usage: /tabard welcome mode click|auto") return end
        s.mode = arg
        GL:Print("mode set to " .. describeMode(s) .. ".")
    elseif sub == "rank" then
        local n = tonumber(arg)
        if not n then GL:Print("usage: /tabard welcome rank N (0 = guild leader)") return end
        s.minRank = math.max(0, math.floor(n))
        GL:Print("welcomes are sent when my rank index is " .. s.minRank .. " or better.")
    elseif sub == "send" then
        if not self:Pump(false) then GL:Print("nothing due to send.") end
    else
        GL:Print("welcome commands: status, on, off, test, preview NAME, list, add TEXT, remove N, reset, delay N, mode click|auto, rank N, send")
    end
end

-- For the window's line editor: the active join lines and whether they are custom; the setter takes a list,
-- or nil to go back to the stock lines.
function Welcome:Lines()
    return lines()
end

function Welcome:SetLines(list)
    local s = settings()
    if not s then return end
    if type(list) == "table" and #list > 0 then s.lines = list else s.lines = nil end
    s.cursor = 1
end
