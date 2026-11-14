-- Tabard: the secure Invite button
-- Typing /ginvite in chat fails on WoW Forever whenever a chat addon (Prat) is loaded: the edit box is tainted,
-- so Blizzard's own parser runs tainted and the invite is refused. An addon may not call C_GuildInfo.Invite,
-- open the Add Member box or put a line into the chat box either. What does work is a SecureActionButton with a
-- "/ginvite Name" macro, clicked by the player (the way the member card promotes). So Tabard keeps one such
-- button, arms it with a name and shows it; the player's click, or a key bound to the button, sends the invite.
-- Arming comes from a whisper by someone outside the guild, from "/tabard invite Name", from the unit right-click
-- menu and from the key binding. Nothing is ever sent from a timer; the timer only hides the bar again.

local ADDON_NAME, GL = ...
local Invite = { armedName = nil, lastArmed = nil, lastWhisperer = nil, pending = nil, parkLater = false }
GL.Invite = Invite

local HIDE_AFTER = 60   -- seconds the bar stays up before it hides itself

BINDING_HEADER_TABARD = "Tabard"
_G["BINDING_NAME_CLICK TabardInviteButton:LeftButton"] = "Invite the last whisperer to the guild"

local frame, button

-- A name safe to put after "/ginvite ": no colour codes, no control characters, one line, not a command.
local function cleanName(name)
    if not GL:IsUsable(name) or type(name) ~= "string" then return nil end
    name = string.gsub(name, "|c%x%x%x%x%x%x%x%x", "")
    name = string.gsub(name, "|r", "")
    name = string.gsub(name, "[%c|]", "")
    name = strtrim((string.gsub(name, "%s+", " ")))
    if name == "" or #name > 60 or string.find(name, "^/") then return nil end
    return GL:ShortName(name)   -- same realm only; a guild cannot invite across realms here
end

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- The secure button is always shown (a key binding only clicks a shown button); parked off screen when idle.
local function park()
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", UIParent, "TOPRIGHT", 400, 400)
    button:SetAlpha(0)
end

local function place()
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 8)
    button:SetAlpha(1)
end

local function build()
    if frame then return true end
    local ok, f = pcall(CreateFrame, "Frame", "TabardUIInviteFrame", UIParent, "TooltipBackdropTemplate")
    if not (ok and f) then
        f = CreateFrame("Frame", "TabardUIInviteFrame", UIParent)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.85)
    end
    frame = f
    frame:SetSize(380, 58)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -160)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.text:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -8)
    frame.text:SetPoint("RIGHT", frame, "RIGHT", -28, 0)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetWordWrap(false)
    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    frame.close:SetScript("OnClick", function() Invite:Disarm() end)
    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.hint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 10)
    frame.hint:SetText("your click sends it")

    button = CreateFrame("Button", "TabardInviteButton", UIParent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    button:SetSize(240, 24)
    button:SetFrameStrata("DIALOG")
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "")
    -- A bound key pressed with nothing armed invites the last whisperer: the name goes on just before the
    -- secure click runs (allowed outside combat).
    button:SetScript("PreClick", function()
        if Invite.armedName or inCombat() then return end
        local name = Invite.lastWhisperer
        if name then Invite:Arm(name, name .. " whispered you last.") end
    end)
    button:HookScript("OnClick", function()
        local name = Invite.armedName
        if not name then return end
        GL:Print("invited " .. name .. " to the guild (the game's own line confirms it).")
        Invite:Disarm()
        if GL.RequestScan then
            GL:RequestScan(true)
            C_Timer.After(3, function() GL:RequestScan(true) end)
        end
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Click to send the guild invite. The game only lets you, not an addon, invite, so this button runs /ginvite as your own click. Typing /ginvite in chat is refused while a chat addon is loaded.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    park()
    return true
end

-- Arms the button for `name` and shows the bar; `why` is the line above the button. In combat the name waits
-- until combat ends (the secure button cannot be changed in combat).
function Invite:Arm(name, why)
    name = cleanName(name)
    if not name then return false end
    if not build() then return false end
    if inCombat() then
        self.pending = { name = name, why = why }
        GL:Print("in combat; the Invite button for " .. name .. " comes up when combat ends.")
        return true
    end
    button:SetAttribute("macrotext", "/ginvite " .. name)
    button:SetText("Invite " .. name)
    place()
    frame.text:SetText(why or (name .. " is not in the guild."))
    frame:Show()
    self.armedName, self.lastArmed, self.pending = name, name, nil
    local stamp = GetTime()
    self.armedAt = stamp
    C_Timer.After(HIDE_AFTER, function()
        if self.armedName == name and self.armedAt == stamp then self:Disarm() end
    end)
    return true
end

-- Hides the bar and clears the button (the clearing waits for the end of combat when needed).
function Invite:Disarm()
    self.armedName, self.pending = nil, nil
    if not frame then return end
    frame:Hide()
    if inCombat() then self.parkLater = true return end
    button:SetAttribute("macrotext", "")
    park()
    self.parkLater = false
end

-- A whisper from someone who is not in the guild offers the invite (Settings: "Offer an Invite button...").
local function onWhisper(text, sender)
    if not (GL.db and GL.settings and GL.settings.inviteBar ~= false) then return end
    if not IsInGuild() then return end
    if CanGuildInvite and not CanGuildInvite() then return end
    local name = cleanName(sender)
    if not name or name == GL:PlayerName() then return end
    local guild = GL:Guild()
    if not guild or guild.members[name] then return end
    Invite.lastWhisperer = name
    local why = name .. " whispered you and is not in the guild."
    if GL.IsBanned and GL:IsBanned(guild, name) then why = "|cffff5555" .. name .. " is on the ban list.|r" end
    Invite:Arm(name, why)
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_WHISPER")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, text, sender)
    if event == "CHAT_MSG_WHISPER" then
        local ok, err = pcall(onWhisper, text, sender)
        if not ok then GL:Print("could not offer an invite: " .. tostring(err)) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Invite.parkLater and button then Invite:Disarm() end
        local pending = Invite.pending
        if pending then Invite.pending = nil Invite:Arm(pending.name, pending.why) end
    elseif event == "PLAYER_LOGIN" then
        pcall(build)   -- so the key binding has its button from the start
    end
end)

-- /tabard invite Name   (no name: what is armed)
function Invite:Command(rest)
    rest = strtrim(rest or "")
    if rest == "" then
        if self.armedName then GL:Print("the Invite button is armed for " .. self.armedName .. "; click it or press the bound key.")
        elseif self.lastWhisperer then GL:Print("nothing armed. Last whisper from outside the guild: " .. self.lastWhisperer .. ". |cffffffff/tabard invite " .. self.lastWhisperer .. "|r arms the button.")
        else GL:Print("usage: |cffffffff/tabard invite NAME|r puts up an Invite button for that player; your click sends the invite.") end
        return
    end
    local guild = GL:Guild()
    local name = cleanName(rest)
    if not name then GL:Print("that does not look like a character name.") return end
    if guild and guild.members[name] then GL:Print(name .. " is already in the guild.") return end
    if not self:Arm(name, "From /tabard invite.") then GL:Print("could not arm the Invite button.") end
end
