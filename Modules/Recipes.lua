-- Blind Tiger: who knows which recipes.
-- The game only shows a character's recipes to that character, and only
-- while their profession window is open. So each player's own addon records
-- their recipes the first time they open a profession, and shares the recipe
-- ids with the guild. After that only newly learned recipes are sent.
-- Recipe names are looked up from the id on each viewer's own game, so
-- nothing but numbers travels.
local _, ns = ...
local R = {}
ns.Recipes = R

local U = ns.U
local PER_EVENT = 100          -- recipe ids per log entry

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- scanned = list of ids I know now; have = set already shared.
-- -> the ids to add, and whether some shared recipe is gone (start over).
function R.Diff(scanned, have)
    local adds, now = {}, {}
    for _, id in ipairs(scanned) do
        if not now[id] then
            now[id] = true
            if not (have and have[id]) then adds[#adds + 1] = id end
        end
    end
    table.sort(adds)
    local gone = false
    for id in pairs(have or {}) do
        if not now[id] then gone = true; break end
    end
    return adds, gone
end

function R.Chunks(ids, per)
    local out = {}
    for i = 1, #ids, per do
        local part = {}
        for j = i, math.min(#ids, i + per - 1) do part[#part + 1] = ids[j] end
        out[#out + 1] = part
    end
    return out
end

-- How many recipes a member has shared for a profession.
function R.Count(st, guid, prof)
    local set = st and st.recipes[guid] and st.recipes[guid][prof]
    local n = 0
    for _ in pairs(set or {}) do n = n + 1 end
    return n
end

-- Rows for the recipe list: { id, name }, by name. filter is part of a name.
function R.List(set, filter, nameOf)
    local rows = {}
    for id in pairs(set or {}) do
        local name = nameOf(id) or ("Recipe " .. id)
        if not filter or filter == "" or name:lower():find(filter, 1, true) then
            rows[#rows + 1] = { id = id, name = name }
        end
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return rows
end

-- Every profession the guild has shared recipes for, with how many
-- different recipes. Only members still in the roster count.
function R.GuildProfs(st, roster)
    local seen = {}
    for guid, byProf in pairs(st and st.recipes or {}) do
        if roster[guid] then
            for prof, set in pairs(byProf) do
                seen[prof] = seen[prof] or {}
                for id in pairs(set) do seen[prof][id] = true end
            end
        end
    end
    local out = {}
    for prof, ids in pairs(seen) do
        local n = 0
        for _ in pairs(ids) do n = n + 1 end
        out[#out + 1] = { name = prof, count = n }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Every recipe the guild knows in one profession, with who can make it.
-- Rows: { id, name, crafters = { guid, ... } (online first), online = n }.
function R.GuildRecipes(st, roster, prof, filter, nameOf)
    local by = {}
    for guid, byProf in pairs(st and st.recipes or {}) do
        local m = roster[guid]
        if m and byProf[prof] then
            for id in pairs(byProf[prof]) do
                by[id] = by[id] or {}
                by[id][#by[id] + 1] = guid
            end
        end
    end
    local rows = {}
    for id, crafters in pairs(by) do
        local name = nameOf(id) or ("Recipe " .. id)
        if not filter or filter == "" or name:lower():find(filter, 1, true) then
            local online = 0
            for _, guid in ipairs(crafters) do if roster[guid].online then online = online + 1 end end
            table.sort(crafters, function(a, b)
                local x, y = roster[a].online and 0 or 1, roster[b].online and 0 or 1
                if x ~= y then return x < y end
                return (roster[a].name or "") < (roster[b].name or "")
            end)
            rows[#rows + 1] = { id = id, name = name, crafters = crafters, online = online }
        end
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return rows
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
-- What a recipe needs: { { item = itemID, n = quantity }, ... }, or nil when
-- the game won't say. Cached.
local reagents = {}
function R.Reagents(id)
    if reagents[id] ~= nil then return reagents[id] or nil end
    local api = C_TradeSkillUI
    local list
    if api and api.GetRecipeSchematic then
        local ok, s = pcall(api.GetRecipeSchematic, id, false)
        if ok and type(s) == "table" and type(s.reagentSlotSchematics) == "table" then
            list = {}
            for _, slot in ipairs(s.reagentSlotSchematics) do
                local first = type(slot.reagents) == "table" and slot.reagents[1]
                local basic = slot.reagentType == nil or slot.reagentType == 1
                if basic and slot.required ~= false and first and first.itemID and (slot.quantityRequired or 0) > 0 then
                    list[#list + 1] = { item = first.itemID, n = slot.quantityRequired }
                end
            end
            if #list == 0 then list = nil end
        end
    end
    reagents[id] = list or false
    return list
end

-- The item a recipe makes, or nil when it makes none (an enchant put straight
-- on someone's gear) or the game won't say. Cached.
local outputs = {}
function R.Output(id)
    if outputs[id] ~= nil then return outputs[id] or nil end
    local api = C_TradeSkillUI
    local item
    if api and api.GetRecipeSchematic then
        local ok, s = pcall(api.GetRecipeSchematic, id, false)
        if ok and type(s) == "table" and type(s.outputItemID) == "number" and s.outputItemID > 0 then item = s.outputItemID end
    end
    outputs[id] = item or false
    return item
end

-- A recipe's name from its id, on this player's own game. Cached.
local names = {}
function R.Name(id)
    if names[id] then return names[id] end
    local name
    local api = C_TradeSkillUI
    if api and api.GetRecipeInfo then
        local ok, info = pcall(api.GetRecipeInfo, id)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then name = info.name end
    end
    if not name and C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    if not name and type(GetSpellInfo) == "function" then
        local ok, n = pcall(GetSpellInfo, id)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    names[id] = name
    return name
end

-- The open profession window, if it is my own: its name and the ids I know.
function R.Read()
    local api = C_TradeSkillUI
    if not (api and api.GetAllRecipeIDs and api.GetRecipeInfo) then return nil, nil, "This game version doesn't list recipes." end
    -- Someone else's linked profession, the guild's, or an NPC's is not mine.
    for _, check in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting" }) do
        if api[check] then
            local ok, yes = pcall(api[check])
            if ok and yes then return nil, nil, "That isn't your own profession window." end
        end
    end
    if api.IsTradeSkillReady then
        local ok, ready = pcall(api.IsTradeSkillReady)
        if ok and ready == false then return nil, nil, "Open one of your profession windows first." end
    end
    local prof
    if api.GetBaseProfessionInfo then
        local ok, info = pcall(api.GetBaseProfessionInfo)
        if ok and type(info) == "table" then prof = info.parentProfessionName or info.professionName end
    end
    if not prof and api.GetChildProfessionInfo then
        local ok, info = pcall(api.GetChildProfessionInfo)
        if ok and type(info) == "table" then prof = info.parentProfessionName or info.professionName end
    end
    if not prof and api.GetTradeSkillLine then
        local ok, _, name, _, _, _, _, parent = pcall(api.GetTradeSkillLine)
        if ok then prof = parent or name end
    end
    if type(prof) ~= "string" or prof == "" then return nil, nil, "Open one of your profession windows first." end
    prof = prof:sub(1, 24)
    local ok, all = pcall(api.GetAllRecipeIDs)
    if not ok or type(all) ~= "table" then return nil, nil, "The game didn't list any recipes." end
    local ids = {}
    for _, id in ipairs(all) do
        local good, info = pcall(api.GetRecipeInfo, id)
        if good and type(info) == "table" and info.learned and type(id) == "number" and id > 0 and id < U.MAX_ID then
            ids[#ids + 1] = id
            if type(info.name) == "string" and info.name ~= "" then names[id] = info.name end
        end
    end
    return prof, ids, #all .. " recipes listed, " .. #ids .. " known"
end

-- Share what changed. Returns how many recipes were sent (0 = nothing new).
function R.Publish(prof, ids)
    if ns.mock or not ns.RBAC.ICan("signup") then return 0 end
    local st = ns.Reducer.State()
    if not st or #ids == 0 then return 0 end
    local have = st.recipes[ns.MyGUID()] and st.recipes[ns.MyGUID()][prof]
    local adds, gone = R.Diff(ids, have)
    local send = adds
    if gone then
        -- A recipe I had shared is no longer known: replace my list.
        send = {}
        local seen = {}
        for _, id in ipairs(ids) do
            if not seen[id] then seen[id] = true; send[#send + 1] = id end
        end
        table.sort(send)
    end
    if #send == 0 then return 0 end
    local sent = 0
    for i, part in ipairs(R.Chunks(send, PER_EVENT)) do
        if ns.Log.New("RECIPES", { p = prof, ids = U.PackIDs(part), reset = (gone and i == 1) or nil }) then
            sent = sent + #part
        end
    end
    return sent
end

-- Read the open window and share. quiet = no chat line when nothing changed.
function R.Scan(quiet)
    local prof, ids, note = R.Read()
    if not prof then
        if not quiet then ns.Print(note) end
        return
    end
    local sent = R.Publish(prof, ids)
    if sent > 0 then
        ns.Print(("Shared %d %s recipes with the guild."):format(sent, prof))
    elseif not quiet then
        ns.Print(("%s: %s. %s"):format(prof, note, ns.mock and "Mock mode is on, so nothing is shared." or "Nothing new to share."))
    end
end

local queued = false
local function scanSoon()
    if queued or not (C_Timer and C_Timer.After) then return end
    queued = true
    C_Timer.After(1.5, function()
        queued = false
        R.Scan(true)
    end)
end
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED" }) do
    ns.On(event, scanSoon)
end
