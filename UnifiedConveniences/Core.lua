local addonName, addon = ...

local title = "Unified Conveniences"
local sliderStep = 5
local sliderLabelMargin = 5
local defaultSliderMax = 50
local settingsRowHeight = 26
local settingsRowLeft = 10
local settingsRowRight = 20
local settingsLabelInset = 37
local settingsControlOffset = -80
local defaults = {
    showZeppelinDestination = false,
    zeppelinVerticalOffset = 10,
    zeppelinHorizontalOffset = 0,
}

local function IsFinite(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

if not IsFinite(UCOffsetSliderMax) or UCOffsetSliderMax <= 0 then
    UCOffsetSliderMax = defaultSliderMax
end

local function AddText(panel, text, font, x, y)
    local label = panel:CreateFontString(nil, "ARTWORK", font)
    label:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function FormatOffset(value)
    local text = tostring(value)
    if tonumber(text) == value then
        return text
    end
    return string.format("%.17g", value)
end

local function CreateSettingRow(panel, name, y)
    -- Mirror the native scroll list's row bounds and its label column.
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(settingsRowHeight)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", settingsRowLeft, y)
    row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -settingsRowRight, y)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", settingsLabelInset, 0)
    label:SetPoint("RIGHT", row, "CENTER", settingsControlOffset - 5, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(name)
    return row
end

local function CreateOffsetRow(panel, label, y, db, key, refreshNameplates)
    local row = CreateSettingRow(panel, label, y)
    local control = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
    control:SetPoint("LEFT", row, "CENTER", settingsControlOffset, 3)
    control:SetWidth(250)
    local slider = control.Slider

    control.MinText:ClearAllPoints()
    control.MinText:SetPoint("TOP", slider.Left, "BOTTOMLEFT", sliderLabelMargin, -sliderLabelMargin)
    control.MaxText:ClearAllPoints()
    control.MaxText:SetPoint("TOP", slider.Right, "BOTTOMRIGHT", -sliderLabelMargin, -sliderLabelMargin)
    local zeroLabel = control:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    zeroLabel:SetPoint("TOP", slider.Middle, "BOTTOM", 0, -sliderLabelMargin)
    zeroLabel:SetText("0")

    local input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    input:SetPoint("LEFT", control, "RIGHT", 12, 0)
    input:SetSize(96, 22)
    input:SetAutoFocus(false)
    input:SetJustifyH("CENTER")

    local syncingSlider = false
    local sliderMax

    local function GetThumbValue(value)
        local minimum, maximum = slider:GetMinMaxValues()
        if value <= minimum or value >= maximum then
            return math.max(minimum, math.min(maximum, value))
        end
        -- The field retains the exact value while the thumb snaps to a slider step.
        local steps = math.floor((value - minimum) / sliderStep + 0.5)
        return math.min(maximum, minimum + steps * sliderStep)
    end

    local function SyncValue()
        local value = db[key]
        syncingSlider = true
        control:SetValue(GetThumbValue(value))
        syncingSlider = false
        input:SetText(FormatOffset(value))
    end

    local function SaveOffset(value)
        if IsFinite(value) and db[key] ~= value then
            db[key] = value
            refreshNameplates()
        end
        SyncValue()
    end

    local function RefreshRow()
        local maximum = UCOffsetSliderMax
        if not IsFinite(maximum) or maximum <= 0 then
            maximum = defaultSliderMax
        end
        if maximum ~= sliderMax then
            sliderMax = maximum
            local labels = MinimalSliderWithSteppersMixin.Label
            local minimumText, maximumText = FormatOffset(-maximum), FormatOffset(maximum)
            local formatters = {
                [labels.Min] = function() return minimumText end,
                [labels.Max] = function() return maximumText end,
            }
            syncingSlider = true
            control:Init(0, -maximum, maximum, 2 * maximum / sliderStep, formatters)
            syncingSlider = false
        end
        SyncValue()
    end

    control:RegisterCallback("OnValueChanged", function(_, value)
        if not syncingSlider then
            SaveOffset(value)
        end
    end, control)
    input:SetScript("OnEditFocusLost", function(self)
        local text = self:GetText()
        if text:match("^%s*[+-]?0[xX]") then
            SyncValue()
            return
        end
        SaveOffset(tonumber(text))
    end)
    input:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", function(self)
        SyncValue()
        self:ClearFocus()
    end)

    return RefreshRow
end

local function RegisterOptions(db, refreshNameplates)
    local panel = CreateFrame("Frame")
    panel:Hide()
    AddText(panel, title, "GameFontHighlightHuge", 7, -22)
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", panel, "TOP", 0, -50)

    local defaultsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    defaultsButton:SetSize(96, 22)
    defaultsButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -36, -16)
    defaultsButton:SetText("Defaults")

    AddText(panel, "Nameplates", "GameFontHighlightLarge", 17, -78)
    AddText(panel, "NPC", "GameFontHighlight", 24, -102)

    local checkboxName = "Zeppelin Destinations"
    local checkboxRow = CreateSettingRow(panel, checkboxName, -124)
    local checkbox = CreateFrame("CheckButton", nil, checkboxRow, "SettingsCheckboxTemplate")
    checkbox:SetPoint("LEFT", checkboxRow, "CENTER", settingsControlOffset, 0)
    checkbox:SetTooltipFunc(function()
        Settings.InitTooltip(checkboxName, "Show destinations on friendly nameplates and in mouseover tooltips.")
    end)
    checkbox:SetScript("OnClick", function(self)
        db.showZeppelinDestination = self:GetChecked() and true or false
        refreshNameplates()
    end)

    local refreshVertical = CreateOffsetRow(panel, "Vertical Offset", -159, db, "zeppelinVerticalOffset", refreshNameplates)
    local refreshHorizontal = CreateOffsetRow(panel, "Horizontal Offset", -207, db, "zeppelinHorizontalOffset", refreshNameplates)

    AddText(panel, "About", "GameFontHighlightLarge", 17, -270)
    AddText(panel, "Version: " .. C_AddOns.GetAddOnMetadata(addonName, "Version"), "GameFontNormal", settingsRowLeft + settingsLabelInset, -300)
    AddText(panel, "Author: " .. C_AddOns.GetAddOnMetadata(addonName, "Author"), "GameFontNormal", settingsRowLeft + settingsLabelInset, -322)

    local function RefreshOptions()
        checkbox:SetChecked(db.showZeppelinDestination)
        refreshVertical()
        refreshHorizontal()
    end
    defaultsButton:SetScript("OnClick", function()
        for key, value in pairs(defaults) do
            db[key] = value
        end
        RefreshOptions()
        refreshNameplates()
    end)
    panel:SetScript("OnShow", RefreshOptions)
    RefreshOptions()

    local category = Settings.RegisterCanvasLayoutCategory(panel, title)
    Settings.RegisterAddOnCategory(category)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loadedAddonName)
    if loadedAddonName ~= addonName then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")

    if type(UCDB) ~= "table" then
        UCDB = {}
    end

    local db = UCDB
    for key, default in pairs(defaults) do
        local value = db[key]
        if type(value) ~= type(default) or (type(default) == "number" and not IsFinite(value)) then
            db[key] = default
        end
    end

    local refreshNameplates = addon.InitializeZeppelinDestinations(db)
    RegisterOptions(db, refreshNameplates)

    local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
    ChatFrameUtil.DisplaySystemMessage(ChatFrame1, title .. ": v" .. version)
end)
