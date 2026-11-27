-- Blood Pact: Drink of the Night. Whoever schedules a raid can give it a
-- drink, and the recipe shows on the raid's sign-up screen so raiders can
-- shop for it before raid night. The built-in list leans on Nashville,
-- Tennessee: recipes published by its bars and distilleries. A guild can
-- type its own too. Purely for fun; nothing here touches DKP or sign-ups.
local _, ns = ...
local D = {}
ns.Drinks = D

local U, RBAC, Red = ns.U, ns.RBAC, ns.Reducer

D.MAX_NAME, D.MAX_RECIPE = 40, 240

-- from = who published it. zero = no alcohol.
D.LIST = {
    { name = "Bushwacker", from = "Nashville's signature frozen drink",
        recipe = "Blend rum, Kahlua, cream of coconut, creme de cacao, milk and ice until smooth. Nutmeg on top." },
    { name = "Smoked Maple Old Fashioned", from = "Bar Tenn at Holston House, Nashville",
        recipe = "2 oz Tennessee whiskey, 1 oz smoked maple syrup, 3 dashes Angostura bitters. Stir over ice." },
    { name = "Cade's Cove", from = "A Nashville bar, published by Nashville Lifestyles",
        recipe = "1.5 oz Tennessee whiskey, 3/4 oz lemon juice, 3/8 oz Italicus, 3/8 oz blackberry jam, 3 dashes Peychaud's bitters, 5 mint leaves. Shake, strain over 2 oz ginger beer." },
    { name = "Just to Satisfy You", from = "A Nashville bar, published by Nashville Lifestyles",
        recipe = "2 oz toasted coconut rum, a little cold brew liqueur, 1/2 oz simple syrup, 1.5 oz espresso. Shake hard until frothy, strain into a coupe, 3 espresso beans." },
    { name = "Summer's End", from = "Aaron Burns, Barlines, Nashville",
        recipe = "Muddle 2 strawberries. Add 1.5 oz bourbon, 1/2 oz elderflower liqueur, 1/2 oz simple syrup, 3 dashes bitters. Shake, strain over ice, lemon peel." },
    { name = "Tennessee Mule", from = "A Nashville favorite",
        recipe = "2 oz Tennessee whiskey, 1/2 oz lime juice, 4 oz ginger beer. Build over ice in a copper mug, lime wedge." },
    { name = "Lynchburg Lemonade", from = "Named for Lynchburg, Tennessee",
        recipe = "1.5 oz Tennessee whiskey, 1 oz triple sec, 1 oz lemon juice. Pour over ice, top with lemon-lime soda." },
    { name = "Shirley Temple", from = "Zero proof", zero = true,
        recipe = "Ginger ale over ice, a splash of grenadine, a cherry." },
    { name = "Arnold Palmer", from = "Zero proof", zero = true,
        recipe = "Half iced tea, half lemonade, over ice." },
}

---------------------------------------------------------------------------
-- Pure rules
---------------------------------------------------------------------------
local function tidy(text)
    return (tostring(text or ""):gsub("|", ""):gsub("%c", " "):gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

function D.Find(name)
    for _, d in ipairs(D.LIST) do if d.name == name then return d end end
    return nil
end

-- A drink ready to save. -> name, recipe; or nil and why.
function D.Clean(name, recipe)
    name, recipe = tidy(name), tidy(recipe)
    if name == "" then return nil, "Give the drink a name." end
    if #name > D.MAX_NAME then return nil, ("Keep the name to %d letters."):format(D.MAX_NAME) end
    if recipe == "" then return nil, "Type the recipe, so raiders know what to buy." end
    if #recipe > D.MAX_RECIPE then return nil, ("Keep the recipe to %d letters."):format(D.MAX_RECIPE) end
    return name, recipe
end

-- The drink set for a raid: { name, recipe, from } or nil.
function D.For(st, raidId)
    local d = st and st.raidDrinks and st.raidDrinks[raidId]
    if not d then return nil end
    local known = D.Find(d.name)
    return { name = d.name, recipe = d.recipe, from = known and known.recipe == d.recipe and known.from or "The guild's own" }
end

-- Tonight's drink: the drink of the next raid that hasn't finished (raids
-- count as running for six hours). raids = time-ordered, as R.List gives.
function D.Tonight(st, raids, now)
    for _, r in ipairs(raids or {}) do
        if r.at >= now - 6 * 3600 then
            local d = D.For(st, r.id)
            return d, r
        end
    end
    return nil
end

function D.Line(drink) return "Drink of the night: " .. drink.name .. "!" end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
function D.Set(raidId, name, recipe)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can set the drink of the night." end
    if not raidId then return nil, "Pick a raid first." end
    local n, r = D.Clean(name, recipe)
    if not n then return nil, r end
    return ns.Log.New("RAID_DRINK", { ev = raidId, on = true, name = n, recipe = r })
end

function D.Clear(raidId)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can set the drink of the night." end
    if not raidId then return nil, "Pick a raid first." end
    return ns.Log.New("RAID_DRINK", { ev = raidId, on = false })
end

---------------------------------------------------------------------------
-- The window: the recipe for everyone, the picker for Team Captains
---------------------------------------------------------------------------
local W = ns.W
local raidId, shown, lastNote

local function build()
    local f = CreateFrame("Frame", "BloodPactDrink", UIParent)
    f:SetSize(520, 330)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:EnableMouse(true)
    W.Glass(f, true)
    f.title = W.Text(f, "", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -9)
    f.title:SetWidth(460)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    W.Button(f, "X", 22, 20, function() f:Hide() end):SetPoint("TOPRIGHT", -6, -6)
    W.Line(f, -32)

    -- Left: the menu. Right: the recipe card.
    f.menuHead = W.Text(f, "The menu", "GameFontNormalSmall")
    f.menuHead:SetPoint("TOPLEFT", 12, -42)
    f.menu = W.List(f, 200, 180, 20, function(row, d)
        local name = f.menu.Col(row, 1, 4, 190)
        name:SetText(U.Safe(d.name, D.MAX_NAME))
        local on = shown and shown.name == d.name
        name:SetTextColor(on and W.C.accent[1] or 1, on and W.C.accent[2] or 1, on and W.C.accent[3] or 1)
    end, function(d)
        shown, lastNote = d, nil
        D.Refresh()
    end)
    f.menu.scroll:SetPoint("TOPLEFT", 12, -60)
    f.menu.scroll:SetSize(200, 180)

    f.name = W.Text(f, "", "GameFontNormalLarge")
    f.name:SetPoint("TOPLEFT", 230, -42)
    f.name:SetWidth(278)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.from = W.Text(f, "", "GameFontDisableSmall")
    f.from:SetPoint("TOPLEFT", 230, -64)
    f.from:SetWidth(278)
    f.from:SetJustifyH("LEFT")
    f.from:SetWordWrap(false)
    f.recipe = W.Text(f, "", "GameFontHighlight")
    f.recipe:SetPoint("TOPLEFT", 230, -86)
    f.recipe:SetWidth(278)
    f.recipe:SetJustifyH("LEFT")
    f.recipe:SetJustifyV("TOP")
    f.recipe:SetWordWrap(true)

    local function done(ok, why)
        lastNote = ok and "Set. It shows on the raid's sign-up screen." or why
        D.Refresh()
    end
    f.set = W.Button(f, "Make this the drink of the night", 230, 24, function()
        if shown then done(D.Set(raidId, shown.name, shown.recipe)) end
    end, "accent")
    f.set:SetPoint("TOPLEFT", 230, -216)
    f.clear = W.Button(f, "No drink", 70, 24, function()
        local ok, why = D.Clear(raidId)
        lastNote = ok and "Cleared." or why
        D.Refresh()
    end)
    f.clear:SetPoint("TOPLEFT", 438, -216)

    -- Team Captains: the guild's own drink.
    f.ownHead = W.Text(f, "Or your own:", "GameFontHighlightSmall")
    f.ownHead:SetPoint("TOPLEFT", 12, -254)
    f.ownName = W.Edit(f, 120, D.MAX_NAME)
    f.ownName:SetPoint("TOPLEFT", 88, -250)
    f.ownRecipe = W.Edit(f, 222, D.MAX_RECIPE)
    f.ownRecipe:SetPoint("TOPLEFT", 214, -250)
    f.ownSet = W.Button(f, "Set", 66, 22, function()
        local ok, why = D.Set(raidId, f.ownName:GetText(), f.ownRecipe:GetText())
        if ok then f.ownName:SetText(""); f.ownRecipe:SetText("") end
        done(ok, why)
    end)
    f.ownSet:SetPoint("TOPLEFT", 442, -250)
    f.ownHint = W.Text(f, "Name, then the recipe.", "GameFontDisableSmall")
    f.ownHint:SetPoint("TOPLEFT", 88, -276)

    f.status = W.Text(f, "", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 12, 10)
    f.status:SetWidth(496)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)
    f:Hide()
    D.frame = f
    return f
end

function D.Refresh()
    local f = D.frame
    if not (f and f:IsShown()) then return end
    local st = Red.State()
    local raid = st and st.raids and st.raids[raidId]
    local current = D.For(st, raidId)
    local captain = RBAC.ICan("schedule")
    f.title:SetText("Drink of the night" .. (raid and (": " .. U.Safe(raid.title, 40)) or ""))
    shown = shown or current or D.LIST[1]
    f.name:SetText(U.Safe(shown.name, D.MAX_NAME))
    f.from:SetText(U.Safe(shown.from or "The guild's own", 60))
    f.recipe:SetText(U.Safe(shown.recipe, D.MAX_RECIPE))
    f.menu:SetItems(D.LIST)
    local isCurrent = current ~= nil and current.name == shown.name and current.recipe == shown.recipe
    f.set:SetShown(captain)
    f.set:SetEnabled(raid ~= nil and not isCurrent)
    f.set:SetText(isCurrent and "This is tonight's drink" or "Make this the drink of the night")
    f.clear:SetShown(captain and current ~= nil)
    for _, w in ipairs({ f.ownHead, f.ownName, f.ownRecipe, f.ownSet, f.ownHint }) do w:SetShown(captain) end
    if lastNote then
        f.status:SetText("|cffffd100" .. lastNote .. "|r")
    elseif current then
        f.status:SetText("This raid's drink: " .. U.Safe(current.name, D.MAX_NAME) .. ". Please drink responsibly, and zero proof counts.")
    elseif captain then
        f.status:SetText("No drink set for this raid yet. Pick one from the menu.")
    else
        f.status:SetText("No drink set for this raid yet. Browse the menu while you wait.")
    end
end

-- Open on a raid's drink (or the menu, when it has none yet).
function D.Open(id)
    local f = D.frame or build()
    raidId, lastNote = id, nil
    shown = D.For(Red.State(), id)
    f:Show()
    D.Refresh()
end

ns.Listen("LOG_CHANGED", function() D.Refresh() end)
