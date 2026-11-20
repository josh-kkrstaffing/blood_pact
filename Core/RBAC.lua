-- Blood Pact: role-based access control.
-- ADMIN is the developer's permanent root role, pinned to character GUIDs in
-- this file. No in-game event can add, remove or restrict it; only a new
-- release can. Every other role comes from the guild rank index.
local _, ns = ...
local R = {}
ns.RBAC = R

-- Developer character GUIDs. Run /bp whoami on each character and paste here.
R.ROOT_ADMINS = {
    "Player-6930-004DE880",   -- Binky Bee (developer)
}

R.LEVEL = { admin = 0, gm = 1, officer = 2, captain = 3, veteran = 4, member = 5, initiate = 6 }
R.LABEL = {
    admin = "ADMIN", gm = "Guild Master", officer = "Officer", captain = "Team Captain",
    veteran = "Veteran", member = "Member", initiate = "Initiate",
}

-- Default map from in-game rank index (0 = Guild Master) to role.
R.DEFAULT_RANKMAP = { [0] = "gm", [1] = "officer", [2] = "captain", [3] = "veteran", [4] = "member", [5] = "initiate" }

-- Lowest role allowed to perform each action.
R.ACTIONS = {
    devtools    = "admin",
    settings    = "gm",
    decay       = "gm",
    award       = "officer",
    spend       = "officer",
    void        = "officer",
    altlink     = "officer",
    recruitEdit = "officer",
    tickets     = "captain",      -- read and work the guild's tickets
    recruit     = "captain",
    schedule    = "captain",
    roster      = "captain",
    signup      = "initiate",
    view        = "initiate",
}

function R.IsRootAdmin(guid)
    for i = 1, #R.ROOT_ADMINS do
        if R.ROOT_ADMINS[i] == guid then return true end
    end
    return false
end

-- Returns the role for a character GUID, or nil if not in the guild roster.
function R.RoleOf(guid)
    if not guid then return nil end
    if R.IsRootAdmin(guid) then return "admin" end
    local entry = ns.roster.byGUID[guid]
    if not entry or entry.rankIndex == nil then return nil end
    return R.DEFAULT_RANKMAP[entry.rankIndex] or "initiate"
end

function R.Can(guid, action)
    local need = R.ACTIONS[action]
    if not need then return false end
    local role = R.RoleOf(guid)
    if not role then return false end
    return R.LEVEL[role] <= R.LEVEL[need]
end

function R.ICan(action)
    return R.Can(ns.MyGUID(), action)
end
