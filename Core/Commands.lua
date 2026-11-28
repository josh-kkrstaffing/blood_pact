-- Speakeasy: slash commands and the addon-compartment entry.
local _, ns = ...

local function help()
    ns.Print("/spk or /bloodpact - open or close the window")
    ns.Print("/spk whoami - show your character GUID and role")
    ns.Print("/spk sync - announce your data to the guild now")
    ns.Print("/spk mock on|off|boss|award|forge|signups|attend|roster|summon|reset - solo test mode")
    ns.Print("/spk status - sync and message queue details")
    ns.Print("/spk about - who makes Speakeasy and how to join us")
    ns.Print("/spk prof - read your professions now, share them, and show what the game reported")
    ns.Print("/spk recipes - with a profession window open: record and share its recipes now")
    ns.Print("/spk pvp - read your PvP rank now, share it, and show what the game reported")
    ns.Print("/spk mail - at a mailbox: list the crafting orders you can mail")
    ns.Print("/spk summon - warlocks: open the summon queue (people type 123 to join it)")
end

SLASH_SPEAKEASY1 = "/spk"
SLASH_SPEAKEASY2 = "/speakeasy"
SLASH_SPEAKEASY3 = "/bp"          -- the old command, kept quietly for habit
SlashCmdList.SPEAKEASY = function(input)
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
    elseif cmd == "pvp" or cmd == "rank" then
        ns.PvP.Diagnose()
    elseif cmd == "recipes" or cmd == "recipe" then
        ns.Recipes.Scan(false)
    elseif cmd == "summon" or cmd == "queue" or cmd == "123" then
        ns.SummonQueue.Show(false)
    elseif cmd == "mail" then
        ns.Mail.Show(false)
    elseif cmd == "about" or cmd == "discord" then
        for _, line in ipairs(ns.AboutLines()) do ns.Print(line) end
        ns.UI.ShowAbout()
    elseif cmd == "status" then
        local g = ns.G()
        local n, provisional = 0, 0
        if g then n, provisional = ns.Log.Count(g) end
        local s = ns.Comm.stats
        ns.Print(("%s | events %d (%d provisional) | queue %d | sent %d, received %d, lockdown holds %d, throttled %d")
            :format(ns.Sync.Status(), n, provisional, ns.Comm.QueueLength(), s.sent, s.received, s.lockdowns, s.throttled))
        -- For working out why data looks lost or stuck.
        local mine, own = 0, ns.MyGUID()
        if g then for _, e in pairs(g.log) do if e.a == own then mine = mine + 1 end end end
        local inInstance = IsInInstance and select(2, IsInInstance()) or "?"
        ns.Print(("v%s | role %s | guild key %s | my records %d | place %s | last hold %s%s"):format(ns.VERSION,
            tostring(ns.RBAC.RoleOf(own) or "none"), tostring(ns.GuildKey()), mine, tostring(inInstance),
            tostring(ns.Comm.lastHold or "none"), ns.Comm.lastError and (" (" .. ns.Comm.lastError .. ")") or ""))
        local stores = {}
        for key, store in pairs(ns.db and ns.db.guilds or {}) do
            local count = 0
            for _ in pairs(store.log or {}) do count = count + 1 end
            stores[#stores + 1] = key .. " = " .. count
        end
        table.sort(stores)
        ns.Print("Saved guild data: " .. (#stores > 0 and table.concat(stores, "; ") or "none"))
    else
        help()
    end
end

-- Named in the TOC as AddonCompartmentFunc.
function Speakeasy_OnCompartmentClick()
    ns.UI.Toggle()
end
