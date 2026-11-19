-- Blood Pact: small widget helpers built on Blizzard's own UI templates.
-- No images or art are bundled with the addon.
local _, ns = ...
local W = {}
ns.W = W

function W.Button(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 120, height or 22)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

function W.Text(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

function W.Edit(parent, width, maxLetters)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width or 80, 20)
    e:SetAutoFocus(false)
    if maxLetters then e:SetMaxLetters(maxLetters) end
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
end

function W.Check(parent, label, onClick)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    local fs = W.Text(parent, label, "GameFontHighlightSmall")
    fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.label = fs
    if onClick then c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end) end
    return c
end

-- Scrolling list. render(row, item) fills a row; onClick(item) on click.
function W.List(parent, width, height, rowHeight, render, onClick)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetSize(width, height)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, rowHeight)
    scroll:SetScrollChild(content)
    local rows, list = {}, { scroll = scroll, items = {}, selected = nil }

    function list:SetItems(items)
        self.items = items
        for i = 1, math.max(#items, #rows) do
            local row = rows[i]
            if not row and items[i] then
                row = CreateFrame("Button", nil, content)
                row:SetSize(width, rowHeight)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row.sel = row:CreateTexture(nil, "BACKGROUND")
                row.sel:SetAllPoints()
                row.sel:SetColorTexture(0.55, 0.1, 0.1, 0.35)
                row.cols = {}
                row:RegisterForClicks("AnyUp")
                row:SetScript("OnClick", function(self)
                    list.selected = self.item
                    for _, r in ipairs(rows) do r.sel:SetShown(r.item ~= nil and r.item == list.selected) end
                    if onClick then onClick(self.item) end
                end)
                rows[i] = row
            end
            if row then
                if items[i] then
                    row.item = items[i]
                    render(row, items[i])
                    row.sel:SetShown(items[i] == list.selected)
                    row:Show()
                else
                    row.item = nil
                    row:Hide()
                end
            end
        end
        content:SetHeight(math.max(1, #items) * rowHeight)
    end

    -- Add a text column to every row at x offset with width.
    function list.Col(row, idx, x, w, justify)
        local fs = row.cols[idx]
        if not fs then
            fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(w)
            fs:SetJustifyH(justify or "LEFT")
            fs:SetWordWrap(false)
            row.cols[idx] = fs
        end
        return fs
    end

    return list
end
