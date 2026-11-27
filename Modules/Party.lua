-- Blood Pact: the Party button. A raid leader or assist presses it and the
-- raid gets a raid warning ("Take a drink!"), the same thing /rw does, so
-- everyone sees it with or without the addon. Raiders with Blood Pact also
-- hear the line spoken by text to speech.
--
-- The lines are a sound board the guild owns: a starter list, plus whatever
-- Team Captains add or switch off. Nothing here is a recorded clip, so there
-- is nothing copyrighted to ship.
local _, ns = ...
local P = {}
ns.Party = P

local U, RBAC, Red = ns.U, ns.RBAC, ns.Reducer

P.COOLDOWN = 10        -- seconds between presses
P.MAX_LINE = 60
P.DEFAULT = { "Take a drink!", "Take a shot!", "Take a puff!", "Bottoms up!", "Cheers, Blood Pact!", "Holler and swaller!" }
P.HOWTO = {
    "Party is for raid nights. The raid leader and assists press it; the whole raid sees a raid warning with the line, the same as typing /rw.",
    "It works in a five-player party too: the party leader presses it. The line goes to party chat, and party members with Blood Pact also get the big on-screen text.",
    "Raiders who have Blood Pact also hear the line spoken. Untick \"Play party sounds\" to keep it quiet on your end.",
    "Word of the night: type a word and press Announce. From then on, whenever anyone types that word in raid or party chat, the next line goes out on its own, with who said it. It listens on the screen of the leader who announced it.",
    "Said on voice and not typed? The addon can't hear voice chat, so press Next line. Clear the box and press Announce to stop listening.",
    "Next plays the lines in order. Random picks one. Click any line to play that one.",
    "Announce the drink sends the raid tonight's Drink of the Night, set on the Raids tab.",
    "Team Captains and above can add lines or switch them off, and the list syncs to the guild.",
    "Inside a raid instance the game stops addons sending chat. There the button puts the /rw line in your chat box and you press Enter. The voice line can't reach others in there.",
}

---------------------------------------------------------------------------
-- Pure rules
---------------------------------------------------------------------------
-- Trim a line to something safe to announce. -> text, or nil and why.
function P.Clean(text)
    text = tostring(text or ""):gsub("|", ""):gsub("%c", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if text == "" then return nil, "Type a line first." end
    if #text > P.MAX_LINE then return nil, ("Keep it to %d letters."):format(P.MAX_LINE) end
    return text
end

-- The sound board: the starter lines the guild hasn't switched off, then the
-- guild's own, in the order they were added.
function P.Lines(st)
    local set, out = st and st.partyLines or {}, {}
    local seen = {}
    for _, line in ipairs(P.DEFAULT) do
        seen[line] = true
        if not (set[line] and set[line].on == false) then out[#out + 1] = line end
    end
    local own = {}
    for line, v in pairs(set) do
        if v.on and not seen[line] then own[#own + 1] = { line = line, t = v.t or 0 } end
    end
    table.sort(own, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.line < b.line
    end)
    for _, o in ipairs(own) do out[#out + 1] = o.line end
    return out
end

-- The line after `last` in the list (wraps round). nil for an empty list.
function P.After(lines, last)
    if #lines == 0 then return nil end
    for i, line in ipairs(lines) do
        if line == last then return lines[i % #lines + 1] end
    end
    return lines[1]
end

-- May this player press it? inGroup, leads = leader or assist, since = seconds
-- since their last press.
function P.CanPress(inGroup, leads, since)
    if not inGroup then return false, "Join a raid or party first." end
    if not leads then return false, "Only the raid leader and assists can press Party, the same as /rw. In a party, the party leader." end
    if since < P.COOLDOWN then return false, ("Give it %d more seconds."):format(math.ceil(P.COOLDOWN - since)) end
    return true
end

function P.WordLine(word) return "The word of the night is: " .. word end

-- Did someone say the word? Whole word, any capitals: "wind" matches "Wind!"
-- and "the wind", not "window" or "rewind".
function P.Said(text, word)
    if type(text) ~= "string" or type(word) ~= "string" or word == "" then return false end
    local hay = " " .. text:lower():gsub("[^%w']", " ") .. " "
    local needle = word:lower():gsub("[^%w']", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if needle == "" then return false end
    return hay:gsub("%s+", " "):find(" " .. needle .. " ", 1, true) ~= nil
end

-- The raid warning when someone says it: who said it, then the next line.
function P.Caught(name, word, line)
    local full = name and (name .. " said " .. word .. ". " .. line) or line
    return #full <= P.MAX_LINE and full or line
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local lastPress = -100
local lastNote

local function prefs() return ns.Char() end

function P.Muted() return prefs().partyMute == true end
function P.SetMuted(on) prefs().partyMute = on and true or nil end

-- The group unit ("raid7", "party2") for a guildmate, or nil.
local function unitOf(guid)
    if not (IsInGroup and IsInGroup()) then return nil end
    local raid = IsInRaid and IsInRaid()
    for i = 1, raid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or 4 do
        local unit = (raid and "raid" or "party") .. i
        if UnitGUID(unit) == guid then return unit end
    end
    return nil
end

local function leads(unit)
    return (UnitIsGroupLeader and UnitIsGroupLeader(unit)) or (UnitIsGroupAssistant and UnitIsGroupAssistant(unit)) or false
end

-- The big centre-screen text, for a party: the game only shows raid warnings to raids.
local function banner(text)
    if P.Muted() then return end
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.1 })
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

local function speak(text)
    if P.Muted() then return end
    if ns.Caller and ns.Caller.Speak then ns.Caller.Speak(text) end
end

-- Announce one line to the group. -> true, or nil and why.
function P.Play(line)
    local why
    line, why = P.Clean(line)
    if not line then return nil, why end
    local ok
    ok, why = P.CanPress(IsInGroup and IsInGroup() or false, leads("player"), GetTime() - lastPress)
    if not ok then return nil, why end
    lastPress = GetTime()
    speak(line)
    -- The voice line for raiders with the addon. It rides the guild's addon channel;
    -- only people grouped with the sender act on it.
    if not ns.mock then ns.Sync.SendLive({ t = "PT", l = line }) end
    -- A raid gets a raid warning. A five-player party gets party chat, which always
    -- delivers; party members with the addon get the banner and the voice from it.
    local raid = IsInRaid and IsInRaid()
    local sent, how = ns.Chat(line, raid and "RAID_WARNING" or "PARTY")
    if not raid then banner(line) end
    if sent then
        lastNote = (raid and "Sent to the raid: " or "Sent to the party: ") .. line
    elseif how == "locked" and ChatFrame_OpenChat then
        -- Inside an instance the game refuses addon chat. Hand the player the line to send.
        ChatFrame_OpenChat((raid and "/rw " or "/p ") .. line)
        lastNote = "The game blocks addon chat in here. The line is in your chat box: press Enter."
    else
        lastNote = "It didn't go out. Type " .. (raid and "/rw " or "/p ") .. line
    end
    return true
end

function P.Next()
    local lines = P.Lines(Red.State())
    local line = P.After(lines, prefs().partyLast)
    if not line then return nil, "The sound board is empty. Add a line first." end
    local ok, why = P.Play(line)
    if ok then prefs().partyLast = line end      -- only the rotation moves the rotation along
    return ok, why
end

function P.Random()
    local lines = P.Lines(Red.State())
    if #lines == 0 then return nil, "The sound board is empty. Add a line first." end
    return P.Play(lines[math.random(#lines)])
end

-- Announce the word of the night, and start listening for it in raid and
-- party chat. An empty box stops the listening.
local listening           -- the word this client is listening for, or nil
function P.Listening() return listening end

function P.Word(word)
    if tostring(word or ""):match("^%s*$") then
        listening, prefs().partyWord = nil, nil
        lastNote = "Stopped listening for the word."
        return true
    end
    local clean, why = P.Clean(word)
    if not clean then return nil, why end
    if #clean > 24 then return nil, "Keep the word short." end
    local ok, why2 = P.Play(P.WordLine(clean))
    if not ok then return nil, why2 end
    prefs().partyWord = clean
    listening = clean
    lastNote = "Listening for \"" .. clean .. "\" in raid and party chat. Whoever types it sets off the next line."
    return true
end

-- Someone typed in raid or party chat. If it's the word, the leader who
-- announced it sends the next line. The cooldown keeps it from piling up.
local function heard(text, sender, _, _, _, _, _, _, _, _, _, guid)
    if not listening then return end
    if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return end
    if type(text) ~= "string" or not P.Said(text, listening) then return end
    if text:find("^The word of the night is") then return end                  -- the announcement itself
    if not (IsInGroup and IsInGroup()) or not leads("player") then return end
    if GetTime() - lastPress < P.COOLDOWN then return end
    local lines = P.Lines(Red.State())
    local line = P.After(lines, prefs().partyLast)
    if not line then return end
    local name = (type(guid) == "string" and guid ~= "" and ns.NameForGUID(guid)) or (type(sender) == "string" and U.ShortName(sender)) or nil
    local said = P.Caught(name, listening, line)
    if P.Play(said) then prefs().partyLast = line end
    P.Refresh()
end
for _, event in ipairs({ "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
    ns.On(event, heard)
end
ns.On("GROUP_LEFT", function() listening = nil end)

-- Announce tonight's drink of the night, when the raid has one.
function P.Drink()
    local st = Red.State()
    local drink = ns.Drinks.Tonight(st, ns.Raids.List(st, ns.Now()), ns.Now())
    if not drink then return nil, "The next raid has no drink of the night yet. Set one on the Raids tab." end
    return P.Play(ns.Drinks.Line(drink))
end

-- Team Captains and above: add a line, or switch one on or off.
function P.SetLine(text, on)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can change the sound board." end
    local line, why = P.Clean(text)
    if not line then return nil, why end
    return ns.Log.New("PARTY_LINE", { text = line, on = on and true or false })
end

-- A guildmate pressed Party. Speak it only if they are in my group and lead it.
ns.Sync.Handle("PT", function(msg, _, sguid)
    local line = type(msg.l) == "string" and P.Clean(msg.l)
    if not line then return end
    local unit = unitOf(sguid)
    if not unit or not leads(unit) then return end
    if not (IsInRaid and IsInRaid()) then banner(line) end
    speak(line)
end)

---------------------------------------------------------------------------
-- The window: opens from the Party button in the title bar, on every tab
---------------------------------------------------------------------------
local W = ns.W
local helping = false

local function build()
    local f = CreateFrame("Frame", "BloodPactParty", UIParent)
    f:SetSize(340, 360)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER", UIParent, "CENTER", 260, 60)
    f:EnableMouse(true)
    W.Glass(f, true)
    W.Text(f, "Party", "GameFontNormal"):SetPoint("TOPLEFT", 10, -9)
    W.Button(f, "X", 22, 20, function() f:Hide() end):SetPoint("TOPRIGHT", -6, -6)
    f.help = W.Button(f, "How does this work?", 140, 20, function()
        helping = not helping
        P.Refresh()
    end)
    f.help:SetPoint("TOPRIGHT", -34, -6)
    W.Line(f, -32)

    local function done(ok, why)
        if not ok then lastNote = why end
        P.Refresh()
    end
    f.next = W.Button(f, "Next line", 150, 26, function() done(P.Next()) end, "accent")
    f.next:SetPoint("TOPLEFT", 12, -42)
    f.random = W.Button(f, "Random line", 150, 26, function() done(P.Random()) end)
    f.random:SetPoint("TOPLEFT", 178, -42)

    f.wordLabel = W.Text(f, "Word of the night", "GameFontHighlightSmall")
    f.wordLabel:SetPoint("TOPLEFT", 12, -80)
    f.word = W.Edit(f, 130, 24)
    f.word:SetPoint("TOPLEFT", 112, -76)
    f.announce = W.Button(f, "Announce", 78, 22, function() done(P.Word(f.word:GetText())) end)
    f.announce:SetPoint("TOPLEFT", 250, -76)

    f.rows = W.List(f, 316, 140, 20, function(row, line)
        f.rows.Col(row, 1, 4, 250):SetText(U.Safe(line, P.MAX_LINE))
        if not row.off then
            row.off = W.Button(row, "Off", 40, 18)
            row.off:SetPoint("RIGHT", -4, 0)
        end
        row.off:SetShown(RBAC.ICan("schedule"))
        row.off:SetScript("OnClick", function() done(P.SetLine(line, false)) end)
    end, function(line) done(P.Play(line)) end)
    f.rows.scroll:SetPoint("TOPLEFT", 12, -108)
    f.rows.scroll:SetSize(316, 140)

    f.add = W.Edit(f, 232, P.MAX_LINE)
    f.add:SetPoint("TOPLEFT", 12, -256)
    f.addBtn = W.Button(f, "Add line", 78, 22, function()
        local ok, why = P.SetLine(f.add:GetText(), true)
        if ok then f.add:SetText("") end
        done(ok, why)
    end)
    f.addBtn:SetPoint("TOPLEFT", 250, -256)

    f.mute = W.Check(f, "Play party sounds", function(on) P.SetMuted(not on); P.Refresh() end)
    f.mute:SetPoint("TOPLEFT", 12, -288)
    f.drink = W.Button(f, "Announce the drink", 150, 22, function() done(P.Drink()) end)
    f.drink:SetPoint("TOPLEFT", 178, -285)
    f.status = W.Text(f, "", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 12, -312)
    f.status:SetWidth(316)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(true)
    f.helpText = W.Text(f, table.concat(P.HOWTO, "\n\n"), "GameFontHighlightSmall")
    f.helpText:SetPoint("TOPLEFT", 12, -42)
    f.helpText:SetWidth(316)
    f.helpText:SetJustifyH("LEFT")
    f.helpText:SetJustifyV("TOP")
    f.helpText:SetWordWrap(true)
    f:Hide()
    P.frame = f
    return f
end

function P.Refresh()
    local f = P.frame
    if not (f and f:IsShown()) then return end
    f.help:SetText(helping and "Back" or "How does this work?")
    local captain = RBAC.ICan("schedule")
    for _, w in ipairs({ f.next, f.random, f.wordLabel, f.word, f.announce, f.mute, f.status, f.drink }) do w:SetShown(not helping) end
    f.rows.scroll:SetShown(not helping)
    f.add:SetShown(not helping and captain)
    f.addBtn:SetShown(not helping and captain)
    f.helpText:SetShown(helping)
    if helping then return end
    f.mute:SetChecked(not P.Muted())
    f.rows:SetItems(P.Lines(Red.State()))
    local can, why = P.CanPress(IsInGroup and IsInGroup() or false, leads("player"), P.COOLDOWN)
    f.status:SetText(lastNote and ("|cffffd100" .. lastNote .. "|r")
        or (not can and why)
        or (listening and ("Listening for \"" .. U.Safe(listening, 24) .. "\". Click a line to send it now.") or "Click a line to send it to the raid."))
end

function P.Toggle()
    local f = P.frame or build()
    if f:IsShown() then f:Hide() return end
    helping, lastNote = false, nil
    f:Show()
    f.word:SetText(tostring(prefs().partyWord or ""))
    P.Refresh()
end

ns.Listen("LOG_CHANGED", function() P.Refresh() end)
