-- Tabard: easier mains and alts
-- Three ways to learn which characters belong together, besides typing a name on the card:
--   1. Your own characters. Every character this account logs into with Tabard, in the same guild, is grouped
--      by itself and announced to the other Tabard users, so nobody has to sort you.
--   2. Suggestions. A character that logs in right after another logs off (more than once), names that share
--      a stem, or a note that mentions another member. They show on the To-do tab as "Alt?" with Link and
--      Not alts.
--   3. The picker (UI.lua): Set... on the card and right-click in the Members list open a searchable list.

local ADDON_NAME, GL = ...

local HANDOFF_WINDOW = 150          -- seconds between one character logging off and the next logging on
local HANDOFF_KEEP = 400            -- transitions remembered per guild
local HANDOFF_DAYS = 45             -- how far back handoffs count
local MIN_SCORE = 3                 -- one stem match or note mention, or two handoffs

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

-- item = { key, member (the likely alt), other (the likely main or one of its alts), reason, score, since }
function GL:AltSuggestions(guild, now)
    if not guild then return {} end
    now = now or self:Now()
    local groupsCount = self:Count(guild.groups)
    local cached = cache[guild]
    if cached and cached.scans == guild.scans and cached.groups == groupsCount and now - cached.t < 60 then return cached.items end
    local dismissed = guild.notAlts or {}
    local found, order = {}, {}
    local function consider(a, b, score, reason, since)
        if a == b then return end
        local ma, mb = guild.members[a], guild.members[b]
        if not (ma and mb) then return end
        if self:GroupOf(guild, ma) and self:GroupOf(guild, mb) then return end   -- both sorted already
        local key = self:AltPairKey(a, b)
        if dismissed[key] then return end
        local entry = found[key]
        if not entry then
            entry = { key = key, a = a, b = b, score = 0, reasons = {}, seen = {}, since = since or now }
            found[key] = entry
            order[#order + 1] = entry
        end
        entry.score = entry.score + score
        if not entry.seen[reason] then entry.seen[reason] = true entry.reasons[#entry.reasons + 1] = reason end
        if since and since < entry.since then entry.since = since end
    end

    -- 1. One logs off, the other logs on within a couple of minutes. Each time counts 2.
    local list = guild.handoffs or {}
    local oldest = now - HANDOFF_DAYS * 86400
    for i = 1, #list do
        local off = list[i]
        if not off.on and off.t >= oldest then
            for j = i + 1, #list do
                local on = list[j]
                if on.t - off.t > HANDOFF_WINDOW then break end
                if on.on and on.n ~= off.n then consider(off.n, on.n, 2, "logs in right after the other logs off", off.t) end
            end
        end
    end

    -- 2. Names that share a stem; 3. a note that mentions another member.
    local names, stems = {}, {}
    for name in pairs(guild.members) do names[#names + 1] = name stems[name] = firstWord(name) end
    table.sort(names)
    for _, name in ipairs(names) do
        local member = guild.members[name]
        if not self:GroupOf(guild, member) then
            local stem = stems[name]
            if #stem >= 4 then
                for _, otherName in ipairs(names) do
                    local otherStem = stems[otherName]
                    if otherName ~= name and #otherStem >= 4 then
                        if string.sub(stem, 1, 4) == string.sub(otherStem, 1, 4) then
                            consider(name, otherName, 3, "names share a stem")
                        elseif #stem >= 6 and #otherStem >= 6 and string.sub(stem, -4) == string.sub(otherStem, -4) then
                            consider(name, otherName, 2, "names share an ending")
                        end
                    end
                end
            end
            for _, text in ipairs({ member.note, member.onote, member.custom }) do
                if type(text) == "string" and #text >= 4 then
                    local lower = string.lower(text)
                    for _, otherName in ipairs(names) do
                        local otherStem = stems[otherName]
                        if otherName ~= name and #otherStem >= 4 and string.find(lower, "%f[%a]" .. escapePattern(otherStem) .. "%f[%A]") then
                            consider(name, otherName, 3, "note mentions " .. otherName)
                        end
                    end
                end
            end
        end
    end

    local items = {}
    for _, entry in ipairs(order) do
        if entry.score >= MIN_SCORE then
            local ma, mb = guild.members[entry.a], guild.members[entry.b]
            local member, other
            if self:GroupOf(guild, mb) then member, other = ma, mb
            elseif self:GroupOf(guild, ma) then member, other = mb, ma
            elseif (ma.level or 0) > (mb.level or 0) then member, other = mb, ma
            else member, other = ma, mb end
            items[#items + 1] = { key = entry.key, member = member, other = other, score = entry.score, reason = table.concat(entry.reasons, "; "), since = entry.since }
        end
    end
    table.sort(items, function(x, y) if x.score ~= y.score then return x.score > y.score end return x.key < y.key end)
    cache[guild] = { scans = guild.scans, groups = groupsCount, t = now, items = items }
    return items
end
