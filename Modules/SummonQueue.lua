-- Speakeasy: the warlock's summon queue.
-- Anyone who wants a summon types the keyword ("123" unless the warlock
-- changes it) in raid, party or guild chat, or whispers it to the warlock.
-- The warlock's addon puts the name in a small list; clicking a name casts
-- Ritual of Summoning on that player. Requests made from the Summon tab join
-- the same list.
-- The click is the game's own secure button (one click, one cast), so the
-- player casts every summon themselves. Nothing is cast, whispered or invited
-- without a click, and the game doesn't let the list change during combat.
local _, ns = ...
local Q = {}
ns.SummonQueue = Q

local U, W = ns.U, ns.W

Q.KEY = "123"           -- the usual word for "summon me"
Q.KEY_MAX = 12
Q.TTL = 1800            -- a name waits at most 30 minutes
Q.ROWS = 8              -- names shown at once
Q.SPELL_ID = 698        -- Ritual of Summoning
Q.list = {}             -- { name, guid, at, src, unit, called }

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- A keyword the warlock typed: one short word, or nil when it won't do.
function Q.CleanKey(s)
    if type(s) ~= "string" then return nil end
    s = s:lower():match("^%s*(.-)%s*$")
    if #s < 1 or #s > Q.KEY_MAX or s:find("%s") then return nil end
    return s
end

-- Is this chat line a summon request? The keyword alone, or the keyword and
-- a few words after it ("123 please"). "1234" and long sentences are not.
function Q.Matches(msg, key)
    if type(msg) ~= "string" or type(key) ~= "string" or key == "" then return false end
    local text = msg:lower():match("^%s*(.-)%s*$")
    key = key:lower()
    if text == key then return true end
    if #text > #key + 20 or text:sub(1, #key) ~= key then return false end
    return text:sub(#key + 1, #key + 1):match("[%s%p]") ~= nil
end

-- Add a name once. -> the entry, and whether it is new
function Q.Add(list, name, guid, now, src)
    local lower = name:lower()
    for _, e in ipairs(list) do
        if (guid and e.guid == guid) or e.name:lower() == lower then return e, false end
    end
    local e = { name = name, guid = guid, at = now, src = src }
    list[#list + 1] = e
    return e, true
end

function Q.Remove(list, entry)
    for i, e in ipairs(list) do
        if e == entry then table.remove(list, i); return true end
    end
    return false
end

-- Drop names that have waited too long. -> how many went
function Q.Prune(list, now, ttl)
    local gone = 0
    for i = #list, 1, -1 do
        if now - list[i].at > (ttl or Q.TTL) then table.remove(list, i); gone = gone + 1 end
    end
    return gone
end

-- Give each name its place in my group ("raid7", "party2"), or none.
--   group = { { unit =, guid =, name = }, ... }
function Q.Assign(list, group)
    for _, e in ipairs(list) do
        e.unit = nil
        local lower = e.name:lower()
        for _, g in ipairs(group) do
            if (e.guid and g.guid == e.guid) or (g.name and g.name:lower() == lower) then
                e.unit = g.unit
                e.guid = e.guid or g.guid
                break
            end
        end
    end
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local panel
local dirty = false        -- the list changed while the game had it locked (combat)
local wantShown = false    -- a request came in during combat: open afterwards
local dismissed = {}       -- [asker guid] = time of the board request I removed

function Q.Key() return Q.CleanKey(ns.Char().summonKey) or Q.KEY end

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function spellName()
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, Q.SPELL_ID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, Q.SPELL_ID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return "Ritual of Summoning"
end

-- Everyone in my party or raid except me.
local function group()
    local out = {}
    if not (IsInGroup and IsInGroup()) then return out end
    local raid = IsInRaid and IsInRaid()
    local me = ns.MyGUID()
    for i = 1, raid and 40 or 4 do
        local unit = (raid and "raid" or "party") .. i
        local guid = UnitGUID(unit)
        if guid and guid ~= me then
            out[#out + 1] = { unit = unit, guid = guid, name = UnitName(unit) }
        end
    end
    return out
end

Q.Group, Q.SpellName = group, spellName

local function inGroup(guid, name)
    local lower = name:lower()
    for _, g in ipairs(group()) do
        if (guid and g.guid == guid) or (g.name and g.name:lower() == lower) then return true end
    end
    return false
end

local refresh

-- Someone asked. Only guild members and people already in my group are
-- listed, so a stranger's whisper can't fill the queue.
function Q.Request(name, guid, src, at)
    if type(name) ~= "string" or name == "" then return false end
    if guid and guid == ns.MyGUID() then return false end
    if not ((guid and ns.roster.byGUID[guid]) or ns.GUIDForName(name) or inGroup(guid, name)) then return false end
    guid = guid or ns.GUIDForName(name)
    local _, new = Q.Add(Q.list, name, guid, at or ns.Now(), src)
    if not new then return false end
    if inCombat() then
        dirty, wantShown = true, true
        ns.Print(U.Safe(name, 40) .. " asked for a summon. The queue updates when you leave combat.")
    else
        Q.Show(true)
    end
    return true
end

local function heard(src)
    return function(text, sender, _, _, _, _, _, _, _, _, _, guid)
        if not ns.Summon.IAmWarlock() then return end
        if not Q.Matches(text, Q.Key()) then return end
        if type(sender) ~= "string" or sender == "" then return end
        if type(guid) ~= "string" or guid == "" then guid = nil end
        local name = (guid and ns.NameForGUID(guid)) or U.ShortName(sender)
        if name == UnitName("player") then return end
        Q.Request(name, guid, src)
    end
end
for event, src in pairs({ CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid", CHAT_MSG_RAID_WARNING = "raid",
    CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party", CHAT_MSG_INSTANCE_CHAT = "raid",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "raid", CHAT_MSG_WHISPER = "whisper", CHAT_MSG_GUILD = "guild" }) do
    ns.On(event, heard(src))
end

-- Requests made from the Summon tab, for any warlock or for me, join the list.
local function mergeBoard()
    if not ns.Summon.IAmWarlock() then return false end
    local me, added = ns.MyGUID(), false
    for _, r in ipairs(ns.Summon.Open(ns.Now())) do
        if r.from ~= me and (r.to == nil or r.to == me) and dismissed[r.from] ~= r.at then
            local name = ns.NameForGUID(r.from)
            if name and Q.Request(name, r.from, "board", r.at) then added = true end
        end
    end
    return added
end

-- Standing next to me already: the summon is done.
local function arrived(e)
    if not e.unit or type(UnitInRange) ~= "function" then return false end
    local ok, near, checked = pcall(UnitInRange, e.unit)
    return ok and near == true and checked ~= false
end

function Q.Drop(entry)
    if not Q.Remove(Q.list, entry) then return end
    -- Don't let the same Summon-tab request put the name straight back.
    local r = entry.guid and ns.Summon.requests[entry.guid]
    if r then dismissed[entry.guid] = r.at end
    refresh()
end

local function classColor(guid)
    local m = guid and ns.roster.byGUID[guid]
    local c = m and m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
    if c then return c.r, c.g, c.b end
    return W.C.text[1], W.C.text[2], W.C.text[3]
end

local function ago(seconds)
    if seconds < 60 then return "now" end
    return math.floor(seconds / 60) .. "m"
end

refresh = function()
    if not panel then return end
    local n = #Q.list
    panel.title:SetText(n > 0 and ("Summon queue (" .. n .. ")") or "Summon queue")
    if inCombat() then
        -- The game locks these buttons during combat. Leave them as they are.
        dirty = true
        panel.note:SetText("In combat: the list updates when it ends.")
        return
    end
    dirty = false
    Q.Assign(Q.list, group())
    local spell, now = spellName(), ns.Now()
    for i, b in ipairs(panel.rows) do
        local e = Q.list[i]
        b.entry = e
        b:SetAttribute("unit", e and e.unit or nil)
        b:SetAttribute("type1", e and e.unit and "spell" or nil)
        b:SetAttribute("spell1", e and e.unit and spell or nil)
        b:SetAttribute("type2", e and e.unit and "target" or nil)
        b:SetShown(e ~= nil)
        b.x:SetShown(e ~= nil)
        local guildmate = e and e.guid and ns.roster.byGUID[e.guid] ~= nil
        b.inv:SetShown(e ~= nil and not e.unit and guildmate)
        if e then
            b.name:SetText(U.Safe(e.name, 24))
            b.name:SetTextColor(classColor(e.guid))
            b.info:SetText(e.unit and ((e.called and "summoning  " or "") .. ago(now - e.at)) or (guildmate and "" or "not in group"))
        end
    end
    panel.empty:SetShown(n == 0)
    panel.empty:SetText(('Nobody is waiting. Anyone can type "%s" in raid, party or guild chat, or whisper it to you.'):format(Q.Key()))
    panel.note:SetText(n > Q.ROWS and ("+" .. (n - Q.ROWS) .. " more waiting") or (n > 0 and "Left-click: summon.  Right-click: target." or ""))
    if not panel.key:HasFocus() then panel.key:SetText(Q.Key()) end
    panel.msgs:SetShown(ns.SummonCall.Allowed())
end

local function build()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(268, 40 + Q.ROWS * 22 + 58)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    local at = ns.Char().summonQueueAt
    if type(at) == "table" and type(at[1]) == "string" then
        f:SetPoint(at[1], UIParent, at[2] or at[1], at[3] or 0, at[4] or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 420, 80)
    end
    W.Glass(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not inCombat() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        if point then ns.Char().summonQueueAt = { point, rel, x, y } end
    end)

    f.title = W.Text(f, "Summon queue", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -9)
    W.Button(f, "X", 22, 20, function()
        if inCombat() then ns.Print("The game locks the summon queue during combat. Close it afterwards.") return end
        wantShown = false
        f:Hide()
    end):SetPoint("TOPRIGHT", -6, -6)
    -- Team Captains and above: the messages sent while they summon.
    f.msgs = W.Button(f, "Messages", 70, 20, function() ns.SummonCall.ShowSettings() end)
    f.msgs:SetPoint("TOPRIGHT", -32, -6)
    W.Line(f, -32)

    f.rows = {}
    for i = 1, Q.ROWS do
        local y = -38 - (i - 1) * 22
        -- The game's secure button: the click itself casts, as an action bar button does.
        local b = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
        b:SetSize(226, 20)
        b:SetPoint("TOPLEFT", 8, y)
        b:RegisterForClicks("AnyUp", "AnyDown")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
        b.name = W.Text(b, "", "GameFontHighlightSmall")
        b.name:SetPoint("LEFT", 6, 0)
        b.info = W.Text(b, "", "GameFontDisableSmall")
        b.info:SetPoint("RIGHT", -6, 0)
        b.info:SetJustifyH("RIGHT")
        b:HookScript("PostClick", function(self, button)
            if button == "LeftButton" and self.entry and self.entry.unit then
                -- Who the next Ritual of Summoning is for (Modules/SummonCall.lua).
                Q.lastClick = { name = self.entry.name, guid = self.entry.guid, at = GetTime() }
                if not self.entry.called then
                    self.entry.called = ns.Now()
                    self.info:SetText("summoning")
                end
            end
        end)
        b.inv = W.Button(f, "Invite", 52, 18, function()
            local e = b.entry
            if not (e and e.guid) then return end
            local ok, why = ns.Summon.Invite(e.guid)
            if ok == "suggested" then
                ns.Print(("You don't lead this group, so %s was asked to invite %s."):format(U.Safe(why, 40), U.Safe(e.name, 40)))
            else
                ns.Print(ok and ("Invited " .. U.Safe(e.name, 40) .. ".") or (why or "The game didn't send the invite."))
            end
        end)
        b.inv:SetPoint("TOPLEFT", 150, y - 1)
        b.inv:SetFrameLevel(b:GetFrameLevel() + 2)
        b.x = W.Button(f, "x", 20, 20, function()
            if b.entry then Q.Drop(b.entry) end
        end)
        b.x:SetPoint("TOPLEFT", 238, y)
        b:Hide(); b.inv:Hide(); b.x:Hide()
        f.rows[i] = b
    end

    f.empty = W.Text(f, "", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 12, -46)
    f.empty:SetWidth(244)
    f.empty:SetWordWrap(true)

    f.note = W.Text(f, "", "GameFontDisableSmall")
    f.note:SetPoint("BOTTOMLEFT", 10, 36)
    W.Text(f, "Keyword", "GameFontHighlightSmall"):SetPoint("BOTTOMLEFT", 10, 13)
    f.key = W.Edit(f, 70, Q.KEY_MAX)
    f.key:SetPoint("BOTTOMLEFT", 64, 8)
    f.key:HookScript("OnEditFocusLost", function(self)
        local key = Q.CleanKey(self:GetText())
        if key then ns.Char().summonKey = key end
        self:SetText(Q.Key())
        if panel and panel.empty:IsShown() then
            panel.empty:SetText(('Nobody is waiting. Anyone can type "%s" in raid, party or guild chat, or whisper it to you.'):format(Q.Key()))
        end
    end)
    W.Button(f, "Clear list", 80, 22, function()
        for i = #Q.list, 1, -1 do
            local e = Q.list[i]
            local r = e.guid and ns.Summon.requests[e.guid]
            if r then dismissed[e.guid] = r.at end
            table.remove(Q.list, i)
        end
        refresh()
    end):SetPoint("BOTTOMRIGHT", -8, 8)
    f:Hide()
    return f
end

-- Open the queue. quiet = no chat lines.
function Q.Show(quiet)
    if not ns.Summon.IAmWarlock() then
        if not quiet then
            ns.Print('Only a warlock gets a summon queue. To ask for a summon, type "123" in raid, party or guild chat, or use the Summon tab.')
        end
        return false
    end
    if inCombat() then
        wantShown, dirty = true, true
        if not quiet then ns.Print("The summon queue opens when you leave combat.") end
        return false
    end
    panel = panel or build()
    panel:Show()
    refresh()
    return true
end

function Q.IsShown() return panel ~= nil and panel:IsShown() end

ns.On("PLAYER_REGEN_ENABLED", function()
    if wantShown then
        wantShown = false
        Q.Show(true)
    elseif dirty then
        refresh()
    end
end)
ns.On("GROUP_ROSTER_UPDATE", function() if Q.IsShown() then refresh() end end)

-- Every few seconds: pick up Summon-tab requests, drop names that have
-- arrived or waited too long.
function Q.Tick()
    local changed = mergeBoard()
    if #Q.list == 0 then return end
    if Q.Prune(Q.list, ns.Now()) > 0 then changed = true end
    Q.Assign(Q.list, group())
    for i = #Q.list, 1, -1 do
        if arrived(Q.list[i]) then table.remove(Q.list, i); changed = true end
    end
    if changed or Q.IsShown() then refresh() end
end
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(3, Q.Tick) end
