-- Tabard: easier mains and alts
-- Three ways to learn which characters belong together, besides typing a name on the card:
--   1. Your own characters. Every character this account logs into with Tabard, in the same guild, is grouped
--      by itself and announced to the other Tabard users, so nobody has to sort you.
--   2. Suggestions. A character that logs in right after another logs off (more than once), names that share
--      a stem, or a note that mentions another member. They show on the To-do tab as "Alt?" with Link and
--      Not alts.
--   3. The picker (UI.lua): Set... on the card and right-click in the Members list open a searchable list.

local ADDON_NAME, GL = ...

-- Handoffs: one character logs off and another logs on. A real switch is quick (character select and a
-- loading screen), so the gap sets the weight, and the weight is shared out when several people logged on in
-- the same window, because in a busy guild most "right after" pairs are coincidence. One handoff is never
-- enough by itself; two are, and two in opposite directions are the signature of one player switching.
local HANDOFF_WINDOW = 150          -- seconds; beyond this a login is not a handoff at all
local HANDOFF_QUICK = 45            -- a real character switch: full weight
local HANDOFF_MEDIUM = 90           -- plausible: medium weight
local HANDOFF_KEEP = 600            -- transitions remembered per guild
local HANDOFF_DAYS = 45             -- how far back handoffs count
local MIN_SCORE = 4                 -- two quick unambiguous handoffs, or one plus a name match, or a strong name match plus a note

local cache = setmetatable({}, { __mode = "k" })   -- guild -> suggestion cache (never saved)

function GL:AltPairKey(a, b)
    if a > b then a, b = b, a end
    return a .. "|" .. b
end

local function firstWord(name)
    return string.lower(string.match(name or "", "^(%S+)") or "")
end

local function escapePattern(text)
    return (string.gsub(text, "%W", "%%%0"))
end

-- Online and offline transitions read from the roster, kept small: { n = name, t = time, on = true | nil }.
function GL:NoteTransition(guild, name, online, now)
    if not (guild and name) then return end
    local list = guild.handoffs
    if type(list) ~= "table" then list = {} guild.handoffs = list end
    list[#list + 1] = { n = name, t = now or self:Now(), on = online and true or nil }
    if #list > HANDOFF_KEEP then
        local keep = {}
        for i = #list - HANDOFF_KEEP + 1, #list do keep[#keep + 1] = list[i] end
        guild.handoffs = keep
    end
    cache[guild] = nil
end

-- Your own characters ------------------------------------------------------------------------------------
local function mineFor(self)
    local key = self:GuildKey()
    if not (key and self.db) then return nil end
    if type(self.db.mine) ~= "table" then self.db.mine = {} end
    if type(self.db.mine[key]) ~= "table" then self.db.mine[key] = {} end
    return self.db.mine[key]
end

-- The names this account has logged into in this guild (and that are still members), sorted.
function GL:MyCharacters(guild)
    local mine = mineFor(self)
    local names = {}
    if not (mine and guild) then return names end
    for name in pairs(mine) do if guild.members[name] then names[#names + 1] = name end end
    table.sort(names)
    return names
end

local function allOurs(guild, group, inSet)
    if guild.members[group.main] and not inSet[group.main] then return false end
    for _, altName in ipairs(group.alts) do
        if guild.members[altName] and not inSet[altName] then return false end
    end
    return true
end

-- Links a set of names that belong to one player. An existing main among them stays the main, otherwise
-- the highest level becomes it. A character already grouped with outsiders is left alone.
function GL:GroupTogether(guild, names, source, stamp, preferredMain)
    local members, inSet = {}, {}
    for _, name in ipairs(names) do
        local member = guild.members[name]
        if member then members[#members + 1] = member inSet[name] = true end
    end
    if #members < 2 then return false end
    local main
    if preferredMain and inSet[preferredMain] then
        local candidate = guild.members[preferredMain]
        local group = self:GroupOf(guild, candidate)
        if not group or allOurs(guild, group, inSet) then main = candidate end
    end
    for _, member in ipairs(members) do
        if main then break end
        local group = self:GroupOf(guild, member)
        if group and allOurs(guild, group, inSet) and guild.members[group.main] then main = guild.members[group.main] break end
    end
    if not main then
        for _, member in ipairs(members) do
            if not self:GroupOf(guild, member) and (not main or (member.level or 0) > (main.level or 0)) then main = member end
        end
    end
    if not main then return false end
    local changed = false
    if preferredMain and main and main.name == preferredMain and self:GroupOf(guild, main) and not self:IsMain(guild, main) then
        -- GRM says this character is the main of the set; make it so within its own group.
        if self:SetMain(guild, main, source, stamp) then changed = true end
    end
    for _, member in ipairs(members) do
        if member ~= main then
            local group = self:GroupOf(guild, member)
            if not group or (group ~= self:GroupOf(guild, main) and allOurs(guild, group, inSet)) then
                if self:LinkAlt(guild, member, main, source, stamp) then changed = true end
            end
        end
    end
    if changed then cache[guild] = nil end
    return changed
end

-- After every roster read: remembers this character and groups this account's characters.
function GL:ApplySelfGroup(guild)
    local mine = mineFor(self)
    if not (mine and guild) then return end
    local me = self:PlayerName()
    if not (me and guild.members[me]) then return end
    local now = self:Now()
    local isNew = mine[me] == nil
    mine[me] = now
    local names = self:MyCharacters(guild)
    if #names >= 2 then self:GroupTogether(guild, names, "scan", now) end
    if (isNew or not self.toldMine) and #names >= 2 and self.Sync and self.Sync.Share then
        self.toldMine = true
        self.Sync:Share(guild, "M")
    end
end

-- Another Tabard user said which characters are theirs. Taken from any member, officer or not, because it
-- only concerns their own characters; the sender must be one of the names.
function GL:ApplyClaimedCharacters(guild, sender, namesText, stamp)
    local names, hasSender = {}, false
    for name in string.gmatch(namesText or "", "[^,]+") do
        names[#names + 1] = name
        if name == sender then hasSender = true end
    end
    if not hasSender or #names < 2 then return false end
    return self:GroupTogether(guild, names, "sync", stamp)
end

-- Suggestions ---------------------------------------------------------------------------------------------
function GL:DismissAltPair(guild, a, b)
    if not (guild and a and b) then return end
    guild.notAlts = guild.notAlts or {}
    guild.notAlts[self:AltPairKey(a, b)] = self:Now()
    cache[guild] = nil
end

-- Links `member` into `other`'s group (or makes `other` the main of a new one).
function GL:AcceptAltPair(guild, member, other)
    if not (guild and member and other) or member == other then return false end
    local main = self:MainOf(guild, other) or other
    local ok = self:LinkAlt(guild, member, main, "user")
    cache[guild] = nil
    return ok
end

local function secondWord(name)
    return string.lower(string.match(name or "", "^%S+%s+(%S+)") or "")
end

local function commonPrefix(a, b)
    local n = 0
    for i = 1, math.min(#a, #b) do
        if string.sub(a, i, i) == string.sub(b, i, i) then n = i else break end
    end
    return n
end

-- The stretches each character was online, from the transition log plus the roster now: { name = { {from, to}, ... } }.
-- Two characters online at the same moment are two players, whatever else looks alike.
local function onlineSpans(guild, list, now)
    local spans, open = {}, {}
    for _, entry in ipairs(list) do
        if entry.on then
            open[entry.n] = entry.t
        elseif open[entry.n] then
            spans[entry.n] = spans[entry.n] or {}
            local s = spans[entry.n]
            s[#s + 1] = { open[entry.n], entry.t }
            open[entry.n] = nil
        end
    end
    for name, from in pairs(open) do
        spans[name] = spans[name] or {}
        local s = spans[name]
        s[#s + 1] = { from, now }
    end
    for name, member in pairs(guild.members) do
        if member.online and not open[name] then
            spans[name] = spans[name] or {}
            local s = spans[name]
            s[#s + 1] = { now, now }
        end
    end
    return spans
end

local function overlap(sa, sb)
    if not (sa and sb) then return false end
    for _, x in ipairs(sa) do
        for _, y in ipairs(sb) do
            if x[1] < y[2] and y[1] < x[2] then return true end
        end
    end
    return false
end

-- item = { key, member (the likely alt), other (the likely main or one of its alts), reason, score, confidence, since }
-- confidence: "likely" or "possible". Scores: a quick unambiguous handoff is 3, medium 2, slow 1, each divided
-- among the people who logged on in the same window; handoffs count only once there are two of them, and both
-- directions add 2. Same first name or surname 3, a 5+ letter shared start 2, a note naming the other 3.
-- A pair ever seen online together is dropped for good, and each character keeps only its best pairing.
function GL:AltSuggestions(guild, now)
    if not guild then return {} end
    now = now or self:Now()
    local groupsCount = self:Count(guild.groups)
    local cached = cache[guild]
    if cached and cached.scans == guild.scans and cached.groups == groupsCount and now - cached.t < 60 then return cached.items end
    guild.notAlts = guild.notAlts or {}
    local dismissed = guild.notAlts
    local found, order = {}, {}
    local function entryFor(a, b, since)
        if a == b then return nil end
        local ma, mb = guild.members[a], guild.members[b]
        if not (ma and mb) then return nil end
        if self:GroupOf(guild, ma) and self:GroupOf(guild, mb) then return nil end   -- both sorted already
        local key = self:AltPairKey(a, b)
        if dismissed[key] then return nil end
        local entry = found[key]
        if not entry then
            entry = { key = key, a = a, b = b, score = 0, reasons = {}, since = since or now,
                handoff = 0, handoffs = 0, quick = 0, directions = {} }
            found[key] = entry
            order[#order + 1] = entry
        end
        if since and since < entry.since then entry.since = since end
        return entry
    end

    -- 1. Handoffs, weighted by how quick and how unambiguous each one was.
    local list = guild.handoffs or {}
    local oldest = now - HANDOFF_DAYS * 86400
    for i = 1, #list do
        local off = list[i]
        if not off.on and off.t >= oldest then
            local candidates, seen = {}, {}
            for j = i + 1, #list do
                local on = list[j]
                if on.t - off.t > HANDOFF_WINDOW then break end
                if on.on and on.n ~= off.n and not seen[on.n] then seen[on.n] = true candidates[#candidates + 1] = on end
            end
            -- how many others logged off just before each login: the login side of the ambiguity
            for _, on in ipairs(candidates) do
                local offs = 0
                for j = i, 1, -1 do
                    local other = list[j]
                    if on.t - other.t > HANDOFF_WINDOW then break end
                    if not other.on and other.n ~= on.n then offs = offs + 1 end
                end
                local gap = on.t - off.t
                local weight = gap <= HANDOFF_QUICK and 3 or gap <= HANDOFF_MEDIUM and 2 or 1
                local entry = entryFor(off.n, on.n, off.t)
                if entry then
                    entry.handoff = entry.handoff + weight / math.max(#candidates, offs, 1)
                    entry.handoffs = entry.handoffs + 1
                    if gap <= HANDOFF_QUICK then entry.quick = entry.quick + 1 end
                    entry.directions[off.n] = true
                end
            end
        end
    end
    for _, entry in ipairs(order) do
        if entry.handoffs >= 2 then
            local both = entry.directions[entry.a] and entry.directions[entry.b]
            entry.score = entry.score + math.min(entry.handoff, 9) + (both and 2 or 0)
            local text = entry.handoffs .. (entry.quick == entry.handoffs and " quick handoffs" or " handoffs")
            entry.reasons[#entry.reasons + 1] = both and (text .. ", both ways") or text
        end
    end

    -- 2. Names; 3. a note that names the other member.
    local names, firsts, seconds = {}, {}, {}
    for name in pairs(guild.members) do names[#names + 1] = name firsts[name] = firstWord(name) seconds[name] = secondWord(name) end
    table.sort(names)
    for _, name in ipairs(names) do
        local member = guild.members[name]
        if not self:GroupOf(guild, member) then
            local first, second = firsts[name], seconds[name]
            for _, otherName in ipairs(names) do
                if otherName > name or self:GroupOf(guild, guild.members[otherName]) then   -- each unsorted pair once; a sorted other is fine
                    local otherFirst, otherSecond = firsts[otherName], seconds[otherName]
                    local score, reason
                    if #first >= 4 and first == otherFirst then score, reason = 3, "same first name"
                    elseif #second >= 4 and second == otherSecond then score, reason = 3, "same surname"
                    elseif #first >= 5 and #otherFirst >= 5 and commonPrefix(first, otherFirst) >= 5 then score, reason = 2, "names start alike"
                    elseif #first >= 4 and #otherFirst >= 4 and commonPrefix(first, otherFirst) >= 4 then score, reason = 1, "names start alike"
                    end
                    if score and otherName ~= name then
                        local entry = entryFor(name, otherName)
                        if entry then entry.score = entry.score + score entry.reasons[#entry.reasons + 1] = reason entry.nameOnly = (score < 3) end
                    end
                end
            end
            for _, text in ipairs({ member.note, member.onote, member.custom }) do
                if type(text) == "string" and #text >= 4 then
                    local lower = string.lower(text)
                    for _, otherName in ipairs(names) do
                        local otherFirst = firsts[otherName]
                        if otherName ~= name and #otherFirst >= 4 and string.find(lower, "%f[%a]" .. escapePattern(otherFirst) .. "%f[%A]") then
                            local entry = entryFor(name, otherName)
                            if entry then entry.score = entry.score + 3 entry.reasons[#entry.reasons + 1] = "note mentions " .. otherName end
                        end
                    end
                end
            end
        end
    end

    -- Seen online together: not the same player. Dropped for good, like "Not alts".
    local spans = onlineSpans(guild, list, now)
    local items = {}
    for _, entry in ipairs(order) do
        if entry.score >= MIN_SCORE then
            if overlap(spans[entry.a], spans[entry.b]) then
                dismissed[entry.key] = now
            else
                local ma, mb = guild.members[entry.a], guild.members[entry.b]
                local member, other
                if self:GroupOf(guild, mb) then member, other = ma, mb
                elseif self:GroupOf(guild, ma) then member, other = mb, ma
                elseif (ma.level or 0) > (mb.level or 0) then member, other = mb, ma
                else member, other = ma, mb end
                items[#items + 1] = { key = entry.key, member = member, other = other, score = entry.score,
                    confidence = entry.score >= 7 and "likely" or "possible",
                    reason = table.concat(entry.reasons, ", "), since = entry.since }
            end
        end
    end
    table.sort(items, function(x, y) if x.score ~= y.score then return x.score > y.score end return x.key < y.key end)
    -- One pairing per character: the best one wins, the rest wait until it is answered.
    local taken, kept = {}, {}
    for _, item in ipairs(items) do
        if not taken[item.member.name] then
            taken[item.member.name] = true
            kept[#kept + 1] = item
        end
    end
    cache[guild] = { scans = guild.scans, groups = groupsCount, t = now, items = kept }
    return kept
end
