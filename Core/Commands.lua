-- Blood Pact: slash commands and the addon-compartment entry.
local _, ns = ...

local function help()
    ns.Print("/bp or /bloodpact - open or close the window")
    ns.Print("/bp whoami - show your character GUID and role")
    ns.Print("/bp sync - announce your data to the guild now")
    ns.Print("/bp mock on|off|boss|award|forge|signups|attend|roster|summon|reset - solo test mode")
    ns.Print("/bp status - sync and message queue details")
    ns.Print("/bp prof - read your professions now, share them, and show what the game reported")
    ns.Print("/bp recipes - with a profession window open: record and share its recipes now")
end

SLASH_BLOODPACT1 = "/bp"
SLASH_BLOODPACT2 = "/bloodpact"
SlashCmdList.BLOODPACT = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.UI.Toggle()
    elseif cmd == "whoami" then
        local role = ns.RBAC.RoleOf(ns.MyGUID())
        ns.Print("GUID: " .. tostring(ns.MyGUID()) .. "  Role: " .. (role and ns.RBAC.LABEL[role] or "none"))
    elseif cmd == "sync" then
        ns.Sync.SendHello()
        ns.Print("Sync announced.")
    elseif cmd == "mock" then
        ns.Mock.Command(rest)
    elseif cmd == "prof" or cmd == "profs" or cmd == "professions" then
        ns.Professions.Diagnose()
    elseif cmd == "recipes" or cmd == "recipe" then
        ns.Recipes.Scan(false)
    elseif cmd == "status" then
        local g = ns.G()
        local n, provisional = 0, 0
        if g then n, provisional = ns.Log.Count(g) end
        local s = ns.Comm.stats
        ns.Print(("%s | events %d (%d provisional) | queue %d | sent %d, received %d, lockdown holds %d, throttled %d")
            :format(ns.Sync.Status(), n, provisional, ns.Comm.QueueLength(), s.sent, s.received, s.lockdowns, s.throttled))
    else
        help()
    end
end

-- Named in the TOC as AddonCompartmentFunc.
function BloodPact_OnCompartmentClick()
    ns.UI.Toggle()
end
