-- Blind Tiger: the minimap button. A small round tiger on the edge of the
-- minimap: click to open the window, right-click for the Casino, drag to
-- move it round the edge. /tiger minimap hides it or brings it back.
-- Written for this addon; it uses no button library.
local _, ns = ...
local B = {}
ns.MiniButton = B

B.DEFAULT_ANGLE = 215     -- degrees, anticlockwise from the right: the lower left
B.SIZE = 30
B.PAD = 4                 -- how far outside the minimap's edge the button's centre sits

-- Where the button goes for an angle, on a round or a square minimap. -> x, y from the minimap's centre
function B.Place(angle, square, width, height)
    local a = math.rad(angle)
    local x, y = math.cos(a), math.sin(a)
    local rx, ry = width / 2 + B.PAD, height / 2 + B.PAD
    if square then
        local scale = 1 / math.max(math.abs(x), math.abs(y))
        return x * scale * rx, y * scale * ry
    end
    return x * rx, y * ry
end

-- The angle from the minimap's centre to a point. -> degrees, 0..360
function B.AngleTo(dx, dy)
    if dx == 0 and dy == 0 then return B.DEFAULT_ANGLE end
    return math.deg(math.atan2(dy, dx)) % 360
end

local function saved()
    ns.db.minimap = ns.db.minimap or {}
    return ns.db.minimap
end

-- Square-minimap addons say so through this shared function; without it the minimap is round.
local function isSquare()
    local shape = GetMinimapShape and GetMinimapShape()
    return shape ~= nil and shape ~= "ROUND"
end

function B.Update()
    local b = B.button
    if not b then return end
    local s = saved()
    b:SetShown(not s.hide)
    local x, y = B.Place(s.angle or B.DEFAULT_ANGLE, isSquare(), Minimap:GetWidth(), Minimap:GetHeight())
    B.at = { x, y }
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function B.Hidden() return saved().hide == true end

function B.SetHidden(hide)
    saved().hide = hide and true or nil
    B.Update()
end

local function follow()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    saved().angle = B.AngleTo(px / scale - mx, py / scale - my)
    B.Update()
end

local function build()
    if B.button or not Minimap then return end
    local b = CreateFrame("Button", "BlindTigerMinimapButton", Minimap)
    b:SetSize(B.SIZE, B.SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\BlindTiger\\Media\\mini")
    icon:SetAllPoints()
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetTexture("Interface\\AddOns\\BlindTiger\\Media\\mini")
    glow:SetAllPoints()
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.35)
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns.Casino.Toggle() else ns.UI.Toggle() end
    end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", follow) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.BRAND)
        GameTooltip:AddLine("Click to open or close the window.", 1, 1, 1)
        GameTooltip:AddLine("Right-click for the Casino.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move. /tiger minimap hides it.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    B.button = b
    B.Update()
end

ns.On("PLAYER_LOGIN", function() if ns.db then build() end end)
