-- Tabard: tools
-- Recommendation lists (inactive members, promotions due), guild actions (remove, promote, demote, notes) with
-- a macro fallback, export text, extra lines on unit tooltips, and the minimap button.

local ADDON_NAME, GL = ...

-- Recommendations -----------------------------------------------------------------------------------------
-- The rank index that counts as the newcomer rank: the one from settings, else the highest index seen.
function GL:NewcomerRank(guild)
    local setting = self.settings.promoteFromRank
    if setting and guild.ranks[setting] then return setting end
    local lowest
    for index in pairs(guild.ranks) do
        if not lowest or index > lowest then lowest = index end
    end
    return lowest
end

-- Members offline longer than kickDays whose whole alt group is also inactive. Sorted by longest away first.
function GL:KickCandidates(guild, now)
    now = now or self:Now()
    local after = (self.settings.kickDays or 60) * 86400
    local maxLevel = self.settings.kickMaxLevel or 0
    local list = {}
    for name, member in pairs(guild.members) do
        local away = member.lastOnline and (now - member.lastOnline) or nil
        local onLeave = self.OnLeave and self:OnLeave(member, now)
        if away and away >= after and not member.online and not onLeave and not self:IsSafe(member, "kick") and (maxLevel == 0 or (member.level or 0) <= maxLevel) then
            local groupActive = false
            for _, other in ipairs(self:AltsOf(guild, member)) do
                if other.online or (other.lastOnline and (now - other.lastOnline) < after) then groupActive = true end
            end
            if not groupActive then list[#list + 1] = { member = member, away = away } end
        end
    end
    table.sort(list, function(a, b) return a.away > b.away end)
    return list
end

-- Members in the newcomer rank for longer than promoteDays. Sorted by longest waiting first.
function GL:PromoteCandidates(guild, now)
    now = now or self:Now()
    local after = (self.settings.promoteDays or 14) * 86400
    local rank = self:NewcomerRank(guild)
    local list = {}
    if not rank then return list end
    for name, member in pairs(guild.members) do
        if member.rankIndex == rank and not self:IsSafe(member, "promote") then
            local since = member.promoted or member.joined or member.firstSeen
            if since and (now - since) >= after then list[#list + 1] = { member = member, waiting = now - since } end
        end
    end
    table.sort(list, function(a, b) return a.waiting > b.waiting end)
    return list
end

-- Members with gaps an officer can fill: no join date, no promotion date, no main/alt status, no ledger note.
function GL:AuditRows(guild)
    local list = {}
    for name, member in pairs(guild.members) do
        local gaps = {}
        if not member.joined then gaps[#gaps + 1] = "join date" end
        if (member.rankIndex or 0) > 0 and not member.promoted and member.rankIndex ~= self:NewcomerRank(guild) then gaps[#gaps + 1] = "promotion date" end
        if not self:GroupOf(guild, member) then gaps[#gaps + 1] = "main or alt" end
        if #gaps > 0 then list[#list + 1] = { member = member, gaps = gaps } end
    end
    table.sort(list, function(a, b) if #a.gaps ~= #b.gaps then return #a.gaps > #b.gaps end return a.member.name < b.member.name end)
    return list
end

-- Guild actions ---------------------------------------------------------------------------------------------
-- These call the game's own guild functions. They only work from a button click (a hardware event) and when the
-- player's rank allows them; when the client refuses, the macro below is the fallback.
function GL:CanRemove() return CanGuildRemove and CanGuildRemove() or false end
function GL:CanPromote() return CanGuildPromote and CanGuildPromote() or false end
function GL:CanDemote() return CanGuildDemote and CanGuildDemote() or false end
function GL:CanEditNote() return CanEditPublicNote and CanEditPublicNote() or false end
function GL:CanEditOfficerNote()
    if C_GuildInfo and C_GuildInfo.CanEditOfficerNote then return C_GuildInfo.CanEditOfficerNote() end
    return CanEditOfficerNote and CanEditOfficerNote() or false
end

local ACTIONS = {
    kick = function(name) local f = (C_GuildInfo and C_GuildInfo.Uninvite) or GuildUninvite; if f then f(name) return true end end,
    promote = function(name) local f = (C_GuildInfo and C_GuildInfo.Promote) or GuildPromote; if f then f(name) return true end end,
    demote = function(name) local f = (C_GuildInfo and C_GuildInfo.Demote) or GuildDemote; if f then f(name) return true end end,
}

function GL:GuildAction(kind, name)
    local action = ACTIONS[kind]
    if not action then return false, "unknown action" end
    local ok, result = pcall(action, name)
    if ok and result then return true end
    return false, ok and "this client has no guild " .. kind .. " function" or tostring(result)
end

-- Runs one action on many names, spaced out so the server accepts them all. onDone(doneCount, failed)
function GL:GuildActionMany(kind, names, onDone)
    local index, done, failed = 0, 0, {}
    local function step()
        index = index + 1
        local name = names[index]
        if not name then
            if onDone then onDone(done, failed) end
            return
        end
        local ok, err = self:GuildAction(kind, name)
        if ok then done = done + 1 else failed[#failed + 1] = name .. " (" .. tostring(err) .. ")" end
        C_Timer.After(0.6, step)
    end
    step()
end

-- Finds the roster index of a member (needed for note editing on older clients).
local function rosterIndex(name)
    for i = 1, GetNumGuildMembers() do
        local rosterName = GetGuildRosterInfo(i)
        if rosterName and GL:ShortName(rosterName) == name then return i end
    end
    return nil
end

function GL:SetNote(member, text, officer)
    text = tostring(text or "")
    if C_GuildInfo and C_GuildInfo.SetNote and member.guid then
        local ok, err = pcall(C_GuildInfo.SetNote, member.guid, text, not officer)
        if ok then return true end
        return false, tostring(err)
    end
    local index = rosterIndex(member.name)
    if not index then return false, "not found in the roster" end
    local setter = officer and GuildRosterSetOfficerNote or GuildRosterSetPublicNote
    if not setter then return false, "this client has no note function" end
    local ok, err = pcall(setter, index, text)
    if ok then return true end
    return false, tostring(err)
end

-- Macro ------------------------------------------------------------------------------------------------------
-- Writes a macro named "Tabard" with one slash command per line, as many names as fit in 255 characters. Returns
-- the names that fit and the ones that did not.
local SLASH_FOR = { kick = "/gremove", promote = "/gpromote", demote = "/gdemote" }

function GL:BuildMacro(kind, names)
    local lines, used, left = {}, {}, {}
    local size = 0
    for _, name in ipairs(names) do
        local line = SLASH_FOR[kind] .. " " .. name
        if size + #line + 1 <= 255 then
            lines[#lines + 1] = line
            size = size + #line + 1
            used[#used + 1] = name
        else
            left[#left + 1] = name
        end
    end
    local body = table.concat(lines, "\n")
    if #lines == 0 then return nil, used, left end
    if InCombatLockdown and InCombatLockdown() then return nil, used, left, "cannot write macros in combat" end
    local index = GetMacroIndexByName and GetMacroIndexByName("Tabard") or 0
    local ok, err
    if index and index > 0 then
        ok, err = pcall(EditMacro, index, "Tabard", "INV_MISC_NOTE_01", body)
    else
        ok, err = pcall(CreateMacro, "Tabard", "INV_MISC_NOTE_01", body, false)
    end
    if not ok then return nil, used, left, tostring(err) end
    return body, used, left
end

-- Export --------------------------------------------------------------------------------------------------------
local function csv(value)
    value = tostring(value == nil and "" or value)
    value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    value = string.gsub(value, "|r", "")
    if string.find(value, '[",\n]') then value = '"' .. string.gsub(value, '"', '""') .. '"' end
    return value
end

local function row(fields)
    for i = 1, #fields do fields[i] = csv(fields[i]) end
    return table.concat(fields, ",")
end

-- what: "members" | "former" | "log" | "bans"
function GL:ExportText(guild, what)
    local lines = {}
    if what == "members" or what == "former" then
        lines[1] = row({ "Name", "Class", "Level", "Rank", "Joined", "Join date source", "Promoted", "Last online", "Main", "Alts", "Note", "Officer note", "Tabard note", "Birthday", what == "former" and "Left" or "First seen", what == "former" and "How" or "Invited by" })
        local names = {}
        local set = what == "members" and guild.members or guild.former
        for name in pairs(set) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local member = set[name]
            local main = self:MainOf(guild, member)
            local alts = {}
            for _, other in ipairs(self:AltsOf(guild, member)) do if not main or other.name ~= main.name then alts[#alts + 1] = other.name end end
            lines[#lines + 1] = row({ name, self:ClassName(member.class), member.level, member.rank,
                member.joined and date("%Y-%m-%d", member.joined) or "", member.joinedSource or "",
                member.promoted and date("%Y-%m-%d", member.promoted) or "",
                member.online and "online" or (member.lastOnline and date("%Y-%m-%d", member.lastOnline) or ""),
                main and main.name ~= name and main.name or (self:IsMain(guild, member) and "(main)" or ""), table.concat(alts, "; "),
                member.note, member.onote, member.custom, member.birthday and self:FormatMonthDay(member.birthday.m, member.birthday.d) or "",
                what == "former" and (member.left and date("%Y-%m-%d", member.left) or "") or (member.firstSeen and date("%Y-%m-%d", member.firstSeen) or ""),
                what == "former" and (member.leftKind == "kick" and ("removed" .. (member.leftBy and (" by " .. member.leftBy) or "")) or "left") or (member.invitedBy or "") })
        end
    elseif what == "log" then
        lines[1] = row({ "Time", "Kind", "Who", "By", "From", "To", "Level", "Text", "Source" })
        for i = #guild.events, 1, -1 do
            local e = guild.events[i]
            lines[#lines + 1] = row({ date("%Y-%m-%d %H:%M", e.t), e.k, e.who, e.by, e.from, e.to, e.level, e.text, e.src })
        end
    elseif what == "bans" then
        lines[1] = row({ "Name", "Class", "Banned on", "By", "Reason", "Lifted", "Lifted by" })
        local names = {}
        for name in pairs(guild.bans) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local ban = guild.bans[name]
            lines[#lines + 1] = row({ name, self:ClassName(ban.class), date("%Y-%m-%d", ban.t or 0), ban.by, ban.reason, ban.lifted and date("%Y-%m-%d", ban.lifted) or "", ban.liftedBy })
        end
    end
    return table.concat(lines, "\n")
end

-- Unit tooltips --------------------------------------------------------------------------------------------------
local function addTooltipLines(tooltip, unit)
    if not (GL.settings and GL.settings.tooltip and GL.db) then return end
    if not (unit and UnitIsPlayer(unit)) then return end
    local guild = GL:Guild()
    if not guild then return end
    local name = GL:ShortName(UnitName(unit))
    local member = name and guild.members[name]
    if not member then return end
    if member.joined then
        tooltip:AddLine("Joined " .. GL:FormatDate(member.joined) .. "  (" .. GL:Span(GL:Now() - member.joined) .. ")", 0.61, 0.84, 1)
    end
    if GL.IsNewcomer and GL:IsNewcomer(member) then
        local done, total = GL:NewcomerSummary(guild, member)
        tooltip:AddLine("New this week" .. (GL:NewcomerContacted(member) and "" or ", nobody has talked to them yet") .. " (" .. done .. "/" .. total .. " first-week steps)", 0.2, 0.87, 0.8)
    end
    local main = GL:MainOf(guild, member)
    if main and main.name ~= name then
        tooltip:AddLine("Alt of " .. GL:ColoredName(main), 0.61, 0.84, 1)
    else
        local alts = GL:AltsOf(guild, member)
        if #alts > 0 then
            local names = {}
            for i, alt in ipairs(alts) do if i <= 6 then names[#names + 1] = GL:ColoredName(alt) end end
            tooltip:AddLine("Alts: " .. table.concat(names, ", ") .. (#alts > 6 and (" +" .. (#alts - 6)) or ""), 0.61, 0.84, 1, true)
        end
    end
    if member.custom then tooltip:AddLine("Tabard note: " .. member.custom, 0.87, 0.6, 1, true) end
    if GL:BanFor(guild, member) then tooltip:AddLine("On the ban list", 1, 0.3, 0.3) end
end

local function hookTooltips()
    if not GameTooltip then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            if tooltip ~= GameTooltip then return end
            local _, unit = tooltip:GetUnit()
            if unit then pcall(addTooltipLines, tooltip, unit) end
        end)
    elseif GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
            local _, unit = tooltip:GetUnit()
            if unit then pcall(addTooltipLines, tooltip, unit) end
        end)
    end
end

-- Minimap button ------------------------------------------------------------------------------------------------------
-- Made with LibDBIcon when the library loaded (so minimap-button collectors such as Leatrix Plus, MBB and the
-- addon compartment can manage it), otherwise a plain button of our own. Either way it wears the guild's tabard.
local minimapButton
local minimapLib          -- LibDBIcon, when it is in use

local function placeMinimapButton()
    if not minimapButton or minimapLib then return end
    local angle = math.rad(GL.settings.minimap.angle or 220)
    local radius = (Minimap:GetWidth() / 2) + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function minimapClick(button)
    if button == "RightButton" then
        GL:RequestScan(true)
        GL:Print("scanning the roster...")
    else
        GL:ToggleWindow()
    end
end

local function guildTitle()
    local guild = GL.db and GL:Guild()
    local name = guild and guild.name and string.gsub(guild.name, "|c%x%x%x%x%x%x%x%x", "") or nil
    name = name and string.gsub(name, "|r", "") or nil
    return name and name ~= "" and (name .. " |cff9d9d9d(Tabard)|r") or "Tabard"
end

local function minimapTooltip(tooltip)
    tooltip:AddLine(guildTitle(), 1, 1, 1)
    local guild = GL.db and GL:Guild()
    if guild and GL.PlayNowCount then
        local near = GL:PlayNowCount(guild)
        if near > 0 then tooltip:AddLine(near .. (near == 1 and " guildie" or " guildies") .. " online within " .. GL.PLAY_BAND .. " levels of you", 0.2, 0.87, 0.8) end
    end
    tooltip:AddLine("Left click: open the ledger", 0.8, 0.8, 0.8)
    tooltip:AddLine("Right click: rescan the roster", 0.8, 0.8, 0.8)
    tooltip:AddLine("Drag to move", 0.6, 0.6, 0.6)
end

-- The guild's tabard on a button: its colour field rounded under the ring, the emblem on top. `icon` is the
-- texture that shows the logo instead when there is no guild.
local function addTabardTo(button, icon)
    local field = button:CreateTexture(nil, "ARTWORK", nil, 1)
    field:SetSize(20, 20)
    if icon then field:SetPoint("CENTER", icon, "CENTER", 0, 0) else field:SetPoint("TOPLEFT", 7, -5) end
    if field.SetMask then pcall(field.SetMask, field, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    field:Hide()
    local emblem = button:CreateTexture(nil, "ARTWORK", nil, 2)
    emblem:SetSize(16, 16)
    emblem:SetPoint("CENTER", field, "CENTER", 0, 0)
    emblem:Hide()
    local border = button:CreateTexture(nil, "ARTWORK", nil, 3)
    border:SetAllPoints(field)
    border:Hide()
    button.tabard = { field = field, emblem = emblem, border = border, icon = icon }
end

-- Puts the guild's tabard on the minimap button, or the logo when there is no guild (or no tabard API).
local function dressMinimapButton()
    if not (minimapButton and minimapButton.tabard) then return end
    local tabard = minimapButton.tabard
    local ok = IsInGuild() and SetLargeGuildTabardTextures ~= nil
        and pcall(SetLargeGuildTabardTextures, "player", tabard.emblem, tabard.field, tabard.border)
        and tabard.emblem:GetTexture() ~= nil
    if ok then
        tabard.field:Show() tabard.emblem:Show()
        tabard.border:Hide()                       -- the tracking ring is the border at this size
        if tabard.icon then tabard.icon:Hide() end
    else
        tabard.field:Hide() tabard.emblem:Hide() tabard.border:Hide()
        if tabard.icon then tabard.icon:Show() end
    end
end

local function createLibraryButton()
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if not (lib and ldb) then return false end
    local settings = GL.settings.minimap
    -- LibDBIcon keeps hide / minimapPos / lock in the same saved table; our older keys stay in step.
    if settings.minimapPos == nil then settings.minimapPos = settings.angle or 220 end
    settings.hide = not settings.shown
    local object = ldb:NewDataObject("Tabard", {
        type = "launcher",
        text = "Tabard",
        icon = "Interface\\AddOns\\Tabard\\logo",
        OnClick = function(_, button) minimapClick(button) end,
        OnTooltipShow = minimapTooltip,
    })
    lib:Register("Tabard", object, settings)
    minimapLib = lib
    minimapButton = lib:GetMinimapButton("Tabard")
    if not minimapButton then minimapLib = nil return false end
    if minimapButton.icon and minimapButton.icon.SetTexCoord then pcall(minimapButton.icon.SetTexCoord, minimapButton.icon, 0.05, 0.95, 0.05, 0.95) end
    addTabardTo(minimapButton, minimapButton.icon)
    if lib.AddButtonToCompartment then pcall(lib.AddButtonToCompartment, lib, "Tabard") end
    return true
end

local function createOwnButton()
    minimapButton = CreateFrame("Button", "TabardUIMinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")
    local background = minimapButton:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)
    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture("Interface\\AddOns\\Tabard\\logo")   -- the addon logo (logo.tga), shown when there is no guild
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 8, -6)
    minimapButton.icon = icon
    addTabardTo(minimapButton, icon)
    minimapButton:SetScript("OnClick", function(self, button) minimapClick(button) end)
    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            GL.settings.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
            placeMinimapButton()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        minimapTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    placeMinimapButton()
end

local function createMinimapButton()
    if minimapButton or not Minimap then return end
    local ok, made = pcall(createLibraryButton)
    if not (ok and made) then
        if not ok and GL.Debug then GL:Debug("LibDBIcon button failed: " .. tostring(made)) end
        minimapButton, minimapLib = nil, nil
        createOwnButton()
    end
end

function GL:UpdateMinimapButton()
    if not self.settings then return end
    createMinimapButton()
    if not minimapButton then return end
    local settings = self.settings.minimap
    settings.hide = not settings.shown
    if minimapLib then
        if settings.shown then minimapLib:Show("Tabard") else minimapLib:Hide("Tabard") end
    elseif settings.shown then
        minimapButton:Show() placeMinimapButton()
    else
        minimapButton:Hide()
    end
    if settings.shown then dressMinimapButton() end
end

-- Chat prefix ------------------------------------------------------------------------------------------------------
-- The guild's emblem in front of every Tabard line, as an inline texture: the emblem sheet, the cell the game picks
-- for this guild, and its colour, read back from a hidden texture the game has dressed. Logo when there is no guild.
local LOGO_PREFIX = GL.prefix
local brandFrame
function GL:GuildEmblemEscape(size)
    if not (IsInGuild() and SetLargeGuildTabardTextures) then return nil end
    if not brandFrame then
        brandFrame = CreateFrame("Frame")
        brandFrame:Hide()
        brandFrame.emblem = brandFrame:CreateTexture()
        brandFrame.field = brandFrame:CreateTexture()
        brandFrame.border = brandFrame:CreateTexture()
    end
    local emblem = brandFrame.emblem
    if not pcall(SetLargeGuildTabardTextures, "player", emblem, brandFrame.field, brandFrame.border) then return nil end
    local file = emblem:GetTexture()
    if not file then return nil end
    local ulx, uly, llx, lly, urx = emblem:GetTexCoord()
    if not (ulx and uly and lly and urx) then return nil end
    local r, g, b = emblem:GetVertexColor()
    r, g, b = r or 1, g or 1, b or 1
    -- Faint emblems vanish on a dark chat frame; lift the colour a little.
    local lift = function(v) return math.floor((0.25 + 0.75 * v) * 255 + 0.5) end
    local W = 1024
    local function px(v) return math.floor(v * W + 0.5) end
    size = size or 14
    return string.format("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d:%d:%d:%d|t", tostring(file), size, size, W, W,
        px(ulx), px(urx), px(uly), px(lly), lift(r), lift(g), lift(b))
end

function GL:RefreshBrand()
    local ok, escape = pcall(self.GuildEmblemEscape, self, 14)
    self.prefix = (ok and escape) and (escape .. " |cffffd100Tabard:|r ") or LOGO_PREFIX
    pcall(dressMinimapButton)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
local brandRefreshes = 0
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if not GL.db then GL:InitDB() end
        pcall(hookTooltips)
        pcall(GL.UpdateMinimapButton, GL)
        GL:RefreshBrand()
        -- Tabard data can arrive after login; dress again once it has.
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function() GL:RefreshBrand() end)
            C_Timer.After(20, function() GL:RefreshBrand() end)
        end
    elseif event == "PLAYER_GUILD_UPDATE" then
        GL:RefreshBrand()
    elseif event == "GUILD_ROSTER_UPDATE" and brandRefreshes < 3 then
        brandRefreshes = brandRefreshes + 1
        GL:RefreshBrand()
    end
end)
