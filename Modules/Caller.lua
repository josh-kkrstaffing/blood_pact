-- Blind Tiger: Raid Caller. Boss plans made of call-outs, spoken by the
-- computer's own text-to-speech voice.
--
-- What the game allows (WoW Forever, checked Nov 26, 2026):
--  * An addon cannot read boss health, stacks or casts in combat, so "at 65%"
--    cannot fire by itself. Those call-outs are a checklist on screen: the
--    leader calls them, and each player clicks the overlay to hear the next.
--  * Addons cannot message other players inside an instance, so a plan has to
--    reach every raider BEFORE they zone in. It syncs with the guild records.
--  * Timed call-outs ("40 seconds after the pull") run on each player's own
--    addon and are spoken automatically.
local _, ns = ...
local C = {}
ns.Caller = C

local U, RBAC, Red = ns.U, ns.RBAC, ns.Reducer

C.WHENS = { "time", "hp", "stack", "phase", "call" }
C.WHEN_LABEL = { time = "Seconds after pull", hp = "At boss health %", stack = "At stacks", phase = "On phase", call = "On the leader's call" }
C.WHOS = { "all", "tanks", "healers", "dps" }
C.WHO_LABEL = { all = "Everyone", tanks = "Tanks", healers = "Healers", dps = "Damage dealers" }
C.MARKS = { "none", "blue", "green", "purple", "red", "yellow", "orange", "silver", "white" }
C.MAX_CUES = 40

-- Common call-outs, grouped the way a raid leader thinks of them.
-- {mark} is replaced by the marker colour when one is picked.
C.GROUPS = {
    { name = "Tanks", items = { { "swap", "Tank swap" }, { "taunt", "Taunt now" }, { "turn", "Turn the boss" },
        { "tankcd", "Tank cooldown now" }, { "pickup", "Pick up the adds" } } },
    { name = "Movement", items = { { "move", "Move to {mark}" }, { "stack", "Stack up on {mark}" }, { "spread", "Spread out" },
        { "out", "Get out" }, { "behind", "Get behind the boss" }, { "wall", "Run to the wall" }, { "still", "Stop moving" } } },
    { name = "Damage", items = { { "adds", "Kill the adds" }, { "burn", "Burn the boss" }, { "stopdps", "Stop damage" },
        { "switch", "Switch target" }, { "dpscd", "Damage cooldowns now" } } },
    { name = "Healing", items = { { "heavy", "Heavy damage, heal up" }, { "dispel", "Dispel now" }, { "healcd", "Healing cooldowns now" } } },
    { name = "Survival", items = { { "prot", "Protection potion now" }, { "stone", "Healthstone or potion now" },
        { "fear", "Fear incoming" }, { "interrupt", "Interrupt" } } },
    { name = "Phases", items = { { "p2", "Phase two" }, { "p3", "Phase three" }, { "p4", "Phase four" }, { "lust", "Final burn, use everything" } } },
}
local PHRASE = {}
for _, g in ipairs(C.GROUPS) do
    for _, i in ipairs(g.items) do PHRASE[i[1]] = i[2] end
end
C.PHRASE = PHRASE

---------------------------------------------------------------------------
-- Pure rules
---------------------------------------------------------------------------
-- What is said out loud: "Tanks. Tank swap." / "Move to green."
function C.Speech(cue)
    local text = cue.text or PHRASE[cue.what or ""] or "Call-out"
    local mark = cue.mark and cue.mark ~= "none" and cue.mark or nil
    if text:find("{mark}", 1, true) then
        text = text:gsub("{mark}", mark or "the marker")
    elseif mark then
        text = text .. ", " .. mark .. " marker"
    end
    if cue.who and cue.who ~= "all" then text = C.WHO_LABEL[cue.who] .. ". " .. text end
    return text
end

-- The trigger in words: "0:40", "At 65%", "At 5 stacks", "Phase 2", "On call".
function C.When(cue)
    if cue.when == "time" then return ("%d:%02d"):format(math.floor(cue.v / 60), cue.v % 60) end
    if cue.when == "hp" then return "At " .. cue.v .. "%" end
    if cue.when == "stack" then return "At " .. cue.v .. (cue.v == 1 and " stack" or " stacks") end
    if cue.when == "phase" then return "Phase " .. cue.v end
    return "On call"
end

-- A plan as two lists. timed: by seconds. list: the checklist, in the order a
-- fight runs: health from high to low, then phases, stacks and calls.
local RANK = { hp = 1, phase = 2, stack = 3, call = 4 }
function C.Split(plan)
    local timed, list = {}, {}
    for id, cue in pairs(plan or {}) do
        local c = { id = id, when = cue.when, v = cue.v, what = cue.what, text = cue.text, who = cue.who, mark = cue.mark, t = cue.t }
        if cue.when == "time" then timed[#timed + 1] = c else list[#list + 1] = c end
    end
    table.sort(timed, function(a, b)
        if a.v ~= b.v then return a.v < b.v end
        return a.id < b.id
    end)
    table.sort(list, function(a, b)
        if RANK[a.when] ~= RANK[b.when] then return RANK[a.when] < RANK[b.when] end
        if (a.v or 0) ~= (b.v or 0) then
            if a.when == "hp" then return (a.v or 0) > (b.v or 0) end
            return (a.v or 0) < (b.v or 0)
        end
        return a.id < b.id
    end)
    return timed, list
end

-- Everything in display order, for the plan editor.
function C.Rows(plan)
    local timed, list = C.Split(plan)
    local rows = {}
    for _, c in ipairs(timed) do rows[#rows + 1] = c end
    for _, c in ipairs(list) do rows[#rows + 1] = c end
    return rows
end

-- Is this call-out for me? kitRole = my Raid Kit role.
function C.ForMe(cue, kitRole)
    if not cue.who or cue.who == "all" then return true end
    if cue.who == "tanks" then return kitRole == "tank" end
    if cue.who == "healers" then return kitRole == "healer" end
    return kitRole ~= "tank" and kitRole ~= "healer"
end

function C.Bosses(st)
    local names = {}
    for boss in pairs(st and st.calls or {}) do names[#names + 1] = boss end
    table.sort(names)
    return names
end

-- The plan whose boss name matches what the game calls the fight.
function C.Match(st, encounterName)
    if type(encounterName) ~= "string" then return nil end
    local want = encounterName:lower()
    for _, boss in ipairs(C.Bosses(st)) do
        if boss:lower() == want then return boss end
    end
    return nil
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local function prefs()
    local c = ns.Char()
    if c.callerVoice == nil then c.callerVoice = true end
    if c.callerOverlay == nil then c.callerOverlay = true end
    return c
end

-- Say it with the computer's default voice. -> true when the game took it.
function C.Speak(text)
    local v = C_VoiceChat
    if not (v and v.SpeakText and v.GetTtsVoices) then return false end
    local ok, voices = pcall(v.GetTtsVoices)
    local voice = ok and type(voices) == "table" and voices[1]
    if not voice then return false end
    return (pcall(v.SpeakText, voice.voiceID, text, 0, 100))
end

local run = { boss = nil, token = 0, list = {}, at = 1, fighting = false, banner = nil, bannerUntil = 0 }
C.run = run

local function announce(cue)
    local p = prefs()
    local text = C.Speech(cue)
    run.banner, run.bannerUntil = text, ns.Now() + 6
    if p.callerVoice and C.ForMe(cue, ns.Kit and ns.Kit.MyRole() or nil) then C.Speak(text) end
    if C.RefreshOverlay then C.RefreshOverlay() end
end

-- Arm a boss: its checklist shows on the overlay, ready for the pull.
function C.Arm(boss)
    local st = Red.State()
    local plan = boss and st and st.calls[boss]
    run.token = run.token + 1
    run.boss, run.at, run.fighting, run.banner = plan and boss or nil, 1, false, nil
    run.timed, run.list = C.Split(plan)
    ns.Char().callerBoss = run.boss
    if C.RefreshOverlay then C.RefreshOverlay() end
    return run.boss ~= nil
end

-- The pull: start the timed call-outs on my own addon.
function C.Start()
    if not run.boss or run.fighting then return end
    run.fighting, run.at = true, 1
    run.token = run.token + 1
    local token = run.token
    for _, cue in ipairs(run.timed or {}) do
        if C_Timer and C_Timer.After then
            C_Timer.After(math.max(0.1, cue.v), function()
                if run.token == token and run.fighting then announce(cue) end
            end)
        end
    end
    if C.RefreshOverlay then C.RefreshOverlay() end
end

function C.Stop()
    if not run.fighting then return end
    run.fighting = false
    run.token = run.token + 1
    run.at, run.banner = 1, nil
    if C.RefreshOverlay then C.RefreshOverlay() end
end

-- The overlay was clicked: say the next checklist call-out and move on.
function C.Next()
    local cue = run.list and run.list[run.at]
    if not cue then return nil end
    run.at = run.at + 1
    announce(cue)
    return cue
end

ns.On("ENCOUNTER_START", function(_, name)
    if issecretvalue and issecretvalue(name) then name = nil end
    local boss = C.Match(Red.State(), name)
    if boss and boss ~= run.boss then C.Arm(boss) end
    if run.boss then
        C.Start()
        run.byGame = true            -- the game will say when it ends
    end
end)
ns.On("ENCOUNTER_END", function() run.byGame = nil; C.Stop() end)
-- If the game doesn't announce the fight, the armed boss starts when I enter combat in a group.
ns.On("PLAYER_REGEN_DISABLED", function()
    if run.boss and not run.fighting and IsInGroup and IsInGroup() then C.Start() end
end)
ns.On("PLAYER_REGEN_ENABLED", function() if not run.byGame then C.Stop() end end)

---------------------------------------------------------------------------
-- Team Captains and above: build the plan
---------------------------------------------------------------------------
local function newId() return ("%x%02d"):format(ns.Now() % 0xfffffff, math.random(0, 99)) end

-- cue = { when, v, what or text, who, mark }
function C.Add(boss, cue)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can change call-outs." end
    boss = (boss or ""):match("^%s*(.-)%s*$")
    if boss == "" or #boss > 30 then return nil, "Type the boss's name first, as the game spells it." end
    local v = tonumber(cue.v)
    if cue.when == "call" then
        v = nil
    elseif not v or v ~= math.floor(v) then
        return nil, "Give a whole number for \"" .. (C.WHEN_LABEL[cue.when] or "when") .. "\"."
    elseif cue.when == "time" and (v < 0 or v > 1800) then
        return nil, "Seconds after the pull must be 0 to 1800."
    elseif cue.when == "hp" and (v < 1 or v > 99) then
        return nil, "Boss health must be 1 to 99 percent."
    elseif (cue.when == "stack" and (v < 1 or v > 99)) or (cue.when == "phase" and (v < 1 or v > 9)) then
        return nil, "That number is out of range."
    end
    local text = cue.text and cue.text:match("^%s*(.-)%s*$") or nil
    if text == "" then text = nil end
    if text and #text > 60 then return nil, "Keep your own words to 60 letters." end
    if not text and not PHRASE[cue.what or ""] then return nil, "Pick a call-out or type your own." end
    local st = Red.State()
    local count = 0
    for _ in pairs(st and st.calls[boss] or {}) do count = count + 1 end
    if count >= C.MAX_CUES then return nil, "A boss can have " .. C.MAX_CUES .. " call-outs." end
    return ns.Log.New("CALL_CUE", { boss = boss, id = newId(), on = true, when = cue.when, v = v,
        what = not text and cue.what or nil, text = text, who = cue.who or "all",
        mark = cue.mark and cue.mark ~= "none" and cue.mark or nil })
end

function C.Remove(boss, id)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can change call-outs." end
    return ns.Log.New("CALL_CUE", { boss = boss, id = id, on = false })
end

---------------------------------------------------------------------------
-- The overlay: next call-outs, and a click to hear the next one
---------------------------------------------------------------------------
local W = ns.W
local overlay

local function buildOverlay()
    local f = CreateFrame("Button", "BlindTigerCaller", UIParent)
    f:SetSize(340, 86)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.Char().callerAt = { point, rel, x, y }
    end)
    local at = ns.Char().callerAt
    if type(at) == "table" then f:SetPoint(at[1], UIParent, at[2], at[3], at[4]) else f:SetPoint("TOP", UIParent, "TOP", 0, -160) end
    W.Glass(f, true)
    f.head = W.Text(f, "", "GameFontNormalSmall")
    f.head:SetPoint("TOPLEFT", 8, -6)
    f.big = W.Text(f, "", "GameFontNormalLarge")
    f.big:SetPoint("TOPLEFT", 8, -24)
    f.big:SetWidth(324)
    f.big:SetJustifyH("LEFT")
    f.big:SetWordWrap(false)
    f.after = W.Text(f, "", "GameFontDisableSmall")
    f.after:SetPoint("TOPLEFT", 8, -48)
    f.after:SetWidth(324)
    f.after:SetJustifyH("LEFT")
    f.after:SetWordWrap(false)
    f.hint = W.Text(f, "", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", 8, 6)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" then C.Arm(nil) else C.Next() end
    end)
    f:Hide()
    overlay = f
    return f
end

function C.RefreshOverlay()
    local p = prefs()
    if not run.boss or not p.callerOverlay or ns.mock then
        if overlay then overlay:Hide() end
        return
    end
    local f = overlay or buildOverlay()
    local now = ns.Now()
    local nextCue, afterCue = run.list[run.at], run.list[run.at + 1]
    f.head:SetText(run.boss .. (run.fighting and "  |cff40ff40fight running|r" or "  |cff808080armed|r"))
    if run.banner and now < run.bannerUntil then
        f.big:SetText("|cffffd100" .. run.banner .. "|r")
    elseif nextCue then
        f.big:SetText(C.When(nextCue) .. ": " .. C.Speech(nextCue))
    else
        f.big:SetText(#run.list > 0 and "Checklist done" or "Timed call-outs only")
    end
    f.after:SetText(afterCue and ("Then " .. C.When(afterCue) .. ": " .. C.Speech(afterCue)) or "")
    f.hint:SetText(nextCue and "Click to say the next one. Right-click to put this away. Drag to move." or "Right-click to put this away. Drag to move.")
    f:Show()
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local viewBoss                     -- the boss shown in the tab
local draft = { when = "time", group = 1, item = 1, who = "all", mark = "none" }

local function cycle(list, cur)
    for i, v in ipairs(list) do
        if v == cur then return list[i % #list + 1] end
    end
    return list[1]
end

ns.UI.AddTab("caller", "Call-outs", "view", function(p)
    -- 1. My switches.
    p.voice = W.Check(p, "Speak call-outs during boss fights", function(on) prefs().callerVoice = on end)
    p.voice:SetPoint("TOPLEFT", 8, -8)
    p.overlay = W.Check(p, "Show the call-out overlay", function(on)
        prefs().callerOverlay = on
        C.RefreshOverlay()
    end)
    p.overlay:SetPoint("TOPLEFT", 280, -8)
    p.test = W.Button(p, "Test voice", 90, 20, function()
        if not C.Speak("Blind Tiger. Tank swap.") then ns.UI.Say("The game didn't speak. Check that your computer has a text-to-speech voice.") end
    end)
    p.test:SetPoint("TOPLEFT", 500, -6)
    p.how = W.Button(p, "How does this work?", 150, 20)
    p.how:SetPoint("TOPLEFT", 596, -6)
    p.how:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Raid Caller")
        for _, l in ipairs(C.HOWTO) do GameTooltip:AddLine(l, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    p.how:HookScript("OnLeave", GameTooltip_Hide)

    -- 2. Pick a boss (left), see its plan (right).
    W.Text(p, "Bosses", "GameFontNormal"):SetPoint("TOPLEFT", 8, -36)
    p.bosses = W.List(p, 180, 200, 18, function(row, b)
        p.bosses.Col(row, 1, 4, 120):SetText((b.name == viewBoss and "|cffffd100" or "|cffffffff") .. U.Safe(b.name, 30) .. "|r")
        p.bosses.Col(row, 2, 128, 46, "RIGHT"):SetText(b.armed and "|cff40ff40armed|r" or tostring(b.n))
    end, function(b) viewBoss = b.name; ns.UI.Refresh() end)
    p.planHead = W.Text(p, "", "GameFontNormal")
    p.planHead:SetPoint("TOPLEFT", 200, -36)
    p.arm = W.Button(p, "", 150, 20, function()
        if run.boss == viewBoss then C.Arm(nil) else C.Arm(viewBoss) end
        ns.UI.Refresh()
    end)
    p.arm:SetPoint("TOPLEFT", 596, -34)
    p.cues = W.List(p, 540, 200, 18, function(row, c)
        p.cues.Col(row, 1, 4, 70):SetText(C.When(c))
        p.cues.Col(row, 2, 78, 330):SetText(U.Safe(C.Speech(c), 90))
        local how = p.cues.Col(row, 3, 412, 90)
        how:SetText(c.when == "time" and "spoken by itself" or "checklist")
        how:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        if not row.del then
            row.del = W.Button(row, "Remove", 60, 14)
            row.del:SetPoint("RIGHT", -4, 0)
        end
        row.del:SetShown(RBAC.ICan("schedule"))
        row.del:SetScript("OnClick", function()
            ns.UI.Try("Call-out removed for the guild.", C.Remove, viewBoss, c.id)
            ns.UI.Refresh()
        end)
    end)
    p.empty = W.Text(p, "", "GameFontDisable")
    p.empty:SetPoint("TOPLEFT", 208, -64)
    p.empty:SetWidth(520)
    p.empty:SetJustifyH("LEFT")
    p.empty:SetWordWrap(true)

    -- 3. Team Captains and above: add a call-out.
    function p.place()
        local can = RBAC.ICan("schedule")
        p.fold:SetShown(can)
        local foldH = can and (p.fold:Height() + 8) or 0
        if can then
            p.fold:ClearAllPoints()
            p.fold:SetPoint("BOTTOMLEFT", 8, 8 + (p.fold.open and (p.fold.bodyHeight + 6) or 0))
        end
        p.bosses:Stretch(8, -54, nil, foldH + 8)
        p.cues:Stretch(200, -58, 8, foldH + 8)
        if ns.UI.FitWindow then ns.UI.FitWindow() end
    end
    p.fold = W.Accordion(p, "Add a call-out (Team Captain and above)", 740, 86, "callerAdd", function() p.place() end, true)
    local s = p.fold.body
    W.Text(s, "Boss", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -6)
    s.boss = W.Edit(s, 150, 30)
    s.boss:SetPoint("TOPLEFT", 34, -2)
    s.when = W.Button(s, "", 150, 22, function() draft.when = cycle(C.WHENS, draft.when); ns.UI.Refresh() end)
    s.when:SetPoint("TOPLEFT", 196, -2)
    s.v = W.Edit(s, 44, 4)
    s.v:SetPoint("TOPLEFT", 352, -2)
    s.who = W.Button(s, "", 130, 22, function() draft.who = cycle(C.WHOS, draft.who); ns.UI.Refresh() end)
    s.who:SetPoint("TOPLEFT", 408, -2)
    s.mark = W.Button(s, "", 130, 22, function() draft.mark = cycle(C.MARKS, draft.mark); ns.UI.Refresh() end)
    s.mark:SetPoint("TOPLEFT", 544, -2)

    s.group = W.Button(s, "", 150, 22, function()
        draft.group = draft.group % #C.GROUPS + 1
        draft.item = 1
        ns.UI.Refresh()
    end)
    s.group:SetPoint("TOPLEFT", 0, -30)
    s.item = W.Button(s, "", 190, 22, function()
        draft.item = draft.item % #C.GROUPS[draft.group].items + 1
        ns.UI.Refresh()
    end)
    s.item:SetPoint("TOPLEFT", 156, -30)
    W.Text(s, "or your own words", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 354, -34)
    s.text = W.Edit(s, 190, 60)
    s.text:SetPoint("TOPLEFT", 462, -30)
    s.add = W.Button(s, "Add", 70, 22, function()
        local g = C.GROUPS[draft.group]
        local ok = ns.UI.Try("Call-out added for the guild.", C.Add, s.boss:GetText(),
            { when = draft.when, v = s.v:GetText(), what = g.items[draft.item][1], text = s.text:GetText(), who = draft.who, mark = draft.mark })
        if ok then
            viewBoss = s.boss:GetText():match("^%s*(.-)%s*$")
            s.text:SetText("")
        end
        ns.UI.Refresh()
    end, "accent")
    s.add:SetPoint("TOPLEFT", 660, -30)
    s.preview = W.Text(s, "", "GameFontDisableSmall")
    s.preview:SetPoint("TOPLEFT", 0, -60)
    s.preview:SetWidth(730)
    s.preview:SetJustifyH("LEFT")
    s.preview:SetWordWrap(false)
    s.hear = W.Button(s, "Hear it", 70, 18, function()
        local g = C.GROUPS[draft.group]
        local text = s.text:GetText():match("^%s*(.-)%s*$")
        C.Speak(C.Speech({ what = g.items[draft.item][1], text = text ~= "" and text or nil, who = draft.who, mark = draft.mark }))
    end)
    s.hear:SetPoint("TOPLEFT", 660, -58)
    p.place()
end, function(p)
    local st = Red.State()
    local pr = prefs()
    p.voice:SetChecked(pr.callerVoice)
    p.overlay:SetChecked(pr.callerOverlay)
    local names = C.Bosses(st)
    local known = false
    for _, n in ipairs(names) do if n == viewBoss then known = true end end
    if not known then viewBoss = names[1] end
    local list = {}
    for _, n in ipairs(names) do
        local count = 0
        for _ in pairs(st.calls[n]) do count = count + 1 end
        list[#list + 1] = { name = n, n = count, armed = run.boss == n }
    end
    p.bosses:SetItems(list)
    local rows = viewBoss and C.Rows(st.calls[viewBoss]) or {}
    p.planHead:SetText(viewBoss and (U.Safe(viewBoss, 30) .. ": " .. #rows .. (#rows == 1 and " call-out" or " call-outs")) or "No plans yet")
    p.arm:SetShown(viewBoss ~= nil)
    p.arm:SetText(run.boss == viewBoss and "Put away" or "Arm for the next pull")
    p.cues:SetItems(rows)
    p.empty:SetText(#names == 0 and (RBAC.ICan("schedule")
        and "No boss plans yet. Add the first call-out below: type the boss's name the way the game spells it."
        or "No boss plans yet. A Team Captain or above builds them.") or "")
    if RBAC.ICan("schedule") then
        local s = p.fold.body
        local g = C.GROUPS[draft.group]
        if not s.boss:HasFocus() and s.boss:GetText() == "" and viewBoss then s.boss:SetText(viewBoss) end
        s.when:SetText(C.WHEN_LABEL[draft.when])
        s.v:SetShown(draft.when ~= "call")
        s.who:SetText("For: " .. C.WHO_LABEL[draft.who])
        s.mark:SetText("Marker: " .. draft.mark)
        s.group:SetText("Type: " .. g.name)
        s.item:SetText(g.items[draft.item][2])
        local text = s.text:GetText():match("^%s*(.-)%s*$")
        s.preview:SetText("Will say: \"" .. C.Speech({ what = g.items[draft.item][1], text = text ~= "" and text or nil, who = draft.who, mark = draft.mark })
            .. "\"   " .. (draft.when == "time" and "Spoken by itself, that many seconds after the pull."
                or "Goes on the checklist: the game hides boss health and stacks from addons."))
    end
    p.place()
end)

C.HOWTO = {
    "A Team Captain or above builds a plan for each boss from call-outs.",
    "Timed call-outs are spoken by your own computer's voice, counted from the pull.",
    "Health, stack and phase call-outs can't fire by themselves: the game hides those numbers from addons. They show on the overlay as a checklist. Click the overlay to hear the next one.",
    "Plans reach you through the guild records, so log in before you enter the raid. Inside a raid the game doesn't let addons talk to each other.",
    "The plan starts by itself when the boss's name matches the fight. If it doesn't, press \"Arm for the next pull\" before the pull.",
    "Call-outs marked for tanks or healers are only spoken to them, using your Raid Kit role.",
    "Turn the voice or the overlay off with the two boxes at the top.",
}

ns.UI.Need("caller", function(p)
    return 58 + 6 * 18 + (RBAC.ICan("schedule") and (p.fold:Height() + 16) or 8), 760
end)

-- After a reload, bring back the boss that was armed.
ns.Listen("LOG_CHANGED", function()
    if run.boss then
        local st = Red.State()
        if st and st.calls[run.boss] and not run.fighting then run.timed, run.list = C.Split(st.calls[run.boss]) end
        C.RefreshOverlay()
    end
end)
