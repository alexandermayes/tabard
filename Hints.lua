-- Tabard: main-name hints in chat
-- When an alt talks, the chat line shows whose alt it is: "[Ooh Woo (Check Myspeed)]: hi". Uses the client's
-- sender-name filter, so it works in every chat frame and with chat addons; the link behind the name still
-- carries the real character name. The client skips the filter while names are secret (boss encounters).
-- An alt group can carry a nickname (group.nick) that is shown instead of the main's name.

local ADDON_NAME, GL = ...

local Hints = {}
GL.Hints = Hints

local HINT_COLOR = "ff9d9d9d"

local function enabled()
    return GL.settings and GL.settings.hints ~= false and GL.db ~= nil
end

-- The text to show after this character's name, or nil.
function Hints:For(guild, name)
    if not (guild and name) then return nil end
    local member = guild.members[name]
    if not member then return nil end
    local parts = {}
    local main, group = GL:MainOf(guild, member)
    if group and main and main ~= member then parts[#parts + 1] = group.nick or main.name end
    if GL.IsNewcomer and GL:IsNewcomer(member) then parts[#parts + 1] = "new" end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

local function filter(event, decorated, text, senderName)
    if not enabled() then return nil end
    if type(senderName) ~= "string" or not GL:IsUsable(senderName) or not GL:IsUsable(decorated) then return nil end
    local short = GL:ShortName(senderName)
    if not short or short == GL:PlayerName() then return nil end
    local guild = GL:Guild()
    if not guild then return nil end
    local hint = Hints:For(guild, short)
    if not hint then return nil end
    return decorated .. " |c" .. HINT_COLOR .. "(" .. hint .. ")|r"
end

local function senderNameFilter(...)
    local ok, result = pcall(filter, ...)
    if ok then return result end
    return nil
end

local installed = false
function Hints:Install()
    if installed then return true end
    if ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter then
        ChatFrameUtil.AddSenderNameFilter(senderNameFilter)
        installed = true
    end
    return installed
end

function Hints:Command(rest)
    rest = string.lower(strtrim(rest or ""))
    if rest == "on" then GL.settings.hints = true
    elseif rest == "off" then GL.settings.hints = false
    elseif rest ~= "" then GL:Print("usage: /tabard hints on|off") return end
    GL:Print(string.format("main-name hints in chat are %s%s.", GL.settings.hints ~= false and "on" or "off",
        installed and "" or " (this client has no sender-name filter, so nothing is shown)"))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    if GL.settings and GL.settings.hints == nil then GL.settings.hints = true end
    Hints:Install()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
