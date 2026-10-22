local ADDON = ...
local XS = CreateFrame("Frame")
local floor, max, min = math.floor, math.max, math.min
local defaults = {
    enabled = { mh = true, oh = true, ranged = true },
    width = 340, height = 5, spacing = 25,
    fill = { 0.94, 0.94, 0.94 }, text = { 0.94, 0.94, 0.94 },
    fontSize = 11, showLabels = true, showCountdown = true,
    locked = false, point = { "CENTER", "UIParent", "CENTER", 0, -100 },
}
local db, settings, container
local order = { "mh", "oh", "ranged" }
local names = { mh = "Main Hand", oh = "Off Hand", ranged = "Ranged" }
local timers = { mh = {}, oh = {}, ranged = {} }
local bars = {}
local preview = false
local function copyMissing(dest, src)
    for k, v in pairs(src) do
        if dest[k] == nil then
            if type(v) == "table" then
                dest[k] = {}
                copyMissing(dest[k], v)
            else dest[k] = v end
        elseif type(v) == "table" and type(dest[k]) == "table" then
            copyMissing(dest[k], v)
        end
    end
end
local function now() return GetTime() end
-- WoW Forever can return secret values from combat-related APIs.
-- Even comparing or doing arithmetic on them causes a Lua error.
local function safeNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "number" then return nil end
    return value
end
local function safeValue(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end
local function getSpeed(key)
    if key == "ranged" then
        if UnitRangedDamage then
            local speed = safeNumber(select(1, UnitRangedDamage("player")))
            if speed and speed > 0 then return speed end
        end
        return nil
    end
    local mh, oh = UnitAttackSpeed("player")
    local s
    if key == "mh" then s = safeNumber(mh) else s = safeNumber(oh) end
    return s and s > 0 and s or nil
end
local function active(key) return timers[key].endTime and timers[key].endTime > now() end
local function start(key, eventDuration)
    local speed = safeNumber(eventDuration) or getSpeed(key)
    if not speed or speed <= 0 or speed > 60 then return end
    local t = timers[key]
    local time = now()
    if key == "ranged" and t.lastStart and time - t.lastStart < 0.12 then return end
    t.lastStart = time
    t.speed = speed
    t.startTime = time
    t.endTime = time + speed
end
local function rescale()
    local time = now()
    for _, key in ipairs(order) do
        local t = timers[key]
        local speed = getSpeed(key)
        if t.endTime and t.endTime > time and speed and t.speed and math.abs(speed - t.speed) > 0.01 then
            local frac = min(1, max(0, (time - t.startTime) / t.speed))
            t.speed = speed
            t.startTime = time - frac * speed
            t.endTime = t.startTime + speed
        end
    end
end
local function buildBar(key)
    local holder = CreateFrame("Frame", nil, container)
    -- Bar layers are visual only; never intercept world clicks.
    holder:EnableMouse(false)
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.78)
    local edge = holder:CreateTexture(nil, "BORDER")
    edge:SetColorTexture(0.55, 0.55, 0.55, 0.35)
    edge:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, -1)
    edge:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, -1)
    edge:SetHeight(1)
    local fill = holder:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetWidth(1)
    fill:SetColorTexture(1, 1, 1, 1)
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetJustifyH("LEFT")
    label:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 4)
    local count = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    count:SetJustifyH("RIGHT")
    count:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 0, 4)
    bars[key] = { holder = holder, fill = fill, label = label, count = count }
end
local function layout()
    if not container then return end
    local count = 0
    for _, key in ipairs(order) do if db.enabled[key] then count = count + 1 end end
    container:SetSize(db.width, max(db.height, count * (db.height + db.spacing)))
    local index = 0
    for _, key in ipairs(order) do
        local b = bars[key]
        if db.enabled[key] then
            b.holder:Show()
            b.holder:ClearAllPoints()
            b.holder:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -index * (db.height + db.spacing) - db.fontSize - 5)
            b.holder:SetSize(db.width, db.height)
            b.fill:SetColorTexture(db.fill[1], db.fill[2], db.fill[3], 1)
            b.label:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
            b.count:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
            b.label:SetTextColor(unpack(db.text))
            b.count:SetTextColor(unpack(db.text))
            b.label:SetText(names[key])
            b.label:SetShown(db.showLabels)
            b.count:SetShown(db.showCountdown)
            index = index + 1
        else b.holder:Hide() end
    end
    -- Locking makes the whole display click-through, including bar children.
    -- Dragging is available only while unlocked.
    container:EnableMouse(not db.locked)
    for _, key in ipairs(order) do
        bars[key].holder:EnableMouse(false)
    end
end
local function update()
    local time = now()
    for _, key in ipairs(order) do
        local b, t = bars[key], timers[key]
        local fraction, remain = 0, 0
        if preview then
            fraction = (time % 3) / 3
            remain = (1 - fraction) * 3
        elseif t.endTime and t.endTime > time and t.speed and t.speed > 0 then
            remain = t.endTime - time
            fraction = min(1, max(0, 1 - remain / t.speed))
        end
        b.fill:SetWidth(max(0.1, db.width * fraction))
        b.count:SetText(string.format("%.1fs", remain))
        -- No leftover filled bar after the swing expires.
        b.fill:SetShown(preview or remain > 0)
    end
end
local function setPosition()
    container:ClearAllPoints()
    local p = db.point
    container:SetPoint(p[1] or "CENTER", UIParent, p[3] or "CENTER", p[4] or 0, p[5] or -100)
end
local function savePosition()
    local cx, cy = container:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if cx and ux then
        local scale = container:GetEffectiveScale() / UIParent:GetEffectiveScale()
        db.point = { "CENTER", "UIParent", "CENTER", (cx * scale - ux), (cy * scale - uy) }
    end
end
local function slider(parent, text, minVal, maxVal, step, getter, setter, y)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOP", parent, "TOP", 0, y)
    s:SetSize(235, 16)
    s:SetMinMaxValues(minVal, maxVal)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s.Low:SetText(tostring(minVal))
    s.High:SetText(tostring(maxVal))
    s.Text:SetText(text .. ": " .. tostring(getter()))
    s:SetValue(getter())
    s:SetScript("OnValueChanged", function(self, value)
        value = floor(value / step + 0.5) * step
        setter(value)
        self.Text:SetText(text .. ": " .. tostring(value))
        layout()
    end)
    return s
end
local function checkbox(parent, title, checked, click, x, y)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetPoint("TOPLEFT", x, y)
    c:SetSize(24, 24)
    c:SetChecked(checked)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", c, "RIGHT", 3, 0)
    fs:SetText(title)
    c:SetScript("OnClick", function(self) click(not not self:GetChecked()); layout() end)
    return c
end
local function colorPicker(which)
    local old = { unpack(db[which]) }
    local function apply(r, g, b)
        db[which] = { r, g, b }
        layout()
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = old[1], g = old[2], b = old[3], hasOpacity = false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                apply(r, g, b)
            end,
            cancelFunc = function(previous)
                if type(previous) == "table" then apply(previous.r or old[1], previous.g or old[2], previous.b or old[3])
                else apply(unpack(old)) end
            end,
        })
    else
        ColorPickerFrame.func = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            apply(r, g, b)
        end
        ColorPickerFrame.cancelFunc = function() apply(unpack(old)) end
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(unpack(old))
        ColorPickerFrame:Show()
    end
end
local function button(parent, label, x, y, width, callback)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 25)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", callback)
    return b
end
local function createSettings()
    local f = CreateFrame("Frame", "SwingerSettings", UIParent, "BackdropTemplate")
    f:SetSize(340, 555)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.055, 0.075, 0.085, 0.97)
    f:SetBackdropBorderColor(0.28, 0.32, 0.34, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("Swinger")
    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 18, -39)
    subtitle:SetText("Minimalist swing timer  |  v0.1.3-dev")
    button(f, "X", 300, -11, 27, function() f:Hide() end)
    local section = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section:SetPoint("TOPLEFT", 20, -76)
    section:SetText("Visible timers")
    checkbox(f, "Main Hand", db.enabled.mh, function(v) db.enabled.mh = v end, 18, -95)
    checkbox(f, "Off Hand", db.enabled.oh, function(v) db.enabled.oh = v end, 165, -95)
    checkbox(f, "Ranged", db.enabled.ranged, function(v) db.enabled.ranged = v end, 18, -123)
    checkbox(f, "Show labels", db.showLabels, function(v) db.showLabels = v end, 165, -123)
    checkbox(f, "Countdown text", db.showCountdown, function(v) db.showCountdown = v end, 18, -151)
    local locked = checkbox(f, "Lock position", db.locked, function(v) db.locked = v end, 165, -151)
    local visual = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    visual:SetPoint("TOPLEFT", 20, -194)
    visual:SetText("Appearance")
    slider(f, "Bar width", 100, 650, 5, function() return db.width end, function(v) db.width = v end, -235)
    slider(f, "Bar height", 2, 35, 1, function() return db.height end, function(v) db.height = v end, -288)
    slider(f, "Text size", 8, 24, 1, function() return db.fontSize end, function(v) db.fontSize = v end, -341)
    slider(f, "Bar spacing", 10, 55, 1, function() return db.spacing end, function(v) db.spacing = v end, -394)
    button(f, "Fill colour", 20, -443, 140, function() colorPicker("fill") end)
    button(f, "Text colour", 180, -443, 140, function() colorPicker("text") end)
    button(f, "Reset position", 20, -491, 140, function()
        db.point = { "CENTER", "UIParent", "CENTER", 0, -100 }
        setPosition()
    end)
    local demo = button(f, "Preview: On", 180, -491, 140, function(self)
        preview = not preview
        self:SetText(preview and "Preview: On" or "Preview: Off")
    end)
    f:SetScript("OnShow", function() preview = true; demo:SetText("Preview: On") end)
    f:SetScript("OnHide", function() preview = false end)
    settings = f
end
local function init()
    SwingerDB = SwingerDB or XenSwingDB or {}
    db = SwingerDB
    copyMissing(db, defaults)
    container = CreateFrame("Frame", "SwingerBars", UIParent)
    container:SetFrameStrata("MEDIUM")
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
    container:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)
    setPosition()
    for _, key in ipairs(order) do buildBar(key) end
    layout()
    createSettings()
    container:SetScript("OnUpdate", function(_, elapsed)
        XS.elapsed = (XS.elapsed or 0) + elapsed
        if XS.elapsed > 0.025 then XS.elapsed = 0; update() end
    end)
    SLASH_SWINGER1 = "/swinger"
    SLASH_SWINGER2 = "/xswing"
    SlashCmdList.SWINGER = function(msg)
        msg = (msg or ""):lower()
        if msg == "reset" then
            db.point = { "CENTER", "UIParent", "CENTER", 0, -100 }
            setPosition()
            print("|cffb8e3d1Swinger|r position reset.")
        elseif msg == "lock" then
            db.locked = not db.locked; layout()
            print("|cffb8e3d1Swinger|r " .. (db.locked and "locked" or "unlocked") .. ".")
        else
            if settings:IsShown() then settings:Hide() else settings:Show() end
        end
    end
    print("|cffb8e3d1Swinger|r loaded. Type /swinger for settings.")
end
-- WoW Forever provides an explicit, readable native swing event:
-- PLAYER_SWING(swingDuration, swingType); Enum.PlayerSwingType 0/1/2.
-- IMPORTANT: Never register COMBAT_LOG_EVENT_UNFILTERED on Forever.
-- The modern client forbids that event and raises ADDON_ACTION_FORBIDDEN.
XS:RegisterEvent("ADDON_LOADED")
XS:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON then
            init()
            XS:RegisterEvent("PLAYER_SWING")
            -- These events can update our *cached* speeds outside protected contexts.
            XS:RegisterEvent("UNIT_ATTACK_SPEED")
            XS:RegisterEvent("UNIT_RANGEDDAMAGE")
            XS:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        end
        return
    end
    if not db then return end
    if event == "PLAYER_SWING" then
        local duration, swingType = ...
        duration = safeNumber(duration)
        swingType = safeNumber(swingType)
        if duration and swingType then
            local key = swingType == 0 and "mh" or swingType == 1 and "oh" or swingType == 2 and "ranged" or nil
            if key then start(key, duration) end
        end
    elseif event == "UNIT_ATTACK_SPEED" or event == "UNIT_RANGEDDAMAGE" then
        local unit = safeValue(...)
        if unit == nil or unit == "player" then rescale() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        rescale()
    end
end)
