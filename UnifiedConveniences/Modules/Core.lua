local addonName, addon = ...

local title = "Unified Conveniences"
local sliderStep = 5
local sliderLabelMargin = 5
local defaultSliderMax = 50
-- Match the native Settings list insets, row metrics and control anchors.
local settingsRowHeight = 26
local settingsRowSpacing = 9
local settingsRowStep = settingsRowHeight + settingsRowSpacing
local settingsListPadding = 10
local settingsRowLeft = 25
local settingsSectionHeight = 45
local settingsSectionInset = 7
local settingsSectionTitleY = -16
local settingsLabelInset = 37
local settingsControlOffset = -80
local settingsLabelRight = settingsControlOffset - 5
local settingsBodyLeft = -15
local settingsBodyTop = 52
local settingsBodyBottom = -2
local settingsScrollBarSpace = 20
local settingsDropdownOffset = -48
local settingsDropdownWidth = 220
local settingsControlLift = 3
local checkboxDropdownGap = 32
local sliderWidth = 250
local sliderRowStep = settingsRowStep + 13 -- Extra room for the value labels below the thumb.
local sliderInputGap = 12
local categorySymbolGap = 12
local categorySymbolSize = 24
local categoryLabelRight = settingsLabelRight - categorySymbolGap - categorySymbolSize
local numberInputWidth = 96
local numberInputHeight = 22
local indicatorCategories = addon.friendlyIndicatorCategories
local colourModes = { "Default", "Class", "Custom" }
local defaults = {
    showZeppelinDestination = false,
    zeppelinVerticalOffset = 10,
    zeppelinHorizontalOffset = 0,
}
local indicatorDefaults = {
    enabled = false,
    size = 24,
    horizontalOffset = 0,
    verticalOffset = 0,
}
local indicatorSize = {
    minimum = 1,
    maximum = 50,
    step = 1,
    arrowStep = 5,
}

local function IsFinite(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

if not IsFinite(UCOffsetSliderMax) or UCOffsetSliderMax <= 0 then
    UCOffsetSliderMax = defaultSliderMax
end

local function ApplyDefaults(settings, values, reset)
    for key, default in pairs(values) do
        local value = settings[key]
        if reset or type(value) ~= type(default) or (type(default) == "number" and not IsFinite(value)) then
            settings[key] = default
        end
    end
end

local function IsColourChannel(value)
    return IsFinite(value) and value >= 0 and value <= 1
end

local function ApplyIndicatorDefaults(settings, reset)
    ApplyDefaults(settings, indicatorDefaults, reset)
    settings.size = math.max(indicatorSize.minimum, math.floor(settings.size))
    for _, category in ipairs(indicatorCategories) do
        local style = settings[category.key]
        if type(style) ~= "table" then
            style = {}
            settings[category.key] = style
        end
        if reset or type(style.enabled) ~= "boolean" then
            style.enabled = true
        end
        local colour = style.colour
        if reset or type(colour) ~= "table" or not (IsColourChannel(colour.r) and IsColourChannel(colour.g) and IsColourChannel(colour.b)) then
            style.colour = nil
        end
        if reset or (style.colourMode ~= "Class" and (style.colourMode ~= "Custom" or not style.colour)) then
            style.colourMode = "Default"
        end
    end
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

local function CreateSectionHeading(panel, name, y)
    AddText(panel, name, "GameFontHighlightLarge", settingsRowLeft + settingsSectionInset, y + settingsSectionTitleY)
    return y - settingsSectionHeight - settingsRowSpacing
end

local function CreateSettingRow(panel, name, y, labelRight)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(settingsRowHeight)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", settingsRowLeft, y)
    row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", settingsLabelInset, 0)
    label:SetPoint("RIGHT", row, "CENTER", labelRight or settingsLabelRight, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(name)
    return row
end

local function CreateNumberInput(row)
    local input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    input:SetSize(numberInputWidth, numberInputHeight)
    input:SetAutoFocus(false)
    input:SetJustifyH("CENTER")
    input:SetScript("OnEnterPressed", input.ClearFocus)
    return input
end

local function CreateNumericRow(panel, label, y, settings, key, onChange, sizeConfig)
    local row = CreateSettingRow(panel, label, y)
    local control = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
    control:SetPoint("LEFT", row, "CENTER", settingsControlOffset, settingsControlLift)
    control:SetWidth(sliderWidth)
    local slider = control.Slider

    control.MinText:ClearAllPoints()
    control.MinText:SetPoint("TOP", slider.Left, "BOTTOMLEFT", sliderLabelMargin, -sliderLabelMargin)
    control.MaxText:ClearAllPoints()
    control.MaxText:SetPoint("TOP", slider.Right, "BOTTOMRIGHT", -sliderLabelMargin, -sliderLabelMargin)
    if not sizeConfig then
        local zeroLabel = control:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        zeroLabel:SetPoint("TOP", slider.Middle, "BOTTOM", 0, -sliderLabelMargin)
        zeroLabel:SetText("0")
    end

    local input = CreateNumberInput(row)
    input:SetPoint("LEFT", control, "RIGHT", sliderInputGap, 0)

    local syncingSlider = false
    local step = sizeConfig and sizeConfig.step or sliderStep
    local sliderMin, sliderMax

    local function GetThumbValue(value)
        if value <= sliderMin or value >= sliderMax then
            return math.max(sliderMin, math.min(sliderMax, value))
        end
        -- The field retains the exact value while the thumb snaps to a slider step.
        local steps = math.floor((value - sliderMin) / step + 0.5)
        return math.min(sliderMax, sliderMin + steps * step)
    end

    local function SyncValue()
        local value = settings[key]
        syncingSlider = true
        control:SetValue(GetThumbValue(value))
        syncingSlider = false
        input:SetText(sizeConfig and string.format("%.0f", value) or FormatOffset(value))
    end

    local function SaveValue(value)
        if IsFinite(value) and settings[key] ~= value then
            settings[key] = value
            onChange()
        end
        SyncValue()
    end

    local function RefreshRow()
        local minimum, maximum
        if sizeConfig then
            minimum, maximum = sizeConfig.minimum, sizeConfig.maximum
        else
            maximum = UCOffsetSliderMax
            if not IsFinite(maximum) or maximum <= 0 then
                maximum = defaultSliderMax
            end
            minimum = -maximum
        end
        if minimum ~= sliderMin or maximum ~= sliderMax then
            sliderMin, sliderMax = minimum, maximum
            local labels = MinimalSliderWithSteppersMixin.Label
            local suffix = sizeConfig and " px" or ""
            local formatters = {
                [labels.Min] = function() return FormatOffset(minimum) .. suffix end,
                [labels.Max] = function() return FormatOffset(maximum) .. suffix end,
            }
            syncingSlider = true
            control:Init(GetThumbValue(settings[key]), minimum, maximum, (maximum - minimum) / step, formatters)
            syncingSlider = false
        end
        SyncValue()
    end

    control:RegisterCallback("OnValueChanged", function(_, value)
        if not syncingSlider then
            SaveValue(value)
        end
    end, control)
    if sizeConfig then
        local function StepSize(delta)
            local value = math.max(sliderMin, math.min(sliderMax, slider:GetValue() + delta))
            SaveValue(value)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        control.Back:SetScript("OnClick", function() StepSize(-sizeConfig.arrowStep) end)
        control.Forward:SetScript("OnClick", function() StepSize(sizeConfig.arrowStep) end)
    end

    input:SetScript("OnEditFocusLost", function(self)
        local text = self:GetText()
        local value
        if sizeConfig then
            if text:match("^%s*[+-]?%d+%s*$") then
                local number = tonumber(text)
                if IsFinite(number) then
                    value = math.max(sizeConfig.minimum, number)
                end
            end
        elseif not text:match("^%s*[+-]?0[xX]") then
            value = tonumber(text)
        end
        SaveValue(value)
    end)
    input:SetScript("OnEscapePressed", function(self)
        SyncValue()
        self:ClearFocus()
    end)

    return RefreshRow
end

local function CreateCheckbox(row, name, description, onChange)
    local checkbox = CreateFrame("CheckButton", nil, row, "SettingsCheckboxTemplate")
    checkbox:SetPoint("LEFT", row, "CENTER", settingsControlOffset, 0)
    if description then
        checkbox:SetTooltipFunc(function()
            Settings.InitTooltip(name, description)
        end)
    end
    checkbox:SetScript("OnClick", function(self)
        onChange(self:GetChecked() and true or false)
    end)
    return checkbox
end

local function CreateSettingsDropdown(row, populateMenu, checkbox, defaultText)
    local control = CreateFrame("Frame", nil, row, "SettingsDropdownWithButtonsTemplate")
    if checkbox then
        control:SetPoint("LEFT", checkbox, "RIGHT", checkboxDropdownGap, 0)
    else
        control:SetPoint("LEFT", row, "CENTER", settingsDropdownOffset, settingsControlLift)
    end
    local dropdown = control.Dropdown
    dropdown:SetWidth(settingsDropdownWidth)
    if defaultText then
        dropdown:SetDefaultText(defaultText)
    end
    dropdown:SetupMenu(populateMenu)
    control:SetSteppersShown(true)
    return control
end

local function RefreshDropdown(control)
    control.Dropdown:GenerateMenu()
    control:UpdateSteppers()
end

local function CreateSettingsBody(panel)
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", settingsBodyLeft, -settingsBodyTop)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -settingsScrollBarSpace, settingsBodyBottom)
    scroll:EnableMouseWheel(true)

    local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 0, -4)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -1, 7)
    scrollBar:SetHideIfUnscrollable(true)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)

    local body = CreateFrame("Frame", nil, scroll)
    body:SetWidth(math.max(1, scroll:GetWidth()))
    scroll:SetScrollChild(body)
    scroll:SetScript("OnSizeChanged", function(_, width)
        body:SetWidth(math.max(1, width))
    end)
    return body
end

local function CreateIndicatorColourRows(body, y, settings, preview, refreshIndicators)
    local dropdowns, checkboxes, symbols = {}, {}, {}

    local function RefreshSymbol(key)
        local previewColour = preview.key == key and preview.colour
        local colour = addon.GetFriendlyIndicatorPreviewColour(key, settings[key], previewColour)
        symbols[key]:SetVertexColor(colour.r, colour.g, colour.b)
    end

    local function FinishPreview(save)
        local key = preview.key
        if not key then
            return
        end
        if save then
            local style = settings[key]
            style.colourMode = "Custom"
            style.colour = preview.colour
        end
        preview.key, preview.colour = nil, nil
        RefreshSymbol(key)
        RefreshDropdown(dropdowns[key])
        refreshIndicators()
    end

    local function CancelPreview()
        if preview.key then
            if ColorPickerFrame:IsShown() and ColorPickerFrame:GetExtraInfo() == preview then
                ColorPickerFrame:OnCancel()
            else
                FinishPreview(false)
            end
        end
    end

    -- The native swatch callback also fires while the wheel is moving.
    ColorPickerFrame.Footer.OkayButton:HookScript("OnClick", function()
        if ColorPickerFrame:GetExtraInfo() == preview then
            FinishPreview(true)
        end
    end)

    local function OpenPicker(key)
        CancelPreview()
        local colour = settings[key].colour or WHITE_FONT_COLOR
        preview.key, preview.colour = key, colour
        ColorPickerFrame:SetupColorPickerAndShow({
            r = colour.r, g = colour.g, b = colour.b,
            hasOpacity = false,
            extraInfo = preview,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                preview.colour = { r = r, g = g, b = b }
                RefreshSymbol(key)
                refreshIndicators()
            end,
            cancelFunc = function() FinishPreview(false) end,
        })
        RefreshSymbol(key)
        refreshIndicators()
    end

    for index, category in ipairs(indicatorCategories) do
        local key = category.key
        local style = settings[key]
        local row = CreateSettingRow(body, category.label, y - (index - 1) * settingsRowStep, categoryLabelRight)
        local checkbox = CreateCheckbox(row, category.label, nil, function(value)
            style.enabled = value
            refreshIndicators()
        end)
        checkboxes[key] = checkbox

        local symbol = row:CreateTexture(nil, "OVERLAY")
        symbol:SetPoint("RIGHT", checkbox, "LEFT", -categorySymbolGap, 0)
        symbol:SetSize(categorySymbolSize, categorySymbolSize)
        addon.SetFriendlyIndicatorTexture(symbol, category)
        symbols[key] = symbol

        dropdowns[key] = CreateSettingsDropdown(row, function(_, menu)
            for _, mode in ipairs(colourModes) do
                menu:CreateRadio(mode, function(value)
                    local current = preview.key == key and "Custom" or style.colourMode
                    return current == value
                end, function(value)
                    if value == "Custom" then
                        OpenPicker(key)
                    else
                        CancelPreview()
                        style.colourMode = value
                        RefreshSymbol(key)
                        refreshIndicators()
                    end
                end, mode)
            end
        end, checkbox)
    end

    local function RefreshRows()
        for _, category in ipairs(indicatorCategories) do
            local key = category.key
            checkboxes[key]:SetChecked(settings[key].enabled)
            RefreshDropdown(dropdowns[key])
            RefreshSymbol(key)
        end
    end

    local chatColourRefreshPending = false
    body:RegisterEvent("UPDATE_CHAT_COLOR")
    body:SetScript("OnEvent", function(_, _, chatType)
        if chatColourRefreshPending or not addon.IsFriendlyIndicatorChatColour(chatType) then
            return
        end
        chatColourRefreshPending = true
        -- Wait for Blizzard's chat frames to update ChatTypeInfo.
        C_Timer.After(0, function()
            chatColourRefreshPending = false
            for key in pairs(symbols) do
                RefreshSymbol(key)
            end
            refreshIndicators()
        end)
    end)

    return RefreshRows, CancelPreview
end

local function CreateTrackingRows(body, selectionY, tracking)
    local selectionRow = CreateSettingRow(body, "Tracking", selectionY)
    local dropdown = CreateSettingsDropdown(selectionRow, tracking.PopulateMenu, nil, "Unavailable")

    local treasureCheckbox
    local intervalY = selectionY - settingsRowStep
    if tracking.isDwarf then
        local treasureRow = CreateSettingRow(body, "Find Treasure", intervalY)
        treasureCheckbox = CreateCheckbox(treasureRow, "Find Treasure", "Keep Find Treasure active independently of the selected tracker.", tracking.SetTreasure)
        intervalY = intervalY - settingsRowStep
    end

    local intervalRow = CreateSettingRow(body, "Interval (s)", intervalY)
    local input = CreateNumberInput(intervalRow)
    input:SetPoint("LEFT", intervalRow, "CENTER", settingsControlOffset, 0)
    local function RefreshInterval()
        input:SetText(string.format("%.0f", tracking.settings.interval))
    end
    input:SetScript("OnEditFocusLost", function(self)
        local value = self:GetText():match("^%s*%+?(%d+)%s*$")
        if value then
            tracking.SetInterval(tonumber(value))
        end
        RefreshInterval()
    end)
    input:SetScript("OnEscapePressed", function(self)
        RefreshInterval()
        self:ClearFocus()
    end)

    local function RefreshSelection()
        RefreshDropdown(dropdown)
        if treasureCheckbox then
            treasureCheckbox:SetChecked(tracking.settings.findTreasure)
        end
    end
    tracking.RefreshOptions = function()
        if selectionRow:IsVisible() then
            RefreshSelection()
        end
    end
    return intervalY - settingsRowStep, function()
        RefreshSelection()
        RefreshInterval()
    end
end

local function RegisterOptions(db, refreshNameplates, refreshIndicators, preview, tracking)
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

    local body = CreateSettingsBody(panel)
    local indicators = db.friendlyIndicators
    local indicatorsTitle = "Friendly Indicators"
    local y = CreateSectionHeading(body, indicatorsTitle, -settingsListPadding)
    local indicatorsRow = CreateSettingRow(body, indicatorsTitle, y)
    local indicatorsCheckbox = CreateCheckbox(indicatorsRow, indicatorsTitle, "Show symbols above friendly player names. In the open world, this can temporarily enable name-only plates when friendly player nameplates are off.", function(value)
        indicators.enabled = value
        refreshIndicators()
    end)
    y = y - settingsRowStep
    local refreshSize = CreateNumericRow(body, "Size", y, indicators, "size", refreshIndicators, indicatorSize)
    y = y - sliderRowStep
    local refreshIndicatorHorizontal = CreateNumericRow(body, "Horizontal Offset", y, indicators, "horizontalOffset", refreshIndicators)
    y = y - sliderRowStep
    local refreshIndicatorVertical = CreateNumericRow(body, "Vertical Offset", y, indicators, "verticalOffset", refreshIndicators)
    y = y - sliderRowStep
    local refreshIndicatorRows, cancelColourPreview = CreateIndicatorColourRows(body, y, indicators, preview, refreshIndicators)

    y = CreateSectionHeading(body, "Tracking Manager", y - #indicatorCategories * settingsRowStep)
    local nextSectionY, refreshTracking = CreateTrackingRows(body, y, tracking)

    local zeppelinTitle = "Zeppelin Destinations"
    y = CreateSectionHeading(body, zeppelinTitle, nextSectionY)
    local zeppelinRow = CreateSettingRow(body, zeppelinTitle, y)
    local zeppelinCheckbox = CreateCheckbox(zeppelinRow, zeppelinTitle, "Show Zeppelin Master destinations on nameplates and in mouseover tooltips. In the open world, this can temporarily enable friendly NPC nameplates.", function(value)
        db.showZeppelinDestination = value
        refreshNameplates()
    end)
    y = y - settingsRowStep
    local refreshZeppelinHorizontal = CreateNumericRow(body, "Horizontal Offset", y, db, "zeppelinHorizontalOffset", refreshNameplates)
    y = y - sliderRowStep
    local refreshZeppelinVertical = CreateNumericRow(body, "Vertical Offset", y, db, "zeppelinVerticalOffset", refreshNameplates)

    y = CreateSectionHeading(body, "About", y - sliderRowStep)
    CreateSettingRow(body, "Version: " .. C_AddOns.GetAddOnMetadata(addonName, "Version"), y)
    y = y - settingsRowStep
    CreateSettingRow(body, "Author: " .. C_AddOns.GetAddOnMetadata(addonName, "Author"), y)
    body:SetHeight(-y + settingsRowHeight + settingsListPadding)

    local function RefreshOptions()
        indicatorsCheckbox:SetChecked(indicators.enabled)
        refreshSize()
        refreshIndicatorHorizontal()
        refreshIndicatorVertical()
        refreshIndicatorRows()
        refreshTracking()
        zeppelinCheckbox:SetChecked(db.showZeppelinDestination)
        refreshZeppelinHorizontal()
        refreshZeppelinVertical()
    end
    defaultsButton:SetScript("OnClick", function()
        cancelColourPreview()
        ApplyDefaults(db, defaults, true)
        ApplyIndicatorDefaults(indicators, true)
        tracking.Reset()
        RefreshOptions()
        refreshNameplates()
        refreshIndicators()
    end)
    panel:SetScript("OnShow", RefreshOptions)
    panel:SetScript("OnHide", cancelColourPreview)
    RefreshOptions()

    local category = Settings.RegisterCanvasLayoutCategory(panel, title)
    Settings.RegisterAddOnCategory(category)
    return category
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
    ApplyDefaults(db, defaults)
    if type(db.friendlyIndicators) ~= "table" then
        db.friendlyIndicators = {}
    end
    ApplyIndicatorDefaults(db.friendlyIndicators)

    local preview = {}
    local refreshNameplates = addon.InitializeZeppelinDestinations(db, defaults.zeppelinVerticalOffset)
    local refreshIndicators = addon.InitializeFriendlyIndicators(db.friendlyIndicators, preview)
    local tracking = addon.InitializeTrackingManager(db)
    local category = RegisterOptions(db, refreshNameplates, refreshIndicators, preview, tracking)
    addon.CreateTrackingMinimapButton(tracking.PopulateMenu, function()
        Settings.OpenToCategory(category:GetID())
    end)

    local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
    ChatFrameUtil.DisplaySystemMessage(ChatFrame1, title .. ": v" .. version)
end)
