-- Blood Pact: messages while a warlock summons.
-- For warlocks of Team Captain rank and above, and only while they are
-- channeling their own Ritual of Summoning:
--   * the player being summoned gets a whisper telling them to accept, and
--   * if the portal is still short of clickers a few seconds after it
--     appears, one line in raid (or party) chat names the group members
--     standing nearby who aren't clicking.
-- Both follow the warlock's own cast and never fire on a timer or for anyone
-- else's summon. Each has its own off switch and its own editable text.
local _, ns = ...
local C = {}
ns.SummonCall = C

local U, W = ns.U, ns.W

C.WAIT = 4               -- seconds into the channel before calling anyone out
C.MAX_NAMES = 3
C.CHAT_MAX = 255
C.CALL_MAX = 200         -- letters the callout box takes
C.TELL_MAX = 500         -- letters the whisper box takes (sent as up to 2 whispers)
C.DEFAULT_CALL = "Yo! Click the purple oval! I see you {names} doing nothing!"
C.DEFAULT_TELL = "Abra-cadabra-fel-o-rama, bibbidi-bobbidi-doom, get your pixelated posterior out of the tavern and into this room! "
    .. "Shazam-a-ling-ding, shadowy-wing, purple-portal-thingy-ding - stop dancing in town, click the portal now, "
    .. "or I'm summoning you straight into a pack of angry elite mobs!"

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- Cut a long message into pieces the chat box takes, at the end of a
-- sentence when there is one, else at a space.
function C.Split(text, max)
    max = max or C.CHAT_MAX
    local parts = {}
    text = tostring(text or ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    while #text > max do
        local cut
        for i = max, math.floor(max / 3), -1 do
            local ch = text:sub(i, i)
            if (ch == "." or ch == "!" or ch == "?") and text:sub(i + 1, i + 1) == " " then cut = i; break end
        end
        if not cut then
            for i = max, 2, -1 do
                if text:sub(i, i) == " " then cut = i - 1; break end
            end
        end
        cut = cut or max
        parts[#parts + 1] = text:sub(1, cut)
        text = text:sub(cut + 1):match("^%s*(.-)%s*$")
    end
    if text ~= "" then parts[#parts + 1] = text end
    return parts
end

-- "Solo", "Solo & Holly", "Solo, Holly & Rex"; nobody named = "all".
function C.Names(names)
    local n = math.min(#names, C.MAX_NAMES)
    if n == 0 then return "all" end
    if n == 1 then return names[1] end
    return table.concat(names, ", ", 1, n - 1) .. " & " .. names[n]
end

-- The line for raid chat: {names} in the text becomes who is standing idle.
function C.Callout(template, names)
    local who = C.Names(names)
    local text = tostring(template or ""):gsub("{names}", function() return who end)
    text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
    return text:sub(1, C.CHAT_MAX)
end

-- Who to call out. members = { { name =, near =, clicking =, summoned = }, ... }
-- -> names of group members standing near the warlock and not clicking, and
--    how many are clicking.
function C.Idle(members)
    local idle, clicking = {}, 0
    for _, m in ipairs(members) do
        if m.clicking then
            clicking = clicking + 1
        elseif m.near and not m.summoned and m.name then
            idle[#idle + 1] = m.name
        end
    end
    table.sort(idle)
    return idle, clicking
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
-- Warlocks who can summon, Team Captain and above.
function C.Allowed()
    return ns.Summon.IAmWarlock() and ns.RBAC.ICan("schedule")
end

local function opt(key) return ns.Char()[key] ~= false end       -- on unless switched off
local function textOf(key, default)
    local t = ns.Char()[key]
    if type(t) ~= "string" or t:match("^%s*$") then return default end
    return t
end
function C.CallText() return textOf("summonCallText", C.DEFAULT_CALL) end
function C.TellText() return textOf("summonTellText", C.DEFAULT_TELL) end

local function isRitual(spellID)
    if spellID == ns.SummonQueue.SPELL_ID then return true end
    if type(spellID) ~= "number" then return false end
    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spellID)
        if ok then name = n end
    end
    if not name and type(GetSpellInfo) == "function" then
        local ok, n = pcall(GetSpellInfo, spellID)
        if ok then name = n end
    end
    return name ~= nil and name == ns.SummonQueue.SpellName()
end

-- Inside an instance the game refuses addon chat: say so once, not every ritual.
local lastWarned = -1000
local function send(msg, kind, target)
    local ok, why = ns.Chat(msg, kind, target)
    if not ok and why == "locked" and GetTime() - lastWarned > 300 then
        lastWarned = GetTime()
        ns.Print(ns.CHAT_LOCKED .. " Your summon messages weren't sent.")
    end
    return ok
end

-- Who this ritual is for: the name just clicked in the summon queue, else my
-- target if they are in my group.
local function summoned()
    local click = ns.SummonQueue.lastClick
    if click and GetTime() - click.at <= 6 then return click.name, click.guid end
    local name = UnitName("target")
    if type(name) ~= "string" then return nil end
    for _, g in ipairs(ns.SummonQueue.Group()) do
        if g.name == name then return g.name, g.guid end
    end
    return nil
end

-- The ritual I'm in the middle of: { at, name, guid, up, over }.
local ritual = { at = -100, over = true }
local told = {}            -- [name] = when I last whispered them

-- Group members near me, and whether each is channeling on the portal.
local function members(summonedGuid)
    local out, canSee = {}, type(UnitChannelInfo) == "function"
    local ritual = ns.SummonQueue.SpellName()
    for _, g in ipairs(ns.SummonQueue.Group()) do
        local near = false
        if type(UnitInRange) == "function" then
            local ok, inRange, checked = pcall(UnitInRange, g.unit)
            near = ok and inRange == true and checked ~= false
        end
        local clicking = false
        if canSee then
            local ok, spell = pcall(UnitChannelInfo, g.unit)
            clicking = ok and spell ~= nil and spell == ritual
        end
        out[#out + 1] = { name = g.name, near = near, clicking = clicking, summoned = g.guid == summonedGuid }
    end
    return out, canSee
end

-- A few seconds after the portal is up: if it is still short of clickers,
-- one line in raid or party chat.
function C.Check(r)
    if r ~= ritual or r.over or not opt("summonCall") or ns.mock then return end
    if not (IsInGroup and IsInGroup()) then return end
    local list, canSee = members(r.guid)
    local idle, clicking = C.Idle(list)
    if canSee and clicking >= ns.Summon.HELPERS then return end      -- the portal has its clickers
    -- If the game won't say who is clicking, nobody is named.
    local msg = C.Callout(C.CallText(), canSee and idle or {})
    if msg == "" then return end
    send(msg, (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
end

local function whisper(name)
    if not opt("summonTell") or ns.mock or GetTime() - (told[name] or -1000) <= 60 then return end
    told[name] = GetTime()
    for i, part in ipairs(C.Split(C.TellText())) do
        if i > 2 then break end
        if i == 1 then
            send(part, "WHISPER", U.ShortName(name))
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0.4, function() send(part, "WHISPER", U.ShortName(name)) end)
        end
    end
end

-- My Ritual of Summoning, as the game reports it: the cast starts, then the
-- portal is up (the cast succeeds, or my channel on it begins).
local function onCast(portalUp)
    return function(unit, _, spellID)
        if unit ~= "player" or not isRitual(spellID) or not C.Allowed() then return end
        if ritual.over or GetTime() - ritual.at > 15 then
            local name, guid = summoned()
            ritual = { at = GetTime(), name = name, guid = guid }
            if name then whisper(name) end
        end
        if portalUp and not ritual.up then
            ritual.up = true
            local r = ritual
            if C_Timer and C_Timer.After then C_Timer.After(C.WAIT, function() C.Check(r) end) end
        end
    end
end
local function onStop(unit, _, spellID)
    if unit == "player" and (spellID == nil or isRitual(spellID)) then ritual.over = true end
end
ns.On("UNIT_SPELLCAST_START", onCast(false))
ns.On("UNIT_SPELLCAST_SUCCEEDED", onCast(true))
ns.On("UNIT_SPELLCAST_CHANNEL_START", onCast(true))
ns.On("UNIT_SPELLCAST_CHANNEL_STOP", onStop)
ns.On("UNIT_SPELLCAST_INTERRUPTED", onStop)

---------------------------------------------------------------------------
-- The two messages and their switches
---------------------------------------------------------------------------
local panel

local function build()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(470, 300)
    -- Above the main window (which is on DIALOG), so nothing of it shows through.
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    if f.SetToplevel then f:SetToplevel(true) end
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:EnableMouse(true)
    W.Fill(f, { W.C.bg[1], W.C.bg[2], W.C.bg[3], 1 })
    W.Border(f)
    W.Text(f, "Summon messages", "GameFontNormal"):SetPoint("TOPLEFT", 10, -9)
    W.Button(f, "X", 22, 20, function() f:Hide() end):SetPoint("TOPRIGHT", -6, -6)
    W.Line(f, -32)

    f.call = W.Check(f, "Call out group members who aren't clicking my portal (raid or party chat)", function(on)
        ns.Char().summonCall = on
    end)
    f.call:SetPoint("TOPLEFT", 12, -44)
    f.callBox = W.Edit(f, 446, C.CALL_MAX)
    f.callBox:SetPoint("TOPLEFT", 12, -68)
    f.callBox:HookScript("OnEditFocusLost", function(self) ns.Char().summonCallText = self:GetText() end)
    local hint = W.Text(f, ("{names} becomes who is standing near you and not clicking. Sent once, %d seconds after your portal appears, only if it is still short of clickers."):format(C.WAIT), "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -96)
    hint:SetWidth(446)
    hint:SetHeight(28)                  -- two lines, so the next row never moves up into it
    hint:SetJustifyV("TOP")
    hint:SetWordWrap(true)

    f.tell = W.Check(f, "Whisper the player I'm summoning when my ritual starts", function(on)
        ns.Char().summonTell = on
    end)
    f.tell:SetPoint("TOPLEFT", 12, -140)
    local bg = CreateFrame("Frame", nil, f)
    bg:SetPoint("TOPLEFT", 12, -164)
    bg:SetSize(446, 84)
    W.Panel(bg)
    f.tellBox = CreateFrame("EditBox", nil, bg)
    f.tellBox:SetMultiLine(true)
    f.tellBox:SetFontObject(W.F.bodySm)
    f.tellBox:SetPoint("TOPLEFT", 6, -6)
    f.tellBox:SetPoint("BOTTOMRIGHT", -6, 6)
    f.tellBox:SetAutoFocus(false)
    f.tellBox:SetMaxLetters(C.TELL_MAX)
    f.tellBox:SetScript("OnEscapePressed", f.tellBox.ClearFocus)
    f.tellBox:SetScript("OnEditFocusLost", function(self) ns.Char().summonTellText = self:GetText() end)

    W.Button(f, "Use the standard messages", 190, 22, function()
        ns.Char().summonCallText, ns.Char().summonTellText = nil, nil
        f.callBox:SetText(C.CallText())
        f.tellBox:SetText(C.TellText())
    end):SetPoint("BOTTOMLEFT", 12, 10)
    local foot = W.Text(f, "A long whisper is sent as two.", "GameFontDisableSmall")
    foot:SetPoint("BOTTOMLEFT", 212, 15)
    f:Hide()
    return f
end

function C.ShowSettings()
    if not C.Allowed() then
        ns.Print("Summon messages are for warlocks of Team Captain rank and above.")
        return false
    end
    panel = panel or build()
    panel.call:SetChecked(opt("summonCall"))
    panel.tell:SetChecked(opt("summonTell"))
    panel.callBox:SetText(C.CallText())
    panel.tellBox:SetText(C.TellText())
    panel:Show()
    if panel.Raise then panel:Raise() end
    return true
end
