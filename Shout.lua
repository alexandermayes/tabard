-- Guild-chat shoutouts: a short line in gchat when a member hits a milestone level (and, if turned
-- on, when someone is promoted or logs in after a long break). Each line is picked from a pool for
-- that milestone and gets one true fact about the person tacked on when the ledger has one: how
-- long the last stretch took, how many 60s their account has, how many of their class are at 60,
-- or how long they have been in the guild. Delivery works like the welcome whispers: the line goes
-- out on the next click or chat line, because the client blocks chat sent from a timer.

local ADDON_NAME, GL = ...
local Shout = {}
GL.Shout = Shout

local MAX_BYTES = 255
local MAX_LEVEL = 60

-- Pools by milestone, written the way people actually type in gchat (from a read of real Forever chat):
-- short, no full stops, capitals and stretched letters for the hype ("OO WOO 30", "noiceeee"), the rest
-- lowercase with a :D or <3. {name} and {level} are filled in, {NAME} is the name in capitals; a fact is
-- added in brackets when one fits.
local LINES = {
    [10] = {
        "GZZZ {NAME} 10!!",
        "{NAME} HIT 10 LETS GOOO",
        "HELL YEAH {NAME}!! talents unlocked",
        "10!!! gz {name} :D",
    },
    [20] = {
        "{NAME} 20!!",
        "GZZZZ {NAME}!! LEVEL 20",
        "LETS GOOO {NAME} 20 <3",
        "GZ {NAME} 20!! keep it rolling",
    },
    [30] = {
        "{NAME} 30!!!",
        "GZZZ {NAME} LEVEL 30",
        "HELL YEAH {NAME}!! 30 already",
        "LETS GOOO {NAME} 30!! big number",
    },
    [40] = {
        "{NAME} 40!!! MOUNT TIME",
        "GZZZZ {NAME}!! no more walking",
        "HELL YEAH {NAME} 40!! go get that mount",
        "LETS GOOOO {NAME} 40 <3",
    },
    [50] = {
        "{NAME} 50!!!",
        "GZZZ {NAME} LEVEL 50!! home stretch",
        "LETS GOOO {NAME}!! 10 more",
        "HELL YEAH {NAME} 50!! so close",
    },
    [60] = {
        "{NAME} 60!!!! GZZZZ",
        "GZZZZZ {NAME}!!! LEVEL 60",
        "HELL YEAH {NAME}!! 60!!! <3",
        "LETS GOOOOO {NAME} 60!!!",
        "{NAME} DID IT!! 60!!! welcome to the top",
        "SIXTY!!! gz gz gz {name} :D",
    },
}

-- Used for levels without a pool of their own (every-level mode, or custom milestones).
local ANY_LINES = {
    "gz {name}!!",
    "GZ {NAME} {level}!!",
    "{NAME} {level} LETS GOOO",
    "ding {level} gz {name} :D",
}

-- Rank names are nouns ("Member", "Raider", "Officer"), so lines that say what someone is now use
-- {a rank}, which comes out as "a Raider" or "an Officer" ({A RANK}: "A RAIDER").
local PROMOTE_LINES = {
    "gz on the promo {name}!! <3",
    "{NAME} IS {A RANK}!! hell yeah",
    "{NAME} IS {A RANK} NOW LETS GOOO",
    "GZZZ {NAME}!! officially {a rank} <3",
    "HELL YEAH {NAME}!! {a rank} now :D",
    "{NAME} GOT THE PROMO!! gz :D",
    "welcome to the {rank} club {name} :D",
    "look at {name} go!! {a rank} now <3",
}

local BACK_LINES = {
    "{NAME}!!! wb :D",
    "LOOK WHO'S BACK!! hi {name} <3",
    "wb {name}!! been {away} lol",
}

local DEFAULTS = {
    enabled = false,                 -- opt in: off until an officer turns it on in Settings
    levels = "10 20 30 40 50 60",   -- milestone levels that get a shout
    every = false,                   -- shout every level (milestones keep their own pools)
    promote = false,                 -- shout promotions (the game already prints these)
    back = false,                    -- shout when someone is back after a long break
    delay = 10,                      -- seconds after the ding before the line is due
    mode = "click",                  -- "click" or "auto" (timer first, click if blocked)
    minRank = 0,                     -- only this rank index or better posts (0 = guild leader)
    nameStyle = "firstlower",        -- how {name} is written: "full", "first", "firstlower", "fulllower"
    maxWait = 600,                   -- drop a line that could not be posted after this long
    lines = nil,                     -- custom pools: { ["60"] = { ... }, any = { ... } }
    cursors = nil,                   -- rotation position per pool
}

-- Settings ---------------------------------------------------------------------------------------
local function settings()
    if not GL.settings then return nil end
    local s = GL.settings.shout
    if type(s) ~= "table" then s = {}; GL.settings.shout = s end
    for key, value in pairs(DEFAULTS) do
        if s[key] == nil and value ~= nil then s[key] = value end
    end
    if type(s.cursors) ~= "table" then s.cursors = {} end
    return s
end

local function milestones(s)
    local set = {}
    for n in string.gmatch(s.levels or "", "%d+") do set[tonumber(n)] = true end
    return set
end

-- The pool for a key ("60", "any", "promote", "back"), custom first.
local function pool(key)
    local s = settings()
    local custom = s and type(s.lines) == "table" and s.lines[key]
    if type(custom) == "table" and #custom > 0 then return custom, true end
    local level = tonumber(key)
    if level and LINES[level] then return LINES[level], false end
    if key == "promote" then return PROMOTE_LINES, false end
    if key == "back" then return BACK_LINES, false end
    return ANY_LINES, false
end

local function poolKey(item)
    if item.kind == "level" then
        local key = tostring(item.level)
        if LINES[item.level] or (settings().lines and settings().lines[key]) then return key end
        return "any"
    end
    return item.kind
end

function Shout:NextTemplate(key, take)
    local s = settings()
    local list = pool(key)
    local i = tonumber(s.cursors[key]) or 1
    if i < 1 or i > #list then i = 1 end
    if take then s.cursors[key] = (i % #list) + 1 end
    return list[i], i
end

-- Facts ------------------------------------------------------------------------------------------
local function plural(n, word) return n == 1 and word or (word .. "s") end

local function ordinal(n)
    local words = { "a first", "a second", "a third", "a fourth", "a fifth", "a sixth" }
    return words[n] or ("number " .. n)
end

local function daysBetween(a, b) return math.floor(math.abs(b - a) / 86400 + 0.5) end

-- How long the last stretch took: from the newest level/join event at or below the previous
-- milestone (so every-level mode still reports "50 to 60", not "59 to 60") to now.
local function pace(guild, name, prev, level, now)
    if not (prev and prev > 0) then return nil end
    local target = prev
    for m in pairs(milestones(settings())) do
        if m < level and m <= prev and (target == prev or m > target) then target = m end
    end
    local best
    for i = #guild.events, 1, -1 do
        local e = guild.events[i]
        if e.who == name and (e.k == "level" or e.k == "join" or e.k == "rejoin") and e.level and e.level <= target and e.level < level then
            if not best or e.t > best.t then best = e end
        end
    end
    if not best or now - best.t > 365 * 86400 then return nil end
    local from = best.level
    -- "9 to 10 in under a day" says nothing; only a real stretch is worth a mention.
    if level - from < 5 then return nil end
    local days = daysBetween(best.t, now)
    if days <= 0 then return string.format("%d to %d in under a day", from, level) end
    if days == 1 then return string.format("%d to %d in a day", from, level) end
    return string.format("%d to %d in %d days", from, level, days)
end

local function altsAtMax(guild, member)
    if not GL.AltsOf then return nil end
    local group = GL.GroupOf and GL:GroupOf(guild, member)
    if not group then return nil end
    local count = (member.level or 0) >= MAX_LEVEL and 1 or 0
    for _, other in ipairs(GL:AltsOf(guild, member)) do
        if (other.level or 0) >= MAX_LEVEL then count = count + 1 end
    end
    if count < 2 then return nil end
    local mainName = group.main or member.name
    return string.format("that's %s %d for %s", ordinal(count), MAX_LEVEL, mainName)
end

local function classAtMax(guild, member)
    if not member.class then return nil end
    local count = 0
    for _, other in pairs(guild.members) do
        if other.class == member.class and (other.level or 0) >= MAX_LEVEL then count = count + 1 end
    end
    if count < 2 then return nil end
    local className = string.lower(GL:ClassName(member.class))
    return string.format("%d %s at %d in the guild now", count, plural(count, className), MAX_LEVEL)
end

local function sinceJoin(member, now)
    local joined = member.joined
    if not joined then return nil end
    local days = daysBetween(joined, now)
    if days < 3 then return nil end
    if days < 14 then return string.format("%d days after joining", days) end
    local weeks = math.floor(days / 7)
    if weeks < 9 then return string.format("%d weeks after joining", weeks) end
    local months = math.floor(days / 30.4)
    return string.format("%d %s after joining", months, plural(months, "month"))
end

-- The facts worth saying about this ding, best first. Only real data makes the list.
function Shout:Facts(guild, member, item, now)
    local list = {}
    if item.kind ~= "level" then return list end
    local p = pace(guild, member.name, item.prev, item.level, now)
    if p then list[#list + 1] = p end
    if item.level >= MAX_LEVEL then
        local a = altsAtMax(guild, member)
        if a then list[#list + 1] = a end
        local c = classAtMax(guild, member)
        if c then list[#list + 1] = c end
    end
    local j = sinceJoin(member, now)
    if j then list[#list + 1] = j end
    return list
end

-- Composition ------------------------------------------------------------------------------------
local function tidy(text)
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

-- {name} the way the guild talks: by default the first name in lower case ("Zev Zev" -> "zev"); Settings offers the others.
local function styledName(name)
    if type(name) ~= "string" or name == "" then return "someone" end
    local s = settings()
    local style = s and s.nameStyle or "firstlower"
    local out = name
    if style == "first" or style == "firstlower" then out = string.match(name, "^(%S+)") or name end
    if style == "firstlower" or style == "fulllower" then out = string.lower(out) end
    return out
end

local function fill(template, item)
    local text = template
    local name = string.gsub(styledName(item.name), "%%", "%%%%")
    local rank = string.gsub(item.rank or "a new rank", "%%", "%%%%")
    -- "a Yiker", "an Officer"; a rank that already starts with an article, or no rank at all, is left as is.
    local arank = rank
    if item.rank and not string.find(string.lower(rank), "^an? ") and not string.find(string.lower(rank), "^the ") then
        arank = (string.find(rank, "^[AEIOUaeiou]") and "an " or "a ") .. rank
    end
    text = string.gsub(text, "{name}", name)
    text = string.gsub(text, "{NAME}", string.upper(name))
    text = string.gsub(text, "{level}", tostring(item.level or "?"))
    text = string.gsub(text, "{a rank}", arank)
    text = string.gsub(text, "{A RANK}", string.upper(arank))
    text = string.gsub(text, "{rank}", rank)
    text = string.gsub(text, "{RANK}", string.upper(rank))
    text = string.gsub(text, "{away}", item.away or "a while")
    text = string.gsub(text, "{me}", GL:PlayerFirstName())
    return tidy(text)
end

-- Builds the line: the template, then the first fact that fits. `rotate` shifts which fact leads so
-- the same person does not hear the same kind of fact every time.
function Shout:Compose(template, item, facts, rotate)
    local text = fill(template, item)
    facts = facts or {}
    if #facts > 0 then
        local start = ((rotate or 1) - 1) % #facts
        for k = 0, #facts - 1 do
            local fact = facts[((start + k) % #facts) + 1]
            -- In brackets, the way people tack an aside onto a chat line (no full stop in the middle).
            local candidate = text .. " (" .. fact .. ")"
            if #candidate <= MAX_BYTES then text = candidate break end
        end
    end
    if #text > MAX_BYTES then text = string.sub(text, 1, MAX_BYTES - 1) end
    return text
end

-- Queue -------------------------------------------------------------------------------------------
local queue = {}
local armed = false          -- only dings seen after the first scan of this session count
local clickOnly = false
local lastAuto = nil

local function myRankOk(s)
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex == nil then return false end
    return rankIndex <= (s.minRank or 0)
end

local function shoutedLevel(guild, name)
    local list = guild.shouted
    return type(list) == "table" and type(list[name]) == "table" and list[name].level or 0
end

local function markShouted(guild, item)
    if type(guild.shouted) ~= "table" then guild.shouted = {} end
    local rec = guild.shouted[item.name]
    if type(rec) ~= "table" then rec = {}; guild.shouted[item.name] = rec end
    if item.kind == "level" then rec.level = math.max(rec.level or 0, item.level)
    else rec[item.kind] = GL:Now() end
end

local function queued(name, kind)
    for _, item in ipairs(queue) do if item.name == name and item.kind == kind then return item end end
    return nil
end

local function push(s, item)
    local now = GetTime()
    item.queuedAt, item.dueAt = now, now + (s.delay or 10)
    queue[#queue + 1] = item
    if s.mode == "auto" and not clickOnly then
        C_Timer.After((s.delay or 10) + 0.5, function() Shout:Pump(true) end)
    else
        GL:Print("gchat shout for |cffffffff" .. item.name .. "|r is ready; it goes out on your next click or chat line.")
    end
end

-- Called by the scanner once the first roster pass of the session is done.
function Shout:AfterScan() armed = true end

function Shout:OnLevel(guild, name, from, level, online)
    local s = settings()
    if not (s and s.enabled and armed) then return end
    if not name or name == GL:PlayerName() then return end
    if not online then return end
    if not myRankOk(s) then return end
    if not (s.every or milestones(s)[level]) then return end
    if shoutedLevel(guild, name) >= level then return end
    local pending = queued(name, "level")
    if pending then pending.level = math.max(pending.level, level) return end
    push(s, { kind = "level", name = name, prev = from, level = level })
end

function Shout:OnPromote(guild, name, toRank, online)
    local s = settings()
    if not (s and s.enabled and s.promote and armed and online) then return end
    if not name or name == GL:PlayerName() or not myRankOk(s) then return end
    if queued(name, "promote") then return end
    push(s, { kind = "promote", name = name, rank = toRank })
end

function Shout:OnBack(guild, name, awayText)
    local s = settings()
    if not (s and s.enabled and s.back and armed) then return end
    if not name or name == GL:PlayerName() or not myRankOk(s) then return end
    if queued(name, "back") then return end
    push(s, { kind = "back", name = name, away = awayText })
end

local function isOnline(guild, name)
    local member = GL:Member(guild, name)
    if member and member.online ~= nil then return member.online end
    return true
end

function Shout:Pump(auto)
    if #queue == 0 then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local s = settings()
    local now = GetTime()
    local guild = GL:Guild()
    if not guild then return false end
    for i, item in ipairs(queue) do
        if now - item.queuedAt > (s.maxWait or 600) then
            table.remove(queue, i)
            return false
        end
        if now >= item.dueAt then
            table.remove(queue, i)
            if isOnline(guild, item.name) then
                local member = GL:Member(guild, item.name) or { name = item.name, level = item.level }
                local key = poolKey(item)
                local template, cursor = self:NextTemplate(key, true)
                local text = self:Compose(template, item, self:Facts(guild, member, item, GL:Now()), cursor)
                markShouted(guild, item)
                if auto then lastAuto = { item = item, at = now } end
                GL:SendChat(text, "GUILD")
                return true
            end
        end
    end
    return false
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if arg1 ~= ADDON_NAME or not (type(arg2) == "string" and string.find(arg2, "SendChatMessage")) then return end
    clickOnly = true
    if lastAuto and (GetTime() - lastAuto.at) < 2 then
        local item = lastAuto.item
        lastAuto = nil
        local guild = GL:Guild()
        if guild and guild.shouted and guild.shouted[item.name] and item.kind == "level" then guild.shouted[item.name].level = (item.prev or 0) end
        item.dueAt = GetTime()
        queue[#queue + 1] = item
        GL:Print("the game blocked the timed shout for " .. item.name .. "; it goes out on your next click instead.")
    end
end)

-- Slash ------------------------------------------------------------------------------------------
local function onoff(flag) return flag and "|cff33dd33on|r" or "|cffff5555off|r" end

local function previewFor(name, level)
    local guild = GL:Guild()
    local member = guild and GL:Member(guild, name) or { name = name }
    level = level or member.level or UnitLevel("player")
    local item = { kind = "level", name = name, level = level, prev = (level > 10) and (level - 10) or nil }
    local key = poolKey(item)
    local template, cursor = Shout:NextTemplate(key, false)
    local facts = guild and Shout:Facts(guild, member, item, GL:Now()) or {}
    return Shout:Compose(template, item, facts, cursor), facts
end

function Shout:Command(rest)
    local s = settings()
    if not s then GL:Print("not loaded yet.") return end
    local sub, arg = string.match(rest or "", "^(%S*)%s*(.-)%s*$")
    sub = string.lower(sub or "")
    if sub == "" or sub == "status" then
        GL:Print(string.format("gchat shouts are %s. Levels: %s%s. Promotions %s, welcome-backs %s. Delay %ds, %s mode, rank %d or better. %d queued.",
            onoff(s.enabled), s.levels, s.every and " (and every other level)" or "", onoff(s.promote), onoff(s.back),
            s.delay or 10, (s.mode == "auto" and not clickOnly) and "auto" or "click", s.minRank or 0, #queue))
        if not myRankOk(s) then GL:Print("|cffff9933this character's rank is below the poster rank, so it will not post shouts.|r") end
    elseif sub == "on" or sub == "off" then
        s.enabled = (sub == "on")
        GL:Print("gchat shouts " .. sub .. ".")
    elseif sub == "levels" then
        if arg == "" then GL:Print("milestone levels: " .. s.levels) return end
        local list = {}
        for n in string.gmatch(arg, "%d+") do list[#list + 1] = tonumber(n) end
        table.sort(list)
        s.levels = table.concat(list, " ")
        GL:Print("milestone levels set to " .. s.levels .. ".")
    elseif sub == "every" or sub == "promote" or sub == "back" then
        if arg == "on" or arg == "off" then s[sub] = (arg == "on") else s[sub] = not s[sub] end
        GL:Print(sub .. " shouts " .. (s[sub] and "on" or "off") .. ".")
    elseif sub == "delay" then
        local n = tonumber(arg)
        if n then s.delay = math.max(0, math.floor(n)); GL:Print("shout delay " .. s.delay .. "s.") else GL:Print("usage: /tabard shout delay <seconds>") end
    elseif sub == "mode" then
        if arg == "click" or arg == "auto" then s.mode = arg; GL:Print("shout mode " .. arg .. ".") else GL:Print("usage: /tabard shout mode click|auto") end
    elseif sub == "rank" then
        local n = tonumber(arg)
        if n then s.minRank = math.floor(n); GL:Print("shouts post from rank index " .. s.minRank .. " or better.") else GL:Print("usage: /tabard shout rank <rankIndex>") end
    elseif sub == "preview" then
        local name, level = string.match(arg, "^(.-)%s*(%d*)$")
        name = name ~= "" and name or GL:PlayerName()
        level = tonumber(level)
        local text = previewFor(name, level)
        GL:Print("preview: |cffffffff" .. text .. "|r")
    elseif sub == "test" then
        -- posts a line about yourself to guild chat so you can see it land
        local level = tonumber(arg) or UnitLevel("player")
        local text = previewFor(GL:PlayerName(), level)
        GL:SendChat(text, "GUILD")
    elseif sub == "list" then
        local key = arg ~= "" and arg or "60"
        local list, custom = pool(key)
        GL:Print(string.format("%s pool (%d lines%s):", key, #list, custom and ", custom" or ""))
        for i, line in ipairs(list) do GL:Print(string.format("  %d. %s", i, line)) end
    elseif sub == "add" then
        local key, text = string.match(arg, "^(%S+)%s+(.+)$")
        if not key then GL:Print("usage: /tabard shout add <level|any|promote|back> <text with {name}>") return end
        if type(s.lines) ~= "table" then s.lines = {} end
        if type(s.lines[key]) ~= "table" then
            s.lines[key] = {}
            for _, line in ipairs((pool(key))) do s.lines[key][#s.lines[key] + 1] = line end
        end
        s.lines[key][#s.lines[key] + 1] = text
        GL:Print(string.format("added to the %s pool (#%d).", key, #s.lines[key]))
    elseif sub == "remove" then
        local key, n = string.match(arg, "^(%S+)%s+(%d+)$")
        n = tonumber(n)
        if not key then GL:Print("usage: /tabard shout remove <pool> <number>") return end
        if type(s.lines) ~= "table" or type(s.lines[key]) ~= "table" then
            s.lines = s.lines or {}
            s.lines[key] = {}
            for _, line in ipairs((pool(key))) do s.lines[key][#s.lines[key] + 1] = line end
        end
        if n and s.lines[key][n] then table.remove(s.lines[key], n); GL:Print("removed line " .. n .. " from the " .. key .. " pool.")
        else GL:Print("no line " .. tostring(n) .. " in the " .. key .. " pool.") end
    elseif sub == "reset" then
        s.lines, s.cursors = nil, {}
        GL:Print("shout pools reset to the stock lines.")
    else
        GL:Print("usage: /tabard shout [status|on|off|levels 10 20 40 60|every|promote|back|delay N|mode click|auto|rank N|preview NAME [LEVEL]|test [LEVEL]|list POOL|add POOL TEXT|remove POOL N|reset]")
    end
end

-- For the window's line editor: one pool ("10".."60", "any", "promote", "back") and whether it is custom; the
-- setter takes a list, or nil to go back to the stock pool.
function Shout:Pool(key)
    return pool(tostring(key))
end

function Shout:SetPool(key, list)
    local s = settings()
    if not s then return end
    key = tostring(key)
    if type(s.lines) ~= "table" then s.lines = {} end
    if type(list) == "table" and #list > 0 then s.lines[key] = list else s.lines[key] = nil end
    if type(s.cursors) == "table" then s.cursors[key] = nil end
    if not next(s.lines) then s.lines = nil end
end
