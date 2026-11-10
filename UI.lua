-- Tabard: window
-- One stock window (ButtonFrameTemplate) with bottom tabs: Overview, Log, Members, Former, Bans, Tools, Export,
-- Settings, and a member card that opens beside it. Lists are stock ScrollBox lists with the thin scroll bar;
-- the header row under the title bar is a toolbar.
--
-- Visual language (shared by every page): flat dark background behind the metal frame, faint translucent
-- panels with a one-pixel edge, gold section titles over a thin rule, white numbers, grey explanations, class
-- colours for names, and real bars instead of text art. The Overview is a launchpad: every number on it is
-- a button that opens the page and filter behind it.

local ADDON_NAME, GL = ...

local WINDOW_WIDTH, WINDOW_HEIGHT = 780, 700
local TOOLBAR_TOP, TOOLBAR_HEIGHT = -24, 34     -- from the top of the window
local ROW_HEIGHT = 20
local WHITE, YELLOW, GREY, RED, GREEN = "|cffffffff", "|cffffd100", "|cff9d9d9d", "|cffff5555", "|cff33dd33"
local SOLID = "Interface\\Buttons\\WHITE8x8"
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

-- Accent colours used for tiles, dots and bars (r, g, b).
local ACCENT = {
    gold = { 1, 0.82, 0 }, green = { 0.2, 0.87, 0.2 }, blue = { 0.4, 0.67, 1 }, red = { 1, 0.33, 0.33 },
    purple = { 0.75, 0.6, 1 }, grey = { 0.62, 0.62, 0.62 }, teal = { 0.2, 0.87, 0.8 }, orange = { 1, 0.6, 0.2 },
}

-- Icons: stock textures that ship with every client (spell/item icons and the friends-list status dots), so
-- nothing has to be packaged. Interface\Icons art has a baked border, trimmed off with SetTexCoord.
local ICON = "Interface\\Icons\\"
local STATUS = "Interface\\FriendsFrame\\"
local ICONS = {
    -- event kinds (Log badge, Overview rows, member card history)
    join = ICON .. "Spell_ChargePositive", rejoin = ICON .. "Spell_ChargePositive",
    leave = ICON .. "Spell_ChargeNegative", kick = ICON .. "Ability_Kick",
    promote = "Interface\\Buttons\\UI-MicroStream-Green", demote = "Interface\\Buttons\\UI-MicroStream-Red",
    level = ICON .. "Achievement_Level_10", note = ICON .. "INV_Misc_Note_01", onote = ICON .. "INV_Misc_Note_03",
    custom = ICON .. "INV_Misc_Note_06", rename = ICON .. "INV_Scroll_03", rank = ICON .. "INV_Scroll_05",
    back = ICON .. "Ability_Rogue_Sprint", alt = ICON .. "Ability_Rogue_Disguise", main = ICON .. "INV_Crown_01",
    ban = ICON .. "INV_Misc_Bone_HumanSkull_01", unban = ICON .. "Spell_Holy_DispelMagic",
    joindate = ICON .. "INV_Misc_PocketWatch_01", promodate = ICON .. "INV_Misc_PocketWatch_02", birthday = ICON .. "INV_Misc_Gift_01",
    loa = ICON .. "Spell_Nature_Sleep", trial = ICON .. "INV_Misc_Note_05", strike = ICON .. "Ability_Warrior_Sunder", request = ICON .. "INV_Letter_15",
    -- overview tiles and lists
    members = ICON .. "Achievement_GuildPerk_EverybodysFriend", online = STATUS .. "StatusIcon-Online", dated = ICON .. "INV_Misc_Note_02",
    inactive = STATUS .. "StatusIcon-Offline", bans = ICON .. "INV_Misc_Bone_HumanSkull_01",
    todo = ICON .. "INV_Misc_Note_05", roster = ICON .. "INV_Misc_Spyglass_03", kicks = STATUS .. "StatusIcon-Offline",
    anniversary = ICON .. "Achievement_GuildPerk_EverybodysFriend", other = ICON .. "INV_Misc_Note_06", sharing = ICON .. "INV_Misc_GroupLooking",
}

-- Puts an icon on a texture region; returns false (and hides it) when there is nothing to show.
local ICON_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function setIcon(texture, path, coords, tint)
    if not texture then return false end
    if not path then texture:Hide() return false end
    texture:SetTexture(path)
    local item = string.find(path, "^Interface\\Icons\\") ~= nil
    -- A masked texture refuses SetTexCoord ("Cannot set tex coords when texture has mask"); the mask already
    -- rounds the art, so a masked medallion keeps its full image.
    if not texture.masked then
        if coords then
            texture:SetTexCoord(unpack(coords))
        elseif item then
            texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            texture:SetTexCoord(0, 1, 0, 1)
        end
    end
    -- Spell and item art is busy at 16 px; a round, desaturated, accent-tinted medallion sits with the flat UI.
    if item and tint then
        if texture.SetDesaturated then pcall(texture.SetDesaturated, texture, true) end
        local r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
        texture:SetVertexColor(0.35 + 0.65 * r, 0.35 + 0.65 * g, 0.35 + 0.65 * b, 1)
        if texture.SetMask and not texture.masked then
            if pcall(texture.SetMask, texture, ICON_MASK) then texture.masked = true end
        end
    else
        if texture.SetDesaturated then pcall(texture.SetDesaturated, texture, false) end
        texture:SetVertexColor(1, 1, 1, 1)
    end
    texture:Show()
    return true
end

local function kindIcon(kind) return ICONS[kind] end

local function classIcon(texture, classFile)
    local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if not coords then if texture then texture:Hide() end return false end
    return setIcon(texture, CLASS_CIRCLES, coords)
end

local frame, pages, tabs = nil, {}, {}
local refreshQueued = false
local card   -- the member card
local currentPage

-- Page state. Declared up here so every page (and the Overview's shortcuts) can read and set it.
local logSearch = ""
local memberSearch, memberFilter = "", "all"
-- A class and/or level range on top of the member filter, set from the Overview's class and level bars:
-- { class = "MAGE", lo = 41, hi = 50 }; nil = no extra limit. Picking a filter from the menu clears it.
local memberScope = nil
local memberState = { sort = "name", desc = false }   -- member list sort
local overviewClass = nil   -- the class picked on the Overview's class bars; the Levels panel shows only that class
local formerSearch = ""
local exportWhat = "members"
local todoShowHandled = false

-- Forward declarations (defined further down).
local openCard, showPage, cardAdvance

-- Small helpers ----------------------------------------------------------------------------------------
local function plain(text)
    text = string.gsub(tostring(text or ""), "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    return text
end

local function setText(fontString, text)
    fontString:SetText(text or "")
end

local function hexToRGB(hex)
    hex = hex or "ffffffff"
    return tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255, tonumber(string.sub(hex, 7, 8), 16) / 255
end

local function plural(n, one, many)
    return tostring(n) .. " " .. (n == 1 and one or (many or (one .. "s")))
end

-- Stock pieces, each with a plain fallback so a missing template never stops the window.
local function newFrame(kind, name, parent, template)
    local ok, result = pcall(CreateFrame, kind, name, parent, template)
    if ok and result then return result, true end
    return CreateFrame(kind, name, parent), false
end

local function makeButton(parent, text, width, onClick)
    local button = newFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 100, 22)
    button:SetText(text)
    button:SetScript("OnClick", function(self) onClick(self) end)
    return button
end

-- A tooltip that also shows while the button is disabled, so a greyed button can say why.
-- Toolbar hints: one short sentence that fits between the controls and the count, with the full explanation on
-- hover. A whole sentence used to run under the count on the right and get cut off with "...".
local function hintText(page, short, long)
    page.hint:SetText(short)
    page.hintLong = long
    if not page.hintArea then
        page.hintArea = CreateFrame("Frame", nil, page)
        page.hintArea:SetAllPoints(page.hint)
        page.hintArea:EnableMouse(true)
        page.hintArea:SetScript("OnEnter", function(self)
            if page.hintLong and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:SetText(page.hintLong, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        page.hintArea:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
end

local function explain(button, textOf)
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    button:SetScript("OnEnter", function(self)
        local text = type(textOf) == "function" and textOf(self) or textOf
        if text and text ~= "" and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function makeCheck(parent, label, onClick)
    local box = newFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    local text = box.text or box.Text or box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:ClearAllPoints()
    text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    text:SetText(label)
    text:SetFontObject(GameFontHighlightSmall)
    box.label = text
    box:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false, self) end)
    return box
end

local function makeEditBox(parent, width, numeric)
    local box = newFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    if numeric then box:SetNumeric(true) end
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function tooltipLines(owner, lines)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for i, line in ipairs(lines) do
        if i == 1 then GameTooltip:SetText(line[1], line[2] or 1, line[3] or 1, line[4] or 1, 1, true)
        else GameTooltip:AddLine(line[1], line[2] or 1, line[3] or 1, line[4] or 1, true) end
    end
    GameTooltip:Show()
end

-- Visual pieces ------------------------------------------------------------------------------------------
local function solid(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
    return texture
end

-- A one-pixel edge around a frame.
local function outline(target, alpha)
    local a = alpha or 0.08
    local top = solid(target, "BORDER", 1, 1, 1, a)
    top:SetPoint("TOPLEFT") top:SetPoint("TOPRIGHT") top:SetHeight(1)
    local bottom = solid(target, "BORDER", 1, 1, 1, a)
    bottom:SetPoint("BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT") bottom:SetHeight(1)
    local left = solid(target, "BORDER", 1, 1, 1, a)
    left:SetPoint("TOPLEFT") left:SetPoint("BOTTOMLEFT") left:SetWidth(1)
    local right = solid(target, "BORDER", 1, 1, 1, a)
    right:SetPoint("TOPRIGHT") right:SetPoint("BOTTOMRIGHT") right:SetWidth(1)
    target.edges = { top, bottom, left, right }
end

-- Background art ("theme") ------------------------------------------------------------------------------------
-- Art the game already ships, stretched behind the content under a dark wash so panels and lists stay readable:
--   class     the class art from the Forever talent window (atlas "talent-background-<class>"); the card shows the member's class
--   random    one of the nine class arts, picked fresh each time the window is built
--   guild     the guild's tabard colour with its emblem as a large watermark
--   world     the world map, drawn from the game's own map tiles (C_Map), or the continent you are on
--   zone      the map of the zone you are standing in
--   parchment the Communities window's parchment (atlas "communities-widebackground")
--   none      the plain stock background
-- Anything the client lacks falls back to the plain background without an error.
local CLASS_ART = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }
-- Scenes: large painted backgrounds the client ships for other windows (landing pages, dashboards). Each name
-- is tried in order and a scene is only offered when the client has one of them, so an unknown name costs
-- nothing. /tabard art lists what this client found.
local SCENES = {
    { key = "midnight", label = "Quel'Thalas", atlases = { "talenttree-PowerSystem-background" } },
    { key = "khazalgar", label = "Khaz Algar", atlases = { "warwithin-landingpage-background", "thewarwithin-landingpage-background", "warwithin-landingpage-bg" } },
    { key = "dragonisles", label = "Dragon Isles", atlases = { "dragonflight-landingpage-background", "dragonflight-landingpage-bg" } },
    { key = "delves", label = "Delves", atlases = { "delves-dashboard-background", "delves-background", "delves-dashboard-bg" } },
    { key = "housing", label = "Housing", atlases = { "housing-dashboard-background", "housing-background", "housing-neighborhood-background" } },
    { key = "vault", label = "Great Vault", atlases = { "greatvault-background", "evergreen-weeklyrewards-background", "weeklyrewards-background" } },
    { key = "chromie", label = "Chromie Time", atlases = { "chromietime-background", "ChromieTime-Background" } },
    { key = "sanctum", label = "Shadowlands sanctum", atlases = { "Sanctum-background-kyrian", "sanctum-kyrian-background", "Sanctum-Kyrian-Background" } },
    { key = "classhall", label = "Legion class hall", atlases = { "legionmission-landingpage-background", "ClassHall-LandingPage-Background", "classhall-landingpage-background" } },
    { key = "adventure", label = "Adventure guide", atlases = { "adventureguide-background", "EJ-background", "encounterjournal-background" } },
    { key = "tradingpost", label = "Trading post", atlases = { "perks-background", "tradingpost-background", "perks-program-background" } },
    { key = "warband", label = "Warband", atlases = { "warband-background", "warbands-background", "warband-bank-background" } },
}
local CLASS_PAINTINGS = { "WARLOCK", "MAGE", "PRIEST", "ROGUE", "DRUID", "SHAMAN", "HUNTER", "PALADIN", "WARRIOR" }
local THEME_ORDER = { "none", "stone", "class", "random", "guild", "world", "zone", "parchment", "art-warlock" }
local THEME_LABELS = { none = "Plain grey", stone = "Grey stone", random = "Something different each time", class = "My class art",
    guild = "Guild tabard", world = "World map", zone = "The zone I am in", parchment = "Parchment", ["art-warlock"] = "Violet stone" }
-- The other class paintings, by name, so a painting seen once can be chosen again whatever class is logged in.
for _, classFile in ipairs(CLASS_PAINTINGS) do
    local key = "art-" .. string.lower(classFile)
    if not THEME_LABELS[key] then
        THEME_ORDER[#THEME_ORDER + 1] = key
        local label = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] or (string.sub(classFile, 1, 1) .. string.lower(string.sub(classFile, 2)))
        THEME_LABELS[key] = label .. " painting"
    end
end
local function paintingClass(theme)
    if type(theme) == "string" and string.sub(theme, 1, 4) == "art-" then return string.upper(string.sub(theme, 5)) end
end
for _, scene in ipairs(SCENES) do
    THEME_ORDER[#THEME_ORDER + 1] = scene.key
    THEME_LABELS[scene.key] = scene.label
end
local DEFAULT_THEME = "none"
local WASH_ORDER = { "subtle", "normal", "bright" }
local WASH_LABELS = { subtle = "Subtle", normal = "Normal", bright = "Bright" }
local WASH_ALPHA = { subtle = 0.62, normal = 0.42, bright = 0.22 }

local function atlasIfExists(atlas)
    if type(atlas) ~= "string" then return nil end
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if not (ok and info) then return nil end
    end
    return atlas
end

local function artAtlasFor(classFile)
    if type(classFile) ~= "string" or not CLASS_ART[classFile] then return nil end
    return atlasIfExists("talent-background-" .. string.lower(classFile))
end

local sceneCache = {}
local function sceneAtlas(key)
    if sceneCache[key] ~= nil then return sceneCache[key] or nil end
    local found = false
    for _, scene in ipairs(SCENES) do
        if scene.key == key then
            for _, atlas in ipairs(scene.atlases) do
                if atlasIfExists(atlas) then found = atlas break end
            end
        end
    end
    sceneCache[key] = found
    return found or nil
end

local function addArt(window, inset)
    local state = { inset = inset, tiles = {} }
    state.art = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
    state.art:SetAllPoints(inset)
    state.art:Hide()
    state.fill = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
    state.fill:SetAllPoints(inset)
    state.fill:Hide()
    state.emblemBack = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
    state.emblemBack:SetPoint("CENTER", inset, "CENTER", 0, 0)
    state.emblemBack:Hide()
    state.emblem = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
    state.emblem:SetPoint("CENTER", inset, "CENTER", 0, 0)
    state.emblem:Hide()
    state.emblemBorder = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
    state.emblemBorder:SetPoint("CENTER", inset, "CENTER", 0, 0)
    state.emblemBorder:Hide()
    state.wash = inset:CreateTexture(nil, "BACKGROUND", nil, 2)
    state.wash:SetAllPoints(inset)
    state.wash:SetColorTexture(0, 0, 0, 0.55)
    state.wash:Hide()
    -- Vignette: the art fades to dark at the edges so the content sits in a lit middle.
    state.vignette = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local strip = inset:CreateTexture(nil, "BACKGROUND", nil, 3)
        strip:SetColorTexture(1, 1, 1, 1)
        if side == "TOP" or side == "BOTTOM" then
            strip:SetPoint("LEFT", inset, "LEFT", 0, 0)
            strip:SetPoint("RIGHT", inset, "RIGHT", 0, 0)
            strip:SetPoint(side, inset, side, 0, 0)
            strip:SetHeight(110)
        else
            strip:SetPoint("TOP", inset, "TOP", 0, 0)
            strip:SetPoint("BOTTOM", inset, "BOTTOM", 0, 0)
            strip:SetPoint(side, inset, side, 0, 0)
            strip:SetWidth(90)
        end
        local okGradient = false
        if CreateColor and strip.SetGradient then
            local clear, dark = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.55)
            -- VERTICAL takes the bottom colour then the top; HORIZONTAL the left then the right.
            if side == "TOP" then okGradient = pcall(strip.SetGradient, strip, "VERTICAL", clear, dark)
            elseif side == "BOTTOM" then okGradient = pcall(strip.SetGradient, strip, "VERTICAL", dark, clear)
            elseif side == "LEFT" then okGradient = pcall(strip.SetGradient, strip, "HORIZONTAL", dark, clear)
            else okGradient = pcall(strip.SetGradient, strip, "HORIZONTAL", clear, dark) end
        end
        if not okGradient then strip:SetColorTexture(0, 0, 0, 0) end
        strip:Hide()
        state.vignette[#state.vignette + 1] = strip
    end
    -- The guild emblem, faint, in the bottom right corner.
    state.markBack = inset:CreateTexture(nil, "BACKGROUND", nil, 3)
    state.mark = inset:CreateTexture(nil, "BACKGROUND", nil, 3)
    state.markBorder = inset:CreateTexture(nil, "BACKGROUND", nil, 3)
    for _, mark in ipairs({ state.markBack, state.mark, state.markBorder }) do
        mark:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
        mark:SetSize(240, 240)
        mark:Hide()
    end
    local classes = {}
    for classFile in pairs(CLASS_ART) do classes[#classes + 1] = classFile end
    state.randomClass = classes[math.random(#classes)]
    window.artState = state
end

local function hideArt(state)
    state.art:Hide()
    if state.art.SetDesaturated then pcall(state.art.SetDesaturated, state.art, false) end
    state.fill:Hide()
    state.emblem:Hide()
    state.emblemBack:Hide()
    state.emblemBorder:Hide()
    for _, tile in ipairs(state.tiles) do tile:Hide() end
    for _, strip in ipairs(state.vignette or {}) do strip:Hide() end
    if state.mark then state.mark:Hide() state.markBack:Hide() state.markBorder:Hide() end
end

local function showWatermark(state)
    if not (state.mark and IsInGuild() and SetLargeGuildTabardTextures) then return end
    local ok = pcall(SetLargeGuildTabardTextures, "player", state.mark, state.markBack, state.markBorder)
    if not ok then return end
    state.markBack:SetAlpha(0.16)
    state.mark:SetAlpha(0.20)
    state.markBorder:SetAlpha(0.12)
    state.markBack:Show()
    state.mark:Show()
    state.markBorder:Show()
end

local function showAtlas(state, atlas)
    if not atlas or not state.art.SetAtlas then return false end
    local ok = pcall(state.art.SetAtlas, state.art, atlas, false)
    if not ok then return false end
    -- Keep the art's proportions: crop whatever does not fit instead of squashing it into the window.
    local okInfo, info = pcall(function() return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) end)
    local width, height = state.inset:GetWidth(), state.inset:GetHeight()
    if okInfo and type(info) == "table" and info.width and info.height and info.width > 0 and info.height > 0 and info.leftTexCoord
        and width and height and width > 0 and height > 0 then
        local artAspect, boxAspect = info.width / info.height, width / height
        local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        if artAspect > boxAspect * 1.02 then        -- wider than the window: trim both sides
            local cut = (1 - boxAspect / artAspect) / 2 * (r - l)
            l, r = l + cut, r - cut
        elseif artAspect * 1.02 < boxAspect then    -- taller: keep more of the top (skies, skylines) than the bottom
            local cut = (1 - artAspect / boxAspect) * (b - t)
            t, b = t + cut * 0.35, b - cut * 0.65
        end
        pcall(state.art.SetTexCoord, state.art, l, r, t, b)
    end
    state.art:SetAlpha(0.9)
    state.art:Show()
    return true
end

-- The guild's tabard colour as a fill, its emblem as a watermark in the middle.
local function showTabard(state)
    if not (IsInGuild() and SetLargeGuildTabardTextures) then return false end
    local size = math.floor(math.min(state.inset:GetWidth(), state.inset:GetHeight()) * 0.8)
    state.emblem:SetSize(size, size)
    state.emblemBack:SetSize(size, size)
    state.emblemBorder:SetSize(size, size)
    local ok = pcall(SetLargeGuildTabardTextures, "player", state.emblem, state.emblemBack, state.emblemBorder)
    if not ok then return false end
    local shown = false
    local okInfo, info = pcall(function() return C_GuildInfo and C_GuildInfo.GetGuildTabardInfo and C_GuildInfo.GetGuildTabardInfo("player") end)
    if okInfo and type(info) == "table" and type(info.backgroundColor) == "table" then
        local c = info.backgroundColor
        state.fill:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, 0.9)
        state.fill:Show()
        shown = true
    end
    state.emblemBack:SetAlpha(0.35)
    state.emblem:SetAlpha(0.35)
    state.emblemBorder:SetAlpha(0.25)
    state.emblemBack:Show()
    state.emblem:Show()
    state.emblemBorder:Show()
    return true or shown
end

-- The game's own map tiles for one map, stretched to fill the inset.
local function showMap(state, mapID)
    if not (mapID and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return false end
    local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    local info = ok and type(layers) == "table" and layers[1] or nil
    if not (info and info.layerWidth and info.tileWidth and info.layerWidth > 0 and info.tileWidth > 0) then return false end
    local okTex, textures = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
    if not (okTex and type(textures) == "table" and #textures > 0) then return false end
    local cols = math.ceil(info.layerWidth / info.tileWidth)
    local rows = math.ceil(info.layerHeight / info.tileHeight)
    local width, height = state.inset:GetWidth(), state.inset:GetHeight()
    if not (width and height and width > 0 and height > 0) then return false end
    local scaleX, scaleY = width / info.layerWidth, height / info.layerHeight
    local index = 0
    for row = 1, rows do
        for col = 1, cols do
            index = index + 1
            local fileID = textures[(row - 1) * cols + col]
            if not fileID then break end
            local tile = state.tiles[index]
            if not tile then
                tile = state.inset:CreateTexture(nil, "BACKGROUND", nil, 1)
                state.tiles[index] = tile
            end
            local visibleWidth = math.min(info.tileWidth, info.layerWidth - (col - 1) * info.tileWidth)
            local visibleHeight = math.min(info.tileHeight, info.layerHeight - (row - 1) * info.tileHeight)
            tile:SetTexture(fileID)
            tile:SetTexCoord(0, visibleWidth / info.tileWidth, 0, visibleHeight / info.tileHeight)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", state.inset, "TOPLEFT", (col - 1) * info.tileWidth * scaleX, -(row - 1) * info.tileHeight * scaleY)
            tile:SetSize(math.max(1, visibleWidth * scaleX), math.max(1, visibleHeight * scaleY))
            tile:SetAlpha(0.9)
            tile:Show()
        end
    end
    return index > 0
end

-- The world map when the client has one, else the continent the player is on.
local function worldMapID()
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    local function infoOf(id) local ok, info = pcall(C_Map.GetMapInfo, id) return ok and info or nil end
    local world = infoOf(947)
    if world then return 947 end
    local id = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local guard = 0
    while id and guard < 10 do
        local info = infoOf(id)
        if not info then break end
        if info.mapType and Enum and Enum.UIMapType and (info.mapType == Enum.UIMapType.Continent or info.mapType == Enum.UIMapType.World) then return id end
        id = info.parentMapID
        guard = guard + 1
    end
    return id
end

-- Themes the client can actually draw, for the Settings dropdown and the title-bar picker.
local function availableThemes()
    local list = {}
    for _, key in ipairs(THEME_ORDER) do
        local usable = true
        if key == "class" or key == "stone" then usable = artAtlasFor("WARRIOR") ~= nil
        elseif paintingClass(key) then usable = artAtlasFor(paintingClass(key)) ~= nil
        elseif key == "guild" then usable = SetLargeGuildTabardTextures ~= nil
        elseif key == "world" or key == "zone" then usable = C_Map ~= nil and C_Map.GetMapArtLayerTextures ~= nil
        elseif key == "parchment" then usable = atlasIfExists("communities-widebackground") ~= nil
        elseif key ~= "random" and key ~= "none" then usable = sceneAtlas(key) ~= nil end
        if usable then list[#list + 1] = key end
    end
    return list
end

-- "Something different each time": one pick per session from everything the client can draw (not the plain
-- background, the tabard or parchment, which are deliberate choices).
local randomPick
local function randomTheme()
    if randomPick then return randomPick end
    local pool = {}
    for _, key in ipairs(availableThemes()) do
        if key ~= "random" and key ~= "none" and key ~= "stone" and key ~= "guild" and key ~= "parchment" and not paintingClass(key) then pool[#pool + 1] = key end
    end
    randomPick = pool[math.random(math.max(1, #pool))] or "class"
    return randomPick
end

local function chosenTheme()
    local theme = GL.settings and GL.settings.backgroundArt or DEFAULT_THEME
    if not THEME_LABELS[theme] then theme = DEFAULT_THEME end
    return theme
end

-- Draws the chosen theme behind a window. classFile: the class to show for the class theme (the member on a card).
local function applyArt(window, classFile)
    local state = window.artState
    if not state then return end
    local chosen = chosenTheme()
    local theme = chosen == "random" and randomTheme() or chosen
    hideArt(state)
    local shown = false
    if theme == "class" then
        local class = classFile
        if not class then
            if chosen == "random" then class = state.randomClass else class = select(2, UnitClass("player")) end
        end
        shown = showAtlas(state, artAtlasFor(class))
    elseif paintingClass(theme) then
        shown = showAtlas(state, artAtlasFor(paintingClass(theme)))
    elseif theme == "stone" then
        -- The class painting with its colour taken out: a grey rock texture.
        shown = showAtlas(state, artAtlasFor(select(2, UnitClass("player"))) or artAtlasFor("WARRIOR"))
        if shown and state.art.SetDesaturated then pcall(state.art.SetDesaturated, state.art, true) end
    elseif theme == "guild" then
        shown = showTabard(state)
    elseif theme == "world" then
        shown = showMap(state, worldMapID())
    elseif theme == "zone" then
        shown = showMap(state, C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    elseif theme == "parchment" then
        shown = showAtlas(state, atlasIfExists("communities-widebackground"))
    elseif sceneAtlas(theme) then
        shown = showAtlas(state, sceneAtlas(theme))
    end
    state.shownTheme = shown and theme or nil
    local wash = WASH_ALPHA[GL.settings and GL.settings.artBrightness or "normal"] or 0.42
    state.wash:SetColorTexture(0, 0, 0, wash)
    if shown then
        state.wash:Show()
        for _, strip in ipairs(state.vignette or {}) do strip:Show() end
        if theme ~= "guild" and theme ~= "parchment" then showWatermark(state) end
    else
        state.wash:Hide()
        -- The plain background keeps the guild's crest.
        if theme == "none" then showWatermark(state) end
    end
end

-- Dropdown entries shared by Settings and the title-bar picker.
local function artMenuItems()
    local items = {}
    for _, key in ipairs(availableThemes()) do
        items[#items + 1] = { text = THEME_LABELS[key], isChecked = function() return chosenTheme() == key end,
            toggle = function() GL.settings.backgroundArt = key randomPick = nil GL:RefreshWindow() end }
    end
    return items
end

-- /tabard art            lists the backgrounds this client can draw
-- /tabard art next|prev  cycles through them
-- /tabard art <name>     picks one
function GL:ArtCommand(rest)
    rest = string.lower(rest or "")
    local list = availableThemes()
    local current = chosenTheme()
    local function pick(key)
        GL.settings.backgroundArt = key
        randomPick = nil
        GL:RefreshWindow()
        local shown = frame and frame.artState and frame.artState.shownTheme
        GL:Print("background: " .. (THEME_LABELS[key] or key) .. " (" .. key .. ")" .. ((key == "random" and shown) and (", showing " .. (THEME_LABELS[shown] or shown)) or ""))
    end
    if rest == "next" or rest == "prev" then
        local index = 1
        for i, key in ipairs(list) do if key == current then index = i end end
        if rest == "next" then index = index % #list + 1 else index = (index - 2) % #list + 1 end
        pick(list[index])
    elseif THEME_LABELS[rest] then
        pick(rest)
    else
        local names = {}
        for _, key in ipairs(list) do names[#names + 1] = key == current and ("|cffffffff" .. key .. "|r") or key end
        GL:Print("background is " .. THEME_LABELS[current] .. ". This client can draw: " .. table.concat(names, ", ")
            .. ". |cffffffff/tabard art next|r tries the next one, |cffffffff/tabard art <name>|r picks one; the Background button on the window does the same.")
    end
end

-- A faint card: translucent dark fill with a thin edge.
local function panel(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder.bg = solid(holder, "BACKGROUND", 0, 0, 0, 0.32)
    holder.bg:SetAllPoints()
    outline(holder, 0.07)
    return holder
end

-- A titled section: a panel with a gold title over a thin rule. Children anchor to `section.body`.
local function section(parent, title, x, y, width, height, anchor)
    local holder = panel(parent)
    holder:SetPoint("TOPLEFT", anchor or parent, "TOPLEFT", x, y)
    holder:SetSize(width, height)
    holder.title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    holder.title:SetPoint("TOPLEFT", holder, "TOPLEFT", 10, -8)
    holder.title:SetText(title)
    holder.aside = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.aside:SetPoint("RIGHT", holder, "TOPRIGHT", -10, -15)
    holder.aside:SetTextColor(0.62, 0.62, 0.62)
    holder.rule = solid(holder, "ARTWORK", 1, 1, 1, 0.12)
    holder.rule:SetPoint("TOPLEFT", holder, "TOPLEFT", 10, -28)
    holder.rule:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -10, -28)
    holder.rule:SetHeight(1)
    holder.body = CreateFrame("Frame", nil, holder)
    holder.body:SetPoint("TOPLEFT", holder, "TOPLEFT", 10, -34)
    holder.body:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -10, 8)
    return holder
end

-- A big number with a caption; clicking it opens the page behind the number.
local function statTile(parent, caption, accent, onClick, hint, icon)
    local tile = CreateFrame("Button", nil, parent)
    tile.bg = solid(tile, "BACKGROUND", 0, 0, 0, 0.36)
    tile.bg:SetAllPoints()
    outline(tile, 0.08)
    local r, g, b = unpack(accent or ACCENT.gold)
    tile.accent = solid(tile, "ARTWORK", r, g, b, 0.85)
    tile.accent:SetPoint("TOPLEFT", 1, -1) tile.accent:SetPoint("TOPRIGHT", -1, -1) tile.accent:SetHeight(2)
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetSize(20, 20)
    tile.icon:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -8)
    tile.icon:SetAlpha(0.9)
    setIcon(tile.icon, icon, nil, { r, g, b })
    tile.number = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    tile.number:SetPoint("TOPLEFT", tile, "TOPLEFT", 10, -9)
    tile.number:SetTextColor(1, 1, 1)
    -- The detail ("in Big Yikes", "186 of 198") stops short of the icon and truncates rather than run under it.
    tile.small = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tile.small:SetPoint("BOTTOMLEFT", tile.number, "BOTTOMRIGHT", 4, 3)
    tile.small:SetPoint("RIGHT", tile.icon, "LEFT", -4, 0)
    tile.small:SetJustifyH("LEFT")
    tile.small:SetWordWrap(false)
    tile.small:SetTextColor(0.62, 0.62, 0.62)
    tile.caption = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tile.caption:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 10, 8)
    tile.caption:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
    tile.caption:SetJustifyH("LEFT")
    tile.caption:SetTextColor(0.75, 0.75, 0.75)
    tile.caption:SetText(caption)
    tile:SetHighlightTexture(SOLID)
    local highlight = tile:GetHighlightTexture()
    if highlight then highlight:SetVertexColor(1, 1, 1, 0.06) end
    if onClick then
        tile:SetScript("OnClick", function() if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end onClick() end)
        tile:SetScript("OnEnter", function(self) if hint then tooltipLines(self, { { caption }, { hint, 0.62, 0.62, 0.62 } }) end end)
        tile:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    function tile.Set(value, small)
        tile.number:SetText(tostring(value))
        tile.small:SetText(small or "")
    end
    return tile
end

-- A labelled horizontal bar: label, count, then a track with a coloured fill.
local function barRow(parent, labelWidth)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(14)
    row:EnableMouse(false)   -- only bars given a click (SetClick) take the mouse
    row.clickReady = false
    row.selectedBg = solid(row, "BACKGROUND", 1, 1, 1, 0.1)
    row.selectedBg:SetPoint("TOPLEFT", row, "TOPLEFT", -4, 1)
    row.selectedBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 4, -1)
    row.selectedBg:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(12, 12)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:Hide()
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWidth(labelWidth or 70)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    -- An icon in front of the label (class circle, for the class bars); the label slides right to make room.
    function row.SetIcon(path, coords)
        row.label:ClearAllPoints()
        if setIcon(row.icon, path, coords) then
            row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.label:SetWidth((labelWidth or 70) - 16)
        else
            row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.label:SetWidth(labelWidth or 70)
        end
    end
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("LEFT", row.label, "RIGHT", 2, 0)
    row.count:SetWidth(28)
    row.count:SetJustifyH("RIGHT")
    row.track = solid(row, "BACKGROUND", 1, 1, 1, 0.07)
    row.track:SetPoint("LEFT", row.count, "RIGHT", 8, 0)
    row.track:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.track:SetHeight(9)
    row.fill = solid(row, "ARTWORK", 1, 1, 1, 0.9)
    row.fill:SetPoint("TOPLEFT", row.track, "TOPLEFT", 0, 0)
    row.fill:SetPoint("BOTTOMLEFT", row.track, "BOTTOMLEFT", 0, 0)
    row.fill:SetWidth(1)
    function row.Set(label, count, fraction, r, g, b)
        row.label:SetText(label)
        row.label:SetTextColor(r or 1, g or 1, b or 1)
        row.count:SetText(tostring(count))
        local width = math.max(1, (row.track:GetWidth() or 1) * math.max(0, math.min(1, fraction or 0)))
        row.fill:SetWidth(width)
        row.fill:SetColorTexture(r or 1, g or 1, b or 1, 0.85)
        row:Show()
    end
    -- Makes the bar a button. tooltip: a function returning tooltipLines() lines, read on hover.
    function row.SetClick(onClick, tooltip)
        row.onClick, row.tooltip = onClick, tooltip
        if row.clickReady then return end
        row.clickReady = true
        row:EnableMouse(true)
        row:SetHighlightTexture(SOLID)
        local highlight = row:GetHighlightTexture()
        if highlight then
            highlight:ClearAllPoints()
            highlight:SetPoint("TOPLEFT", row, "TOPLEFT", -4, 1)
            highlight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 4, -1)
            highlight:SetVertexColor(1, 1, 1, 0.06)
        end
        row:SetScript("OnClick", function(self)
            if not self.onClick then return end
            if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
            self.onClick()
        end)
        row:SetScript("OnEnter", function(self)
            local lines = self.tooltip and self.tooltip()
            if lines then tooltipLines(self, lines) end
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    -- selected: true = marked, false = dimmed (another bar is picked), nil = normal.
    function row.SetSelected(selected)
        if selected then row.selectedBg:Show() else row.selectedBg:Hide() end
        row:SetAlpha(selected == false and 0.5 or 1)
    end
    return row
end

-- A clickable line with a coloured dot: "12 members have no join date  >"
local function linkRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(20)
    row.dot = solid(row, "ARTWORK", 1, 1, 1, 1)
    row.dot:SetSize(6, 6)
    row.dot:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:Hide()
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.dot, "RIGHT", 8, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -18, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow:SetTexture(ARROW)
    row.arrow:SetSize(12, 12)
    row.arrow:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.arrow:SetAlpha(0.5)
    row:SetHighlightTexture(SOLID)
    local highlight = row:GetHighlightTexture()
    if highlight then highlight:SetVertexColor(1, 1, 1, 0.06) end
    row:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    row:SetScript("OnEnter", function(self) if self.hint then tooltipLines(self, { { plain(self.text:GetText() or "") }, { self.hint, 0.62, 0.62, 0.62 } }) end end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    function row.Set(text, accent, onClick, hint, icon)
        local r, g, b = unpack(accent or ACCENT.grey)
        row.dot:SetColorTexture(r, g, b, 1)
        if setIcon(row.icon, icon, nil, { r, g, b }) then row.dot:Hide() else row.dot:Show() end
        row.text:SetText(text)
        row.onClick, row.hint = onClick, hint
        if onClick then row.arrow:Show() else row.arrow:Hide() end
        row:Show()
    end
    return row
end

-- Popups ----------------------------------------------------------------------------------------------
-- One text prompt and one confirmation, reused everywhere. data = { prompt, default, onAccept(text) } / { onAccept }
local function definePopups()
    if not StaticPopupDialogs then return end
    StaticPopupDialogs["TABARDUI_TEXT"] = StaticPopupDialogs["TABARDUI_TEXT"] or {
        text = "%s",
        button1 = SAVE or "Save",
        button2 = CANCEL or "Cancel",
        hasEditBox = true,
        editBoxWidth = 260,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(self, data)
            local box = self.EditBox or self.editBox
            if box then box:SetText(data.default or "") box:SetFocus() box:HighlightText() end
        end,
        OnAccept = function(self, data)
            local box = self.EditBox or self.editBox
            data.onAccept(box and box:GetText() or "")
        end,
        EditBoxOnEnterPressed = function(self)
            local dialog = self:GetParent()
            local data = dialog.data
            if data and data.onAccept then data.onAccept(self:GetText() or "") end
            dialog:Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    }
    StaticPopupDialogs["TABARDUI_CONFIRM"] = StaticPopupDialogs["TABARDUI_CONFIRM"] or {
        text = "%s",
        button1 = YES or "Yes",
        button2 = CANCEL or "Cancel",
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
        OnAccept = function(self, data) data.onAccept() end,
    }
end

local function askText(prompt, default, onAccept)
    if not StaticPopup_Show then return end
    StaticPopup_Show("TABARDUI_TEXT", prompt, nil, { prompt = prompt, default = default, onAccept = onAccept })
end

local function confirm(prompt, onAccept)
    if not StaticPopup_Show then onAccept() return end
    StaticPopup_Show("TABARDUI_CONFIRM", prompt, nil, { onAccept = onAccept })
end

-- Window ------------------------------------------------------------------------------------------
local function styleWindow(window, name, title, width, height)
    local isStock
    window, isStock = newFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    window:SetSize(width, height)
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:SetClampedToScreen(true)
    window:RegisterForDrag("LeftButton")
    window:Hide()
    if isStock then
        if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, window) end
        if ButtonFrameTemplate_HideAttic then pcall(ButtonFrameTemplate_HideAttic, window) end
        -- Flat dark background behind the metal frame (the same colour ForeverAuras uses).
        if window.Bg and window.Bg.SetColorTexture then pcall(window.Bg.SetColorTexture, window.Bg, 0.098, 0.102, 0.118, 0.94) end
    end
    if window.SetTitle then pcall(window.SetTitle, window, title)
    elseif window.TitleContainer and window.TitleContainer.TitleText then window.TitleContainer.TitleText:SetText(title)
    elseif window.TitleText then window.TitleText:SetText(title) end
    local inset = window.Inset
    if not inset then
        inset = newFrame("Frame", nil, window, "InsetFrameTemplate")
        window.Inset = inset
    end
    return window, inset
end

local function setWindowTitle(window, title)
    if window.SetTitle then pcall(window.SetTitle, window, title)
    elseif window.TitleContainer and window.TitleContainer.TitleText then window.TitleContainer.TitleText:SetText(title)
    elseif window.TitleText then window.TitleText:SetText(title) end
end

-- The round portrait at the top left: the guild's tabard for the main window, a class circle for the card.
local function portraitOf(window)
    local container = window.PortraitContainer
    return (container and container.portrait) or window.portrait or window.Portrait
end

local function setPortraitIcon(window, texture, coords)
    local portrait = portraitOf(window)
    if not portrait then return end
    if coords then
        portrait:SetTexture(texture)
        portrait:SetTexCoord(unpack(coords))
    elseif SetPortraitToTexture then
        pcall(SetPortraitToTexture, portrait, texture)
    else
        portrait:SetTexture(texture)
    end
    portrait:Show()
end

local function showGuildEmblem(window)
    local portrait = portraitOf(window)
    if not portrait then return end
    if not window.tabard then
        -- Same pieces and offsets as the stock Communities window's portrait overlay.
        local overlay = CreateFrame("Frame", nil, window)
        overlay:SetAllPoints(window)
        overlay:SetFrameLevel(window:GetFrameLevel() + 6)
        local background = overlay:CreateTexture(nil, "BACKGROUND", nil, 1)
        background:SetSize(60, 60)
        background:SetPoint("TOPLEFT", window, "TOPLEFT", -5, 8)
        background:SetTexture("Interface\\GuildFrame\\GuildFrame")
        background:SetTexCoord(0.63183594, 0.69238281, 0.61914063, 0.74023438)
        local emblem = overlay:CreateTexture(nil, "BACKGROUND", nil, 2)
        emblem:SetSize(56, 64)
        emblem:SetPoint("CENTER", window, "TOPLEFT", 25, -23)
        emblem:SetTexture("Interface\\GuildFrame\\GuildEmblemsLG_01")
        local border = overlay:CreateTexture(nil, "BACKGROUND", nil, 3)
        border:SetSize(60, 59)
        border:SetPoint("TOPLEFT", window, "TOPLEFT", -5, 7)
        border:SetTexture("Interface\\GuildFrame\\GuildFrame")
        border:SetTexCoord(0.63183594, 0.69238281, 0.74414063, 0.86523438)
        window.tabard = { overlay = overlay, background = background, emblem = emblem, border = border }
    end
    local tabard = window.tabard
    local ok = IsInGuild() and SetLargeGuildTabardTextures and pcall(SetLargeGuildTabardTextures, "player", tabard.emblem, tabard.background, tabard.border)
    if ok then
        tabard.overlay:Show()
        portrait:Hide()
    else
        tabard.overlay:Hide()
        setPortraitIcon(window, "Interface\\AddOns\\Tabard\\logo")
    end
end

local function createWindow()
    local inset
    frame, inset = styleWindow(nil, "TabardUIFrame", "Tabard", WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        GL.settings.windowPoint = { point, x, y }
    end)
    tinsert(UISpecialFrames, "TabardUIFrame")
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, TOOLBAR_TOP - TOOLBAR_HEIGHT)
    inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    pcall(showGuildEmblem, frame)
    pcall(addArt, frame, inset)
    local saved = GL.settings.windowPoint
    if type(saved) == "table" and saved[1] then
        frame:ClearAllPoints()
        frame:SetPoint(saved[1], UIParent, saved[1], saved[2] or 0, saved[3] or 0)
    end
end

-- Lists ----------------------------------------------------------------------------------------------
-- A stock scroll list filling `parent`; rows are plain buttons built by `buildRow` and filled by `fillRow`.
-- Every other row carries a faint tint so long lists stay readable.
local function createList(parent, buildRow, fillRow, onClick, rowHeight, extentFor)
    local list = {}
    local scrollBox, hasBox = newFrame("Frame", nil, parent, "WowScrollBoxList")
    local scrollBar, hasBar = newFrame("EventFrame", nil, parent, "MinimalScrollBar")
    scrollBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 3, -3)
    scrollBox:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 3)
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 5, -4)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 5, 4)
    if not (hasBox and hasBar and CreateScrollBoxListLinearView and ScrollUtil and ScrollUtil.InitScrollBoxListWithScrollBar and CreateDataProvider) then
        local notice = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        notice:SetPoint("CENTER")
        notice:SetText("This client is missing the stock list templates; the list cannot be shown.")
        list.SetRows = function() end
        return list
    end
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(rowHeight or ROW_HEIGHT)
    if extentFor and view.SetElementExtentCalculator then
        view:SetElementExtentCalculator(function(_, data) return extentFor(data) or rowHeight or ROW_HEIGHT end)
        list.variable = true
    end
    view:SetElementInitializer("Button", function(button, data)
        if not button.built then
            button.built = true
            button.zebra = solid(button, "BACKGROUND", 1, 1, 1, 0.035)
            button.zebra:SetAllPoints()
            button:SetHighlightTexture(SOLID)
            local highlight = button:GetHighlightTexture()
            if highlight then highlight:SetVertexColor(1, 1, 1, 0.08) end
            buildRow(button)
            button:SetScript("OnClick", function(self, mouseButton)
                if onClick then onClick(self, self.data, mouseButton) end
            end)
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        button.data = data
        if type(data) == "table" and data.index and data.index % 2 == 0 then button.zebra:Show() else button.zebra:Hide() end
        fillRow(button, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    list.scrollBox = scrollBox
    function list.SetRows(rows)
        for i, row in ipairs(rows) do if type(row) == "table" then row.index = i end end
        local provider = CreateDataProvider(rows)
        scrollBox:SetDataProvider(provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    end
    return list
end

-- A list with clickable column headers. columns = { { key, label, width, icon = true for a class circle } }
local function createTable(parent, columns, state, fillCell, onClick, onEnter)
    local headers = {}
    local headerBar = solid(parent, "BACKGROUND", 1, 1, 1, 0.05)
    headerBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 3, -2)
    headerBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -2)
    headerBar:SetHeight(20)
    local x = 6
    for _, column in ipairs(columns) do
        local header = CreateFrame("Button", nil, parent)
        header:SetSize(column.width, 20)
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -2)
        header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.text:SetPoint("LEFT", 4, 0)
        header.text:SetText(column.label)
        header.arrow = header:CreateTexture(nil, "OVERLAY")
        header.arrow:SetTexture(ARROW)
        header.arrow:SetSize(10, 10)
        header.arrow:SetPoint("LEFT", header.text, "RIGHT", 2, 0)
        header.arrow:Hide()
        if not column.icon then
            header:SetHighlightTexture(SOLID)
            local highlight = header:GetHighlightTexture()
            if highlight then highlight:SetVertexColor(1, 1, 1, 0.06) end
            header:SetScript("OnClick", function()
                if state.sort == column.key then state.desc = not state.desc else state.sort, state.desc = column.key, false end
                GL:RefreshWindow()
            end)
        end
        headers[column.key] = header
        x = x + column.width
    end
    local rule = solid(parent, "ARTWORK", 1, 1, 1, 0.12)
    rule:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -22)
    rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -24, -22)
    local listArea = CreateFrame("Frame", nil, parent)
    listArea:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -24)
    listArea:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    local list = createList(listArea,
        function(row)
            row.cells = {}
            local offset = 6
            for _, column in ipairs(columns) do
                if column.icon then
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(16, 16)
                    icon:SetPoint("LEFT", row, "LEFT", offset + 3, 0)
                    row.cells[column.key] = icon
                else
                    local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    cell:SetPoint("LEFT", row, "LEFT", offset + 4, 0)
                    cell:SetWidth(column.width - 8)
                    cell:SetJustifyH("LEFT")
                    cell:SetWordWrap(false)
                    row.cells[column.key] = cell
                end
                offset = offset + column.width
            end
            row:SetScript("OnEnter", function(self) if onEnter and self.data then onEnter(self, self.data) end end)
            row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end,
        function(row, data)
            for _, column in ipairs(columns) do
                local value = fillCell(column.key, data)
                if column.icon then
                    local icon = row.cells[column.key]
                    local coords = value and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[value]
                    if coords then icon:SetTexture(CLASS_CIRCLES) icon:SetTexCoord(unpack(coords)) icon:Show() else icon:Hide() end
                else
                    setText(row.cells[column.key], value)
                end
            end
        end,
        onClick)
    list.headers = headers
    list.area = listArea
    function list.UpdateHeaders()
        for _, column in ipairs(columns) do
            local header = headers[column.key]
            local active = state.sort == column.key
            header.text:SetTextColor(active and 1 or 1, active and 1 or 0.82, active and 1 or 0)
            if active then
                header.arrow:Show()
                if header.arrow.SetRotation then header.arrow:SetRotation(state.desc and -math.pi / 2 or math.pi / 2) end
            else
                header.arrow:Hide()
            end
        end
    end
    function list.Sort(rows, valueOf)
        local key = state.sort
        table.sort(rows, function(a, b)
            local x, y = valueOf(a, key), valueOf(b, key)
            if type(x) ~= type(y) then x, y = tostring(x or ""), tostring(y or "") end
            if type(x) == "string" then x, y = string.lower(x), string.lower(y) end
            if x == y then return string.lower(a.member.name) < string.lower(b.member.name) end
            if state.desc then return x > y end
            return x < y
        end)
    end
    return list
end

-- Toolbar pieces -------------------------------------------------------------------------------------
local function createSearchBox(parent, onChange)
    local box, isStock = newFrame("EditBox", nil, parent, "SearchBoxTemplate")
    box:SetSize(180, 20)
    box:SetAutoFocus(false)
    if not isStock then
        box:SetFontObject(GameFontHighlightSmall)
        local border = newFrame("Frame", nil, box, "InsetFrameTemplate")
        border:SetPoint("TOPLEFT", -4, 4)
        border:SetPoint("BOTTOMRIGHT", 4, -4)
    end
    box:HookScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if text ~= (self.lastText or "") then
            self.lastText = text
            onChange(text)
        end
    end)
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

-- A stock filter button with a check-box menu. `items` = { { text, isChecked(), toggle() } | { text, action() } | { separator } }
-- The button's text follows the current choice (button.SetLabel), so the active filter is always visible.
local function createFilter(parent, label, items, width)
    local button, isStock = newFrame("DropdownButton", nil, parent, "WowStyle1FilterDropdownTemplate")
    local generator = function(_, root)
        for _, item in ipairs(items) do
            if item.separator then
                if root.CreateDivider then root:CreateDivider() end
            elseif item.toggle then
                root:CreateCheckbox(item.text, function() return item.isChecked() end, function() item.toggle() end)
            elseif item.action then
                root:CreateButton(item.text, function() item.action() end)
            end
        end
    end
    local function setLabel(self, text)
        if self.SetText then pcall(self.SetText, self, text) elseif self.Text then self.Text:SetText(text) end
    end
    if isStock and button.SetupMenu then
        button:SetSize(width or 110, 22)
        setLabel(button, label)
        pcall(button.SetupMenu, button, generator)
        button.SetLabel = setLabel
        return button
    end
    button = newFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 110, 22)
    button:SetText(label)
    button.SetLabel = function(self, text) self:SetText(text) end
    if MenuUtil and MenuUtil.CreateContextMenu then
        button:SetScript("OnClick", function(self) MenuUtil.CreateContextMenu(self, generator) end)
    else
        button:Hide()
    end
    return button
end

-- Member picker ----------------------------------------------------------------------------------------
-- A searchable list of members; `onPick(member)` runs for the one clicked. Used wherever a name used to be
-- typed: Set... for the main on the card, and the right-click menu in the Members list.
local pickWindow
local pickState = { search = "", onPick = nil, exclude = nil }

local function refreshPicker()
    if not (pickWindow and pickWindow:IsShown()) then return end
    local guild = GL:Guild()
    local rows = {}
    if guild then
        local needle = string.lower(pickState.search or "")
        for name, member in pairs(guild.members) do
            if member ~= pickState.exclude and (needle == "" or string.find(string.lower(name), needle, 1, true)) then
                rows[#rows + 1] = { member = member, guild = guild }
            end
        end
        table.sort(rows, function(a, b)
            local ma, mb = GL:IsMain(guild, a.member), GL:IsMain(guild, b.member)
            if ma ~= mb then return ma end
            return a.member.name < b.member.name
        end)
    end
    pickWindow.list.SetRows(rows)
    pickWindow.count:SetText(plural(#rows, "member"))
end

local function buildPicker()
    local inset
    pickWindow, inset = styleWindow(nil, "TabardUIPickFrame", "Pick a member", 340, 460)
    pickWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    pickWindow:SetScript("OnDragStart", pickWindow.StartMoving)
    pickWindow:SetScript("OnDragStop", pickWindow.StopMovingOrSizing)
    pickWindow:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "TabardUIPickFrame")
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", pickWindow, "TOPLEFT", 9, -84)
    inset:SetPoint("BOTTOMRIGHT", pickWindow, "BOTTOMRIGHT", -6, 30)
    setPortraitIcon(pickWindow, "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")
    pickWindow.hint = pickWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pickWindow.hint:SetPoint("TOPLEFT", pickWindow, "TOPLEFT", 70, -32)
    pickWindow.hint:SetPoint("RIGHT", pickWindow, "RIGHT", -16, 0)
    pickWindow.hint:SetJustifyH("LEFT")
    pickWindow.hint:SetTextColor(0.62, 0.62, 0.62)
    pickWindow.search = createSearchBox(pickWindow, function(text) pickState.search = text refreshPicker() end)
    pickWindow.search:SetPoint("TOPLEFT", pickWindow, "TOPLEFT", 18, -58)
    pickWindow.search:SetSize(190, 20)
    pickWindow.count = pickWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pickWindow.count:SetPoint("LEFT", pickWindow.search, "RIGHT", 10, 0)
    pickWindow.count:SetTextColor(0.62, 0.62, 0.62)
    pickWindow.list = createList(inset,
        function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetWidth(150)
            row.name:SetJustifyH("LEFT")
            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.detail:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
            row.detail:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.detail:SetJustifyH("LEFT")
            row.detail:SetTextColor(0.62, 0.62, 0.62)
        end,
        function(row, data)
            local member = data.member
            classIcon(row.icon, member.class)
            setText(row.name, GL:ColoredName(member))
            local main, group = GL:MainOf(data.guild, member)
            local detail = "level " .. tostring(member.level or "?")
            if group and main and main.name ~= member.name then detail = "alt of " .. plain(main.name)
            elseif group then detail = "main of " .. plural(#group.alts, "alt") end
            setText(row.detail, detail)
        end,
        function(row, data)
            local onPick = pickState.onPick
            pickWindow:Hide()
            if onPick then onPick(data.member) end
        end)
end

local function openPicker(title, hint, onPick, exclude)
    if not pickWindow then
        local ok, err = pcall(buildPicker)
        if not ok then pickWindow = nil GL:Print("the picker could not be built: " .. tostring(err)) return end
    end
    pickState.onPick, pickState.exclude, pickState.search = onPick, exclude, ""
    setWindowTitle(pickWindow, title)
    pickWindow.hint:SetText(hint or "")
    pickWindow.search:SetText("")
    pickWindow:Show()
    refreshPicker()
    pickWindow.search:SetFocus()
end

-- Links `member` to the main the picker returns (or makes them the main when they pick themselves).
local function pickMainFor(member)
    openPicker("Who is " .. plain(member.name) .. "'s main?", "Pick the character they play most. Picking one of their alts links to that alt's main.", function(main)
        local guild = GL:Guild()
        if not guild then return end
        local realMain = GL:MainOf(guild, main) or main
        local finish = cardAdvance(member)
        if realMain == member then GL:SetMain(guild, member, "user") else GL:LinkAlt(guild, member, realMain, "user") end
        finish()
    end, member)
end

-- Links the character the picker returns as an alt of `member` (or of their main, when `member` is an alt).
-- A character not yet in a group becomes a main with this first alt.
local function pickAltFor(member)
    openPicker("Which character is an alt of " .. plain(member.name) .. "?", "Pick one of their other characters. It becomes an alt of this one, which becomes the main if it was not in a group yet.", function(alt)
        local guild = GL:Guild()
        if not guild then return end
        local main = GL:IsAlt(guild, member) and GL:MainOf(guild, member) or member
        local finish = cardAdvance(member)
        GL:LinkAlt(guild, alt, main, "user")
        finish()
    end, member)
end

-- Right-click on a member: the things officers do most, without opening the card.
local function memberMenu(owner, member)
    local guild = GL:Guild()
    if not (guild and member) then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then pickMainFor(member) return end
    local grouped = GL:GroupOf(guild, member) ~= nil
    local ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
        if root.CreateTitle then root:CreateTitle(plain(member.name)) end
        root:CreateButton("Open card", function() openCard(member) end)
        root:CreateButton("Link as an alt of...", function() pickMainFor(member) end)
        root:CreateButton("Add an alt...", function() pickAltFor(member) end)
        if grouped and not GL:IsMain(guild, member) then root:CreateButton("Make main", function() GL:SetMain(guild, member, "user") GL:RefreshWindow() end) end
        if grouped then root:CreateButton("Unlink", function() GL:Unlink(guild, member, "user") GL:RefreshWindow() end) end
        root:CreateButton("Tabard note...", function()
            askText("Note on " .. plain(member.name) .. " (only Tabard users see it)", member.custom or "", function(text) GL:SetCustomNote(guild, member, text, "user") GL:RefreshWindow() end)
        end)
    end)
    if not ok then pickMainFor(member) end
end

-- Pages ----------------------------------------------------------------------------------------------
local function createPage(key)
    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, TOOLBAR_TOP)
    page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    page:Hide()
    page.body = CreateFrame("Frame", nil, page)     -- the inset's content area
    page.body:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 0, 0)
    page.body:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", 0, 0)
    page.empty = page.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    page.empty:SetPoint("CENTER")
    page.empty:SetWidth(420)
    page.empty:SetJustifyH("CENTER")
    page.empty:Hide()
    page.count = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.count:SetTextColor(0.62, 0.62, 0.62)
    pages[key] = page
    return page
end

local function showEmpty(page, text)
    if text then page.empty:SetText(text) page.empty:Show() else page.empty:Hide() end
end

-- Shortcuts other pages use to land on a page with a filter already set.
local MEMBER_FILTER_LABELS = { all = "Everyone", online = "Online now", inactive = "Inactive", mains = "Mains and ungrouped", alts = "Alts only",
    ungrouped = "No main or alt set", nodate = "Missing a join date", noted = "Has a Tabard note", banned = "On the ban list",
    trial = "In the trial rank", loa = "On leave", altproblem = "Alt groups with a problem", new = "New this week" }

local function goMembers(filter)
    memberFilter = filter or "all"
    memberScope = nil
    memberSearch = ""
    if pages.members and pages.members.search then pages.members.search:SetText("") end
    showPage("members")
end

-- Opens the member list limited to a class and/or level range, highest level first.
-- scope = { class = "MAGE", lo = 41, hi = 50 } (each part optional).
local function goMembersScope(scope)
    memberFilter, memberScope, memberSearch = "all", scope, ""
    memberState.sort, memberState.desc = "level", true
    if pages.members and pages.members.search then pages.members.search:SetText("") end
    showPage("members")
end

-- "Mage, 41-50", "Mage", "Level 51+" for the member filter button.
local function scopeLabel(scope)
    local range
    if scope.lo and scope.hi then range = scope.lo .. "-" .. scope.hi
    elseif scope.hi then range = "1-" .. scope.hi
    elseif scope.lo then range = scope.lo .. "+" end
    if scope.class then return GL:ClassName(scope.class) .. (range and (", " .. range) or "") end
    return range and ("Level " .. range) or "Everyone"
end

-- Shows only the given kinds in the log (nil = everything), then opens it.
local function goLog(kinds)
    GL.settings.showFilters = {}
    if kinds then
        local any = false
        for _, kind in ipairs(GL.KIND_ORDER) do
            if kinds[kind] then any = true else GL.settings.showFilters[kind] = false end
        end
        if not any then GL.settings.showFilters = {} end   -- an empty set would hide everything
    end
    showPage("log")
end

-- Log page ---------------------------------------------------------------------------------------------
local function kindShown(kind)
    local shown = GL.settings.showFilters[kind]
    return shown == nil or shown == true
end

local function hiddenKinds()
    local n = 0
    for _, kind in ipairs(GL.KIND_ORDER) do if not kindShown(kind) then n = n + 1 end end
    return n
end

local function eventText(event, guild)
    if not event.plainCache then
        event.plainCache = string.lower(plain(GL:Describe(event, guild)))
    end
    return event.plainCache
end

local function logRows()
    local guild = GL:Guild()
    if not guild then return {}, 0, 0 end
    if hiddenKinds() >= #GL.KIND_ORDER then GL.settings.showFilters = {} end   -- a filter that hides everything is no filter
    local rows, total = {}, #guild.events
    local needle = string.lower(logSearch)
    for i = #guild.events, 1, -1 do
        local event = guild.events[i]
        if kindShown(event.k) and (needle == "" or string.find(eventText(event, guild), needle, 1, true)) then
            rows[#rows + 1] = { event = event, guild = guild }
        end
    end
    table.sort(rows, function(a, b) return a.event.t > b.event.t end)
    local shown = #rows
    -- What happened since your last login sits above a divider, the rest under "Earlier".
    local since = guild.visitSince
    if type(since) == "number" and #rows > 0 and rows[1].event.t > since then
        local fresh = 0
        for _, row in ipairs(rows) do if row.event.t > since then fresh = fresh + 1 else break end end
        if fresh < #rows then tinsert(rows, fresh + 1, { header = "Earlier", guild = guild }) end
        tinsert(rows, 1, { header = "Since your last visit", aside = plural(fresh, "event") .. ", " .. GL:Ago(since), guild = guild })
    end
    return rows, total, shown
end

-- The second, dim line under a leave: when they joined and the rank they held, so the time as a member reads
-- at a glance. nil for everything else.
local function leaveDetail(data)
    local event = data.event
    if not event or not (event.k == "leave" or event.k == "kick") then return nil end
    local member = data.guild and event.who and GL:Member(data.guild, event.who)
    local since = event.since or (member and member.joined)
    local parts = {}
    if type(since) == "number" and since > 0 then parts[#parts + 1] = "joined " .. GL:FormatDate(since) end
    if event.from then parts[#parts + 1] = "last rank " .. tostring(event.from) end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

local function logExtent(data)
    if type(data) ~= "table" then return nil end
    if data.header then return 26 end
    if leaveDetail(data) then return ROW_HEIGHT + 13 end
    return nil
end

local function buildLogPage()
    local page = createPage("log")
    page.search = createSearchBox(page, function(text) logSearch = text GL:RefreshWindow() end)
    page.search:SetPoint("TOPLEFT", page, "TOPLEFT", 72, -7)

    local items = {}
    for _, kind in ipairs(GL.KIND_ORDER) do
        items[#items + 1] = { text = GL.KINDS[kind].label, isChecked = function() return kindShown(kind) end,
            toggle = function() GL.settings.showFilters[kind] = not kindShown(kind) GL:RefreshWindow() end }
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = "Show everything", action = function() GL.settings.showFilters = {} GL:RefreshWindow() end }
    items[#items + 1] = { text = "Only joins and leaves", action = function() goLog({ join = true, rejoin = true, leave = true, kick = true }) end }
    items[#items + 1] = { text = "Only rank changes", action = function() goLog({ promote = true, demote = true, rank = true }) end }
    items[#items + 1] = { text = "Only officer edits", action = function() goLog({ note = true, onote = true, custom = true, alt = true, main = true, ban = true, unban = true, joindate = true, promodate = true, birthday = true }) end }
    page.filter = createFilter(page, FILTER or "Filter", items, 120)
    page.filter:SetPoint("RIGHT", page, "TOPRIGHT", -10, -TOOLBAR_HEIGHT / 2)
    page.count:SetPoint("RIGHT", page.filter, "LEFT", -10, 0)

    -- Each row: a faint tint and a coloured badge naming the kind, then the time and the sentence.
    page.list = createList(page.body,
        function(row)
            row.tint = row:CreateTexture(nil, "BACKGROUND")
            row.tint:SetAllPoints()
            row.tint:SetColorTexture(1, 1, 1, 0.05)
            row.stripe = solid(row, "BORDER", 1, 1, 1, 0.6)
            row.stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.stripe:SetWidth(2)
            row.badgeBack = row:CreateTexture(nil, "BORDER")
            row.badgeBack:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.badgeBack:SetSize(104, 16)
            row.badgeBack:SetColorTexture(1, 1, 1, 0.12)
            row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.badge:SetPoint("CENTER", row.badgeBack, "CENTER", 0, 0)
            row.badge:SetWidth(84)
            row.badge:SetJustifyH("CENTER")
            row.kindIcon = row:CreateTexture(nil, "ARTWORK")
            row.kindIcon:SetSize(13, 13)
            row.kindIcon:SetPoint("LEFT", row.badgeBack, "LEFT", 3, 0)
            row.badge:ClearAllPoints()
            row.badge:SetPoint("LEFT", row.kindIcon, "RIGHT", 2, 0)
            row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.time:SetPoint("LEFT", row.badgeBack, "RIGHT", 8, 0)
            row.time:SetWidth(110)
            row.time:SetJustifyH("LEFT")
            row.time:SetTextColor(0.62, 0.62, 0.62)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.time, "RIGHT", 4, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -1)
            row.sub:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.sub:SetJustifyH("LEFT")
            row.sub:SetWordWrap(false)
            row.sub:SetTextColor(0.62, 0.62, 0.62)
            row.heading = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.heading:SetPoint("LEFT", row, "LEFT", 8, 1)
            row.headingAside = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.headingAside:SetPoint("LEFT", row.heading, "RIGHT", 8, 0)
            row.headingAside:SetTextColor(0.62, 0.62, 0.62)
            row.headingRule = solid(row, "ARTWORK", 1, 1, 1, 0.12)
            row.headingRule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 2)
            row.headingRule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 2)
            row.headingRule:SetHeight(1)
            row:SetScript("OnEnter", function(self)
                if not self.data or self.data.header then return end
                local event = self.data.event
                local lines = { { plain(GL:Describe(event, self.data.guild)) }, { GL:FormatTime(event.t) .. "  (" .. GL:Ago(event.t) .. ")", 0.62, 0.62, 0.62 } }
                if event.src == "game" then lines[#lines + 1] = { "From the game's guild event log; the time is rounded to the hour.", 0.62, 0.62, 0.62 } end
                if event.src == "sync" then lines[#lines + 1] = { "Shared by another officer.", 0.62, 0.62, 0.62 } end
                if event.who and GL:Member(self.data.guild, event.who) then lines[#lines + 1] = { "Click to open " .. event.who .. ".", 0.62, 0.62, 0.62 } end
                tooltipLines(self, lines)
            end)
            row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end,
        function(row, data)
            local parts = { row.tint, row.stripe, row.badgeBack, row.badge, row.kindIcon, row.time, row.text }
            if data.header then
                row.zebra:Hide()
                for _, part in ipairs(parts) do part:Hide() end
                row.sub:Hide()
                row.heading:SetText(data.header)
                row.headingAside:SetText(data.aside or "")
                row.heading:Show() row.headingAside:Show() row.headingRule:Show()
                return
            end
            row.heading:Hide() row.headingAside:Hide() row.headingRule:Hide()
            for _, part in ipairs(parts) do part:Show() end
            local kind = GL.KINDS[data.event.k] or { label = data.event.k, color = "ffffffff" }
            local r, g, b = hexToRGB(kind.color)
            row.tint:SetColorTexture(r, g, b, 0.03)
            row.stripe:SetColorTexture(r, g, b, 0.7)
            row.badgeBack:SetColorTexture(r, g, b, 0.16)
            row.badge:SetText(kind.label)
            row.badge:SetTextColor(r, g, b)
            if not setIcon(row.kindIcon, kindIcon(data.event.k), nil, { r, g, b }) then row.kindIcon:Hide() end
            setText(row.time, GL:FormatTime(data.event.t))
            setText(row.text, GL:Describe(data.event, data.guild))
            local detail = page.list and page.list.variable and leaveDetail(data) or nil
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", row.time, "RIGHT", 4, detail and 7 or 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            if detail then row.sub:SetText(detail) row.sub:Show() else row.sub:Hide() end
        end,
        function(row, data)
            if data.header then return end
            local member = data.event.who and GL:Member(data.guild, data.event.who)
            if member then openCard(member) end
        end, nil, logExtent)

    page.refresh = function()
        local rows, total, shown = logRows()
        page.list.SetRows(rows)
        if total == 0 then
            showEmpty(page, "Nothing recorded yet. Events are added as members join, leave, level up or change rank while you are online.")
        elseif shown == 0 then
            showEmpty(page, "No events match the search and filter.")
        else
            showEmpty(page, nil)
        end
        local hidden = hiddenKinds()
        page.filter:SetLabel(hidden == 0 and (FILTER or "Filter") or (hidden .. " hidden"))
        setText(page.count, (shown == total) and plural(total, "event") or (shown .. " of " .. plural(total, "event")))
    end
end

-- Members page --------------------------------------------------------------------------------------------
local MEMBER_COLUMNS = {
    { key = "icon", label = "", width = 22, icon = true },
    { key = "name", label = "Name", width = 140 },
    { key = "nick", label = "Nickname", width = 72 },
    { key = "level", label = "Level", width = 44 },
    { key = "rank", label = "Rank", width = 90 },
    { key = "main", label = "Main", width = 96 },
    { key = "joined", label = "Joined", width = 88 },
    { key = "lastOnline", label = "Last online", width = 92 },
    { key = "raids", label = "Raids", width = 44 },
    { key = "note", label = "Note", width = 56 },
}

local function memberRows(guild)
    local rows, total = {}, 0
    local needle = string.lower(memberSearch)
    local now = GL:Now()
    local kickAfter = (GL.settings.kickDays or 60) * 86400
    local trialRank = GL.TrialRank and GL:TrialRank(guild)
    local altProblems
    if memberFilter == "altproblem" then
        altProblems = {}
        local ok, list = pcall(function() return GL.AltAudit and GL:AltAudit(guild) or {} end)
        if ok then for _, row in ipairs(list) do altProblems[row.member.name] = row.problem end end
    end
    for name, member in pairs(guild.members) do
        total = total + 1
        local keep = true
        if memberFilter == "nodate" then keep = member.joined == nil
        elseif memberFilter == "trial" then keep = trialRank ~= nil and member.rankIndex == trialRank
        elseif memberFilter == "loa" then keep = GL.OnLeave ~= nil and GL:OnLeave(member, now)
        elseif memberFilter == "altproblem" then keep = altProblems[name] ~= nil
        elseif memberFilter == "online" then keep = member.online == true
        elseif memberFilter == "new" then keep = GL.IsNewcomer ~= nil and GL:IsNewcomer(member, now)
        elseif memberFilter == "inactive" then keep = (not member.online) and member.lastOnline ~= nil and (now - member.lastOnline) >= kickAfter
        elseif memberFilter == "mains" then keep = not GL:IsAlt(guild, member)
        elseif memberFilter == "alts" then keep = GL:IsAlt(guild, member)
        elseif memberFilter == "ungrouped" then keep = GL:GroupOf(guild, member) == nil
        elseif memberFilter == "noted" then keep = member.custom ~= nil
        elseif memberFilter == "banned" then keep = GL:BanFor(guild, member) ~= nil end
        if keep and memberScope then
            local level = member.level or 0
            if memberScope.class and member.class ~= memberScope.class then keep = false
            elseif memberScope.lo and level < memberScope.lo then keep = false
            elseif memberScope.hi and level > memberScope.hi then keep = false end
        end
        if keep and needle ~= "" then
            keep = string.find(string.lower(name), needle, 1, true) ~= nil or string.find(string.lower(member.rank or ""), needle, 1, true) ~= nil
                or string.find(string.lower(member.note or ""), needle, 1, true) ~= nil or string.find(string.lower(member.custom or ""), needle, 1, true) ~= nil
                or string.find(string.lower(GL:Nickname(guild, member) or ""), needle, 1, true) ~= nil
        end
        if keep then
            local main = GL:MainOf(guild, member)
            rows[#rows + 1] = { member = member, guild = guild, main = main and main.name ~= name and main or nil }
        end
    end
    return rows, total
end

local function memberTooltip(row, data)
    local member, guild = data.member, data.guild or GL:Guild()
    if not guild then return end
    local r, g, b = GL:ClassColor(member.class)
    local lines = { { member.name, r, g, b } }
    lines[#lines + 1] = { "Level " .. tostring(member.level or "?") .. " " .. GL:ClassName(member.class) .. ", " .. tostring(member.rank or ""), 1, 1, 1 }
    if member.joined then
        lines[#lines + 1] = { "Joined " .. GL:FormatDate(member.joined) .. " (" .. (GL.SOURCE_LABEL[member.joinedSource or ""] or "") .. ")", 1, 1, 1 }
    else
        lines[#lines + 1] = { "No join date yet. First seen " .. GL:FormatDate(member.firstSeen) .. ".", 1, 0.82, 0 }
    end
    if member.promoted then lines[#lines + 1] = { "In this rank since " .. GL:FormatDate(member.promoted), 1, 1, 1 } end
    if member.invitedBy then lines[#lines + 1] = { "Invited by " .. member.invitedBy, 1, 1, 1 } end
    if GL.IsNewcomer and GL:IsNewcomer(member) then
        local done, total, parts, minutes = GL:NewcomerSummary(guild, member)
        lines[#lines + 1] = { "New this week: " .. minutes .. " min online, " .. done .. "/" .. total .. " steps" .. (#parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""), 0.2, 0.87, 0.8 }
        if not GL:NewcomerContacted(member) then lines[#lines + 1] = { "Nobody has talked to them yet.", 1, 0.6, 0.2 } end
    end
    local main = GL:MainOf(guild, member)
    if main and main.name ~= member.name then lines[#lines + 1] = { "Alt of " .. plain(main.name), 0.75, 0.63, 1 } end
    local alts = GL:AltsOf(guild, member)
    if #alts > 0 and (not main or main.name == member.name) then
        local names = {}
        for _, alt in ipairs(alts) do names[#names + 1] = alt.name end
        lines[#lines + 1] = { "Alts: " .. table.concat(names, ", "), 0.75, 0.63, 1 }
    end
    if member.note and member.note ~= "" then lines[#lines + 1] = { "Note: " .. member.note, 0.8, 0.8, 0.8 } end
    if member.onote and member.onote ~= "" then lines[#lines + 1] = { "Officer note: " .. member.onote, 0.8, 0.6, 1 } end
    if member.custom then lines[#lines + 1] = { "Tabard note: " .. member.custom, 0.87, 0.6, 1 } end
    if GL:BanFor(guild, member) then lines[#lines + 1] = { "On the ban list", 1, 0.3, 0.3 } end
    lines[#lines + 1] = { "Click to open the member card.", 0.62, 0.62, 0.62 }
    tooltipLines(row, lines)
end

local function buildMembersPage()
    local page = createPage("members")
    page.search = createSearchBox(page, function(text) memberSearch = text GL:RefreshWindow() end)
    page.search:SetPoint("TOPLEFT", page, "TOPLEFT", 72, -7)

    local function choose(value) return function() memberFilter = value memberScope = nil GL:RefreshWindow() end end
    local function chosen(value) return function() return memberScope == nil and memberFilter == value end end
    page.filter = createFilter(page, "Everyone", {
        { text = "Everyone", isChecked = chosen("all"), toggle = choose("all") },
        { text = "Online now", isChecked = chosen("online"), toggle = choose("online") },
        { text = "New this week", isChecked = chosen("new"), toggle = choose("new") },
        { text = "Inactive", isChecked = chosen("inactive"), toggle = choose("inactive") },
        { separator = true },
        { text = "Mains and ungrouped", isChecked = chosen("mains"), toggle = choose("mains") },
        { text = "Alts only", isChecked = chosen("alts"), toggle = choose("alts") },
        { text = "No main or alt set", isChecked = chosen("ungrouped"), toggle = choose("ungrouped") },
        { separator = true },
        { text = "Missing a join date", isChecked = chosen("nodate"), toggle = choose("nodate") },
        { text = "Has a Tabard note", isChecked = chosen("noted"), toggle = choose("noted") },
        { text = "On the ban list", isChecked = chosen("banned"), toggle = choose("banned") },
        { separator = true },
        { text = "In the trial rank", isChecked = chosen("trial"), toggle = choose("trial") },
        { text = "On leave", isChecked = chosen("loa"), toggle = choose("loa") },
        { text = "Alt groups with a problem", isChecked = chosen("altproblem"), toggle = choose("altproblem") },
    }, 150)
    page.filter:SetPoint("RIGHT", page, "TOPRIGHT", -10, -TOOLBAR_HEIGHT / 2)
    page.count:SetPoint("RIGHT", page.filter, "LEFT", -10, 0)

    -- With "No main or alt set" showing: everyone listed becomes a main of their own in one go, for when the
    -- list is long and most of them really are one-character members. Real alts can still be linked afterwards.
    page.massMain = makeButton(page, "Make all mains", 110, function()
        local guild, rows = GL:Guild(), page.rows or {}
        if not guild or #rows == 0 then return end
        confirm(string.format("Make all %d of these mains? Each starts a group of their own and stops counting as unsorted. Anyone who is really an alt can still be linked from their card.", #rows), function()
            local done = 0
            for _, row in ipairs(rows) do
                if GL:GroupOf(guild, row.member) == nil and GL:SetMain(guild, row.member, "user") then done = done + 1 end
            end
            GL:Print(plural(done, "member") .. " made mains.")
            GL:RefreshWindow()
        end)
    end)
    page.massMain:SetPoint("RIGHT", page.count, "LEFT", -10, 0)
    page.massMain:Hide()
    explain(page.massMain, "Everyone in this list becomes a main of their own group, in one go. Use it when most of them are one-character members; link the real alts from their cards afterwards.")

    page.table = createTable(page.body, MEMBER_COLUMNS, memberState,
        function(key, data)
            local member = data.member
            if key == "icon" then return member.class
            elseif key == "name" then return GL:ColoredName(member)
            elseif key == "nick" then return GL:Nickname(data.guild, member) or ""
            elseif key == "level" then return member.level and tostring(member.level) or ""
            elseif key == "rank" then return member.rank or ""
            elseif key == "main" then
                if data.main then return GREY .. "alt of |r" .. GL:ColoredName(data.main) end
                local alts = GL:AltsOf(data.guild, member)
                if #alts > 0 then return GREY .. "main of " .. plural(#alts, "alt") .. "|r" end
                return ""
            elseif key == "joined" then return member.joined and GL:FormatDate(member.joined) or (YELLOW .. "not set|r")
            elseif key == "lastOnline" then return member.online and (GREEN .. "online|r") or GL:Ago(member.lastOnline)
            elseif key == "raids" then
                if (page.raidsHeld or 0) == 0 then return "" end
                local rate = page.attendance[(data.main or member).name]
                return rate and (math.floor(rate * 100 + 0.5) .. "%") or (GREY .. "0%|r")
            elseif key == "note" then return member.custom and ("|cffdd99ff" .. member.custom .. "|r") or (GREY .. (member.note or "") .. "|r") end
        end,
        function(row, data, mouseButton)
            if mouseButton == "RightButton" then memberMenu(row, data.member) else openCard(data.member) end
        end,
        memberTooltip)
    page.attendance, page.raidsHeld = {}, 0

    page.refresh = function()
        local guild = GL:Guild()
        local rows, total = {}, 0
        if guild then rows, total = memberRows(guild) end
        -- Raid attendance over the last 30 days, by main (Raids.lua), read once per refresh.
        page.attendance, page.raidsHeld = {}, 0
        if guild then
            local ok, list, held = pcall(function() if GL.Attendance then return GL:Attendance(guild, GL:Now(), 30) end end)
            if ok and type(list) == "table" then
                page.raidsHeld = held or 0
                for _, entry in ipairs(list) do page.attendance[entry.name] = entry.rate end
            end
        end
        page.table.Sort(rows, function(row, key)
            local member = row.member
            if key == "raids" then return page.attendance[(row.main or member).name] or 0 end
            if key == "nick" then return GL:Nickname(guild, member) or "~" end   -- "~" sorts the blanks last
            if key == "rank" then return member.rankIndex or 99 end
            if key == "main" then return row.main and row.main.name or (GL:IsMain(guild, member) and ("" .. member.name) or "~") end
            if key == "lastOnline" then return member.online and GL:Now() or (member.lastOnline or 0) end
            if key == "note" then return member.custom or member.note or "" end
            return member[key]
        end)
        page.table.SetRows(rows)
        page.table.UpdateHeaders()
        page.rows = rows   -- in the order shown, for the card to walk (cardAdvance) and the mass action
        if memberScope == nil and memberFilter == "ungrouped" and #rows > 0 then page.massMain:Show() else page.massMain:Hide() end
        page.filter:SetLabel(memberScope and scopeLabel(memberScope)
            or memberFilter == "inactive" and ("Inactive " .. (GL.settings.kickDays or 60) .. "+ days") or MEMBER_FILTER_LABELS[memberFilter] or "Everyone")
        if total == 0 then
            showEmpty(page, IsInGuild() and "No members recorded yet; the roster is read a few seconds after you log in." or "You are not in a guild.")
        elseif #rows == 0 then
            showEmpty(page, "No members match the search and filter.")
        else
            showEmpty(page, nil)
        end
        local online = 0
        if guild then for _, member in pairs(guild.members) do if member.online then online = online + 1 end end end
        if #rows == total then
            setText(page.count, string.format("%d members, %d online", total, online))
        else
            setText(page.count, string.format("%d of %d members", #rows, total))
        end
    end
end

-- Former members page --------------------------------------------------------------------------------------
local formerState = { sort = "left", desc = true }
local FORMER_COLUMNS = {
    { key = "icon", label = "", width = 22, icon = true },
    { key = "name", label = "Name", width = 160 },
    { key = "level", label = "Level", width = 44 },
    { key = "rank", label = "Last rank", width = 110 },
    { key = "joined", label = "Joined", width = 100 },
    { key = "left", label = "Left", width = 100 },
    { key = "how", label = "How", width = 150 },
    { key = "ban", label = "Ban", width = 60 },
}

local function buildFormerPage()
    local page = createPage("former")
    page.search = createSearchBox(page, function(text) formerSearch = text GL:RefreshWindow() end)
    page.search:SetPoint("TOPLEFT", page, "TOPLEFT", 72, -7)
    page.count:SetPoint("RIGHT", page, "TOPRIGHT", -16, -TOOLBAR_HEIGHT / 2)

    page.table = createTable(page.body, FORMER_COLUMNS, formerState,
        function(key, data)
            local member = data.member
            if key == "icon" then return member.class
            elseif key == "name" then return GL:ColoredName(member)
            elseif key == "level" then return member.level and tostring(member.level) or ""
            elseif key == "rank" then return member.rank or ""
            elseif key == "joined" then return member.joined and GL:FormatDate(member.joined) or ""
            elseif key == "left" then return GL:FormatDate(member.left)
            elseif key == "how" then return member.leftKind == "kick" and (RED .. "removed|r" .. (member.leftBy and (GREY .. " by " .. member.leftBy .. "|r") or "")) or "left"
            elseif key == "ban" then return GL:IsBanned(data.guild, member.name) and (RED .. "banned|r") or "" end
        end,
        function(row, data) openCard(data.member) end,
        memberTooltip)

    page.refresh = function()
        local guild = GL:Guild()
        local rows, total = {}, 0
        if guild then
            local needle = string.lower(formerSearch)
            for name, member in pairs(guild.former) do
                total = total + 1
                if needle == "" or string.find(string.lower(name), needle, 1, true) then rows[#rows + 1] = { member = member, guild = guild } end
            end
        end
        page.table.Sort(rows, function(row, key)
            local member = row.member
            if key == "rank" then return member.rankIndex or 99 end
            if key == "how" then return member.leftKind or "" end
            if key == "ban" then return GL:IsBanned(guild, member.name) and 1 or 0 end
            return member[key] or 0
        end)
        page.table.SetRows(rows)
        page.table.UpdateHeaders()
        showEmpty(page, total == 0 and "Nobody has left since the ledger started." or (#rows == 0 and "No former members match the search." or nil))
        setText(page.count, plural(total, "former member"))
    end
end

-- Bans page ---------------------------------------------------------------------------------------------------
local banState = { sort = "t", desc = true }
local BAN_COLUMNS = {
    { key = "icon", label = "", width = 22, icon = true },
    { key = "name", label = "Name", width = 160 },
    { key = "t", label = "Banned on", width = 100 },
    { key = "by", label = "By", width = 120 },
    { key = "reason", label = "Reason", width = 250 },
    { key = "status", label = "Status", width = 90 },
}

local function addBan(name)
    local guild = GL:Guild()
    if not guild then return end
    local function finish(who)
        who = strtrim(who or "")
        if who == "" then return end
        local member = GL:FindMember(guild, who, true)
        who = member and member.name or who
        if GL:IsBanned(guild, who) then GL:Print(who .. " is already on the ban list.") return end
        askText("Why is " .. who .. " banned? (shown to officers when they try to rejoin)", "", function(reason)
            GL:Ban(guild, who, reason, "user")
            GL:RefreshWindow()
            -- Their alts, if the ledger knows any: offer to ban the whole group.
            local alts = {}
            if member then
                local main = GL:MainOf(guild, member) or member
                if main.name ~= member.name and not GL:IsBanned(guild, main.name) then alts[#alts + 1] = main end
                for _, alt in ipairs(GL:AltsOf(guild, main)) do
                    if alt.name ~= member.name and not GL:IsBanned(guild, alt.name) then alts[#alts + 1] = alt end
                end
            end
            if #alts > 0 then
                local names = {}
                for _, alt in ipairs(alts) do names[#names + 1] = alt.name end
                confirm("Ban " .. plural(#alts, "linked character", "linked characters") .. " too? (" .. table.concat(names, ", ") .. ")", function()
                    for _, alt in ipairs(alts) do GL:Ban(guild, alt.name, reason, "user") end
                    GL:RefreshWindow()
                end)
            end
        end)
    end
    if name then finish(name) else askText("Name of the character to ban (they do not have to be in the guild)", "", finish) end
end

local function buildBansPage()
    local page = createPage("bans")
    page.add = makeButton(page, "Add a ban", 110, function() addBan() end)
    page.add:SetPoint("LEFT", page, "TOPLEFT", 66, -TOOLBAR_HEIGHT / 2)
    page.hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.hint:SetPoint("LEFT", page.add, "RIGHT", 12, 0)
    page.hint:SetTextColor(0.62, 0.62, 0.62)
    hintText(page, "Click a row to lift or restore a ban.", "Click a row to lift or restore a ban. Tabard warns you when a banned character, or an alt of one, joins.")
    page.count:SetPoint("RIGHT", page, "TOPRIGHT", -16, -TOOLBAR_HEIGHT / 2)
    page.hint:SetPoint("RIGHT", page.count, "LEFT", -12, 0)   -- never runs under the count on the right
    page.hint:SetJustifyH("LEFT")
    page.hint:SetWordWrap(false)

    page.table = createTable(page.body, BAN_COLUMNS, banState,
        function(key, data)
            local ban = data.ban
            if key == "icon" then return ban.class
            elseif key == "name" then return GL:ColoredName({ name = data.name, class = ban.class })
            elseif key == "t" then return GL:FormatDate(ban.t)
            elseif key == "by" then return ban.by or ""
            elseif key == "reason" then return ban.reason or ""
            elseif key == "status" then return ban.lifted and (GREY .. "lifted|r") or (data.inGuild and (RED .. "in the guild!|r") or (GREEN .. "active|r")) end
        end,
        function(row, data, mouseButton)
            local guild = data.guild
            if data.ban.lifted then
                confirm("Ban " .. data.name .. " again?", function() data.ban.lifted = nil GL:Ban(guild, data.name, data.ban.reason, "user") GL:RefreshWindow() end)
            else
                confirm("Lift the ban on " .. data.name .. "?", function() GL:Unban(guild, data.name, "user") GL:RefreshWindow() end)
            end
        end,
        function(row, data)
            tooltipLines(row, { { data.name }, { data.ban.reason or "", 1, 1, 1 }, { "Banned by " .. (data.ban.by or "?") .. " on " .. GL:FormatDate(data.ban.t), 0.8, 0.8, 0.8 },
                { data.ban.lifted and ("Lifted by " .. (data.ban.liftedBy or "?") .. " on " .. GL:FormatDate(data.ban.lifted) .. ". Click to ban again.") or "Click to lift the ban.", 0.62, 0.62, 0.62 } })
        end)

    page.refresh = function()
        local guild = GL:Guild()
        local rows, active = {}, 0
        if guild then
            for name, ban in pairs(guild.bans) do
                rows[#rows + 1] = { name = name, ban = ban, guild = guild, member = { name = name }, inGuild = guild.members[name] ~= nil }
                if not ban.lifted then active = active + 1 end
            end
        end
        page.table.Sort(rows, function(row, key)
            if key == "name" then return row.name end
            if key == "status" then return row.ban.lifted and 1 or 0 end
            return row.ban[key] or 0
        end)
        page.table.SetRows(rows)
        page.table.UpdateHeaders()
        showEmpty(page, #rows == 0 and "No bans yet. Add one here or from a member's card." or nil)
        setText(page.count, plural(active, "active ban"))
    end
end

-- Play page -------------------------------------------------------------------------------------------------------
-- Guildies online near your level, grouped by zone, with the dungeons that fit. Roster data only.
local playBand = GL.PLAY_BAND or 4
local function openWhisper(name)
    local text = "/w " .. name .. " "
    if ChatFrameUtil and ChatFrameUtil.OpenChat then ChatFrameUtil.OpenChat(text)
    elseif ChatFrame_OpenChat then ChatFrame_OpenChat(text) end
end

local function buildPlayPage()
    local page = createPage("play")
    local function band(value) return function() playBand = value GL:RefreshWindow() end end
    local function isBand(value) return function() return playBand == value end end
    page.filter = createFilter(page, "Within 4 levels", {
        { text = "Within 4 levels", isChecked = isBand(4), toggle = band(4) },
        { text = "Within 8 levels", isChecked = isBand(8), toggle = band(8) },
        { text = "Everyone online", isChecked = isBand(nil), toggle = band(nil) },
    }, 150)
    page.filter:SetPoint("LEFT", page, "TOPLEFT", 66, -TOOLBAR_HEIGHT / 2)
    page.hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.hint:SetPoint("LEFT", page.filter, "RIGHT", 12, 0)
    page.hint:SetTextColor(0.62, 0.62, 0.62)
    hintText(page, "Online near your level. Click to whisper.", "Who you could play with right now. AFK, DND and app users are left out. Click a row to whisper, right-click for more.")
    page.count:SetPoint("RIGHT", page, "TOPRIGHT", -16, -TOOLBAR_HEIGHT / 2)
    page.hint:SetPoint("RIGHT", page.count, "LEFT", -12, 0)
    page.hint:SetJustifyH("LEFT")
    page.hint:SetWordWrap(false)

    page.list = createList(page.body,
        function(row)
            row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.header:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.header:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.header:SetJustifyH("LEFT")
            row.header:SetWordWrap(false)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", row, "LEFT", 24, 0)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetWidth(260)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
            row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.level:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
            row.level:SetWidth(70)
            row.level:SetJustifyH("LEFT")
            row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.tag:SetPoint("LEFT", row.level, "RIGHT", 8, 0)
            row.tag:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.tag:SetJustifyH("LEFT")
            row.tag:SetWordWrap(false)
        end,
        function(row, data)
            local isHeader = data.header ~= nil or data.note ~= nil
            row.header:SetShown(isHeader)
            row.icon:SetShown(not isHeader)
            row.name:SetShown(not isHeader)
            row.level:SetShown(not isHeader)
            row.tag:SetShown(not isHeader)
            if data.note then
                row.header:SetText(GREY .. data.note .. "|r")
                row.zebra:Hide()
            elseif data.header then
                row.header:SetText(data.header .. "  " .. GREY .. plural(data.n, "guildie") .. "|r")
                row.zebra:Hide()
            else
                local member, guild = data.member, data.guild
                classIcon(row.icon, member.class)
                row.name:SetText(GL:ColoredName(member))
                row.level:SetText("Level " .. tostring(member.level or "?"))
                local bits = {}
                local main = GL:MainOf(guild, member)
                if main and main ~= member then bits[#bits + 1] = "alt of " .. plain(main.name) end
                if GL.IsNewcomer and GL:IsNewcomer(member) then bits[#bits + 1] = "|cff33ddccnew this week|r" end
                row.tag:SetText(#bits > 0 and (GREY .. table.concat(bits, ", ") .. "|r") or "")
            end
        end,
        function(row, data, mouseButton)
            if not data.member then return end
            if mouseButton == "RightButton" then memberMenu(row, data.member) else openWhisper(data.member.name) end
        end,
        22, function(data) return (data.header or data.note) and 26 or 22 end)

    page.refresh = function()
        local guild = GL:Guild()
        local rows, total = {}, 0
        local level = (UnitLevel and tonumber(UnitLevel("player"))) or 0
        if guild and GL.PlayNow then
            local dungeons = GL:DungeonsFor(level)
            rows[#rows + 1] = { note = "Dungeons for level " .. level .. ": " .. (#dungeons > 0 and table.concat(dungeons, ", ") or "none in range") }
            for _, group in ipairs(GL:PlayNow(guild, nil, playBand)) do
                rows[#rows + 1] = { header = group.zone, n = #group.members }
                for _, member in ipairs(group.members) do
                    rows[#rows + 1] = { member = member, guild = guild }
                    total = total + 1
                end
            end
        end
        page.list.SetRows(rows)
        page.filter:SetLabel(playBand and ("Within " .. playBand .. " levels") or "Everyone online")
        showEmpty(page, total == 0 and (playBand and "Nobody is online near your level right now. Try a wider band." or "Nobody else is online right now.") or nil)
        setText(page.count, plural(total, "guildie") .. " online" .. (playBand and (" within " .. playBand .. " levels of you") or ""))
    end
end

-- Tools page ------------------------------------------------------------------------------------------------------
-- Four panels: members to consider removing and members due a promotion on top (with actions), then retention by
-- join week and who recruits people who stay (read-only, from Officers.lua).
local function buildToolsPage()
    local page = createPage("tools")
    page.body:Hide()
    local inset = frame.Inset
    local GAP = 8
    local SPLIT = 30      -- the top row gets this much more height than the bottom one

    local function quad(column, rowIndex, title)
        local holder = section(page, title, 0, 0, 10, 10)
        holder:ClearAllPoints()
        if column == 1 then
            holder:SetPoint("LEFT", inset, "LEFT", GAP, 0)
            holder:SetPoint("RIGHT", inset, "CENTER", -GAP / 2, 0)
        else
            holder:SetPoint("LEFT", inset, "CENTER", GAP / 2, 0)
            holder:SetPoint("RIGHT", inset, "RIGHT", -GAP, 0)
        end
        if rowIndex == 1 then
            holder:SetPoint("TOP", inset, "TOP", 0, -GAP)
            holder:SetPoint("BOTTOM", inset, "CENTER", 0, GAP / 2 - SPLIT)
        else
            holder:SetPoint("TOP", inset, "CENTER", 0, -GAP / 2 - SPLIT)
            holder:SetPoint("BOTTOM", inset, "BOTTOM", 0, GAP)
        end
        holder.help = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        holder.help:SetPoint("TOPLEFT", holder.body, "TOPLEFT", 0, 0)
        holder.help:SetPoint("RIGHT", holder.body, "RIGHT", 0, 0)
        holder.help:SetJustifyH("LEFT")
        holder.help:SetTextColor(0.62, 0.62, 0.62)
        holder.listArea = CreateFrame("Frame", nil, holder)
        if rowIndex == 1 then
            holder.listArea:SetPoint("TOPLEFT", holder.body, "TOPLEFT", -6, -30)
        else
            holder.listArea:SetPoint("TOPLEFT", holder.help, "BOTTOMLEFT", -6, -4)   -- the help text may wrap; the list starts under it
        end
        holder.listArea:SetPoint("BOTTOMRIGHT", holder.body, "BOTTOMRIGHT", 6, rowIndex == 1 and 30 or 0)
        if rowIndex == 1 then
            holder.footRule = solid(holder, "ARTWORK", 1, 1, 1, 0.12)
            holder.footRule:SetPoint("BOTTOMLEFT", holder.body, "BOTTOMLEFT", 0, 26)
            holder.footRule:SetPoint("BOTTOMRIGHT", holder.body, "BOTTOMRIGHT", 0, 26)
            holder.footRule:SetHeight(1)
        end
        holder.empty = holder.listArea:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        holder.empty:SetPoint("CENTER")
        holder.empty:SetWidth(300)
        return holder
    end

    local function listIn(holder, fillLine, onClick, onEnter)
        return createList(holder.listArea,
            function(row)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(14, 14)
                row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -120, 0)
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.right:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.right:SetWidth(112)
                row.right:SetJustifyH("RIGHT")
                row.right:SetTextColor(0.62, 0.62, 0.62)
                row:SetScript("OnEnter", function(self) if self.data and onEnter then onEnter(self, self.data) end end)
                row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            end,
            function(row, data)
                local left, right, classFile = fillLine(data)
                setText(row.text, left)
                setText(row.right, right)
                local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
                if coords then row.icon:SetTexture(CLASS_CIRCLES) row.icon:SetTexCoord(unpack(coords)) row.icon:Show() else row.icon:Hide() end
            end,
            onClick)
    end

    local function runAll(kind, rows, verb)
        local names = {}
        for _, row in ipairs(rows) do names[#names + 1] = row.member.name end
        if #names == 0 then return end
        confirm(string.format("%s %d members now? This uses your guild permissions and cannot be undone.", verb, #names), function()
            GL:GuildActionMany(kind, names, function(done, failed)
                GL:Print(string.format("%s %d of %d.", verb, done, #names) .. (#failed > 0 and (" Could not: " .. table.concat(failed, ", ")) or ""))
                GL:RequestScan(true)
            end)
        end)
    end

    local function macroFor(kind, rows)
        local names = {}
        for _, row in ipairs(rows) do names[#names + 1] = row.member.name end
        if #names == 0 then return end
        local body, used, left, err = GL:BuildMacro(kind, names)
        if not body then GL:Print("could not write the macro" .. (err and (": " .. err) or ".")) return end
        GL:Print(string.format("macro \"Ledger\" written with %d names%s. Drag it from the macro window (/macro) to a bar and press it.", #used, #left > 0 and ("; " .. #left .. " did not fit and will go in the next one") or ""))
    end

    local function nameLine(data)
        return GL:ColoredName(data.member) .. GREY .. "  " .. (data.member.level or "") .. " " .. (data.member.rank or "") .. "|r", nil, data.member.class
    end

    -- Top left: inactive
    local inactive = quad(1, 1, "Inactive members")
    inactive.list = listIn(inactive,
        function(data) local left, _, class = nameLine(data) return left, GL:Span(data.away), class end,
        function(row, data, mouseButton)
            if mouseButton == "RightButton" then GL:SetSafe(GL:Guild(), data.member, "kick", true, "user") GL:Print(data.member.name .. " will not be suggested for removal.") GL:RefreshWindow()
            else openCard(data.member) end
        end, memberTooltip)
    inactive.days = makeEditBox(inactive, 40, true)
    inactive.days:SetPoint("BOTTOMLEFT", inactive.body, "BOTTOMLEFT", 54, 0)
    inactive.daysLabel = inactive:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    inactive.daysLabel:SetPoint("RIGHT", inactive.days, "LEFT", -8, 0)
    inactive.daysLabel:SetText("Away for")
    inactive.daysAfter = inactive:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    inactive.daysAfter:SetPoint("LEFT", inactive.days, "RIGHT", 4, 0)
    inactive.daysAfter:SetText("days")
    inactive.days:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    inactive.days:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if value and value >= 1 then GL.settings.kickDays = math.floor(value) end
        GL:RefreshWindow()
    end)
    inactive.remove = makeButton(inactive, "Remove all", 100, function() runAll("kick", inactive.rows or {}, "Removed") end)
    inactive.remove:SetPoint("BOTTOMRIGHT", inactive.body, "BOTTOMRIGHT", 0, -1)
    explain(inactive.remove, function(self) if not self:IsEnabled() then return GL:CanRemove() and "Nobody to remove." or "Your guild rank cannot remove members. Use the macro instead." end return "Removes everyone in this list, one every half second." end)
    inactive.macro = makeButton(inactive, "Macro", 70, function() macroFor("kick", inactive.rows or {}) end)
    inactive.macro:SetPoint("RIGHT", inactive.remove, "LEFT", -4, 0)
    explain(inactive.macro, "Writes a macro named \"Tabard\" with one /gremove line per name, for when the game refuses addon actions.")

    -- Top right: promotions
    local promote = quad(2, 1, "Promotions due")
    promote.list = listIn(promote,
        function(data) local left, _, class = nameLine(data) return left, GL:Span(data.waiting), class end,
        function(row, data, mouseButton)
            if mouseButton == "RightButton" then GL:SetSafe(GL:Guild(), data.member, "promote", true, "user") GL:Print(data.member.name .. " will not be suggested for promotion.") GL:RefreshWindow()
            else openCard(data.member) end
        end, memberTooltip)
    promote.days = makeEditBox(promote, 40, true)
    promote.days:SetPoint("BOTTOMLEFT", promote.body, "BOTTOMLEFT", 40, 0)
    promote.daysLabel = promote:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    promote.daysLabel:SetPoint("RIGHT", promote.days, "LEFT", -8, 0)
    promote.daysLabel:SetText("After")
    promote.daysAfter = promote:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    promote.daysAfter:SetPoint("LEFT", promote.days, "RIGHT", 4, 0)
    promote.daysAfter:SetText("days in rank")
    promote.days:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if value and value >= 1 then GL.settings.promoteDays = math.floor(value) end
        GL:RefreshWindow()
    end)
    promote.run = makeButton(promote, "Promote all", 100, function() runAll("promote", promote.rows or {}, "Promoted") end)
    promote.run:SetPoint("BOTTOMRIGHT", promote.body, "BOTTOMRIGHT", 0, -1)
    explain(promote.run, function(self) if not self:IsEnabled() then return GL:CanPromote() and "Nobody to promote." or "Your guild rank cannot promote members. Use the macro instead." end return "Promotes everyone in this list one rank, one every half second." end)
    promote.macro = makeButton(promote, "Macro", 70, function() macroFor("promote", promote.rows or {}) end)
    promote.macro:SetPoint("RIGHT", promote.run, "LEFT", -4, 0)
    explain(promote.macro, "Writes a macro named \"Tabard\" with one /gpromote line per name, for when the game refuses addon actions.")

    -- Bottom left: retention by join week
    local cohorts = quad(1, 2, "Retention by join week")
    cohorts.help:SetText("Of the people who joined each week, how many were still here 7, 14 and 30 days later.")
    local function weekLabel(week)
        local y, m, d = string.match(week or "", "^(%d+)%-(%d+)%-(%d+)$")
        if not y then return tostring(week) end
        return "Week of " .. GL:FormatDate(time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))
    end
    local function kept(row, days)
        if row.judged[days] == 0 then return "-" end
        return row.kept[days] .. "/" .. row.judged[days]
    end
    cohorts.list = listIn(cohorts,
        function(data)
            local row = data.row
            return weekLabel(row.week) .. GREY .. "  " .. plural(row.joined, "join") .. "|r", "7d " .. kept(row, 7) .. "  14d " .. kept(row, 14) .. "  30d " .. kept(row, 30), nil
        end, nil,
        function(self, data)
            local row = data.row
            tooltipLines(self, { { weekLabel(row.week) }, { plural(row.joined, "member") .. " joined that week.", 1, 1, 1 },
                { "Still in the guild after 7 days: " .. kept(row, 7) .. ", after 14: " .. kept(row, 14) .. ", after 30: " .. kept(row, 30) .. ".", 0.8, 0.8, 0.8 },
                { "A dash means not enough time has passed to judge yet.", 0.62, 0.62, 0.62 } })
        end)

    -- Bottom right: recruiters
    local recruiters = quad(2, 2, "Recruiters, last 90 days")
    recruiters.help:SetText("Who invites people, and how many of those are still here two weeks later.")
    recruiters.list = listIn(recruiters,
        function(data)
            local row = data.row
            local rate = row.rate and (math.floor(row.rate * 100 + 0.5) .. "% kept") or "too new to judge"
            return GL:ColoredName(row.member, row.name) .. GREY .. "  " .. plural(row.invites, "invite") .. "|r", row.here .. " here, " .. rate, row.member and row.member.class or nil
        end,
        function(row, data) if data.row.member then openCard(data.row.member) end end,
        function(self, data)
            local row = data.row
            tooltipLines(self, { { plain(row.name) }, { plural(row.invites, "invite") .. " in the last 90 days; " .. row.here .. " of them are still in the guild.", 1, 1, 1 },
                { row.judged > 0 and (row.kept .. " of the " .. row.judged .. " old enough to judge stayed at least 14 days.") or "None of them are two weeks old yet.", 0.8, 0.8, 0.8 },
                { row.member and "Click to open the member card." or "", 0.62, 0.62, 0.62 } })
        end)

    page.refresh = function()
        local guild = GL:Guild()
        if not guild then return end
        local now = GL:Now()
        inactive.rows = GL:KickCandidates(guild, now)
        inactive.list.SetRows(inactive.rows)
        inactive.aside:SetText(plural(#inactive.rows, "member"))
        inactive.help:SetText(string.format("Offline for %d+ days, with every alt in their group also away. Right-click a name to leave them alone.", GL.settings.kickDays or 60))
        if not inactive.days:HasFocus() then inactive.days:SetText(tostring(GL.settings.kickDays or 60)) end
        inactive.empty:SetText(#inactive.rows == 0 and "Nobody has been away that long." or "")
        inactive.remove:SetEnabled(GL:CanRemove() and #inactive.rows > 0)
        inactive.macro:SetEnabled(#inactive.rows > 0)

        promote.rows = GL:PromoteCandidates(guild, now)
        promote.list.SetRows(promote.rows)
        local rank = GL:NewcomerRank(guild)
        promote.aside:SetText(plural(#promote.rows, "member"))
        promote.help:SetText(string.format("In \"%s\" for %d+ days. Right-click a name to leave them alone.", rank and guild.ranks[rank] or "the newest rank", GL.settings.promoteDays or 14))
        if not promote.days:HasFocus() then promote.days:SetText(tostring(GL.settings.promoteDays or 14)) end
        promote.empty:SetText(#promote.rows == 0 and "Nobody is waiting on a promotion." or "")
        promote.run:SetEnabled(GL:CanPromote() and #promote.rows > 0)
        promote.macro:SetEnabled(#promote.rows > 0)

        local cohortRows = {}
        local okCohorts, list = pcall(function() return GL.Cohorts and GL:Cohorts(guild, now, 10) or {} end)
        if okCohorts and type(list) == "table" then for _, row in ipairs(list) do cohortRows[#cohortRows + 1] = { row = row } end end
        cohorts.list.SetRows(cohortRows)
        cohorts.empty:SetText(#cohortRows == 0 and "No joins recorded in the last ten weeks." or "")
        cohorts.aside:SetText(#cohortRows > 0 and plural(#cohortRows, "week") or "")

        local recruiterRows = {}
        local okRecruiters, people = pcall(function() return GL.Recruiters and GL:Recruiters(guild, now, 90) or {} end)
        if okRecruiters and type(people) == "table" then for _, row in ipairs(people) do recruiterRows[#recruiterRows + 1] = { row = row } end end
        recruiters.list.SetRows(recruiterRows)
        recruiters.empty:SetText(#recruiterRows == 0 and "No invites with a known inviter in the last 90 days." or "")
        recruiters.aside:SetText(#recruiterRows > 0 and plural(#recruiterRows, "recruiter") or "")
    end
end

-- Export page ------------------------------------------------------------------------------------------------------
local function buildExportPage()
    local page = createPage("export")
    page.body:Hide()
    local inset = frame.Inset
    local LABELS = { members = "Members", former = "Former members", log = "Log", bans = "Bans", attendance = "Raid attendance (30 days)", raid = "Last raid" }
    local items = {}
    for _, key in ipairs({ "members", "former", "log", "bans", "attendance", "raid" }) do
        items[#items + 1] = { text = LABELS[key], isChecked = function() return exportWhat == key end, toggle = function() exportWhat = key GL:RefreshWindow() end }
    end
    page.pick = createFilter(page, "Members", items, 150)
    page.pick:SetPoint("LEFT", page, "TOPLEFT", 66, -TOOLBAR_HEIGHT / 2)
    page.hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.hint:SetPoint("LEFT", page.pick, "RIGHT", 12, 0)
    page.hint:SetTextColor(0.62, 0.62, 0.62)
    hintText(page, "Ctrl+A, Ctrl+C in the box, then paste into a spreadsheet.", "Comma-separated text. Click in the box, press Ctrl+A then Ctrl+C, and paste into a spreadsheet.")
    page.count:SetPoint("RIGHT", page, "TOPRIGHT", -16, -TOOLBAR_HEIGHT / 2)
    page.hint:SetPoint("RIGHT", page.count, "LEFT", -12, 0)
    page.hint:SetJustifyH("LEFT")
    page.hint:SetWordWrap(false)

    local scroll = newFrame("ScrollFrame", "TabardUIExportScroll", page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -28, 8)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontSmall or GameFontHighlightSmall)
    box:SetWidth(WINDOW_WIDTH - 60)
    box:SetHeight(440)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.exportText or "") self:HighlightText() end end)
    scroll:SetScrollChild(box)
    page.box = box

    page.refresh = function()
        local guild = GL:Guild()
        local text = ""
        if guild and exportWhat == "raid" then
            local ok, sessions = pcall(function() return GL.RaidSessions and GL:RaidSessions(guild, GL:Now(), 365) or {} end)
            local session = ok and type(sessions) == "table" and sessions[1] or nil
            text = session and GL:RaidDigest(guild, session) or "No raid recorded yet. Raids are tracked while you are in a raid group (see Settings)."
        elseif guild and exportWhat == "attendance" then
            local ok, list, held = pcall(function() if GL.Attendance then return GL:Attendance(guild, GL:Now(), 30) end end)
            local lines = { "Main,Attended,Held,Rate,Benched,Late,Pulls,Kills,Characters" }
            if ok and type(list) == "table" then
                for _, entry in ipairs(list) do
                    local chars = {}
                    for k, v in pairs(entry.chars or {}) do chars[#chars + 1] = type(k) == "string" and k or tostring(v) end
                    table.sort(chars)
                    lines[#lines + 1] = string.format("%s,%d,%d,%d%%,%d,%d,%d,%d,%s", plain(entry.name), entry.attended or 0, held or 0, math.floor((entry.rate or 0) * 100 + 0.5),
                        entry.benched or 0, entry.late or 0, entry.pulls or 0, entry.kills or 0, table.concat(chars, "; "))
                end
            end
            text = table.concat(lines, "\n")
        elseif guild then
            text = GL:ExportText(guild, exportWhat)
        end
        box.exportText = text
        box:SetText(text)
        page.pick:SetLabel(LABELS[exportWhat])
        local lines = 0
        for _ in string.gmatch(text, "\n") do lines = lines + 1 end
        setText(page.count, plural(lines, "row"))
    end
end

-- To-do page --------------------------------------------------------------------------------------------------
-- Everything that wants an officer's eyes (Officers.lua): trials due, leaves that ended, banned characters in
-- the guild, alts whose main left, whispered requests, promotions due and returning members. One officer marks
-- an item handled for everyone; requests get Approve / Decline.
local TODO_KINDS = {
    roster = { label = "Roster", color = ACCENT.red }, trial = { label = "Trial", color = { 0.84, 0.66, 0.36 } },
    loa = { label = "Leave", color = { 0.56, 0.72, 1 } }, banned = { label = "Banned", color = ACCENT.red },
    orphan = { label = "Alt", color = ACCENT.purple }, request = { label = "Request", color = { 0.7, 0.55, 1 } },
    altpair = { label = "Alt?", color = ACCENT.purple },
    promote = { label = "Promote", color = ACCENT.gold }, back = { label = "Back", color = ACCENT.teal },
    newcomer = { label = "New", color = ACCENT.teal },
}

local function buildTodoPage()
    local page = createPage("todo")
    page.showHandled = makeCheck(page, "Show handled", function(checked) todoShowHandled = checked GL:RefreshWindow() end)
    page.showHandled:SetPoint("LEFT", page, "TOPLEFT", 64, -TOOLBAR_HEIGHT / 2)
    page.hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.hint:SetPoint("LEFT", page.showHandled.label, "RIGHT", 16, 0)
    page.hint:SetTextColor(0.62, 0.62, 0.62)
    hintText(page, "Handled once, handled for every officer.", "Marking an item handled hides it for every officer running Tabard. Members can whisper you !main, !bday or !loa and the request lands here.")
    page.count:SetPoint("RIGHT", page, "TOPRIGHT", -16, -TOOLBAR_HEIGHT / 2)
    page.hint:SetPoint("RIGHT", page.count, "LEFT", -12, 0)
    page.hint:SetJustifyH("LEFT")
    page.hint:SetWordWrap(false)

    page.list = createList(page.body,
        function(row)
            row.stripe = solid(row, "BORDER", 1, 1, 1, 0.6)
            row.stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.stripe:SetWidth(2)
            row.badgeBack = row:CreateTexture(nil, "BORDER")
            row.badgeBack:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.badgeBack:SetSize(66, 16)
            row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.badge:SetPoint("CENTER", row.badgeBack, "CENTER", 0, 0)
            row.badge:SetWidth(62)
            row.badge:SetJustifyH("CENTER")
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(14, 14)
            row.icon:SetPoint("LEFT", row.badgeBack, "RIGHT", 8, 0)
            row.who = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.who:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.who:SetWidth(110)
            row.who:SetJustifyH("LEFT")
            row.who:SetWordWrap(false)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.who, "RIGHT", 4, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -248, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.since = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.since:SetPoint("RIGHT", row, "RIGHT", -156, 0)
            row.since:SetWidth(88)
            row.since:SetJustifyH("RIGHT")
            row.since:SetTextColor(0.62, 0.62, 0.62)
            local function guildAnd(callback) return function() local data = row.data if data then callback(data.guild, data.item) end GL:RefreshWindow() end end
            row.handle = makeButton(row, "Handled", 70, guildAnd(function(guild, item) GL:MarkHandled(guild, item.key, "user") end))
            row.handle:SetSize(70, 20)
            row.handle:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            explain(row.handle, "Mark this handled for every officer. It stays visible under \"Show handled\" for 30 days.")
            row.undo = makeButton(row, "Undo", 70, guildAnd(function(guild, item) GL:ClearHandled(guild, item.key) end))
            row.undo:SetSize(70, 20)
            row.undo:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.decline = makeButton(row, "Decline", 70, function()
                local data = row.data
                if not (data and data.item.member) then return end
                local name = data.item.member.name
                if data.item.kind == "altpair" then
                    GL:DismissAltPair(data.guild, name, data.item.other and data.item.other.name or "")
                    GL:RefreshWindow()
                    return
                end
                askText("Tell " .. name .. " why? (optional)", "", function(why) GL:DeclineRequest(data.guild, name, why) GL:RefreshWindow() end)
            end)
            row.decline:SetSize(70, 20)
            row.decline:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            explain(row.decline, function() local item = row.data and row.data.item return (item and item.kind == "altpair") and "Not alts: hides this pair for good." or "Drops the request and whispers the member (on your next click)." end)
            row.approve = makeButton(row, "Approve", 70, guildAnd(function(guild, item)
                if item.kind == "altpair" then
                    if item.member and item.other and GL:AcceptAltPair(guild, item.member, item.other) then
                        GL:Print("linked " .. plain(item.member.name) .. " as an alt of " .. plain((GL:MainOf(guild, item.other) or item.other).name) .. ".")
                    end
                    return
                end
                if item.member and GL:ApproveRequest(guild, item.member.name) then GL:Print("applied " .. plain(item.member.name) .. "'s request.")
                else GL:Print("could not apply that request; the character may have left.") end
            end))
            row.approve:SetSize(70, 20)
            row.approve:SetPoint("RIGHT", row.decline, "LEFT", -4, 0)
            explain(row.approve, function() local item = row.data and row.data.item return (item and item.kind == "altpair") and "Links them as an alt of the other character's main." or "Applies the request as if you had typed it, and whispers the member (on your next click)." end)
            row:SetScript("OnEnter", function(self)
                local data = self.data
                if not data then return end
                local item = data.item
                local lines = { { item.member and plain(item.member.name) or (TODO_KINDS[item.kind] and TODO_KINDS[item.kind].label or item.kind) }, { item.text, 1, 1, 1 } }
                lines[#lines + 1] = { "Since " .. GL:FormatDate(item.since) .. " (" .. GL:Ago(item.since) .. ")", 0.62, 0.62, 0.62 }
                if item.handled then lines[#lines + 1] = { "Handled by " .. tostring(item.handled.by) .. " " .. GL:Ago(item.handled.t), 0.62, 0.62, 0.62 } end
                if item.member then lines[#lines + 1] = { "Click to open the member card.", 0.62, 0.62, 0.62 } end
                tooltipLines(self, lines)
            end)
            row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end,
        function(row, data)
            local item = data.item
            local kind = TODO_KINDS[item.kind] or { label = item.kind, color = ACCENT.grey }
            local r, g, b = unpack(kind.color)
            local dim = item.handled and 0.45 or 1
            row.stripe:SetColorTexture(r, g, b, 0.7 * dim)
            row.badgeBack:SetColorTexture(r, g, b, 0.16 * dim)
            row.badge:SetText(kind.label)
            row.badge:SetTextColor(r * dim, g * dim, b * dim)
            local coords = item.member and item.member.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[item.member.class]
            if coords then row.icon:SetTexture(CLASS_CIRCLES) row.icon:SetTexCoord(unpack(coords)) row.icon:SetAlpha(dim) row.icon:Show() else row.icon:Hide() end
            setText(row.who, item.member and GL:ColoredName(item.member) or "")
            row.who:SetAlpha(dim)
            setText(row.text, item.text)
            row.text:SetAlpha(dim)
            setText(row.since, item.handled and ("handled by " .. tostring(item.handled.by)) or GL:Ago(item.since))
            local isRequest = (item.kind == "request" or item.kind == "altpair") and not item.handled and item.member ~= nil
            row.approve:SetText(item.kind == "altpair" and "Link" or "Approve")
            row.decline:SetText(item.kind == "altpair" and "Not alts" or "Decline")
            if item.handled then row.undo:Show() else row.undo:Hide() end
            if isRequest then row.approve:Show() row.decline:Show() else row.approve:Hide() row.decline:Hide() end
            if item.handled or isRequest then row.handle:Hide() else row.handle:Show() end
        end,
        function(row, data) if data.item.member then openCard(data.item.member) end end,
        24)

    page.refresh = function()
        local guild = GL:Guild()
        local rows, open, handled = {}, 0, 0
        if guild then
            local ok, items = pcall(function() return GL.TodoItems and GL:TodoItems(guild, GL:Now()) or {} end)
            if ok and type(items) == "table" then
                for _, item in ipairs(items) do
                    if item.handled then handled = handled + 1 else open = open + 1 end
                    if todoShowHandled or not item.handled then rows[#rows + 1] = { item = item, guild = guild } end
                end
            end
        end
        page.list.SetRows(rows)
        page.showHandled:SetChecked(todoShowHandled)
        showEmpty(page, #rows == 0 and (open + handled == 0 and "Nothing needs an officer right now." or "Everything is handled. Tick \"Show handled\" to see what was done.") or nil)
        setText(page.count, plural(open, "open item") .. (handled > 0 and (", " .. handled .. " handled") or ""))
    end
end

-- Overview page ---------------------------------------------------------------------------------------------------------
-- A launchpad: five big numbers across the top, then "last 30 days", "needs attention", "coming up" on the left
-- and class / level bars plus the sharing status on the right. Every number and line opens the page behind it.
-- A class bar narrows the Levels panel to that class (with its leader); a level bar opens the member list for that
-- range, highest level first.
local function buildOverviewPage()
    local page = createPage("overview")
    page.body:Hide()
    local inset = frame.Inset
    local PAD, GAP = 12, 8
    local innerWidth = WINDOW_WIDTH - 15 - PAD * 2      -- inset spans x 9 .. width-6
    local tileWidth = math.floor((innerWidth - GAP * 4) / 5)
    local tileHeight = 58

    -- Row of big numbers.
    page.tiles = {}
    local tileSpecs = {
        { key = "members", caption = "Members", accent = ACCENT.gold, go = function() goMembers("all") end, hint = "Everyone in the guild. Click to open the member list.", icon = ICONS.members },
        { key = "online", caption = "Online now", accent = ACCENT.green, go = function() goMembers("online") end, hint = "Click to list who is online.", icon = ICONS.online },
        { key = "dated", caption = "Join dates known", accent = ACCENT.blue, go = function() goMembers("nodate") end, hint = "Click to list members whose join date is still missing.", icon = ICONS.dated },
        { key = "inactive", caption = "Inactive", accent = ACCENT.orange, go = function() showPage("tools") end, hint = "Offline longer than your removal threshold. Click to review them.", icon = ICONS.inactive },
        { key = "bans", caption = "Ban list", accent = ACCENT.red, go = function() showPage("bans") end, hint = "Click to open the ban list.", icon = ICONS.bans },
    }
    for i, spec in ipairs(tileSpecs) do
        local tile = statTile(page, spec.caption, spec.accent, spec.go, spec.hint, spec.icon)
        tile:SetSize(tileWidth, tileHeight)
        tile:SetPoint("TOPLEFT", inset, "TOPLEFT", PAD + (i - 1) * (tileWidth + GAP), -PAD)
        page.tiles[spec.key] = tile
    end

    -- Since your last visit: the lines themselves (joins, leaves and rank changes first, level-ups on one line).
    local newsHeight = 34 + 4 * 20 + 8
    page.news = section(page, "Since your last visit", PAD, -(PAD + tileHeight + GAP), innerWidth, newsHeight, inset)
    page.news.rows = {}
    for i = 1, 4 do
        local row = linkRow(page.news.body)
        row:SetPoint("TOPLEFT", page.news.body, "TOPLEFT", 0, -(i - 1) * 20)
        row:SetPoint("RIGHT", page.news.body, "RIGHT", 0, 0)
        row:Hide()
        page.news.rows[i] = row
    end
    page.news.none = page.news.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    page.news.none:SetPoint("TOPLEFT", page.news.body, "TOPLEFT", 4, -4)
    page.news.none:SetPoint("RIGHT", page.news.body, "RIGHT", -4, 0)
    page.news.none:SetJustifyH("LEFT")

    local columnTop = -(PAD + tileHeight + GAP + newsHeight + GAP)
    local leftWidth = math.floor(innerWidth * 0.5) - GAP / 2
    local rightX = PAD + leftWidth + GAP
    local rightWidth = innerWidth - leftWidth - GAP
    local bottom = -(WINDOW_HEIGHT + TOOLBAR_TOP - TOOLBAR_HEIGHT - 6 - PAD)   -- lowest y inside the inset

    -- Left column: last 30 days (four small numbers), needs attention, coming up.
    local recentHeight = 96
    page.recent = section(page, "Last 30 days", PAD, columnTop, leftWidth, recentHeight, inset)
    page.recent.tiles = {}
    local miniWidth = math.floor((leftWidth - 20 - GAP * 3) / 4)
    local miniSpecs = {
        { key = "joins", caption = "Joined", accent = ACCENT.green, kinds = { join = true, rejoin = true }, icon = ICONS.join },
        { key = "leaves", caption = "Left", accent = ACCENT.red, kinds = { leave = true, kick = true }, icon = ICONS.leave },
        { key = "promotions", caption = "Promoted", accent = ACCENT.gold, kinds = { promote = true, demote = true }, icon = ICONS.promote },
        { key = "levels", caption = "Level-ups", accent = ACCENT.blue, kinds = { level = true }, icon = ICONS.level },
    }
    for i, spec in ipairs(miniSpecs) do
        local tile = statTile(page.recent.body, spec.caption, spec.accent, function() goLog(spec.kinds) end, "Click to see these events in the log.", spec.icon)
        tile:SetSize(miniWidth, 50)
        tile.icon:SetSize(16, 16)
        tile.icon:ClearAllPoints()
        tile.icon:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -6, -6)
        tile:SetPoint("TOPLEFT", page.recent.body, "TOPLEFT", (i - 1) * (miniWidth + GAP), 0)
        tile.number:SetFontObject(GameFontNormalLarge)
        tile.number:SetTextColor(1, 1, 1)
        tile.number:ClearAllPoints()
        tile.number:SetPoint("TOPLEFT", tile, "TOPLEFT", 8, -6)
        tile.caption:ClearAllPoints()
        tile.caption:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 8, 6)
        page.recent.tiles[spec.key] = tile
    end

    local attentionTop = columnTop - recentHeight - GAP
    local attentionHeight = 34 + 6 * 20 + 8
    page.attention = section(page, "Needs attention", PAD, attentionTop, leftWidth, attentionHeight, inset)
    page.attention.rows = {}
    for i = 1, 6 do
        local row = linkRow(page.attention.body)
        row:SetPoint("TOPLEFT", page.attention.body, "TOPLEFT", 0, -(i - 1) * 20)
        row:SetPoint("RIGHT", page.attention.body, "RIGHT", 0, 0)
        row:Hide()
        page.attention.rows[i] = row
    end
    page.attention.none = page.attention.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    page.attention.none:SetPoint("TOPLEFT", page.attention.body, "TOPLEFT", 4, -4)
    page.attention.none:SetText("Everything is in order.")

    local upcomingTop = attentionTop - attentionHeight - GAP
    page.upcoming = section(page, "Coming up", PAD, upcomingTop, leftWidth, -bottom - (-upcomingTop), inset)
    page.upcoming.rows = {}
    for i = 1, 4 do
        local row = linkRow(page.upcoming.body)
        row:SetPoint("TOPLEFT", page.upcoming.body, "TOPLEFT", 0, -(i - 1) * 20)
        row:SetPoint("RIGHT", page.upcoming.body, "RIGHT", 0, 0)
        row:Hide()
        page.upcoming.rows[i] = row
    end
    page.upcoming.none = page.upcoming.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    page.upcoming.none:SetPoint("TOPLEFT", page.upcoming.body, "TOPLEFT", 4, -4)
    page.upcoming.none:SetPoint("RIGHT", page.upcoming.body, "RIGHT", -4, 0)
    page.upcoming.none:SetJustifyH("LEFT")
    page.upcoming.none:SetText("No join anniversaries or birthdays in the next 30 days. Birthdays are set on a member's card.")

    -- Right column: classes, levels, sharing.
    local classesHeight = 34 + 9 * 14 + 8
    page.classes = section(page, "Classes", rightX, columnTop, rightWidth, classesHeight, inset)
    page.classes.bars = {}
    for i = 1, 12 do
        local bar = barRow(page.classes.body, 64)
        bar:SetPoint("TOPLEFT", page.classes.body, "TOPLEFT", 0, -(i - 1) * 14)
        bar:SetPoint("RIGHT", page.classes.body, "RIGHT", 0, 0)
        bar:Hide()
        page.classes.bars[i] = bar
    end

    local levelsTop = columnTop - classesHeight - GAP
    local levelsHeight = 34 + 6 * 14 + 8
    page.levels = section(page, "Levels", rightX, levelsTop, rightWidth, levelsHeight, inset)
    page.levels.bars = {}
    for i = 1, 6 do
        local bar = barRow(page.levels.body, 64)
        bar:SetPoint("TOPLEFT", page.levels.body, "TOPLEFT", 0, -(i - 1) * 14)
        bar:SetPoint("RIGHT", page.levels.body, "RIGHT", 0, 0)
        page.levels.bars[i] = bar
    end
    -- "all classes" beside the title while one class is picked on the class bars.
    local clear = CreateFrame("Button", nil, page.levels)
    clear:SetSize(64, 16)
    clear:SetPoint("LEFT", page.levels.title, "RIGHT", 8, 0)
    clear.text = clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clear.text:SetPoint("LEFT", clear, "LEFT", 0, 0)
    clear.text:SetText("all classes")
    clear.text:SetTextColor(0.62, 0.62, 0.62)
    clear:SetScript("OnClick", function() overviewClass = nil GL:RefreshWindow() end)
    clear:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) tooltipLines(self, { { "Every class" }, { "Shows the levels of the whole guild again.", 0.62, 0.62, 0.62 } }) end)
    clear:SetScript("OnLeave", function(self) self.text:SetTextColor(0.62, 0.62, 0.62) if GameTooltip then GameTooltip:Hide() end end)
    clear:Hide()
    page.levels.clear = clear

    local sharingTop = levelsTop - levelsHeight - GAP
    page.sharing = section(page, "Sharing", rightX, sharingTop, rightWidth, -bottom - (-sharingTop), inset)
    page.sharing.text = page.sharing.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.sharing.text:SetPoint("TOPLEFT", page.sharing.body, "TOPLEFT", 0, -2)
    page.sharing.text:SetPoint("RIGHT", page.sharing.body, "RIGHT", 0, 0)
    page.sharing.text:SetJustifyH("LEFT")
    page.sharing.text:SetJustifyV("TOP")
    page.sharing.text:SetSpacing(3)
    page.sharing.ask = makeButton(page.sharing, "Ask officers", 100, function()
        if GL.Sync and GL.Sync.Hello then GL.Sync:Hello(true) GL:Print("asked other Tabard users in the guild for their data.") end
    end)
    page.sharing.ask:SetPoint("TOPRIGHT", page.sharing, "TOPRIGHT", -8, -5)
    page.sharing.ask:SetSize(96, 20)
    explain(page.sharing.ask, "Asks every other Tabard user in the guild to send their join dates, alts, bans and notes.")

    page.refresh = function()
        local guild = GL:Guild()
        if not guild then
            for _, tile in pairs(page.tiles) do tile.Set("-") end
            page.sharing.text:SetText(GREY .. "You are not in a guild.|r")
            return
        end
        local now = GL:Now()
        local kickDays = GL.settings.kickDays or 60
        local kickAfter = kickDays * 86400
        local members, online, dated, alts, mains, inactive, levelSum, maxLevel, ungrouped = 0, 0, 0, 0, 0, 0, 0, 0, 0
        local classStats, brackets = {}, { 0, 0, 0, 0, 0, 0 }   -- classStats[classFile] = { count, sum, brackets, members }
        local bannedInGuild = 0
        for name, member in pairs(guild.members) do
            members = members + 1
            if member.online then online = online + 1 end
            if member.joined then dated = dated + 1 end
            if GL:IsAlt(guild, member) then alts = alts + 1 elseif GL:IsMain(guild, member) then mains = mains + 1 else ungrouped = ungrouped + 1 end
            if not member.online and member.lastOnline and (now - member.lastOnline) >= kickAfter then inactive = inactive + 1 end
            if GL:BanFor(guild, member) then bannedInGuild = bannedInGuild + 1 end
            local level = member.level or 0
            levelSum = levelSum + level
            if level > maxLevel then maxLevel = level end
            local bracket = math.max(1, math.min(6, math.floor((level - 1) / 10) + 1))
            brackets[bracket] = brackets[bracket] + 1
            if member.class then
                local stat = classStats[member.class]
                if not stat then
                    stat = { count = 0, sum = 0, brackets = { 0, 0, 0, 0, 0, 0 }, members = {} }
                    classStats[member.class] = stat
                end
                stat.count = stat.count + 1
                stat.sum = stat.sum + level
                stat.brackets[bracket] = stat.brackets[bracket] + 1
                stat.members[#stat.members + 1] = member
            end
        end
        local joins, leaves, levelsUp, promotions = 0, 0, 0, 0
        for i = #guild.events, 1, -1 do
            local event = guild.events[i]
            if now - event.t > 30 * 86400 then break end
            if event.k == "join" or event.k == "rejoin" then joins = joins + 1
            elseif event.k == "leave" or event.k == "kick" then leaves = leaves + 1
            elseif event.k == "level" then levelsUp = levelsUp + 1
            elseif event.k == "promote" or event.k == "demote" then promotions = promotions + 1 end
        end
        local activeBans = 0
        for _, ban in pairs(guild.bans) do if not ban.lifted then activeBans = activeBans + 1 end end

        page.tiles.members.Set(members, "in " .. plain(guild.name or ""))
        page.tiles.online.Set(online, members > 0 and (math.floor(online * 100 / members + 0.5) .. "%") or "")
        page.tiles.dated.Set(members > 0 and (math.floor(dated * 100 / members + 0.5) .. "%") or "0%", dated .. " of " .. members)
        page.tiles.inactive.Set(inactive, kickDays .. "+ days")
        page.tiles.inactive.caption:SetText("Inactive")
        page.tiles.bans.Set(activeBans, bannedInGuild > 0 and (RED .. bannedInGuild .. " in guild|r") or "")

        page.recent.tiles.joins.Set(joins)
        page.recent.tiles.leaves.Set(leaves)
        page.recent.tiles.promotions.Set(promotions)
        page.recent.tiles.levels.Set(levelsUp)
        page.recent.aside:SetText("seen while online")

        -- Since your last visit: the lines themselves.
        local okNews, news = pcall(function() return GL.WhatsNew and GL:WhatsNew(guild) or nil end)
        if not okNews then news = nil end
        local newsRows = page.news.rows
        local sinceText = type(guild.visitSince) == "number" and ("since " .. GL:Ago(guild.visitSince)) or ""
        if type(news) ~= "table" then
            for _, row in ipairs(newsRows) do row:Hide() end
            page.news.none:SetText("After your next login this lists what changed while you were away.")
            page.news.none:Show()
            page.news.aside:SetText("")
        elseif #news == 0 then
            for _, row in ipairs(newsRows) do row:Hide() end
            page.news.none:SetText("Nothing changed while you were away.")
            page.news.none:Show()
            page.news.aside:SetText(sinceText)
        else
            page.news.none:Hide()
            local limit = #news > #newsRows and (#newsRows - 1) or #news
            for i, row in ipairs(newsRows) do
                local item = news[i]
                if i <= limit and item then
                    local go = item.member and function() openCard(item.member) end or function() goLog(item.kinds) end
                    local NEWS_ICONS = { green = ICONS.join, red = ICONS.leave, gold = ICONS.promote, blue = ICONS.level, purple = ICONS.note, grey = ICONS.other }
                    row.Set(item.text, ACCENT[item.accent or "grey"] or ACCENT.grey, go, item.member and "Click to open the member card." or "Click to see these in the log.", item.icon or NEWS_ICONS[item.accent or "grey"])
                elseif i == limit + 1 and #news > #newsRows then
                    row.Set(GREY .. "and " .. (#news - limit) .. " more in the log|r", ACCENT.grey, function() goLog(nil) end, "The log starts with everything since your last visit.", ICONS.other)
                else
                    row:Hide()
                end
            end
            local okAway, away = pcall(function() return GL:AwayText(GL:SinceLastVisit(guild)) end)
            page.news.aside:SetText((okAway and type(away) == "string" and away ~= "") and (away .. ", " .. sinceText) or sinceText)
        end

        -- Needs attention: one line per thing an officer can act on, most urgent first.
        local items = {}
        local todoOpen, todoRequests, todoAlts = 0, 0, 0
        local okTodo, todo = pcall(function() return GL.TodoItems and GL:TodoItems(guild, now) or {} end)
        if okTodo and type(todo) == "table" then
            for _, item in ipairs(todo) do
                if not item.handled then
                    todoOpen = todoOpen + 1
                    if item.kind == "request" then todoRequests = todoRequests + 1 elseif item.kind == "altpair" then todoAlts = todoAlts + 1 end
                end
            end
        end
        if todoOpen > 0 then
            items[#items + 1] = { text = plural(todoOpen, "item needs", "items need") .. " an officer" .. (todoRequests > 0 and (", " .. plural(todoRequests, "whispered request") .. " waiting") or "") .. (todoAlts > 0 and (", " .. plural(todoAlts, "likely alt") .. " to confirm") or ""),
                accent = todoRequests > 0 and ACCENT.purple or ACCENT.red, go = function() showPage("todo") end, hint = "Trials due, leaves that ended, banned characters, requests, promotions. Click to open the to-do list.", icon = todoRequests > 0 and ICONS.request or ICONS.todo }
        elseif guild.partialScan then
            items[#items + 1] = { text = "The last roster read was incomplete; leaves are not recorded until a full read.", accent = ACCENT.red,
                go = function() GL:RequestScan(true) GL:Print("scanning the roster...") end, hint = "Click to read the roster again.", icon = ICONS.roster }
        end
        if bannedInGuild > 0 and not okTodo then
            items[#items + 1] = { text = plural(bannedInGuild, "banned character is", "banned characters are") .. " in the guild right now", accent = ACCENT.red, go = function() goMembers("banned") end, hint = "Click to list them.", icon = ICONS.bans }
        end
        if GL.Newcomers then
            local newcomers = GL:Newcomers(guild, now)
            local online, quiet = 0, 0
            for _, row in ipairs(newcomers) do
                if row.member.online then online = online + 1 end
                if row.needsAttention then quiet = quiet + 1 end
            end
            if #newcomers > 0 then
                items[#items + 1] = { text = plural(#newcomers, "member is", "members are") .. " in their first week" .. (online > 0 and (", " .. online .. " online now") or "") .. (quiet > 0 and (", " .. quiet .. " nobody has talked to") or ""),
                    accent = quiet > 0 and ACCENT.orange or ACCENT.teal, go = function() goMembers("new") end,
                    hint = "Members in their first seven days. Click to list them; the quiet ones could use a hello.", icon = ICONS.members }
            end
        end
        local kicks = GL:KickCandidates(guild, now)
        if #kicks > 0 then
            items[#items + 1] = { text = plural(#kicks, "member", "members") .. " could be removed (" .. kickDays .. "+ days away, alts included)", accent = ACCENT.orange, go = function() showPage("tools") end, hint = "Click to review them on the Tools page.", icon = ICONS.kicks }
        end
        local okAudit, audit = pcall(function() return GL.AltAudit and GL:AltAudit(guild) or {} end)
        if okAudit and type(audit) == "table" and #audit > 0 then
            items[#items + 1] = { text = plural(#audit, "alt is", "alts are") .. " ranked above their main or have no main left", accent = ACCENT.purple, go = function() goMembers("altproblem") end, hint = "Click to list them.", icon = ICONS.alt }
        end
        if members - dated > 0 then
            items[#items + 1] = { text = plural(members - dated, "member has", "members have") .. " no join date", accent = ACCENT.blue, go = function() goMembers("nodate") end, hint = "Open a member's card and press Set next to Joined. Other officers' dates arrive through sharing.", icon = ICONS.joindate }
        end
        if ungrouped > 0 then
            items[#items + 1] = { text = plural(ungrouped, "member is", "members are") .. " not sorted into main or alt", accent = ACCENT.purple, go = function() goMembers("ungrouped") end, hint = "Right-click a member in the list to link them, or confirm the likely alts on the To-do tab. Notes like \"alt of Zev\" are read automatically, and everyone with Tabard groups their own characters.", icon = ICONS.alt }
        end
        for i, row in ipairs(page.attention.rows) do
            local item = items[i]
            if item then row.Set(item.text, item.accent, item.go, item.hint, item.icon) else row:Hide() end
        end
        if #items == 0 then page.attention.none:Show() else page.attention.none:Hide() end
        page.attention.aside:SetText(#items > 0 and plural(#items, "item") or "")

        -- Coming up.
        local upcoming = GL:Upcoming(guild, 30, now)
        for i, row in ipairs(page.upcoming.rows) do
            local item = upcoming[i]
            if item then
                local when = item.days == 0 and "today" or item.days == 1 and "tomorrow" or ("in " .. item.days .. " days")
                local what = item.kind == "anniversary" and (plural(item.years, "year") .. " in the guild") or "birthday"
                row.Set(GL:ColoredName(item.member) .. GREY .. "  " .. what .. ", " .. when .. "|r", item.kind == "anniversary" and ACCENT.gold or ACCENT.teal,
                    function() openCard(item.member) end, "Click to open the member card.", item.kind == "anniversary" and ICONS.anniversary or ICONS.birthday)
            else
                row:Hide()
            end
        end
        if #upcoming == 0 then page.upcoming.none:Show() else page.upcoming.none:Hide() end
        page.upcoming.aside:SetText(#upcoming > #page.upcoming.rows and ("first " .. #page.upcoming.rows .. " of " .. #upcoming) or "next 30 days")

        -- Classes. A click picks that class for the Levels panel below; a second click shows every class again.
        local function byLevel(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return string.lower(a.name or "") < string.lower(b.name or "")
        end
        local classList = {}
        for classFile, stat in pairs(classStats) do
            table.sort(stat.members, byLevel)
            classList[#classList + 1] = { classFile = classFile, count = stat.count, stat = stat }
        end
        if overviewClass and not classStats[overviewClass] then overviewClass = nil end   -- the last one left the guild
        table.sort(classList, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.classFile < b.classFile end)
        local most = classList[1] and classList[1].count or 1
        for i, bar in ipairs(page.classes.bars) do
            local item = classList[i]
            if item then
                local classFile, stat = item.classFile, item.stat
                local r, g, b = GL:ClassColor(classFile)
                local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
                bar.SetIcon(coords and CLASS_CIRCLES or nil, coords)
                bar.Set(GL:ClassName(classFile), item.count, item.count / most, r, g, b)
                local selected = nil
                if overviewClass then selected = overviewClass == classFile end
                bar.SetSelected(selected)
                bar.SetClick(function()
                    overviewClass = (overviewClass ~= classFile) and classFile or nil
                    GL:RefreshWindow()
                end, function()
                    local lines = { { GL:ClassName(classFile), r, g, b },
                        { item.count .. " in the guild, average level " .. math.floor(stat.sum / math.max(1, stat.count) + 0.5), 1, 1, 1 } }
                    for rank = 1, math.min(5, #stat.members) do
                        local member = stat.members[rank]
                        lines[#lines + 1] = { rank .. ". " .. plain(member.name) .. "  " .. ((member.level or 0) > 0 and tostring(member.level) or "?"), 0.85, 0.85, 0.85 }
                    end
                    lines[#lines + 1] = { overviewClass == classFile and "Click again to show every class." or "Click to see their levels below.", 0.62, 0.62, 0.62 }
                    return lines
                end)
            else
                bar:Hide()
            end
        end
        page.classes.aside:SetText(#classList > 0 and (#classList .. " played") or "")

        -- Levels: the whole guild, or only the class picked above. Each bar opens the member list for its range.
        local names = { "1-10", "11-20", "21-30", "31-40", "41-50", "51-60" }
        local ranges = { { nil, 10 }, { 11, 20 }, { 21, 30 }, { 31, 40 }, { 41, 50 }, { 51, nil } }
        local picked = overviewClass and classStats[overviewClass]
        local counts = picked and picked.brackets or brackets
        local pickedClass = picked and overviewClass or nil
        local cr, cg, cb, hex = GL:ClassColor(pickedClass)
        local biggest = 1
        for i = 1, 6 do if counts[i] > biggest then biggest = counts[i] end end
        for i, bar in ipairs(page.levels.bars) do
            local count = counts[i]
            if picked then
                bar.Set(names[i], count, count / biggest, cr, cg, cb)
            else
                local shade = 0.45 + 0.55 * (i - 1) / 5
                bar.Set(names[i], count, count / biggest, 0.4 + 0.2 * (1 - shade), 0.55 + 0.25 * shade, 1)
            end
            local lo, hi = ranges[i][1], ranges[i][2]
            bar.SetClick(function() goMembersScope({ class = pickedClass, lo = lo, hi = hi }) end, function()
                local who = pickedClass and (GL:ClassName(pickedClass) .. ", level ") or "Level "
                return { { who .. names[i] }, { plural(count, "character") .. ". Click to list them, highest level first.", 0.62, 0.62, 0.62 } }
            end)
        end
        if picked then
            page.levels.title:SetText("|c" .. hex .. GL:ClassName(pickedClass) .. "|r levels")
            page.levels.clear:Show()
            -- The leader by first name, with how many more share that level.
            local top = picked.members[1]
            local tied = 0
            for i = 2, #picked.members do
                if (picked.members[i].level or 0) == (top.level or 0) then tied = tied + 1 else break end
            end
            local first = string.match(plain(top.name), "^(%S+)") or plain(top.name)
            page.levels.aside:SetText("highest " .. tostring(top.level or 0) .. ": " .. first .. (tied > 0 and (" +" .. tied) or ""))
        else
            page.levels.title:SetText("Levels")
            page.levels.clear:Hide()
            page.levels.aside:SetText(members > 0 and ("average " .. math.floor(levelSum / members + 0.5) .. ", highest " .. maxLevel) or "")
        end

        -- Sharing.
        local lines = {}
        local peers = {}
        local okPeers, list = pcall(function() return GL.Sync and GL.Sync.Peers and GL.Sync:Peers(guild) or {} end)
        if okPeers and type(list) == "table" then peers = list end
        if GL.newerVersion then
            lines[#lines + 1] = "|cffffd100Tabard " .. tostring(GL.newerVersion) .. " is available (you have " .. tostring(GL.version) .. "). Update it in the CurseForge app.|r"
        end
        if #peers == 0 then
            lines[#lines + 1] = GREY .. "Nobody else runs Tabard yet. Officers who install it share join dates, alts, bans and notes with you automatically.|r"
        else
            local shown = {}
            for i, peer in ipairs(peers) do
                if i <= 4 then shown[#shown + 1] = GL:ColoredName(peer.member, peer.name) .. GREY .. " (" .. GL:Ago(peer.t, now) .. ")|r" end
            end
            lines[#lines + 1] = plural(#peers, "officer") .. " sharing with you: " .. table.concat(shown, ", ") .. (#peers > 4 and (GREY .. " and " .. (#peers - 4) .. " more|r") or "")
        end
        local okStatus, status = pcall(function() return GL.Sync and GL.Sync.Status and GL.Sync:Status() end)
        if okStatus and type(status) == "string" and status ~= "" then lines[#lines + 1] = GREY .. "Sync: " .. status .. "|r" end
        lines[#lines + 1] = GREY .. "Ledger started " .. GL:FormatDate(guild.seeded or guild.created) .. ", " .. plural(#guild.events, "event") .. ", " .. plural(guild.scans or 0, "roster read") .. ".|r"
        page.sharing.text:SetText(table.concat(lines, "\n"))
        page.sharing.ask:SetEnabled(GL.settings.sync ~= false)
    end
end

-- Settings page -----------------------------------------------------------------------------------------
-- Two columns inside a scroll frame (the page is taller than the window): announcements, welcome whispers and
-- guild chat shoutouts on the left; sharing, thresholds and data on the right. Every option the slash commands
-- offer is here too.
local WELCOME_DEFAULTS = { enabled = false, delay = 8, mode = "click", minRank = 1 }
local SHOUT_DEFAULTS = { enabled = false, levels = "10 20 30 40 50 60", every = false, promote = false, back = false, delay = 10, mode = "click", minRank = 0, nameStyle = "firstlower" }
local NAME_STYLES = { firstlower = "first name, lowercase (zev)", first = "first name (Zev)", full = "full name (Zev Zev)", fulllower = "full name, lowercase (zev zev)" }
local LOGIN_LABELS = { card = "Show a small since-your-last-visit card", always = "Open the window", todo = "Open it when the to-do list has items", never = "Stay closed" }
local LOGIN_DEFAULT = "card"
local NOTE_DATE_LABELS = { none = "Nothing", public = "The public note", officer = "The officer note" }

local function welcomeSettings()
    if type(GL.settings.welcome) ~= "table" then GL.settings.welcome = {} end
    local s = GL.settings.welcome
    for key, value in pairs(WELCOME_DEFAULTS) do if s[key] == nil then s[key] = value end end
    return s
end

local function shoutSettings()
    if type(GL.settings.shout) ~= "table" then GL.settings.shout = {} end
    return GL.settings.shout
end

local function shoutValue(key)
    local value = shoutSettings()[key]
    if value == nil then return SHOUT_DEFAULTS[key] end
    return value
end

-- Lines editor -------------------------------------------------------------------------------------------
-- A small window listing the welcome lines or one shoutout pool, with Remove on each row and an Add box.
-- Editing a stock list first copies it into your own lines, so the stock set is always one click away.
local linesWindow
local SHOUT_POOLS = { "10", "20", "30", "40", "50", "60", "any", "promote", "back" }
local SHOUT_POOL_LABELS = { any = "any level", promote = "promotions", back = "back from a break" }

local function linesSource()
    if not linesWindow then return nil end
    if linesWindow.kind == "welcome" then
        if not (GL.Welcome and GL.Welcome.Lines) then return nil end
        local list, custom = GL.Welcome:Lines()
        return list, custom, function(newList) GL.Welcome:SetLines(newList) end
    end
    if not (GL.Shout and GL.Shout.Pool) then return nil end
    local list, custom = GL.Shout:Pool(linesWindow.pool)
    return list, custom, function(newList) GL.Shout:SetPool(linesWindow.pool, newList) end
end

local function copyList(list)
    local out = {}
    for i, line in ipairs(list or {}) do out[i] = line end
    return out
end

local function refreshLinesWindow()
    if not (linesWindow and linesWindow:IsShown()) then return end
    local list, custom = linesSource()
    list = list or {}
    local rows = {}
    for i, line in ipairs(list) do rows[#rows + 1] = { n = i, text = line } end
    linesWindow.list.SetRows(rows)
    local what = linesWindow.kind == "welcome" and "Welcome lines" or ("Shoutout lines: " .. (SHOUT_POOL_LABELS[linesWindow.pool] or ("level " .. linesWindow.pool)))
    if linesWindow.SetTitle then pcall(linesWindow.SetTitle, linesWindow, what) end
    linesWindow.hint:SetText(linesWindow.kind == "welcome" and "{name} {level} {class} and {me} are filled in. Keep lines under 230 characters."
        or "Fills in {name} {level} {rank} {a rank} {away} {me}; {NAME}, {A RANK} for caps")
    linesWindow.count:SetText(plural(#list, "line") .. (custom and ", your own" or ", stock"))
    linesWindow.reset:SetEnabled(custom and true or false)
    if linesWindow.pools then linesWindow.pools:SetLabel(SHOUT_POOL_LABELS[linesWindow.pool] or ("level " .. linesWindow.pool)) end
    if linesWindow.pools then if linesWindow.kind == "shout" then linesWindow.pools:Show() else linesWindow.pools:Hide() end end
end

local function buildLinesWindow()
    local inset
    linesWindow, inset = styleWindow(nil, "TabardUILinesFrame", "Lines", 560, 440)
    linesWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    linesWindow:SetScript("OnDragStart", linesWindow.StartMoving)
    linesWindow:SetScript("OnDragStop", linesWindow.StopMovingOrSizing)
    tinsert(UISpecialFrames, "TabardUILinesFrame")
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", linesWindow, "TOPLEFT", 9, -58)
    inset:SetPoint("BOTTOMRIGHT", linesWindow, "BOTTOMRIGHT", -6, 40)
    setPortraitIcon(linesWindow, "Interface\\Icons\\INV_Misc_Note_01")
    linesWindow.hint = linesWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    linesWindow.hint:SetPoint("TOPLEFT", linesWindow, "TOPLEFT", 70, -32)
    linesWindow.hint:SetPoint("RIGHT", linesWindow, "RIGHT", -16, 0)
    linesWindow.hint:SetJustifyH("LEFT")
    linesWindow.hint:SetTextColor(0.62, 0.62, 0.62)
    linesWindow.hint:SetText("{name} {level} {class} and {me} are filled in. Keep lines under 230 characters.")
    linesWindow.count = linesWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    linesWindow.count:SetPoint("TOPRIGHT", linesWindow, "TOPRIGHT", -16, -44)
    linesWindow.count:SetTextColor(0.62, 0.62, 0.62)
    local poolItems = {}
    for _, key in ipairs(SHOUT_POOLS) do
        poolItems[#poolItems + 1] = { text = SHOUT_POOL_LABELS[key] or ("level " .. key), isChecked = function() return linesWindow.pool == key end,
            toggle = function() linesWindow.pool = key refreshLinesWindow() end }
    end
    linesWindow.pools = createFilter(linesWindow, "level 60", poolItems, 150)
    linesWindow.pools:SetPoint("TOPLEFT", linesWindow, "TOPLEFT", 70, -44)

    linesWindow.list = createList(inset,
        function(row)
            row.n = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.n:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.n:SetWidth(24)
            row.n:SetJustifyH("RIGHT")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.n, "RIGHT", 8, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -76, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.remove = makeButton(row, "Remove", 64, function()
                local data = row.data
                if not data then return end
                local list, custom, set = linesSource()
                if not list then return end
                local mine = copyList(list)
                table.remove(mine, data.n)
                set(mine)
                refreshLinesWindow()
            end)
            row.remove:SetSize(64, 20)
            row.remove:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row:SetScript("OnEnter", function(self) if self.data then tooltipLines(self, { { "Line " .. self.data.n }, { self.data.text, 1, 1, 1 } }) end end)
            row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end,
        function(row, data)
            row.n:SetText(tostring(data.n) .. ".")
            setText(row.text, data.text)
        end, nil, 22)

    linesWindow.box = makeEditBox(linesWindow, 300, false)
    linesWindow.box:SetPoint("BOTTOMLEFT", linesWindow, "BOTTOMLEFT", 20, 12)
    linesWindow.box:SetPoint("RIGHT", linesWindow, "RIGHT", -190, 0)
    linesWindow.box:SetMaxLetters(230)
    linesWindow.add = makeButton(linesWindow, "Add", 60, function()
        local text = strtrim(linesWindow.box:GetText() or "")
        if text == "" then return end
        local list, custom, set = linesSource()
        if not list then return end
        local mine = copyList(list)
        mine[#mine + 1] = text
        set(mine)
        linesWindow.box:SetText("")
        linesWindow.box:ClearFocus()
        refreshLinesWindow()
    end)
    linesWindow.add:SetPoint("LEFT", linesWindow.box, "RIGHT", 6, 0)
    linesWindow.box:SetScript("OnEnterPressed", function() linesWindow.add:Click() end)
    linesWindow.reset = makeButton(linesWindow, "Back to stock", 100, function()
        confirm("Drop your own lines here and use the stock ones again?", function()
            local list, custom, set = linesSource()
            if set then set(nil) end
            refreshLinesWindow()
        end)
    end)
    linesWindow.reset:SetPoint("LEFT", linesWindow.add, "RIGHT", 6, 0)
    explain(linesWindow.reset, "Removes your custom lines for this list and restores the stock ones.")
end

local function openLinesEditor(kind, pool)
    if not linesWindow then
        local ok, err = pcall(buildLinesWindow)
        if not ok then GL:Print("the lines editor could not be built: " .. tostring(err)) return end
    end
    linesWindow.kind, linesWindow.pool = kind, pool or "60"
    linesWindow:Show()
    refreshLinesWindow()
end

local function buildSettingsPage()
    local page = createPage("settings")
    page.body:Hide()
    local inset = frame.Inset
    local PAD, GAP = 12, 8

    -- Scrolling content.
    -- The modern scroll frame carries the thin scroll bar; the older template is the fallback.
    local scroll, isModern = newFrame("ScrollFrame", "TabardUISettingsScroll", page, "ScrollFrameTemplate")
    if not (isModern and scroll.ScrollBar) then
        scroll:Hide()
        scroll = newFrame("ScrollFrame", "TabardUISettingsScrollClassic", page, "UIPanelScrollFrameTemplate")
    end
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -24, 2)
    local content = CreateFrame("Frame", nil, scroll)
    local innerWidth = WINDOW_WIDTH - 15 - 24 - PAD * 2
    content:SetWidth(innerWidth + PAD * 2)
    scroll:SetScrollChild(content)
    page.scroll, page.content = scroll, content
    local leftWidth = math.floor(innerWidth * 0.5) - GAP / 2
    local rightX = PAD + leftWidth + GAP
    local rightWidth = innerWidth - leftWidth - GAP

    -- Left: chat announcements, three columns of check boxes.
    local LABELS = { join = "joins", rejoin = "rejoins", leave = "leaves", kick = "is removed", promote = "is promoted", demote = "is demoted",
        level = "levels up", note = "has a note changed", onote = "has an officer note changed", custom = "has a Tabard note changed", rename = "changes name",
        rank = "has a rank renamed", back = "returns after a break", alt = "is linked as an alt", main = "is made a main", ban = "is banned", unban = "has a ban lifted",
        nick = "has a nickname set" }
    local perColumn = 10
    local announceHeight = 34 + perColumn * 24 + 10
    page.announceBox = section(content, "Announce in chat when someone...", PAD, -PAD, leftWidth, announceHeight)
    page.announce = {}
    local column, y = 0, 0
    local columnWidth = math.floor((leftWidth - 20) / 2)
    for _, kind in ipairs(GL.KIND_ORDER) do
        if LABELS[kind] then
            local box = makeCheck(page.announceBox.body, LABELS[kind], function(checked) GL.settings.announce[kind] = checked end)
            box:SetPoint("TOPLEFT", page.announceBox.body, "TOPLEFT", column * columnWidth - 4, y + 2)
            box.label:SetWidth(columnWidth - 26)
            box.label:SetJustifyH("LEFT")
            box.label:SetWordWrap(false)
            page.announce[kind] = box
            y = y - 24
            if y <= -24 * perColumn and column < 1 then column, y = column + 1, 0 end
        end
    end
    -- Logins are not recorded events, so this box sits outside the kinds list.
    page.announce.online = makeCheck(page.announceBox.body, "comes online", function(checked) GL.settings.announce.online = checked end)
    page.announce.online:SetPoint("TOPLEFT", page.announceBox.body, "TOPLEFT", column * columnWidth - 4, y + 2)
    page.announce.online.label:SetWidth(columnWidth - 26)
    page.announce.online.label:SetJustifyH("LEFT")
    page.announce.online.label:SetWordWrap(false)

    -- Left, middle: welcome whispers.
    local welcomeTop = -PAD - announceHeight - GAP
    local welcomeHeight = 34 + 178
    page.welcomeBox = section(content, "Welcome whispers", PAD, welcomeTop, leftWidth, welcomeHeight)
    local wb = page.welcomeBox.body
    page.welcomeHelp = wb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.welcomeHelp:SetPoint("TOPLEFT", wb, "TOPLEFT", 0, 0)
    page.welcomeHelp:SetPoint("RIGHT", wb, "RIGHT", 0, 0)
    page.welcomeHelp:SetJustifyH("LEFT")
    page.welcomeHelp:SetTextColor(0.62, 0.62, 0.62)
    page.welcomeHelp:SetText("New members get a whisper from you, rotating through a list of lines. The game only lets addons whisper on a click, so it goes out on your next click or chat line.")
    page.welcomeOn = makeCheck(wb, "Send welcome whispers", function(checked) welcomeSettings().enabled = checked GL:RefreshWindow() end)
    page.welcomeOn:SetPoint("TOPLEFT", wb, "TOPLEFT", -4, -40)
    page.welcomeAuto = makeCheck(wb, "Try a timed send first, fall back to click mode if the game blocks it", function(checked) welcomeSettings().mode = checked and "auto" or "click" end)
    page.welcomeAuto:SetPoint("TOPLEFT", page.welcomeOn, "BOTTOMLEFT", 0, 0)
    page.welcomeAuto.label:SetWidth(leftWidth - 56)
    page.welcomeAuto.label:SetJustifyH("LEFT")
    page.welcomeDelay = makeEditBox(wb, 40, true)
    page.welcomeDelay:SetPoint("TOPLEFT", page.welcomeAuto, "BOTTOMLEFT", 10, -4)
    page.welcomeDelay:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if value then welcomeSettings().delay = math.max(2, math.min(120, math.floor(value))) end
        GL:RefreshWindow()
    end)
    local delayLabel = wb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    delayLabel:SetPoint("LEFT", page.welcomeDelay, "RIGHT", 8, 0)
    delayLabel:SetText("seconds after the join")
    page.welcomeRank = makeEditBox(wb, 40, true)
    page.welcomeRank:SetPoint("TOPLEFT", page.welcomeDelay, "BOTTOMLEFT", 0, -6)
    page.welcomeRank:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if value then welcomeSettings().minRank = math.max(0, math.floor(value)) end
        GL:RefreshWindow()
    end)
    local rankLabel = wb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rankLabel:SetPoint("LEFT", page.welcomeRank, "RIGHT", 8, 0)
    rankLabel:SetText("lowest rank index that sends them (0 = guild leader)")
    local function welcome(command) if GL.Welcome and GL.Welcome.Command then GL.Welcome:Command(command) else GL:Print("welcome whispers are not loaded.") end end
    page.welcomeTest = makeButton(wb, "Test on me", 80, function() welcome("test") end)
    page.welcomeTest:SetPoint("BOTTOMLEFT", wb, "BOTTOMLEFT", 0, 0)
    explain(page.welcomeTest, "Whispers you the next line in the rotation, so you can see exactly what a new member gets.")
    page.welcomeList = makeButton(wb, "Edit lines", 100, function() openLinesEditor("welcome") end)
    page.welcomeList:SetPoint("LEFT", page.welcomeTest, "RIGHT", 4, 0)
    explain(page.welcomeList, "See, add and remove the lines new members get. Put your Discord link and raid nights in them.")
    page.welcomePreview = makeButton(wb, "Preview next", 100, function() welcome("preview") end)
    page.welcomePreview:SetPoint("LEFT", page.welcomeList, "RIGHT", 4, 0)
    explain(page.welcomePreview, "Prints the next line in your chat window without sending it.")

    -- Left, bottom: guild chat shoutouts (Shout.lua).
    local shoutTop = welcomeTop - welcomeHeight - GAP
    local shoutHeight = 34 + 330
    page.shoutBox = section(content, "Guild chat shoutouts", PAD, shoutTop, leftWidth, shoutHeight)
    local sb = page.shoutBox.body
    local function shout(command) if GL.Shout and GL.Shout.Command then GL.Shout:Command(command) else GL:Print("shoutouts are not loaded.") end end
    page.shoutHelp = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.shoutHelp:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
    page.shoutHelp:SetPoint("RIGHT", sb, "RIGHT", 0, 0)
    page.shoutHelp:SetJustifyH("LEFT")
    page.shoutHelp:SetTextColor(0.62, 0.62, 0.62)
    page.shoutHelp:SetText("A short guild chat line when a member hits a milestone level, with one real fact from the ledger added: how long the last stretch took, their class at 60, or their time in the guild. Goes out on your next click or chat line.")
    page.shoutOn = makeCheck(sb, "Post in guild chat when someone hits a milestone level", function(checked) shoutSettings().enabled = checked GL:RefreshWindow() end)
    page.shoutOn:SetPoint("TOPLEFT", sb, "TOPLEFT", -4, -52)
    page.shoutOn.label:SetWidth(leftWidth - 56)
    page.shoutOn.label:SetJustifyH("LEFT")
    page.shoutLevelsLabel = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.shoutLevelsLabel:SetPoint("TOPLEFT", page.shoutOn, "BOTTOMLEFT", 10, -5)
    page.shoutLevelsLabel:SetText("Levels")
    page.shoutLevels = makeEditBox(sb, 150, false)
    page.shoutLevels:SetPoint("LEFT", page.shoutLevelsLabel, "RIGHT", 8, 0)
    page.shoutLevels:SetScript("OnEditFocusLost", function(self)
        local text = strtrim(self:GetText() or "")
        if text ~= "" and text ~= tostring(shoutValue("levels")) then shout("levels " .. text) end
        GL:RefreshWindow()
    end)
    page.shoutLevels:SetScript("OnEnter", function(self) tooltipLines(self, { { "Milestone levels" }, { "Numbers separated by spaces, for example 10 20 30 40 50 60. Press Enter to save.", 0.62, 0.62, 0.62 } }) end)
    page.shoutLevels:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    page.shoutNameLabel = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.shoutNameLabel:SetPoint("TOPLEFT", page.shoutOn, "BOTTOMLEFT", 10, -33)
    page.shoutNameLabel:SetText("Name as")
    local nameItems = {}
    for _, key in ipairs({ "firstlower", "first", "full", "fulllower" }) do
        nameItems[#nameItems + 1] = { text = NAME_STYLES[key], isChecked = function() return shoutValue("nameStyle") == key end, toggle = function() shoutSettings().nameStyle = key GL:RefreshWindow() end }
    end
    page.shoutName = createFilter(sb, NAME_STYLES.firstlower, nameItems, 200)
    page.shoutName:SetPoint("LEFT", page.shoutNameLabel, "RIGHT", 8, 0)
    explain(page.shoutName, "How the member's name is written in the line. \"Zev Zev\" becomes \"zev\" with the default.")
    page.shoutEvery = makeCheck(sb, "Also post every other level", function(checked) shoutSettings().every = checked end)
    page.shoutEvery:SetPoint("TOPLEFT", page.shoutOn, "BOTTOMLEFT", 0, -58)
    page.shoutPromote = makeCheck(sb, "Post promotions (the game already prints these)", function(checked) shoutSettings().promote = checked end)
    page.shoutPromote:SetPoint("TOPLEFT", page.shoutEvery, "BOTTOMLEFT", 0, 0)
    page.shoutPromote.label:SetWidth(leftWidth - 56)
    page.shoutPromote.label:SetJustifyH("LEFT")
    page.shoutBack = makeCheck(sb, "Post when someone is back after a long break", function(checked) shoutSettings().back = checked end)
    page.shoutBack:SetPoint("TOPLEFT", page.shoutPromote, "BOTTOMLEFT", 0, 0)
    page.shoutBack.label:SetWidth(leftWidth - 56)
    page.shoutBack.label:SetJustifyH("LEFT")
    page.shoutAuto = makeCheck(sb, "Try a timed post first, fall back to click mode if the game blocks it", function(checked) shoutSettings().mode = checked and "auto" or "click" end)
    page.shoutAuto:SetPoint("TOPLEFT", page.shoutBack, "BOTTOMLEFT", 0, 0)
    page.shoutAuto.label:SetWidth(leftWidth - 56)
    page.shoutAuto.label:SetJustifyH("LEFT")
    page.shoutDelay = makeEditBox(sb, 40, true)
    page.shoutDelay:SetPoint("TOPLEFT", page.shoutAuto, "BOTTOMLEFT", 10, -4)
    page.shoutDelay:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if value then shoutSettings().delay = math.max(0, math.min(300, math.floor(value))) end
        GL:RefreshWindow()
    end)
    local shoutDelayLabel = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shoutDelayLabel:SetPoint("LEFT", page.shoutDelay, "RIGHT", 8, 0)
    shoutDelayLabel:SetText("seconds after the ding")
    page.shoutRank = makeEditBox(sb, 40, true)
    page.shoutRank:SetPoint("TOPLEFT", page.shoutDelay, "BOTTOMLEFT", 0, -6)
    page.shoutRank:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if value then shoutSettings().minRank = math.max(0, math.floor(value)) end
        GL:RefreshWindow()
    end)
    local shoutRankLabel = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shoutRankLabel:SetPoint("LEFT", page.shoutRank, "RIGHT", 8, 0)
    shoutRankLabel:SetText("lowest rank index that posts (0 = guild leader only, so officers do not double-post)")
    shoutRankLabel:SetWidth(leftWidth - 20 - 10 - 40 - 8)
    shoutRankLabel:SetJustifyH("LEFT")
    page.shoutPreview = makeButton(sb, "Preview on me", 100, function() shout("preview") end)
    page.shoutPreview:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 26)
    explain(page.shoutPreview, "Prints the line it would post about you. Nothing is sent to chat.")
    page.shoutTest = makeButton(sb, "Post test", 80, function() confirm("Post a test shoutout about yourself to guild chat now?", function() shout("test") end) end)
    page.shoutTest:SetPoint("LEFT", page.shoutPreview, "RIGHT", 4, 0)
    explain(page.shoutTest, "Really posts a line about you to guild chat (asks first).")
    page.shoutList = makeButton(sb, "Edit lines", 100, function() openLinesEditor("shout", "60") end)
    page.shoutList:SetPoint("LEFT", page.shoutTest, "RIGHT", 4, 0)
    explain(page.shoutList, "See, add and remove the lines for each milestone level, plus the pools for any level, promotions and returns.")
    page.shoutReset = makeButton(sb, "Reset all lines", 110, function() confirm("Restore the stock shoutout lines in every pool?", function() shout("reset") end) end)
    page.shoutReset:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0)
    explain(page.shoutReset, "Removes your custom lines in every pool and restores the stock ones.")

    -- Right: sharing and tooltips.
    local options = {
        { key = "sync", label = "Share join dates, alts, bans and notes with other Tabard users in the guild" },
        { key = "shareUsage", label = "Share which Tabard pages I open and which features are on (counts only, no names)", default = true },
        { key = "tooltip", label = "Add join date, main and alts to guild members' tooltips" },
        { key = "autoAlts", label = "Read notes like \"alt of Zev\" to link alts automatically" },
        { key = "learnFromGRM", label = "Keep taking alt groups from Guild Roster Manager while it is installed", default = true },
        { key = "mainTags", label = "Show (main) or (alt of ...) after names in chat lines and the Log", default = true },
        { key = "firstWeek", label = "Track new members' first week (time online, whether anyone talked to them)", default = true },
        { key = "anniversaries", label = "Mention join anniversaries and birthdays at login" },
        { key = "loginReport", label = "At login, list who joined, left and changed rank while I was away" },
        { key = "hints", label = "Show the main's name, or the nickname, after names in guild chat", default = true },
        { key = "requests", label = "Accept requests whispered to you (!main, !bday, !loa); they land on the To-do tab", default = true },
        { key = "raidTracking", label = "Track raid attendance, bench and loot while you are in a raid group", default = true },
    }
    local behaviourHeight = 34 + 12 * 30 + 6
    page.behaviourBox = section(content, "Sharing and tooltips", rightX, -PAD, rightWidth, behaviourHeight)
    page.options = {}
    page.optionDefaults = {}
    y = 2
    for _, option in ipairs(options) do
        local box = makeCheck(page.behaviourBox.body, option.label, function(checked) GL.settings[option.key] = checked GL:RefreshWindow() end)
        box:SetPoint("TOPLEFT", page.behaviourBox.body, "TOPLEFT", -4, y)
        box.label:SetWidth(rightWidth - 56)
        box.label:SetJustifyH("LEFT")
        page.options[option.key] = box
        page.optionDefaults[option.key] = option.default or false
        y = y - 30
    end
    explain(page.options.shareUsage, "Goes to other Tabard users in this guild with the sharing hello, so whoever maintains Tabard can see what gets used. /tabard usage shows exactly what is sent; /tabard users shows what the others use.")
    page.minimap = makeCheck(page.behaviourBox.body, "Show the minimap button", function(checked) GL.settings.minimap.shown = checked GL:UpdateMinimapButton() end)
    page.minimap:SetPoint("TOPLEFT", page.behaviourBox.body, "TOPLEFT", -4, y)
    y = y - 32
    page.loginLabel = page.behaviourBox.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.loginLabel:SetPoint("TOPLEFT", page.behaviourBox.body, "TOPLEFT", 4, y - 4)
    page.loginLabel:SetText("When I log in or reload:")
    local loginItems = {}
    for _, key in ipairs({ "card", "always", "todo", "never" }) do
        loginItems[#loginItems + 1] = { text = LOGIN_LABELS[key], isChecked = function() return (GL.settings.openOnLogin or LOGIN_DEFAULT) == key end, toggle = function() GL.settings.openOnLogin = key GL:RefreshWindow() end }
    end
    page.login = createFilter(page.behaviourBox.body, LOGIN_LABELS[LOGIN_DEFAULT], loginItems, 200)
    page.login:SetPoint("LEFT", page.loginLabel, "RIGHT", 8, 0)
    explain(page.login, "A few seconds after you log in or reload, once the roster has been read. The card lists what changed while you were away and how many to-do items are open, with a button for the whole window; it only shows when there is something on it.")
    y = y - 30
    page.artLabel = page.behaviourBox.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.artLabel:SetPoint("TOPLEFT", page.behaviourBox.body, "TOPLEFT", 4, y - 4)
    page.artLabel:SetText("Background art:")
    page.art = createFilter(page.behaviourBox.body, THEME_LABELS[DEFAULT_THEME], artMenuItems(), 200)
    page.art:SetPoint("LEFT", page.artLabel, "RIGHT", 8, 0)
    explain(page.art, "Art the game already has, behind the window: a different one each session, class art from the talent window (member cards show that member's class), scenes from the game's other windows, your guild tabard, the game's own map tiles, or parchment. The Background button on the window changes it too.")
    y = y - 30
    page.brightnessLabel = page.behaviourBox.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.brightnessLabel:SetPoint("TOPLEFT", page.behaviourBox.body, "TOPLEFT", 4, y - 4)
    page.brightnessLabel:SetText("Art brightness:")
    local washItems = {}
    for _, key in ipairs(WASH_ORDER) do
        washItems[#washItems + 1] = { text = WASH_LABELS[key], isChecked = function() return (GL.settings.artBrightness or "normal") == key end, toggle = function() GL.settings.artBrightness = key GL:RefreshWindow() end }
    end
    page.brightness = createFilter(page.behaviourBox.body, WASH_LABELS.normal, washItems, 200)
    page.brightness:SetPoint("LEFT", page.brightnessLabel, "RIGHT", 8, 0)
    explain(page.brightness, "How much of the art shows through. Bright is closest to the talent window; subtle keeps long lists easiest to read.")
    y = y - 30
    page.noteDateLabel = page.behaviourBox.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.noteDateLabel:SetPoint("TOPLEFT", page.behaviourBox.body, "TOPLEFT", 4, y - 4)
    page.noteDateLabel:SetText("Write the join date into:")
    local noteItems = {}
    for _, key in ipairs({ "none", "public", "officer" }) do
        noteItems[#noteItems + 1] = { text = NOTE_DATE_LABELS[key], isChecked = function() return (GL.settings.noteJoinDate or "none") == key end, toggle = function() GL.settings.noteJoinDate = key GL:RefreshWindow() end }
    end
    page.noteDate = createFilter(page.behaviourBox.body, NOTE_DATE_LABELS.none, noteItems, 200)
    page.noteDate:SetPoint("LEFT", page.noteDateLabel, "RIGHT", 8, 0)
    explain(page.noteDate, "When someone joins and that note is empty, Tabard writes \"Joined 07 Nov 2026\" into it, the way Guild Roster Manager does. Needs note-editing rights.")

    -- Right, middle: thresholds.
    local numbers = {
        { key = "inactiveDays", label = "days away before a return is announced" },
        { key = "kickDays", label = "days away before suggesting removal" },
        { key = "kickMaxLevel", label = "only suggest removal at or below this level (0 = any)" },
        { key = "promoteDays", label = "days in the newest rank before suggesting promotion" },
        { key = "syncMinRank", label = "lowest rank index whose shared data is accepted (0 = guild leader)" },
        { key = "trialDays", label = "days in the trial rank before a review is due", default = 14 },
        { key = "trialRank", label = "rank index that counts as the trial rank (empty = the newest rank)", allowNil = true },
        { key = "strikeDays", label = "days a strike counts (0 = forever)", default = 90 },
        { key = "keepEventDays", label = "days of history to keep; older events are tidied away (0 = keep all)", default = 365 },
    }
    local thresholdsTop = -PAD - behaviourHeight - GAP
    local thresholdsHeight = 34 + 9 * 26 + 6
    page.thresholdBox = section(content, "Thresholds", rightX, thresholdsTop, rightWidth, thresholdsHeight)
    page.numbers = {}
    y = -2
    for _, item in ipairs(numbers) do
        local box = makeEditBox(page.thresholdBox.body, 44, true)
        box:SetPoint("TOPLEFT", page.thresholdBox.body, "TOPLEFT", 6, y)
        box.allowNil, box.default = item.allowNil, item.default
        box:SetScript("OnEditFocusLost", function(self)
            local text = strtrim(self:GetText() or "")
            local value = tonumber(text)
            if text == "" and item.allowNil then GL.settings[item.key] = nil
            elseif value and value >= 0 then GL.settings[item.key] = math.floor(value) end
            GL:RefreshWindow()
        end)
        local label = page.thresholdBox.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", box, "RIGHT", 8, 0)
        label:SetWidth(rightWidth - 20 - 6 - 44 - 8)
        label:SetJustifyH("LEFT")
        label:SetText(item.label)
        box.sideLabel = label
        page.numbers[item.key] = box
        y = y - 26
    end

    -- Right, bottom: data.
    local dataTop = thresholdsTop - thresholdsHeight - GAP
    local dataHeight = 34 + 4 * 26 + 50
    page.dataBox = section(content, "Data", rightX, dataTop, rightWidth, dataHeight)
    local db = page.dataBox.body
    local import = makeButton(db, "Import from Guild Roster Manager", 230, function()
        local guild = GL:Guild()
        if not guild then return end
        local plan, summary = GL:PlanGRMImport(guild)
        if not plan then GL:Print(summary) return end
        confirm("Bring over " .. summary .. " from Guild Roster Manager's saved data? Dates from the game's log and ones you type in still take priority.", function()
            GL:ApplyGRMImport(guild, plan)
            GL:Print("imported " .. summary .. ".")
        end)
    end)
    import:SetPoint("TOPLEFT", db, "TOPLEFT", 0, 0)
    explain(import, "Reads Guild Roster Manager's saved join and promotion dates for this guild, if that addon has run here.")
    local sync = makeButton(db, "Ask officers for their data", 230, function() if GL.Sync then GL.Sync:Hello(true) end GL:Print("asked other Tabard users in the guild for their data.") end)
    sync:SetPoint("TOPLEFT", import, "BOTTOMLEFT", 0, -4)
    local reset = makeButton(db, "Reset this guild's ledger", 230, function()
        local key = GL:GuildKey()
        if not key then GL:Print("you are not in a guild.") return end
        confirm("Delete everything Tabard has recorded for " .. key .. "? This cannot be undone.", function()
            GL.db.guilds[key] = nil
            GL:Print("ledger cleared; the roster will be read again.")
            GL:RequestScan(true)
            GL:RefreshWindow()
        end)
    end)
    reset:SetPoint("TOPLEFT", sync, "BOTTOMLEFT", 0, -4)
    explain(reset, "Deletes every event, date, group, ban and note recorded for this guild on this account.")
    page.backup = makeButton(db, "Back up now", 113, function()
        local guild = GL:Guild()
        if not (guild and GL.Backup) then GL:Print("nothing to back up.") return end
        GL:Backup(guild, "manual")
        GL:Print("backup saved.")
        GL:RefreshWindow()
    end)
    page.backup:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -4)
    explain(page.backup, "Keeps one copy of this guild's ledger in your saved data. Restoring swaps the copy and the live data, so a second restore undoes the first.")
    page.restore = makeButton(db, "Restore backup", 113, function()
        confirm("Replace the live ledger with the backup? The current data becomes the new backup, so you can restore again to undo.", function()
            local ok, err = GL:RestoreBackup()
            if ok then GL:Print("backup restored.") else GL:Print("could not restore: " .. tostring(err)) end
            GL:RequestScan(true)
            GL:RefreshWindow()
        end)
    end)
    page.restore:SetPoint("LEFT", page.backup, "RIGHT", 4, 0)
    page.backupInfo = db:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.backupInfo:SetPoint("TOPLEFT", page.backup, "BOTTOMLEFT", 0, -6)
    page.backupInfo:SetPoint("RIGHT", db, "RIGHT", 0, 0)
    page.backupInfo:SetJustifyH("LEFT")
    page.backupInfo:SetTextColor(0.62, 0.62, 0.62)
    local version = db:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("BOTTOMRIGHT", db, "BOTTOMRIGHT", 0, 0)
    version:SetText("Tabard " .. tostring(GL.version) .. "   /tabard")

    -- Layout: labels wrap at this width, so rows flow top to bottom by their measured height, each box grows
    -- to fit, and the boxes below move down. Runs at build time and again on every refresh (fonts settle late).
    local function textHeight(fontString, fallback)
        local h = fontString and fontString.GetStringHeight and fontString:GetStringHeight()
        return tonumber(h) or fallback or 12
    end
    local function rowHeight(row)
        local w = row.w
        if row.kind == "text" then return textHeight(w) + 2 end
        if row.kind == "check" then return math.max(24, textHeight(w.label) + 8) end
        if row.kind == "pair" then return 22 end
        local h = tonumber(w:GetHeight()) or 22
        if row.label then h = math.max(h, textHeight(row.label) + 4) end
        return h
    end
    local function flow(body, rows)
        local y = 0
        for _, row in ipairs(rows) do
            if row.w then
                local h = rowHeight(row)
                row.w:ClearAllPoints()
                row.w:SetPoint("TOPLEFT", body, "TOPLEFT", row.x or 0, y - (row.kind == "pair" and 5 or 0))
                if row.kind == "text" then row.w:SetPoint("RIGHT", body, "RIGHT", 0, 0) end
                y = y - h - (row.gap or 2)
            end
        end
        return -y
    end
    local function fit(box, used) box:SetHeight(34 + used + 8) return 34 + used + 8 end
    local function below(box, above) box:ClearAllPoints() box:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -GAP) end
    local C, B, T, P = "check", "box", "text", "pair"
    function page.layout()
        local welcomeUsed = flow(wb, {
            { w = page.welcomeHelp, kind = T, gap = 6 }, { w = page.welcomeOn, kind = C, x = -4 }, { w = page.welcomeAuto, kind = C, x = -4 },
            { w = page.welcomeDelay, kind = B, x = 10, label = delayLabel }, { w = page.welcomeRank, kind = B, x = 10, label = rankLabel, gap = 8 },
            { w = page.welcomeTest, kind = B },
        })
        local shoutUsed = flow(sb, {
            { w = page.shoutHelp, kind = T, gap = 6 }, { w = page.shoutOn, kind = C, x = -4 },
            { w = page.shoutLevelsLabel, kind = P, x = 10 }, { w = page.shoutNameLabel, kind = P, x = 10, gap = 6 },
            { w = page.shoutEvery, kind = C, x = -4 }, { w = page.shoutPromote, kind = C, x = -4 }, { w = page.shoutBack, kind = C, x = -4 }, { w = page.shoutAuto, kind = C, x = -4 },
            { w = page.shoutDelay, kind = B, x = 10, label = shoutDelayLabel }, { w = page.shoutRank, kind = B, x = 10, label = shoutRankLabel, gap = 8 },
            { w = page.shoutPreview, kind = B, gap = 4 }, { w = page.shoutReset, kind = B },
        })
        local behaviourRows = {}
        for _, option in ipairs(options) do behaviourRows[#behaviourRows + 1] = { w = page.options[option.key], kind = C, x = -4, gap = 4 } end
        behaviourRows[#behaviourRows + 1] = { w = page.minimap, kind = C, x = -4, gap = 8 }
        for _, label in ipairs({ page.loginLabel, page.artLabel, page.brightnessLabel, page.noteDateLabel }) do behaviourRows[#behaviourRows + 1] = { w = label, kind = P, x = 4, gap = 8 } end
        local behaviourUsed = flow(page.behaviourBox.body, behaviourRows)
        local thresholdRows = {}
        for _, item in ipairs(numbers) do
            local box = page.numbers[item.key]
            thresholdRows[#thresholdRows + 1] = { w = box, kind = B, x = 6, label = box.sideLabel, gap = 4 }
        end
        local thresholdsUsed = flow(page.thresholdBox.body, thresholdRows)
        local welcomeH, shoutH = fit(page.welcomeBox, welcomeUsed), fit(page.shoutBox, shoutUsed)
        local behaviourH, thresholdsH = fit(page.behaviourBox, behaviourUsed), fit(page.thresholdBox, thresholdsUsed)
        below(page.shoutBox, page.welcomeBox)
        below(page.thresholdBox, page.behaviourBox)
        below(page.dataBox, page.thresholdBox)
        local leftBottom = PAD + announceHeight + GAP + welcomeH + GAP + shoutH
        local rightBottom = PAD + behaviourH + GAP + thresholdsH + GAP + dataHeight
        content:SetHeight(math.max(leftBottom, rightBottom) + PAD)
    end
    page.layout()

    page.refresh = function()
        page.layout()
        for kind, box in pairs(page.announce) do box:SetChecked(GL.settings.announce[kind] and true or false) end
        for key, box in pairs(page.options) do
            local value = GL.settings[key]
            if value == nil then value = page.optionDefaults[key] end
            box:SetChecked(value and true or false)
        end
        page.minimap:SetChecked(GL.settings.minimap.shown and true or false)
        for key, box in pairs(page.numbers) do
            if not box:HasFocus() then
                local value = GL.settings[key]
                if value == nil then value = box.default end
                box:SetText(value ~= nil and tostring(value) or (box.allowNil and "" or "0"))
            end
        end
        page.login:SetLabel(LOGIN_LABELS[GL.settings.openOnLogin or LOGIN_DEFAULT] or LOGIN_LABELS[LOGIN_DEFAULT])
        page.art:SetLabel(THEME_LABELS[chosenTheme()] or THEME_LABELS[DEFAULT_THEME])
        page.brightness:SetLabel(WASH_LABELS[GL.settings.artBrightness or "normal"] or WASH_LABELS.normal)
        page.noteDate:SetLabel(NOTE_DATE_LABELS[GL.settings.noteJoinDate or "none"] or NOTE_DATE_LABELS.none)
        local okInfo, backupTime, backupLabel = pcall(function() if GL.BackupInfo then return GL:BackupInfo() end end)
        local okSize, size = pcall(function() if GL.DBSizeText then return GL:DBSizeText() end end)
        page.backupInfo:SetText((okInfo and backupTime and ("Backup from " .. GL:FormatTime(backupTime) .. " (" .. tostring(backupLabel) .. ")") or "No backup yet")
            .. (okSize and size and (". Saved data: " .. size) or "") .. ".")
        page.restore:SetEnabled(okInfo and backupTime ~= nil and GL.RestoreBackup ~= nil)
        page.backup:SetEnabled(GL.Backup ~= nil)
        local w = welcomeSettings()
        page.welcomeOn:SetChecked(w.enabled and true or false)
        page.welcomeAuto:SetChecked(w.mode == "auto")
        if not page.welcomeDelay:HasFocus() then page.welcomeDelay:SetText(tostring(w.delay or 8)) end
        if not page.welcomeRank:HasFocus() then page.welcomeRank:SetText(tostring(w.minRank or 1)) end
        local on = w.enabled and true or false
        page.welcomeAuto:SetEnabled(on)
        page.welcomeDelay:SetEnabled(on)
        page.welcomeRank:SetEnabled(on)
        local list = GL.settings.welcome and GL.settings.welcome.lines
        page.welcomeBox.aside:SetText(type(list) == "table" and #list > 0 and (plural(#list, "custom line")) or "stock lines")

        page.shoutOn:SetChecked(shoutValue("enabled") and true or false)
        if not page.shoutLevels:HasFocus() then page.shoutLevels:SetText(tostring(shoutValue("levels"))) end
        page.shoutEvery:SetChecked(shoutValue("every") and true or false)
        page.shoutPromote:SetChecked(shoutValue("promote") and true or false)
        page.shoutBack:SetChecked(shoutValue("back") and true or false)
        page.shoutAuto:SetChecked(shoutValue("mode") == "auto")
        if not page.shoutDelay:HasFocus() then page.shoutDelay:SetText(tostring(shoutValue("delay"))) end
        if not page.shoutRank:HasFocus() then page.shoutRank:SetText(tostring(shoutValue("minRank"))) end
        local shoutOn = shoutValue("enabled") and true or false
        for _, control in ipairs({ page.shoutLevels, page.shoutEvery, page.shoutPromote, page.shoutBack, page.shoutAuto, page.shoutDelay, page.shoutRank }) do
            control:SetEnabled(shoutOn)
        end
        page.shoutName:SetLabel(NAME_STYLES[shoutValue("nameStyle")] or NAME_STYLES.firstlower)
        if page.shoutName.SetEnabled then page.shoutName:SetEnabled(shoutOn) end
        page.shoutBox.aside:SetText(GL.Shout and "" or "module not loaded")
    end
end

-- Member card ---------------------------------------------------------------------------------------------------------
-- Everything about one member in groups: dates, characters, officer file (leave, trial, strikes), notes, actions
-- and their history.
local CARD_WIDTH, CARD_HEIGHT = 380, WINDOW_HEIGHT
local cardMember

local function buildCard()
    local inset
    card, inset = styleWindow(nil, "TabardUIMemberFrame", "Member", CARD_WIDTH, CARD_HEIGHT)
    card:SetPoint("TOPLEFT", frame, "TOPRIGHT", -2, 0)
    card:SetScript("OnDragStart", function() end)
    tinsert(UISpecialFrames, "TabardUIMemberFrame")
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", card, "TOPLEFT", 9, -58)
    inset:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -6, 6)
    pcall(addArt, card, inset)

    card.subtitle = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Centred under the title like the title itself, inside margins that match on both sides so the centre
    -- is the card's centre; the left margin also keeps it clear of the portrait circle.
    card.subtitle:SetPoint("TOPLEFT", card, "TOPLEFT", 84, -30)
    card.subtitle:SetPoint("RIGHT", card, "RIGHT", -84, 0)
    card.subtitle:SetJustifyH("CENTER")
    card.subtitle:SetWordWrap(false)

    local y = -8
    local function groupLabel(text)
        local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, y)
        label:SetText(text)
        label:SetTextColor(1, 0.82, 0)
        local rule = solid(card, "ARTWORK", 1, 1, 1, 0.1)
        rule:SetPoint("LEFT", label, "RIGHT", 8, 0)
        rule:SetPoint("RIGHT", inset, "RIGHT", -10, 0)
        rule:SetHeight(1)
        y = y - 18
        return label
    end

    -- A labelled value with up to three buttons on the right (listed right to left).
    local function fieldRow(label, buttons)
        local row = CreateFrame("Frame", nil, card)
        row:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, y)
        row:SetPoint("RIGHT", inset, "RIGHT", -10, 0)
        row:SetHeight(22)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT")
        row.label:SetWidth(84)
        row.label:SetJustifyH("LEFT")
        row.label:SetTextColor(0.62, 0.62, 0.62)
        row.label:SetText(label)
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
        row.value:SetJustifyH("LEFT")
        row.value:SetWordWrap(false)
        local right = row
        row.buttons = {}
        for _, spec in ipairs(buttons or {}) do
            local button = makeButton(row, spec.text, spec.width or 60, function() spec.onClick() end)
            if right == row then button:SetPoint("RIGHT", row, "RIGHT", 0, 0) else button:SetPoint("RIGHT", right, "LEFT", -4, 0) end
            if spec.hint then explain(button, spec.hint) end
            row.buttons[spec.key or spec.text] = button
            right = button
        end
        row.value:SetPoint("RIGHT", right, right == row and "RIGHT" or "LEFT", -6, 0)
        y = y - 22
        return row
    end

    local function guildOf() return GL:Guild() end
    local badDate = "that is not a date I understand; use 2026-11-04 or 4 Nov 2026."
    -- Officers.lua may be missing on an older install; every officer-file action checks first.
    local function officer(name)
        if GL[name] then return true end
        GL:Print("the officer module is not loaded, so this cannot be set.")
        return false
    end

    groupLabel("Dates")
    card.joined = fieldRow("Joined", { { text = "Set", onClick = function()
        askText("Join date for " .. cardMember.name .. " (for example 2026-11-04 or 4 Nov 2026)", cardMember.joined and date("%Y-%m-%d", cardMember.joined) or "", function(text)
            local t = GL:ParseDate(text)
            if not t then GL:Print(badDate) return end
            GL:SetJoinDate(guildOf(), cardMember.name, t, "user", true)
        end)
    end, hint = "Dates you type in win over imported and shared ones." } })
    card.promoted = fieldRow("In rank since", { { text = "Set", onClick = function()
        askText("Date " .. cardMember.name .. " reached their current rank", cardMember.promoted and date("%Y-%m-%d", cardMember.promoted) or "", function(text)
            local t = GL:ParseDate(text)
            if not t then GL:Print(badDate) return end
            GL:SetPromotedDate(guildOf(), cardMember.name, t, "user", true)
        end)
    end } })
    card.lastOnline = fieldRow("Last online", { { key = "watch", text = "Watch", width = 66, onClick = function()
        cardMember.watch = not cardMember.watch or nil
        GL:Print(cardMember.watch and ("you will be told when " .. plain(cardMember.name) .. " comes online.") or ("no longer watching " .. plain(cardMember.name) .. "."))
        GL:RefreshWindow()
    end, hint = "Print a line in chat the next time this member comes online (only on this account)." } })
    card.birthday = fieldRow("Birthday", { { text = "Set", onClick = function()
        askText("Birthday for " .. cardMember.name .. " (for example 4 Nov or 11/04; leave empty to clear)", cardMember.birthday and GL:FormatMonthDay(cardMember.birthday.m, cardMember.birthday.d) or "", function(text)
            if strtrim(text) == "" then GL:SetBirthday(guildOf(), cardMember, nil, nil, "user") return end
            local m, d = GL:ParseMonthDay(text)
            if not m then GL:Print("that is not a day I understand; use 4 Nov or 11/04.") return end
            GL:SetBirthday(guildOf(), cardMember, m, d, "user")
        end)
    end } })

    y = y - 6
    groupLabel("Characters")
    card.main = fieldRow("Main", {
        { key = "set", text = "Set...", onClick = function() pickMainFor(cardMember) end,
            hint = "Pick the main from a list of members. Make main and Unlink are next to it." },
        { key = "makeMain", text = "Make main", width = 76, onClick = function()
            local finish = cardAdvance(cardMember)
            GL:SetMain(guildOf(), cardMember, "user")
            finish()
        end },
        { key = "unlink", text = "Unlink", onClick = function() GL:Unlink(guildOf(), cardMember, "user") GL:RefreshWindow() end },
    })
    explain(card.main.buttons.makeMain, function(self) return self:IsEnabled() and "Make this character a main: it starts a group of its own, or takes over its current group." or "Already the main of its group." end)
    explain(card.main.buttons.unlink, function(self) return self:IsEnabled() and "Take this character out of its main/alt group." or "Not in a group." end)
    card.alts = fieldRow("Alts", {
        { key = "add", text = "Add alt...", width = 76, onClick = function() pickAltFor(cardMember) end,
            hint = "Pick one of this person's other characters from a list. It is linked as an alt of this character." },
    })
    card.alts:SetHeight(36)
    card.alts.label:ClearAllPoints()
    card.alts.label:SetPoint("TOPLEFT", card.alts, "TOPLEFT", 0, -4)
    card.alts.value:ClearAllPoints()
    card.alts.value:SetPoint("TOPLEFT", card.alts.label, "TOPRIGHT", 4, 0)
    card.alts.value:SetPoint("RIGHT", card.alts.buttons.add, "LEFT", -6, 0)
    card.alts.value:SetWordWrap(true)
    card.alts.value:SetMaxLines(2)
    y = y - 14

    y = y - 6
    groupLabel("Officer file")
    card.leave = fieldRow("Leave", {
        { key = "set", text = "Set", onClick = function()
            if not officer("SetLOA") then return end
            askText("Until when is " .. cardMember.name .. " away? (for example 2026-12-01 or 1 Dec 2026)", cardMember.loa and date("%Y-%m-%d", cardMember.loa.till) or "", function(text)
                local t = GL:ParseDate(text)
                if not t then GL:Print(badDate) return end
                askText("Reason (optional)", cardMember.loa and cardMember.loa.reason or "", function(reason)
                    GL:SetLOA(guildOf(), cardMember, t, reason, "user")
                    GL:RefreshWindow()
                end)
            end)
        end, hint = "A member on leave is left off the removal list until the date passes; after that they show in the to-do list." },
        { key = "clear", text = "Clear", onClick = function() if not officer("SetLOA") then return end GL:SetLOA(guildOf(), cardMember, 0, nil, "user") GL:RefreshWindow() end },
    })
    local function vote(value)
        if not officer("SetTrialVote") then return end
        askText("A few words with your vote on " .. cardMember.name .. " (optional)", "", function(text)
            GL:SetTrialVote(guildOf(), cardMember, value, text, "user")
            GL:RefreshWindow()
        end)
    end
    card.trial = fieldRow("Trial", {
        { key = "clear", text = "Clear", width = 50, onClick = function() if not officer("SetTrialVote") then return end GL:SetTrialVote(guildOf(), cardMember, nil, nil, "user") GL:RefreshWindow() end, hint = "Withdraw your vote." },
        { key = "no", text = "-1", width = 40, onClick = function() vote(-1) end, hint = "Vote against keeping this member after the trial." },
        { key = "yes", text = "+1", width = 40, onClick = function() vote(1) end, hint = "Vote for keeping this member after the trial. Votes are shared with the other officers." },
    })
    card.strikes = fieldRow("Strikes", {
        { key = "remove", text = "Remove", width = 64, onClick = function()
            if not officer("Strikes") or not officer("RemoveStrike") then return end
            local list = GL:Strikes(cardMember)
            if #list == 0 then return end
            confirm("Remove the latest strike (" .. tostring(list[1].text) .. ")?", function() GL:RemoveStrike(guildOf(), cardMember, list[1].id, "user") GL:RefreshWindow() end)
        end, hint = "Removes the most recent strike that still counts." },
        { key = "add", text = "Add", width = 50, onClick = function()
            if not officer("AddStrike") then return end
            askText("What did " .. cardMember.name .. " do?", "", function(text)
                if strtrim(text) == "" then return end
                GL:AddStrike(guildOf(), cardMember, text, "user")
                GL:RefreshWindow()
            end)
        end, hint = "Strikes are a dated case file shared with the other officers; each one expires after the number of days set in Settings." },
    })

    y = y - 6
    groupLabel("Notes")
    -- Notes: public, officer, ledger. Each is an input with a Save button that lights up when the text differs.
    local function noteRow(label, save, hint)
        local row = CreateFrame("Frame", nil, card)
        row:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, y)
        row:SetPoint("RIGHT", inset, "RIGHT", -10, 0)
        row:SetHeight(24)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT")
        row.label:SetWidth(84)
        row.label:SetJustifyH("LEFT")
        row.label:SetTextColor(0.62, 0.62, 0.62)
        row.label:SetText(label)
        row.save = makeButton(row, SAVE or "Save", 60, function() save(row.box:GetText()) row.box:ClearFocus() end)
        row.save:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.box = makeEditBox(row, 100)
        row.box:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
        row.box:SetPoint("RIGHT", row.save, "LEFT", -8, 0)
        row.box:SetMaxLetters(label == "Tabard note" and 160 or 31)
        row.box:SetScript("OnEnterPressed", function(self) row.save:Click() end)
        row.box:SetScript("OnTextChanged", function(self) row.save:SetEnabled(row.editable and self:GetText() ~= (row.current or "")) end)
        row.box:SetScript("OnEnter", function(self) if hint then tooltipLines(self, { { label }, { hint, 0.62, 0.62, 0.62 } }) end end)
        row.box:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        y = y - 26
        return row
    end
    card.note = noteRow("Public note", function(text)
        local ok, err = GL:SetNote(cardMember, text, false)
        if not ok then GL:Print("could not set the note: " .. tostring(err)) else GL:RequestScan(true) end
    end, "The guild note everyone can see (31 characters). Press Enter or Save to write it to the roster.")
    card.onote = noteRow("Officer note", function(text)
        local ok, err = GL:SetNote(cardMember, text, true)
        if not ok then GL:Print("could not set the officer note: " .. tostring(err)) else GL:RequestScan(true) end
    end, "The officer note from the guild roster (31 characters).")
    card.custom = noteRow("Tabard note", function(text) GL:SetCustomNote(guildOf(), cardMember, text, "user") GL:RefreshWindow() end,
        "A longer note (160 characters) that only Tabard users see. Shared with other officers running the addon.")
    card.nick = noteRow("Nickname", function(text) GL:SetNickname(guildOf(), cardMember, text, "user") GL:RefreshWindow() end,
        "What people call them (31 characters). Shown after their name, and the names of their alts, in guild chat and on tooltips. Kept on their main and shared with other officers.")

    card.safeKick = makeCheck(card, "Never suggest removing", function(checked) GL:SetSafe(guildOf(), cardMember, "kick", checked, "user") end)
    card.safeKick:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, y + 2)
    card.safePromote = makeCheck(card, "Never suggest promoting", function(checked) GL:SetSafe(guildOf(), cardMember, "promote", checked, "user") end)
    card.safePromote:SetPoint("LEFT", card.safeKick, "RIGHT", 150, 0)
    y = y - 26

    -- Actions
    local actions = CreateFrame("Frame", nil, card)
    actions:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, y)
    actions:SetPoint("RIGHT", inset, "RIGHT", -10, 0)
    actions:SetHeight(24)
    -- Guild actions. On this client an addon may not promote, demote or remove by itself (the game raises
    -- ADDON_ACTION_FORBIDDEN), but a click on a secure button that runs "/gpromote Name" is the player's own
    -- act and goes through. So Promote and Demote are lists of ranks (nearest first) and Remove is a button,
    -- and each of them arms one secure "Promote Zev Zev to Raider" button in place of the row, which the next
    -- click fires. Cancel, or opening another member, disarms it. A rank further away is several lines of
    -- the same command, since the client only has one-step promote and demote.
    local SLASH = { promote = "/gpromote", demote = "/gdemote", kick = "/gremove" }
    local armed = CreateFrame("Frame", nil, card)
    armed:SetAllPoints(actions)   -- made after the row's buttons, so it draws over them while armed
    armed:Hide()
    card.armed = armed
    armed.go = CreateFrame("Button", "TabardUIMemberGoButton", armed, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    armed.go:SetSize(256, 22)
    armed.go:SetPoint("LEFT")
    armed.go:RegisterForClicks("LeftButtonUp")
    armed.go:SetAttribute("useOnKeyDown", false)
    armed.go:SetAttribute("type", "macro")
    armed.go:HookScript("OnClick", function()
        if armed.what then GL:Print(armed.what .. ".") end
        armed.member = nil
        armed:Hide()
        GL:RequestScan(true)
        C_Timer.After(2, function() GL:RequestScan(true) end)
    end)
    explain(armed.go, "Click to do it. The game only lets you, not an addon, change ranks and membership, so this button runs the command as your own click.")
    armed.cancel = makeButton(armed, "Cancel", 80, function() armed.member = nil armed:Hide() end)
    armed.cancel:SetPoint("RIGHT")
    local function armAction(kind, member, steps, rankName)
        if InCombatLockdown and InCombatLockdown() then GL:Print("not in combat; try again afterwards.") return end
        local lines = {}
        for i = 1, steps do lines[i] = SLASH[kind] .. " " .. plain(member.name) end
        armed.go:SetAttribute("macrotext", table.concat(lines, "\n"))
        local label = kind == "kick" and ("Remove " .. plain(member.name)) or ((kind == "promote" and "Promote " or "Demote ") .. plain(member.name) .. " to " .. rankName)
        armed.go:SetText(label .. (steps > 1 and (" (" .. steps .. " steps)") or ""))
        armed.what = (kind == "kick" and "removed " or (kind == "promote" and "promoted " or "demoted ")) .. plain(member.name) .. (rankName and (" to " .. rankName) or "")
        armed.member = member
        armed:Show()
    end
    card.promoteItems, card.demoteItems = {}, {}
    card.promote = createFilter(actions, "Promote", card.promoteItems, 84)
    card.promote:SetPoint("LEFT")
    explain(card.promote, function(self) return self:IsEnabled() and "Pick the rank to promote to." or "Your rank cannot promote this member, or they are already at the top." end)
    card.demote = createFilter(actions, "Demote", card.demoteItems, 84)
    card.demote:SetPoint("LEFT", card.promote, "RIGHT", 4, 0)
    explain(card.demote, function(self) return self:IsEnabled() and "Pick the rank to demote to." or "Your rank cannot demote this member, or they are already at the bottom." end)
    card.fillRankMenus = function(guild, member)
        for _, list in ipairs({ card.promoteItems, card.demoteItems }) do for i = #list, 1, -1 do list[i] = nil end end
        local current = member.rankIndex
        if not (guild and current) then return end
        local top = 0
        for index in pairs(guild.ranks or {}) do if type(index) == "number" and index > top then top = index end end
        for i = current - 1, 1, -1 do   -- never to guild leader (0)
            local name = guild.ranks[i] or ("rank " .. i)
            card.promoteItems[#card.promoteItems + 1] = { text = name, action = function() armAction("promote", member, current - i, name) end }
        end
        for i = current + 1, top do
            local name = guild.ranks[i] or ("rank " .. i)
            card.demoteItems[#card.demoteItems + 1] = { text = name, action = function() armAction("demote", member, i - current, name) end }
        end
    end
    card.kick = makeButton(actions, "Remove", 80, function() armAction("kick", cardMember, 1, nil) end)
    card.kick:SetPoint("LEFT", card.demote, "RIGHT", 4, 0)
    explain(card.kick, function(self) return self:IsEnabled() and "Remove from the guild. A red button appears to confirm it." or "Your rank cannot remove this member." end)
    card.ban = makeButton(actions, "Ban", 80, function()
        local guild = guildOf()
        if GL:IsBanned(guild, cardMember.name) then
            confirm("Lift the ban on " .. cardMember.name .. "?", function() GL:Unban(guild, cardMember.name, "user") GL:RefreshWindow() end)
        else
            addBan(cardMember.name)
        end
    end)
    card.ban:SetPoint("RIGHT")
    explain(card.ban, "Put this character on the ban list (with a reason). Tabard warns when a banned character or one of their alts joins.")
    y = y - 30

    groupLabel("History")
    local historyArea = CreateFrame("Frame", nil, card)
    historyArea:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, y + 2)
    historyArea:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 0)
    card.history = createList(historyArea,
        function(row)
            row.stripe = solid(row, "BORDER", 1, 1, 1, 0.6)
            row.stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 4, 0)
            row.stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 0)
            row.stripe:SetWidth(2)
            row.kindIcon = row:CreateTexture(nil, "ARTWORK")
            row.kindIcon:SetSize(12, 12)
            row.kindIcon:SetPoint("LEFT", row, "LEFT", 9, 0)
            row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.badge:SetPoint("LEFT", row.kindIcon, "RIGHT", 3, 0)
            row.badge:SetWidth(74)
            row.badge:SetJustifyH("LEFT")
            row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.time:SetPoint("LEFT", row.badge, "RIGHT", 4, 0)
            row.time:SetWidth(78)
            row.time:SetJustifyH("LEFT")
            row.time:SetTextColor(0.62, 0.62, 0.62)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.time, "RIGHT", 4, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row:SetScript("OnEnter", function(self)
                if self.data then tooltipLines(self, { { plain(GL:Describe(self.data.event, self.data.guild)) }, { GL:FormatTime(self.data.event.t), 0.62, 0.62, 0.62 } }) end
            end)
            row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end,
        function(row, data)
            local kind = GL.KINDS[data.event.k] or { label = data.event.k, color = "ffffffff" }
            local r, g, b = hexToRGB(kind.color)
            row.stripe:SetColorTexture(r, g, b, 0.7)
            row.badge:SetText(kind.label)
            row.badge:SetTextColor(r, g, b)
            if not setIcon(row.kindIcon, kindIcon(data.event.k), nil, { r, g, b }) then row.kindIcon:Hide() end
            setText(row.time, GL:FormatDate(data.event.t))
            setText(row.text, GL:Describe(data.event, data.guild))
        end, nil, 18)
    card.historyEmpty = historyArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.historyEmpty:SetPoint("TOP", historyArea, "TOP", 0, -8)
    card.historyEmpty:SetText("Nothing recorded about this member yet.")

    card.refresh = function()
        local guild = GL:Guild()
        local member = cardMember
        if not (guild and member) then card:Hide() return end
        -- the member may have been renamed or moved to former
        member = GL:Member(guild, member.name) or member
        cardMember = member
        local now = GL:Now()
        local former = guild.former[member.name] ~= nil and guild.members[member.name] == nil
        if card.SetTitle then pcall(card.SetTitle, card, plain(member.name)) elseif card.TitleContainer and card.TitleContainer.TitleText then card.TitleContainer.TitleText:SetText(plain(member.name)) end
        local coords = member.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[member.class]
        if coords then
            setPortraitIcon(card, CLASS_CIRCLES, coords)
        else
            setPortraitIcon(card, "Interface\\Icons\\INV_Misc_QuestionMark")
        end
        pcall(applyArt, card, member.class)
        local _, _, _, hex = GL:ClassColor(member.class)
        card.subtitle:SetText(string.format("|c%sLevel %s %s|r, %s%s", hex, tostring(member.level or "?"), GL:ClassName(member.class), tostring(member.rank or ""),
            former and (RED .. "  (no longer in the guild)|r") or (member.online and (GREEN .. "  online|r") or "")))
        card.joined.value:SetText(member.joined and (GL:FormatDate(member.joined) .. GREY .. "  " .. (GL.SOURCE_LABEL[member.joinedSource or ""] or "") .. "|r") or (YELLOW .. "not set|r" .. GREY .. "  first seen " .. GL:FormatDate(member.firstSeen) .. "|r"))
        card.promoted.value:SetText(member.promoted and (GL:FormatDate(member.promoted) .. GREY .. "  " .. GL:Span(now - member.promoted) .. "|r") or (GREY .. "unknown|r"))
        card.lastOnline.value:SetText((member.online and (GREEN .. "online now|r") or (member.lastOnline and (GL:Ago(member.lastOnline) .. GREY .. "  " .. GL:FormatDate(member.lastOnline) .. "|r") or (GREY .. "unknown|r")))
            .. (member.invitedBy and (GREY .. "  invited by " .. member.invitedBy .. "|r") or ""))
        card.lastOnline.buttons.watch:SetText(member.watch and "Unwatch" or "Watch")
        card.lastOnline.buttons.watch:SetEnabled(not former)
        local main, group = GL:MainOf(guild, member)
        if group and main and main.name ~= member.name then card.main.value:SetText("alt of " .. GL:ColoredName(main))
        elseif group then card.main.value:SetText(#group.alts > 0 and "this character is the main" or "a main, no alts linked yet")
        else card.main.value:SetText(GREY .. "not set|r") end
        card.main.buttons.makeMain:SetEnabled(not former and not GL:IsMain(guild, member))
        card.main.buttons.unlink:SetEnabled(group ~= nil)
        local alts = GL:AltsOf(guild, member)
        local names = {}
        for _, alt in ipairs(alts) do if not main or alt.name ~= main.name or main.name == member.name then names[#names + 1] = GL:ColoredName(alt) end end
        if main and main.name ~= member.name then
            for _, other in ipairs(GL:AltsOf(guild, main)) do if other.name ~= member.name then names[#names + 1] = GL:ColoredName(other) end end
            names = { GL:ColoredName(main) .. GREY .. " (main)|r", unpack(names) }
        end
        card.alts.value:SetText(#names > 0 and table.concat(names, ", ") or (GREY .. "none linked|r"))
        card.birthday.value:SetText(member.birthday and GL:FormatMonthDay(member.birthday.m, member.birthday.d) or (GREY .. "unknown|r"))

        -- Officer file (Officers.lua may be absent on an older install; every call is guarded).
        local loa = member.loa
        if loa and GL.OnLeave and GL:OnLeave(member, now) then
            card.leave.value:SetText("|cff8fb8ffuntil " .. GL:FormatDate(loa.till) .. "|r" .. (loa.reason and (GREY .. "  " .. loa.reason .. "|r") or ""))
        elseif loa then
            card.leave.value:SetText(RED .. "ended " .. GL:FormatDate(loa.till) .. "|r" .. (loa.reason and (GREY .. "  " .. loa.reason .. "|r") or ""))
        else
            card.leave.value:SetText(GREY .. "not on leave|r")
        end
        card.leave.buttons.set:SetEnabled(GL.SetLOA ~= nil and not former)
        card.leave.buttons.clear:SetEnabled(GL.SetLOA ~= nil and loa ~= nil)
        local trialRank = GL.TrialRank and GL:TrialRank(guild)
        local inTrial = trialRank ~= nil and member.rankIndex == trialRank and not former
        if inTrial then
            local plus, minus, count, mine = 0, 0, 0, nil
            for by, v in pairs(member.trial and member.trial.votes or {}) do
                count = count + 1
                if v.v > 0 then plus = plus + 1 elseif v.v < 0 then minus = minus + 1 end
                if by == GL:PlayerName() then mine = v end
            end
            local since = member.promoted or member.joined or member.firstSeen
            card.trial.value:SetText(string.format("%s%d|r in rank, %s+%d|r / %s-%d|r%s", WHITE, since and math.floor((now - since) / 86400) or 0, GREEN, plus, RED, minus,
                mine and (GREY .. "  yours: " .. (mine.v > 0 and "+1" or mine.v < 0 and "-1" or "0") .. "|r") or ""))
            card.trial.label:SetText("Trial (days)")
        else
            card.trial.label:SetText("Trial")
            card.trial.value:SetText(GREY .. (trialRank and ("not in \"" .. tostring(guild.ranks[trialRank]) .. "\"") or "no trial rank") .. "|r")
        end
        for _, button in pairs(card.trial.buttons) do button:SetEnabled(inTrial and GL.SetTrialVote ~= nil) end
        local strikes = GL.Strikes and GL:Strikes(member, now) or {}
        if #strikes > 0 then
            card.strikes.value:SetText("|cffff8c5a" .. plural(#strikes, "strike") .. "|r" .. GREY .. "  latest: " .. tostring(strikes[1].text) .. "|r")
        else
            card.strikes.value:SetText(GREY .. "none|r")
        end
        card.strikes.buttons.add:SetEnabled(GL.AddStrike ~= nil and not former)
        card.strikes.buttons.remove:SetEnabled(GL.RemoveStrike ~= nil and #strikes > 0)

        local function fill(row, text, editable)
            row.current = text or ""
            row.editable = editable and not former
            if not row.box:HasFocus() then row.box:SetText(row.current) end
            row.box:SetEnabled(row.editable)
            row.save:SetEnabled(false)
        end
        fill(card.note, member.note, GL:CanEditNote())
        fill(card.onote, member.onote, GL:CanEditOfficerNote())
        fill(card.custom, member.custom, true)
        card.custom.editable = true
        card.custom.box:SetEnabled(true)
        fill(card.nick, GL:Nickname(guild, member), true)
        card.safeKick:SetChecked(GL:IsSafe(member, "kick"))
        card.safePromote:SetChecked(GL:IsSafe(member, "promote"))
        card.fillRankMenus(guild, member)
        if card.armed.member ~= member then card.armed.member = nil card.armed:Hide() end
        if card.promote.SetEnabled then card.promote:SetEnabled(not former and GL:CanPromote() and #card.promoteItems > 0) end
        if card.demote.SetEnabled then card.demote:SetEnabled(not former and GL:CanDemote() and #card.demoteItems > 0) end
        card.kick:SetEnabled(not former and GL:CanRemove() and (member.rankIndex or 0) > 0)
        card.ban:SetText(GL:IsBanned(guild, member.name) and "Lift ban" or "Ban")
        local rows = {}
        for _, event in ipairs(GL:EventsFor(guild, member.name)) do rows[#rows + 1] = { event = event, guild = guild } end
        card.history.SetRows(rows)
        if #rows == 0 then card.historyEmpty:Show() else card.historyEmpty:Hide() end
    end
end

openCard = function(member)
    if not member then return end
    if not card then
        local ok, err = pcall(buildCard)
        if not ok then GL:Print("the member card could not be built: " .. tostring(err)) return end
    end
    cardMember = member
    card:Show()
    card.refresh()
    if GL.Usage then pcall(GL.Usage.Card, GL.Usage) end
end

-- Working down the Members list from the card. Call it before a change that may drop the card's member out of
-- the list (sorting a main or an alt while "No main or alt set" is showing) and call what it returns after:
-- that refreshes the window and, when the member has gone from the list, moves the card on to whoever came
-- next in the order shown, so a whole list can be worked through from the card without going back to the table.
cardAdvance = function(member)
    local page = pages.members
    local before, index = page and page.rows, nil
    if before and currentPage == "members" and card and card:IsShown() and cardMember == member then
        for i, row in ipairs(before) do if row.member == member then index = i break end end
    end
    return function()
        GL:RefreshWindow()
        if not index or cardMember ~= member or currentPage ~= "members" then return end
        local listed = {}
        for _, row in ipairs(page.rows or {}) do listed[row.member] = true end
        if listed[member] then return end
        for i = index + 1, #before do
            if listed[before[i].member] then openCard(before[i].member) return end
        end
        for i = index - 1, 1, -1 do   -- that was the last one: step back instead
            if listed[before[i].member] then openCard(before[i].member) return end
        end
    end
end

-- Tabs ------------------------------------------------------------------------------------------------------
local TAB_ORDER = { { "overview", "Overview" }, { "todo", "To-do" }, { "log", "Log" }, { "members", "Members" }, { "play", "Play" }, { "former", "Former" }, { "bans", "Bans" }, { "tools", "Tools" }, { "export", "Export" }, { "settings", "Settings" } }
local TAB_KEYS = {}
for _, pair in ipairs(TAB_ORDER) do TAB_KEYS[pair[1]] = true end

-- opened: the window was just opened, so the page counts as viewed even when it was already the current one
showPage = function(key, opened)
    if not pages[key] then return end
    if GL.Usage and (opened or key ~= currentPage) then pcall(GL.Usage.Page, GL.Usage, key) end
    currentPage = key
    for name, page in pairs(pages) do
        if name == key then page:Show() else page:Hide() end
    end
    for i, tab in ipairs(tabs) do
        if tab.key == key and PanelTemplates_SetTab then PanelTemplates_SetTab(frame, i) end
    end
    GL:RefreshWindow()
end

local function createTabs()
    local previous
    for i, pair in ipairs(TAB_ORDER) do
        local tab, isStock = newFrame("Button", "TabardUIFrameTab" .. i, frame, "PanelTabButtonTemplate")
        tab.key = pair[1]
        tab:SetID(i)
        tab:SetText(pair[2])
        if previous then tab:SetPoint("TOPLEFT", previous, "TOPRIGHT", isStock and -15 or 1, 0) else tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2) end
        if not isStock then tab:SetSize(80, 32) tab:SetNormalFontObject(GameFontNormalSmall) end
        tab:SetScript("OnClick", function(self)
            if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
            showPage(self.key)
        end)
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
        frame["Tab" .. i] = tab
        tabs[i] = tab
        previous = tab
    end
    frame.Tabs = tabs
    frame.numTabs = #tabs
    -- Background picker in the title bar, so a theme can be tried without opening Settings.
    frame.artButton = createFilter(frame, "Background", artMenuItems(), 112)
    frame.artButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -2)
    frame.artButton:SetFrameLevel((tonumber(frame:GetFrameLevel()) or 0) + 10)
    explain(frame.artButton, "The art behind the window. Settings has the brightness.")
    if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, frame, #tabs) end
end

-- Public --------------------------------------------------------------------------------------------------
function GL:RefreshWindow()
    if not frame then return end
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if frame:IsShown() then
            pcall(applyArt, frame)
            -- The window is the guild's: its name in the title, "Tabard" only when there is no guild.
            local guild = GL:Guild()
            local name = guild and plain(guild.name or "") or ""
            setWindowTitle(frame, name ~= "" and name or "Tabard")
        end
        if frame:IsShown() and currentPage then
            local page = pages[currentPage]
            local ok, err = pcall(page.refresh)
            if not ok then GL:Print("could not draw the " .. currentPage .. " page: " .. tostring(err)) end
        end
        if card and card:IsShown() then
            local ok, err = pcall(card.refresh)
            if not ok then GL:Print("could not draw the member card: " .. tostring(err)) end
        end
    end)
end

function GL:OnLedgerChanged()
    self:RefreshWindow()
end

function GL:OpenMember(name)
    local guild = self:Guild()
    local member = guild and self:Member(guild, name)
    if member and self:ToggleWindow(true) then openCard(member) end
end

-- Opens the window on a page: GL:ShowPage("members") etc.
function GL:ShowPage(key)
    -- opening straight onto the page, so the page last shown is not counted as viewed on the way
    if TAB_KEYS[key] and not (frame and frame:IsShown()) then currentPage = key end
    if self:ToggleWindow(true) and pages[key] then showPage(key) end
end

local function ensureWindow()
    if frame then return true end
    local ok, err = pcall(function()
        definePopups()
        createWindow()
        buildOverviewPage()
        buildTodoPage()
        buildLogPage()
        buildMembersPage()
        buildPlayPage()
        buildFormerPage()
        buildBansPage()
        buildToolsPage()
        buildExportPage()
        buildSettingsPage()
        createTabs()
    end)
    if not ok then
        GL:Print("the window could not be built: " .. tostring(err))
        return false
    end
    frame:SetScript("OnShow", function()
        if GL.HideLoginCard then GL:HideLoginCard() end   -- the whole window replaces the login card
        pcall(showGuildEmblem, frame) GL:RequestScan(false) GL:RefreshWindow()
    end)
    frame:SetScript("OnHide", function() if card then card:Hide() end end)
    return true
end

-- show = true opens without toggling. Returns true when the window is shown afterwards.
function GL:ToggleWindow(show)
    if not self.db then return false end
    if not ensureWindow() then return false end
    if frame:IsShown() and not show then
        frame:Hide()
        return false
    end
    local wasShown = frame:IsShown()
    frame:Show()
    if self.HideLoginCard then self:HideLoginCard() end   -- the whole window replaces the login card
    if not wasShown and GL.Usage then pcall(GL.Usage.Opened, GL.Usage) end
    showPage(currentPage or "overview", not wasShown)
    return true
end

-- Opening at login ----------------------------------------------------------------------------------------
-- Like Guild Roster Manager, the window opens by itself after you log in or reload (settings.openOnLogin:
-- "always" (default), "todo" = only when the to-do list has open items, "never"). It waits a few seconds so
-- the roster has been read, and never opens in combat.
-- Guild roster and unit menus -------------------------------------------------------------------------------
-- Right-clicking a guild member in the Communities roster, on a unit frame, in a friends list or in chat opens
-- Blizzard's menu; Menu.ModifyMenu (Blizzard_Menu) lets an addon add entries once the stock ones are built. The
-- entries open the member's Tabard card or set a nickname, and only appear for people in the ledger. Tags are
-- "MENU_UNIT_" .. the menu name registered in UnitPopupSharedMenus.lua (wow-ui-source, forever branch).
local MENU_NAMES = { "COMMUNITIES_GUILD_MEMBER", "GUILD", "GUILD_OFFLINE", "PLAYER", "PARTY", "RAID_PLAYER", "FRIEND", "TARGET", "FOCUS", "CHAT_ROSTER" }

local function menuMemberFor(contextData)
    if type(contextData) ~= "table" then return nil end
    local name = contextData.name
    if not GL:IsUsable(name) or type(name) ~= "string" or name == "" then return nil end
    -- Units come as name and surname ("Zev", "Zev"); the roster passes the whole name ("Zev Zev").
    local surname = contextData.surname
    if GL:IsUsable(surname) and type(surname) == "string" and surname ~= "" and not string.find(name, " ", 1, true) then name = name .. " " .. surname end
    name = GL:ShortName(name)
    local guild = GL:Guild()
    if not guild then return nil end
    return guild.members[name], guild
end

local function addMenuEntries(ownerRegion, rootDescription, contextData)
    local member, guild = menuMemberFor(contextData)
    if not (member and rootDescription and rootDescription.CreateButton) then return end
    if rootDescription.CreateDivider then rootDescription:CreateDivider() end
    if rootDescription.CreateTitle then rootDescription:CreateTitle("Tabard") end
    rootDescription:CreateButton("Open in Tabard", function() GL:OpenMember(member.name) end)
    rootDescription:CreateButton("Nickname...", function()
        askText("Nickname for " .. plain(member.name) .. " (shown after their name in guild chat)", GL:Nickname(guild, member) or "", function(text)
            GL:SetNickname(guild, member, text, "user")
            GL:RefreshWindow()
        end)
    end)
end

local menusInstalled = false
function GL:InstallUnitMenus()
    if menusInstalled then return true end
    if not (Menu and Menu.ModifyMenu) then return false end
    menusInstalled = true
    for _, which in ipairs(MENU_NAMES) do
        pcall(Menu.ModifyMenu, "MENU_UNIT_" .. which, function(owner, root, contextData)
            local ok, err = pcall(addMenuEntries, owner, root, contextData)
            if not ok then GL:Print("could not add the menu entries: " .. tostring(err)) end
        end)
    end
    return true
end

-- The login card --------------------------------------------------------------------------------------------
-- A small window instead of the whole one at login (settings.openOnLogin = "card", the default): what changed
-- while you were away, as on the Overview, how many to-do items are open, and a button for the whole window.
-- It only shows when there is something on it, and goes away when the window opens.
local loginCard
local LOGIN_ROWS = 6
local LOGIN_WIDTH = 400

local function buildLoginCard()
    local inset
    loginCard, inset = styleWindow(nil, "TabardUILoginFrame", "Tabard", LOGIN_WIDTH, 200)
    loginCard:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    loginCard:SetScript("OnDragStart", loginCard.StartMoving)
    loginCard:SetScript("OnDragStop", loginCard.StopMovingOrSizing)
    tinsert(UISpecialFrames, "TabardUILoginFrame")
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", loginCard, "TOPLEFT", 9, -58)
    inset:SetPoint("BOTTOMRIGHT", loginCard, "BOTTOMRIGHT", -6, 6)
    loginCard.inset = inset
    pcall(showGuildEmblem, loginCard)
    pcall(addArt, loginCard, inset)

    loginCard.heading = loginCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    loginCard.heading:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -10)
    loginCard.heading:SetText("Since your last visit")
    loginCard.heading:SetTextColor(1, 0.82, 0)
    loginCard.when = loginCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    loginCard.when:SetPoint("RIGHT", inset, "TOPRIGHT", -12, -17)
    loginCard.when:SetTextColor(0.62, 0.62, 0.62)
    loginCard.rule = solid(loginCard, "ARTWORK", 1, 1, 1, 0.12)
    loginCard.rule:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -30)
    loginCard.rule:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -30)
    loginCard.rule:SetHeight(1)
    loginCard.rows = {}
    for i = 1, LOGIN_ROWS + 1 do   -- the last one is the to-do line
        local row = linkRow(loginCard)
        row:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -36 - (i - 1) * 20)
        row:SetPoint("RIGHT", inset, "RIGHT", -12, 0)
        row:Hide()
        loginCard.rows[i] = row
    end
    loginCard.none = loginCard:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    loginCard.none:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -40)
    loginCard.none:SetText("Nothing changed while you were away.")
    loginCard.open = makeButton(loginCard, "Open Tabard", 110, function() GL:ToggleWindow(true) end)
    loginCard.open:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -12, 10)
    explain(loginCard.open, "The whole window: Overview, To-do, Log, Members and the rest.")
    loginCard.hint = loginCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    loginCard.hint:SetPoint("LEFT", inset, "BOTTOMLEFT", 16, 21)
    loginCard.hint:SetPoint("RIGHT", loginCard.open, "LEFT", -8, 0)
    loginCard.hint:SetJustifyH("LEFT")
    loginCard.hint:SetTextColor(0.5, 0.5, 0.5)
    loginCard.hint:SetText("Settings changes what opens at login.")
end

function GL:HideLoginCard()
    if loginCard then loginCard:Hide() end
end

-- Shows the card when there is something on it; returns whether it was shown.
function GL:ShowLoginCard()
    local guild = self.db and IsInGuild() and self:Guild()
    if not guild or (frame and frame:IsShown()) then return false end
    local okNews, news = pcall(function() return self.WhatsNew and self:WhatsNew(guild) or nil end)
    if not okNews or type(news) ~= "table" then news = {} end
    local open = 0
    local okTodo, todo = pcall(function() return self.TodoItems and self:TodoItems(guild) or {} end)
    if okTodo and type(todo) == "table" then for _, item in ipairs(todo) do if not item.handled then open = open + 1 end end end
    if #news == 0 and open == 0 then return false end
    if not loginCard then
        local ok, err = pcall(buildLoginCard)
        if not ok then self:Print("the login card could not be built: " .. tostring(err)) return false end
    end
    local function openTo(go) return function() if GL:ToggleWindow(true) then go() end end end
    local NEWS_ICONS = { green = ICONS.join, red = ICONS.leave, gold = ICONS.promote, blue = ICONS.level, purple = ICONS.note, grey = ICONS.other }
    local rows = loginCard.rows
    local limit = #news > LOGIN_ROWS and (LOGIN_ROWS - 1) or #news
    local used = 0
    for i = 1, LOGIN_ROWS do
        local row, item = rows[i], news[i]
        if i <= limit and item then
            local go = item.member and openTo(function() openCard(item.member) end) or openTo(function() goLog(item.kinds) end)
            row.Set(item.text, ACCENT[item.accent or "grey"] or ACCENT.grey, go, item.member and "Click to open the member card." or "Click to see these in the log.", item.icon or NEWS_ICONS[item.accent or "grey"])
            used = i
        elseif i == limit + 1 and #news > LOGIN_ROWS then
            row.Set(GREY .. "and " .. (#news - limit) .. " more in the log|r", ACCENT.grey, openTo(function() goLog(nil) end), "The log starts with everything since your last visit.", ICONS.other)
            used = i
        else
            row:Hide()
        end
    end
    if #news == 0 then loginCard.none:Show() used = 1 else loginCard.none:Hide() end
    local todoRow = rows[LOGIN_ROWS + 1]
    if open > 0 then
        todoRow:ClearAllPoints()
        todoRow:SetPoint("TOPLEFT", loginCard.inset, "TOPLEFT", 12, -36 - used * 20)
        todoRow:SetPoint("RIGHT", loginCard.inset, "RIGHT", -12, 0)
        todoRow.Set(plural(open, "thing", "things") .. " on the to-do list", ACCENT.gold, function() GL:ShowPage("todo") end, "Trials, leaves, likely alts, whispered requests and promotions due.", ICONS.todo)
        used = used + 1
    else
        todoRow:Hide()
    end
    loginCard.when:SetText(type(guild.visitSince) == "number" and ("last here " .. self:Ago(guild.visitSince)) or "")
    loginCard:SetHeight(58 + 36 + used * 20 + 6 + 22 + 10 + 6)
    loginCard:Show()
    return true
end

-- Your own birthday, asked once at login (optional). It goes on your character like a birthday set on a card
-- and is shared with the other Tabard users in the guild the same way, so they know when it is. Empty or
-- cancelled means no, and the question is not asked again; the card can set it any time.
local function askOwnBirthday()
    if not GL.settings or GL.settings.birthdayAsked then return end
    local guild = GL.db and IsInGuild() and GL:Guild()
    local me = guild and guild.members[GL:PlayerName()]
    if not me then return end   -- roster not read yet: ask at the next login instead
    if InCombatLockdown and InCombatLockdown() then return end
    GL.settings.birthdayAsked = true
    if me.birthday then return end
    definePopups()
    askText("When is your birthday? Optional. It goes in Tabard so the other Tabard users in the guild know when it is. For example 4 Nov or 11/04; leave it empty to skip.", "", function(text)
        if strtrim(text or "") == "" then return end
        local m, d = GL:ParseMonthDay(text)
        if not m then GL:Print("that is not a day I understand; use 4 Nov or 11/04. You can set it on your member card any time.") return end
        GL:SetBirthday(guild, me, m, d, "user")
        GL:Print("birthday set: " .. GL:FormatMonthDay(m, d) .. ". The other Tabard users in the guild will see it.")
    end)
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loginFrame:SetScript("OnEvent", function(self, _, isLogin)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    pcall(GL.InstallUnitMenus, GL)
    if isLogin then C_Timer.After(20, function() pcall(askOwnBirthday) end) end
    local mode = GL.settings and GL.settings.openOnLogin or LOGIN_DEFAULT
    if mode == "card" then
        -- At login the last-visit marker is set once the roster has been read (Summary.lua, 12 s); the card waits for it.
        C_Timer.After(isLogin and 13 or 6, function()
            if not (GL.db and IsInGuild()) then return end
            if InCombatLockdown and InCombatLockdown() then return end
            pcall(GL.ShowLoginCard, GL)
        end)
        return
    end
    C_Timer.After(6, function()
        if mode == "never" or not (GL.db and IsInGuild()) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if mode == "todo" then
            local guild = GL:Guild()
            local ok, items = pcall(function() return GL.TodoItems and GL:TodoItems(guild) or {} end)
            local open = 0
            if ok and type(items) == "table" then for _, item in ipairs(items) do if not item.handled then open = open + 1 end end end
            if open == 0 then return end
            -- opened by itself: counted apart from opening it by hand (Usage.lua)
            if GL.Usage then GL.Usage.auto = true end
            pcall(GL.ShowPage, GL, "todo")
        else
            if GL.Usage then GL.Usage.auto = true end
            pcall(GL.ToggleWindow, GL, true)
        end
        if GL.Usage then GL.Usage.auto = false end
    end)
end)
