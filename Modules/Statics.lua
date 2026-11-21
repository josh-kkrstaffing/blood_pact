-- Blood Pact: statics, the guild's fixed 10-player raid teams.
-- Each Team Captain has one team and looks after it: they add and remove
-- its members and set who tanks, heals and deals damage. Officers and above
-- can edit any team. A member is on one static at a time. Everyone in the
-- guild can see the teams (Roster > Statics).
local _, ns = ...
local S = {}
ns.Statics = S

local U, W, RBAC, Red, Log = ns.U, ns.W, ns.RBAC, ns.Reducer, ns.Log

S.SIZE = 10                    -- the captain and nine more
S.CAPTAIN_RANK = 2             -- the guild rank that is Team Captain
S.ROLES = { "tank", "healer", "dps" }
S.ROLE_LABEL = { tank = "Tank", healer = "Healer", dps = "DPS" }
S.NAME_MAX = 24

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
function S.NextRole(role)
    for i, r in ipairs(S.ROLES) do
        if r == role then return S.ROLES[i % #S.ROLES + 1] end
    end
    return S.ROLES[1]
end

-- The teams to show: one for every Team Captain in the guild, and any other
-- team that has members. Captains who left the guild are dropped.
--   statics = reduced state (st.statics)   roster = ns.roster.byGUID
-- -> { { cap, capName, name, rows = { member... }, n, tank, healer, dps, online }, ... }
function S.Teams(statics, roster)
    local teams = {}
    local function row(guid, role, isCap)
        local m = roster[guid]
        if not m then return nil end           -- left the guild
        return { guid = guid, name = U.ShortName(m.name), class = m.class, classLabel = m.classLabel, level = m.level or 0,
            role = role or "dps", online = m.online and true or false, zone = m.zone or "", isCap = isCap or false }
    end
    local seen = {}
    local function add(cap)
        local m = roster[cap]
        if seen[cap] or not m then return end
        seen[cap] = true
        local t = statics[cap] or { members = {} }
        local team = { cap = cap, capName = U.ShortName(m.name), name = t.name, rows = {}, n = 0, tank = 0, healer = 0, dps = 0, online = 0 }
        local list = { row(cap, t.capRole, true) }
        for guid, role in pairs(t.members) do list[#list + 1] = row(guid, role) end
        local order = { tank = 1, healer = 2, dps = 3 }
        table.sort(list, function(a, b)
            if a.isCap ~= b.isCap then return a.isCap end
            if a.role ~= b.role then return order[a.role] < order[b.role] end
            return a.name < b.name
        end)
        for _, r in ipairs(list) do
            team.n = team.n + 1
            team[r.role] = team[r.role] + 1
            if r.online then team.online = team.online + 1 end
        end
        team.rows = list
        teams[#teams + 1] = team
    end
    for guid, m in pairs(roster) do
        if m.rankIndex == S.CAPTAIN_RANK then add(guid) end
    end
    for cap, t in pairs(statics) do
        if next(t.members) then add(cap) end
    end
    table.sort(teams, function(a, b) return a.capName < b.capName end)
    return teams
end

-- Which team a member is on: the captain's guid, or nil.
function S.TeamOf(statics, guid)
    for cap, t in pairs(statics) do
        if t.members[guid] then return cap end
    end
    return nil
end

-- May `who` join `cap`'s team? Pure. -> true, or nil and why
function S.CanAdd(statics, cap, who, nameOf)
    if who == cap then return nil, "The captain is already on the team." end
    local t = statics[cap]
    if t and t.members[who] then return nil, "They are already on this team." end
    local other = S.TeamOf(statics, who)
    if other then return nil, ("They are on %s's team. Remove them there first."):format(nameOf(other)) end
    local n = 1
    for _ in pairs(t and t.members or {}) do n = n + 1 end
    if n >= S.SIZE then return nil, ("The team has all %d players."):format(S.SIZE) end
    return true
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local function nameOf(guid) return U.ShortName(ns.NameForGUID(guid) or "?") end

function S.CanEdit(cap)
    return (cap == ns.MyGUID() and RBAC.ICan("schedule")) or RBAC.ICan("void")
end

local function post(cap, who, on, role)
    if cap == ns.MyGUID() then return Log.New("STATIC", { who = who, on = on, role = role }) end
    return Log.New("STATIC_MOD", { cap = cap, who = who, on = on, role = role })
end

function S.Add(cap, name, role)
    if not S.CanEdit(cap) then return nil, "Only the team's captain, or an Officer and above, can change a team." end
    local who = ns.GUIDForName((tostring(name or ""):match("^%s*(.-)%s*$")))
    if not who then return nil, "Nobody in the guild has that name." end
    local st = Red.State()
    local ok, why = S.CanAdd(st and st.statics or {}, cap, who, nameOf)
    if not ok then return nil, why end
    return post(cap, who, true, S.ROLE_LABEL[role] and role or "dps")
end

function S.Remove(cap, who)
    if not S.CanEdit(cap) then return nil, "Only the team's captain, or an Officer and above, can change a team." end
    if who == cap then return nil, "The captain can't be removed from their own team." end
    return post(cap, who, false)
end

function S.SetRole(cap, who, role)
    if not S.CanEdit(cap) then return nil, "Only the team's captain, or an Officer and above, can change a team." end
    if not S.ROLE_LABEL[role] then return nil, "Pick Tank, Healer or DPS." end
    return post(cap, who, true, role)
end

function S.Rename(name)
    if not RBAC.ICan("schedule") then return nil, "Only a Team Captain names their team." end
    name = tostring(name or ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if #name > S.NAME_MAX then return nil, ("Keep the name under %d letters."):format(S.NAME_MAX) end
    return Log.New("STATIC_NAME", { name = name })
end

-- Invite the team's online members who aren't in my group yet, from my
-- click. A party holds five, so before it is a raid only four go out.
function S.InviteTeam(team)
    if ns.mock then return nil, "Test mode is on, so nobody is invited." end
    local me = ns.MyGUID()
    local grouped = {}
    if IsInGroup and IsInGroup() then
        local raid = IsInRaid and IsInRaid()
        for i = 1, raid and 40 or 4 do
            local guid = UnitGUID((raid and "raid" or "party") .. i)
            if guid then grouped[guid] = true end
        end
        if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
            return nil, "Only your group's leader can invite."
        end
        -- More than a party's worth: make it a raid first.
        if not raid and team.n > 5 and C_PartyInfo and C_PartyInfo.ConvertToRaid then pcall(C_PartyInfo.ConvertToRaid) end
    end
    local inRaid = IsInRaid and IsInRaid()
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    local sent, held = 0, 0
    for _, r in ipairs(team.rows) do
        if r.guid ~= me and r.online and not grouped[r.guid] then
            if inRaid or sent < 4 then
                local m = ns.roster.byGUID[r.guid]
                if invite and pcall(invite, m.full or m.name) then sent = sent + 1 end
            else
                held = held + 1
            end
        end
    end
    if sent == 0 and held == 0 then return nil, "Nobody else on the team is online and outside your group." end
    return ("Invited %d.%s"):format(sent, held > 0 and (" A party holds five: once someone joins, press again and it becomes a raid for the other %d."):format(held) or "")
end

---------------------------------------------------------------------------
-- Roster > Statics
---------------------------------------------------------------------------
local selected            -- the picked team's captain
local addRole = "dps"

local function classColor(token)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return W.C.text[1], W.C.text[2], W.C.text[3]
end

-- Build the view inside the Roster tab.
function S.Build(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 0, -30)
    f:SetPoint("BOTTOMRIGHT", 0, 0)
    p.statics = f

    W.Text(f, "Teams", "GameFontNormal"):SetPoint("TOPLEFT", 0, 0)
    f.teams = W.List(f, 300, 200, 20, function(row, t)
        f.teams.Col(row, 1, 4, 150):SetText(U.Safe(t.name and t.name ~= "" and t.name or (t.capName .. "'s team"), 40))
        local n = f.teams.Col(row, 2, 158, 44, "RIGHT")
        n:SetText(t.n .. "/" .. S.SIZE)
        local full = t.n >= S.SIZE
        n:SetTextColor(full and 0.25 or W.C.text[1], full and 1 or W.C.text[2], full and 0.25 or W.C.text[3])
        f.teams.Col(row, 3, 210, 86):SetText(("|cffaaaaaa%dT %dH %dD|r"):format(t.tank, t.healer, t.dps))
    end, function(t) selected = t and t.cap or nil; ns.UI.Refresh() end)
    f.teams:Stretch(0, -20, nil, 0)
    f.teams.key = "cap"
    f.none = W.Text(f, "No Team Captains yet. A team appears here for each member with the Team Captain rank.", "GameFontHighlightSmall")
    f.none:SetPoint("TOPLEFT", 4, -26)
    f.none:SetWidth(290)

    -- The picked team.
    f.head = W.Text(f, "", "GameFontNormal")
    f.head:SetPoint("TOPLEFT", 330, 0)
    f.sub = W.Text(f, "", "GameFontDisableSmall")
    f.sub:SetPoint("TOPLEFT", 330, -18)
    f.members = W.List(f, 440, 200, 18, function(row, r)
        local name = f.members.Col(row, 1, 4, 150)
        name:SetText((r.online and "" or "|cff808080") .. U.Safe(r.name, 40) .. (r.isCap and "  |cffffd100captain|r" or ""))
        if r.online then name:SetTextColor(classColor(r.class)) end
        f.members.Col(row, 2, 160, 54):SetText(S.ROLE_LABEL[r.role])
        f.members.Col(row, 3, 218, 28):SetText(r.level)
        f.members.Col(row, 4, 250, 190):SetText(r.online and U.Safe(r.zone, 30) or "|cff808080offline|r")
    end, function(r, button)
        if not (r and selected and S.CanEdit(selected)) then return end
        if button == "RightButton" then
            ns.UI.Try(U.Safe(r.name, 40) .. " is off the team.", S.Remove, selected, r.guid)
        else
            local role = S.NextRole(r.role)
            ns.UI.Try(("%s is now %s."):format(U.Safe(r.name, 40), S.ROLE_LABEL[role]), S.SetRole, selected, r.guid, role)
        end
    end)
    f.members:Stretch(330, -38, 0, 86)
    f.members.key = "guid"

    -- Editing, for the team's captain and for Officers and above.
    local e = CreateFrame("Frame", nil, f)
    e:SetPoint("BOTTOMLEFT", 330, 0)
    e:SetSize(460, 80)
    f.edit = e
    local hint = W.Text(e, "Click a member to change their role. Right-click to take them off the team.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, 0)
    f.addBox = W.Edit(e, 150, 48)
    f.addBox:SetPoint("TOPLEFT", 0, -20)
    f.addRole = W.Button(e, "as DPS", 76, 22, function()
        addRole = S.NextRole(addRole)
        f.addRole:SetText("as " .. S.ROLE_LABEL[addRole])
    end)
    f.addRole:SetPoint("TOPLEFT", 156, -20)
    f.add = W.Button(e, "Add to team", 100, 22, function()
        if selected and ns.UI.Try("Added to the team.", S.Add, selected, f.addBox:GetText(), addRole) then f.addBox:SetText("") end
    end, "accent")
    f.add:SetPoint("TOPLEFT", 236, -20)
    f.nameBox = W.Edit(e, 150, S.NAME_MAX)
    f.nameBox:SetPoint("TOPLEFT", 0, -50)
    f.rename = W.Button(e, "Name my team", 110, 22, function()
        ns.UI.Try("Team name saved.", S.Rename, f.nameBox:GetText())
    end)
    f.rename:SetPoint("TOPLEFT", 156, -50)

    f.inviteAll = W.Button(f, "Invite online members", 170, 22, function()
        local st = Red.State()
        for _, t in ipairs(S.Teams(st and st.statics or {}, ns.roster.byGUID)) do
            if t.cap == selected then
                local line, why = S.InviteTeam(t)
                ns.UI.Say(line or why or "That didn't work.")
            end
        end
    end)
    f.inviteAll:SetPoint("BOTTOMRIGHT", 0, 0)
    f:Hide()
    return f
end

function S.Refresh(p, show)
    local f = p.statics
    f:SetShown(show)
    if not show then return end
    local st = Red.State()
    local teams = S.Teams(st and st.statics or {}, ns.roster.byGUID)
    local me = ns.MyGUID()
    local sel
    for _, t in ipairs(teams) do if t.cap == selected then sel = t end end
    if not sel then
        -- My own team first, else the first one.
        local mine = st and S.TeamOf(st.statics, me) or nil
        for _, t in ipairs(teams) do
            if t.cap == me or t.cap == mine then sel = t end
        end
        sel = sel or teams[1]
    end
    selected = sel and sel.cap or nil
    f.teams.selected = sel
    f.teams:SetItems(teams)
    f.none:SetShown(#teams == 0)
    f.members:SetItems(sel and sel.rows or {})
    local can = sel ~= nil and S.CanEdit(sel.cap)
    f.edit:SetShown(can)
    f.inviteAll:SetShown(sel ~= nil)
    for _, w in ipairs({ f.nameBox, f.rename }) do w:SetShown(can and sel.cap == me) end
    if not sel then
        f.head:SetText("")
        f.sub:SetText("")
        return
    end
    f.head:SetText(U.Safe(sel.name and sel.name ~= "" and sel.name or (sel.capName .. "'s team"), 40))
    f.sub:SetText(("Captain %s   %d of %d players   %d tanks, %d healers, %d DPS   %d online"):format(
        U.Safe(sel.capName, 40), sel.n, S.SIZE, sel.tank, sel.healer, sel.dps, sel.online))
    if can and sel.cap == me and not f.nameBox:HasFocus() then f.nameBox:SetText(sel.name or "") end
end
