-- Blood Pact: widgets in Blood Pact's own flat style: dark panels, 1-pixel
-- borders, a blood-red accent and the game's built-in fonts. No images, fonts
-- or art are bundled with the addon; every texture is a flat color.
local _, ns = ...
local W = {}
ns.W = W

---------------------------------------------------------------------------
-- Palette and fonts
---------------------------------------------------------------------------
W.C = {
    bg       = { 0.055, 0.055, 0.065, 0.97 },
    bar      = { 0.035, 0.035, 0.042, 1 },
    panel    = { 0.085, 0.085, 0.10, 1 },
    field    = { 0.04, 0.04, 0.05, 1 },
    border   = { 0.22, 0.22, 0.26, 1 },
    btn      = { 0.13, 0.13, 0.155, 1 },
    btnHover = { 0.19, 0.19, 0.22, 1 },
    accent   = { 0.80, 0.16, 0.16, 1 },
    text     = { 0.93, 0.93, 0.94 },
    muted    = { 0.56, 0.56, 0.60 },
    gold     = { 0.96, 0.80, 0.42 },
}

-- Fonts that ship with the game client.
local BODY = "Fonts\\ARIALN.TTF"
local TITLE = "Fonts\\FRIZQT__.TTF"

local function font(name, file, size, color, base)
    local f = CreateFont(name)
    if base and _G[base] then f:CopyFontObject(_G[base]) end
    f:SetFont(file, size, "")
    f:SetTextColor(color[1], color[2], color[3])
    f:SetShadowColor(0, 0, 0, 0.8)
    f:SetShadowOffset(1, -1)
    return f
end

W.F = {
    title     = font("BloodPactFontTitle", TITLE, 15, W.C.text, "GameFontNormalLarge"),
    header    = font("BloodPactFontHeader", BODY, 14, W.C.gold, "GameFontNormal"),
    headerSm  = font("BloodPactFontHeaderSmall", BODY, 13, W.C.gold, "GameFontNormalSmall"),
    body      = font("BloodPactFontBody", BODY, 14, W.C.text, "GameFontHighlight"),
    bodySm    = font("BloodPactFontBodySmall", BODY, 13, W.C.text, "GameFontHighlightSmall"),
    muted     = font("BloodPactFontMuted", BODY, 12, W.C.muted, "GameFontDisableSmall"),
    disabled  = font("BloodPactFontDisabled", BODY, 13, W.C.muted, "GameFontDisable"),
}

-- Older calls ask for Blizzard font names; map them to ours.
local FONT_MAP = {
    GameFontNormalLarge = W.F.title, GameFontNormal = W.F.header, GameFontNormalSmall = W.F.headerSm,
    GameFontHighlight = W.F.body, GameFontHighlightSmall = W.F.bodySm, GameFontDisableSmall = W.F.muted,
}

---------------------------------------------------------------------------
-- Flat drawing helpers
---------------------------------------------------------------------------
local function crisp(tex)
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    return tex
end

function W.Fill(frame, color, layer)
    local t = crisp(frame:CreateTexture(nil, layer or "BACKGROUND"))
    t:SetAllPoints()
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return t
end

local function onePixel(region, horizontal)
    if PixelUtil and PixelUtil.SetHeight then
        if horizontal then PixelUtil.SetHeight(region, 1) else PixelUtil.SetWidth(region, 1) end
    elseif horizontal then region:SetHeight(1) else region:SetWidth(1) end
end

-- A 1-pixel border inside the frame's edges. Returns the four lines.
function W.Border(frame, color)
    color = color or W.C.border
    local lines = {}
    local function line(p1, p2, horizontal)
        local t = crisp(frame:CreateTexture(nil, "BORDER"))
        t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        t:SetPoint(p1)
        t:SetPoint(p2)
        onePixel(t, horizontal)
        lines[#lines + 1] = t
    end
    line("TOPLEFT", "TOPRIGHT", true)
    line("BOTTOMLEFT", "BOTTOMRIGHT", true)
    line("TOPLEFT", "BOTTOMLEFT", false)
    line("TOPRIGHT", "BOTTOMRIGHT", false)
    function lines.SetColor(_, c)
        for i = 1, 4 do lines[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    end
    return lines
end

-- A horizontal 1-pixel line across a frame at y.
function W.Line(frame, y, color, left, right)
    local t = crisp(frame:CreateTexture(nil, "BORDER"))
    color = color or W.C.border
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    t:SetPoint("TOPLEFT", left or 0, y)
    t:SetPoint("TOPRIGHT", -(right or 0), y)
    onePixel(t, true)
    return t
end

-- Dark panel with a border, for boxes inside a tab.
function W.Panel(frame)
    W.Fill(frame, W.C.panel)
    W.Border(frame)
    return frame
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
-- style: nil (normal), "accent" (primary action) or "tab".
function W.Button(parent, text, width, height, onClick, style)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, height or 22)
    local bg = W.Fill(b, style == "accent" and W.C.accent or W.C.btn)
    local border = W.Border(b)
    b:SetNormalFontObject(W.F.bodySm)
    b:SetHighlightFontObject(W.F.bodySm)
    b:SetDisabledFontObject(style == "tab" and W.F.bodySm or W.F.disabled)
    b:SetText(text)
    local under
    if style == "tab" then
        bg:SetColorTexture(0, 0, 0, 0)
        border:SetColor({ 0, 0, 0, 0 })
        under = crisp(b:CreateTexture(nil, "ARTWORK"))
        under:SetColorTexture(W.C.accent[1], W.C.accent[2], W.C.accent[3], 1)
        under:SetPoint("BOTTOMLEFT")
        under:SetPoint("BOTTOMRIGHT")
        under:SetHeight(2)
        under:Hide()
        b:SetNormalFontObject(W.F.muted)
    end
    local function paint(hover)
        if style == "tab" then
            bg:SetColorTexture(1, 1, 1, hover and b:IsEnabled() and 0.05 or 0)
            return
        end
        local c = style == "accent" and W.C.accent or (hover and b:IsEnabled() and W.C.btnHover or W.C.btn)
        local a = (not b:IsEnabled() and style ~= "tab") and 0.5 or 1
        bg:SetColorTexture(c[1] * (hover and style == "accent" and 1.15 or 1), c[2], c[3], (c[4] or 1) * a)
        border:SetColor(hover and b:IsEnabled() and W.C.accent or W.C.border)
    end
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    b:SetScript("OnEnable", function() if under then under:Hide() end paint(false) end)
    b:SetScript("OnDisable", function() if under then under:Show() end paint(false) end)
    paint(false)
    if onClick and style == "accent" then
        -- Main actions write to the guild's log: ignore an accidental double click.
        local last = -10
        b:SetScript("OnClick", function(self, ...)
            local now = GetTime()
            if now - last < 0.8 then return end
            last = now
            onClick(self, ...)
        end)
    elseif onClick then
        b:SetScript("OnClick", onClick)
    end
    return b
end

function W.Text(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(FONT_MAP[template] or W.F.body)
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

function W.Edit(parent, width, maxLetters)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width or 80, 22)
    e:SetAutoFocus(false)
    e:SetFontObject(W.F.bodySm)
    e:SetTextInsets(6, 6, 0, 0)
    W.Fill(e, W.C.field)
    local border = W.Border(e)
    if maxLetters then e:SetMaxLetters(maxLetters) end
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnEditFocusGained", function() border:SetColor(W.C.accent) end)
    e:SetScript("OnEditFocusLost", function() border:SetColor(W.C.border) end)
    return e
end

function W.Check(parent, label, onClick)
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetSize(16, 16)
    W.Fill(c, W.C.field)
    W.Border(c)
    local mark = crisp(c:CreateTexture(nil, "ARTWORK"))
    mark:SetColorTexture(W.C.accent[1], W.C.accent[2], W.C.accent[3], 1)
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    c:SetCheckedTexture(mark)
    local hl = crisp(c:CreateTexture(nil, "HIGHLIGHT"))
    hl:SetColorTexture(1, 1, 1, 0.08)
    hl:SetAllPoints()
    local fs = W.Text(parent, label, "GameFontHighlightSmall")
    fs:SetPoint("LEFT", c, "RIGHT", 6, 0)
    c.label = fs
    if onClick then c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end) end
    return c
end

-- Scrolling list. render(row, item) fills a row; onClick(item) on click.
-- Only the rows that fit on screen exist, so a 1,000-member guild costs the
-- same as a 20-member one. Set list.key (a field name such as "guid") to keep
-- the selection when the items are rebuilt.
function W.List(parent, width, height, rowHeight, render, onClick)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetSize(width, height)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, rowHeight)
    scroll:SetScrollChild(content)
    local rows, list = {}, { scroll = scroll, items = {}, selected = nil, key = nil }

    local function makeRow()
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(rowHeight)
        row.stripe = crisp(row:CreateTexture(nil, "BACKGROUND"))
        row.stripe:SetAllPoints()
        row.stripe:SetColorTexture(1, 1, 1, 0.025)
        local hl = crisp(row:CreateTexture(nil, "HIGHLIGHT"))
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        row.sel = crisp(row:CreateTexture(nil, "BORDER"))
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(W.C.accent[1], W.C.accent[2], W.C.accent[3], 0.28)
        row.cols = {}
        row:RegisterForClicks("AnyUp")
        row:SetScript("OnClick", function(self)
            list.selected = self.item
            for _, r in ipairs(rows) do r.sel:SetShown(r.item ~= nil and r.item == list.selected) end
            if onClick then onClick(self.item) end
        end)
        rows[#rows + 1] = row
        return row
    end

    -- Draw the rows that are in view.
    local function update()
        local items = list.items
        local viewHeight = scroll:GetHeight() or height
        if viewHeight < rowHeight then viewHeight = height end
        local visible = math.ceil(viewHeight / rowHeight) + 1
        local first = math.floor((scroll:GetVerticalScroll() or 0) / rowHeight)
        if first > #items - 1 then first = math.max(0, #items - 1) end
        for i = 1, math.max(visible, #rows) do
            local index = first + i
            local item = i <= visible and items[index] or nil
            local row = rows[i]
            if item and not row then row = makeRow() end
            if row then
                if item then
                    row.item = item
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
                    row:SetPoint("RIGHT", content, "RIGHT")
                    row.stripe:SetShown(index % 2 == 0)
                    render(row, item)
                    row.sel:SetShown(item == list.selected)
                    row:Show()
                else
                    row.item = nil
                    row:Hide()
                end
            end
        end
    end
    list.Update = update

    function list:SetItems(items)
        self.items = items
        if self.key and self.selected then
            local want, found = self.selected[self.key], nil
            for i = 1, #items do
                if items[i][self.key] == want then found = items[i]; break end
            end
            self.selected = found
        end
        content:SetHeight(math.max(1, #items) * rowHeight)
        local maxScroll = math.max(0, #items * rowHeight - (scroll:GetHeight() or height))
        if (scroll:GetVerticalScroll() or 0) > maxScroll then scroll:SetVerticalScroll(maxScroll) end
        update()
    end

    scroll:HookScript("OnVerticalScroll", update)
    scroll:HookScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        if w and w > 0 then content:SetWidth(w) end
        update()
    end)

    -- Add a text column to every row at x offset with width.
    function list.Col(row, idx, x, w, justify)
        local fs = row.cols[idx]
        if not fs then
            fs = row:CreateFontString(nil, "OVERLAY")
            fs:SetFontObject(W.F.bodySm)
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(w)
            fs:SetJustifyH(justify or "LEFT")
            fs:SetWordWrap(false)
            row.cols[idx] = fs
        end
        return fs
    end

    -- Stretch the list with its parent when the window is resized. right = nil
    -- keeps the width and only stretches the height.
    function list:Stretch(left, top, right, bottom)
        local w = scroll:GetWidth()
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", left, top)
        if right then
            scroll:SetPoint("BOTTOMRIGHT", -right - 22, bottom)
        else
            scroll:SetPoint("BOTTOMLEFT", left, bottom)
            scroll:SetWidth(w)
        end
    end

    return list
end
