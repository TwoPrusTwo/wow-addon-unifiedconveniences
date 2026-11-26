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
local maxPreviewSize = 50
local categoryLabelRight = settingsLabelRight - categorySymbolGap - maxPreviewSize
local numberInputWidth = 96
local numberInputHeight = 22
local settingsButtonGap = 5
local settingsButtonWidth = 200
local tooltipDialogWidth, tooltipDialogHeight = 530, 480
local tooltipContentPadding = 4
local tooltipCheckboxInset = 16
local tooltipDialogButtonWidth = 96
local tooltipSearchHeight = 22
local indicatorCategories = addon.friendlyIndicatorCategories
local colourModes = { "Default", "Class", "Custom" }
local mouseAnchorModes = { "Off", "Out of Combat", "Always" }
local tooltipAlignments = { "Left", "Centre", "Right" }
local mouseAnchorDefaults = {
    mode = "Off",
    align = "Right",
    horizontalOffset = 0,
    verticalOffset = 0,
}
local defaults = {
    craftTimerEnabled = false,
    showTransportDestinations = false,
    transportVerticalOffset = 10,
    transportHorizontalOffset = 0,
}
local legacyTransportKeys = {
    showTransportDestinations = "showZeppelinDestination",
    transportVerticalOffset = "zeppelinVerticalOffset",
    transportHorizontalOffset = "zeppelinHorizontalOffset",
}
local indicatorDefaults = {
    enabled = false,
    horizontalOffset = 0,
    verticalOffset = 0,
}
local indicatorSizePixels = {
    default = 24,
    minimum = 1,
    maximum = 50,
    step = 1,
    arrowStep = 5,
}

local function IsFinite(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

-- Saved lengths use UIParent coordinates. Controls display physical pixels.
local function GetUIUnitsPerPixel()
    return PixelUtil.GetPixelToUIUnitFactor() / UIParent:GetEffectiveScale()
end

function addon.GetUIToRegionScale(region)
    return UIParent:GetEffectiveScale() / region:GetEffectiveScale()
end

if not IsFinite(UCOffsetSliderMax) or UCOffsetSliderMax <= 0 then
    UCOffsetSliderMax = defaultSliderMax
end

local function IsSettingValue(value, default)
    return type(value) == type(default) and (type(default) ~= "number" or IsFinite(value))
end

local function ApplyDefaults(settings, values, reset)
    for key, default in pairs(values) do
        if reset or not IsSettingValue(settings[key], default) then
            settings[key] = default
        end
    end
end

local function MigrateTransportSettings(db)
    for key, legacyKey in pairs(legacyTransportKeys) do
        if not IsSettingValue(db[key], defaults[key]) then
            db[key] = db[legacyKey]
        end
        db[legacyKey] = nil
    end

    local legacyMode = db.zeppelinNameplateMode
    local mode = db.transportNameplateMode
    if type(mode) ~= "table" then
        db.transportNameplateMode = type(legacyMode) == "table" and legacyMode or {}
    elseif type(legacyMode) == "table" and type(legacyMode.nameplateRestore) == "table" then
        if type(mode.nameplateRestore) ~= "table" then
            mode.nameplateRestore = {}
        end
        for cvar, entry in pairs(legacyMode.nameplateRestore) do
            mode.nameplateRestore[cvar] = mode.nameplateRestore[cvar] or entry
        end
    end
    db.zeppelinNameplateMode = nil
end

local function IsColourChannel(value)
    return IsFinite(value) and value >= 0 and value <= 1
end

local function ApplyIndicatorDefaults(settings, reset)
    ApplyDefaults(settings, indicatorDefaults, reset)
    if reset or not IsFinite(settings.size) then
        settings.size = indicatorSizePixels.default * GetUIUnitsPerPixel()
    elseif settings.sizeInUIUnits ~= true then
        -- Existing saved sizes are whole pixels.
        settings.size = math.max(indicatorSizePixels.minimum, math.floor(settings.size)) * GetUIUnitsPerPixel()
    elseif settings.size <= 0 then
        settings.size = indicatorSizePixels.minimum * GetUIUnitsPerPixel()
    end
    settings.sizeInUIUnits = true
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

local function FormatPixels(value)
    local rounded = string.format("%.0f", value)
    return rounded == "-0" and "0" or rounded
end

local function CreateSectionHeading(panel, name, y)
    local heading = AddText(panel, name, "GameFontHighlightLarge", settingsRowLeft + settingsSectionInset, y + settingsSectionTitleY)
    return y - settingsSectionHeight - settingsRowSpacing, heading
end

local function PositionSettingRow(row, panel, y)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", settingsRowLeft, y)
    row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y)
end

local function CreateSettingRow(panel, name, y, labelRight)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(settingsRowHeight)
    PositionSettingRow(row, panel, y)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", settingsLabelInset, 0)
    label:SetPoint("RIGHT", row, "CENTER", labelRight or settingsLabelRight, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(name)
    return row, label
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
        zeroLabel:SetText("0 px")
    end

    local input = CreateNumberInput(row)
    input:SetPoint("LEFT", control, "RIGHT", sliderInputGap, 0)

    local syncingSlider = false
    local step = sizeConfig and sizeConfig.step or sliderStep
    local sliderMin, sliderMax, displayScale
    local displayedText

    local function GetSliderValue(value)
        return sizeConfig and value / GetUIUnitsPerPixel() or value
    end

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
        local pixels = value / GetUIUnitsPerPixel()
        syncingSlider = true
        control:SetValue(GetThumbValue(GetSliderValue(value)))
        syncingSlider = false
        displayedText = FormatPixels(pixels)
        input:SetText(displayedText)
    end

    local function SaveValue(value)
        if IsFinite(value) and settings[key] ~= value then
            settings[key] = value
            onChange()
        end
        SyncValue()
    end

    local function SaveSliderValue(value)
        SaveValue(sizeConfig and value * GetUIUnitsPerPixel() or value)
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
        local unitsPerPixel = GetUIUnitsPerPixel()
        if minimum ~= sliderMin or maximum ~= sliderMax or unitsPerPixel ~= displayScale then
            sliderMin, sliderMax, displayScale = minimum, maximum, unitsPerPixel
            local labels = MinimalSliderWithSteppersMixin.Label
            local function FormatLimit(value)
                local pixels = sizeConfig and value or value / unitsPerPixel
                return FormatPixels(pixels) .. " px"
            end
            local formatters = {
                [labels.Min] = function() return FormatLimit(minimum) end,
                [labels.Max] = function() return FormatLimit(maximum) end,
            }
            syncingSlider = true
            control:Init(GetThumbValue(GetSliderValue(settings[key])), minimum, maximum, (maximum - minimum) / step, formatters)
            syncingSlider = false
        end
        SyncValue()
    end

    control:RegisterCallback("OnValueChanged", function(_, value)
        if not syncingSlider then
            SaveSliderValue(value)
        end
    end, control)
    if sizeConfig then
        local function StepSize(delta)
            local value = math.max(sliderMin, math.min(sliderMax, slider:GetValue() + delta))
            SaveSliderValue(value)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        control.Back:SetScript("OnClick", function() StepSize(-sizeConfig.arrowStep) end)
        control.Forward:SetScript("OnClick", function() StepSize(sizeConfig.arrowStep) end)
    end

    input:SetScript("OnEditFocusLost", function(self)
        local text = self:GetText()
        if text == displayedText then
            return
        end
        local pixels = tonumber(text:match("^%s*([+-]?%d+)%s*$"))
        if IsFinite(pixels) then
            if sizeConfig then
                pixels = math.max(sizeConfig.minimum, pixels)
            end
            SaveValue(pixels * GetUIUnitsPerPixel())
        else
            SyncValue()
        end
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
    -- Native arrow picks update the selection text without refreshing the steppers.
    hooksecurefunc(dropdown, "Pick", function()
        control:UpdateSteppers()
    end)
    control:SetSteppersShown(true)
    return control
end

local function RefreshDropdown(control)
    control.Dropdown:GenerateMenu()
    control:UpdateSteppers()
end

local function CreateScrollBody(scroll, scrollBar)
    scroll:EnableMouseWheel(true)
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

local function CreateSettingsBody(panel)
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", settingsBodyLeft, -settingsBodyTop)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -settingsScrollBarSpace, settingsBodyBottom)

    local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 0, -4)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -1, 7)
    return CreateScrollBody(scroll, scrollBar)
end

local function CreateIndicatorColourRows(body, y, settings, preview, refreshIndicators)
    local dropdowns, checkboxes, symbols = {}, {}, {}

    local function RefreshSymbolSizes()
        local size = math.min(maxPreviewSize, settings.size * addon.GetUIToRegionScale(body))
        for _, symbol in pairs(symbols) do
            symbol:SetSize(size, size)
        end
    end

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
        symbol:SetPoint("CENTER", checkbox, "LEFT", -categorySymbolGap - maxPreviewSize / 2, 0)
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
        RefreshSymbolSizes()
        for _, category in ipairs(indicatorCategories) do
            local key = category.key
            checkboxes[key]:SetChecked(settings[key].enabled)
            RefreshDropdown(dropdowns[key])
            RefreshSymbol(key)
        end
    end

    local chatColourRefreshPending = false
    body:RegisterEvent("UPDATE_CHAT_COLOR")
    body:RegisterEvent("UI_SCALE_CHANGED")
    body:RegisterEvent("DISPLAY_SIZE_CHANGED")
    body:SetScript("OnEvent", function(_, event, chatType)
        if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
            RefreshSymbolSizes()
            return
        end
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

    return RefreshRows, CancelPreview, RefreshSymbolSizes
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

local function CreateOptionsPanel(panelTitle)
    local panel = CreateFrame("Frame")
    panel:Hide()
    AddText(panel, panelTitle, "GameFontHighlightHuge", 7, -22)
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", panel, "TOP", 0, -50)

    local defaultsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    defaultsButton:SetSize(96, 22)
    defaultsButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -36, -16)
    defaultsButton:SetText("Defaults")
    return panel, defaultsButton
end

local function CreateTooltipDialogSearch(dialog)
    local header = CreateFrame("Frame", nil, dialog)
    header:SetPoint("TOP", dialog.TitleContainer, "BOTTOM")
    header:SetPoint("BOTTOM", dialog.Inset, "TOP")
    header:SetPoint("LEFT", dialog.Inset, "LEFT")
    header:SetPoint("RIGHT", dialog.Inset, "RIGHT")

    local search = CreateFrame("EditBox", nil, header, "SearchBoxTemplate")
    search:SetAutoFocus(false)
    search:SetHeight(tooltipSearchHeight)
    local function PositionSearch(_, _, height)
        local padding = math.max(0, (height - tooltipSearchHeight) / 2)
        search:SetPoint("TOPLEFT", header, "TOPLEFT", padding, -padding)
        search:SetPoint("TOPRIGHT", header, "TOPRIGHT", -padding, -padding)
    end
    header:SetScript("OnSizeChanged", PositionSearch)
    PositionSearch(header, nil, header:GetHeight())
    return search
end

local function CreateTooltipDialogButton(dialog, corner, text)
    local button = CreateFrame("Button", nil, dialog, "MagicButtonTemplate")
    button:SetWidth(tooltipDialogButtonWidth)
    button:SetPoint(corner, dialog, corner)
    -- A Lua-created button receives its corner anchor after the template's OnLoad.
    MagicButton_OnLoad(button)
    button:SetText(text)
    return button
end

local function CreateTooltipIDDialog(panel, categories)
    local dialog = CreateFrame("Frame", "UCTooltipIDsDialog", panel, "ButtonFrameTemplate")
    dialog:Hide()
    dialog:SetSize(tooltipDialogWidth, tooltipDialogHeight)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:EnableMouse(true)
    dialog:SetTitle("Tooltip IDs")
    if ButtonFrameTemplate_HidePortrait then
        ButtonFrameTemplate_HidePortrait(dialog)
    end
    UISpecialFrames[#UISpecialFrames + 1] = dialog:GetName()

    local search = CreateTooltipDialogSearch(dialog)
    local inset = dialog.Inset
    local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    local stepperWidth = math.max(scrollBar.Back:GetWidth(), scrollBar.Forward:GetWidth())
    local scrollBarPadding = tooltipContentPadding + (stepperWidth - scrollBar:GetWidth()) / 2
    scrollBar:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -scrollBarPadding, -tooltipContentPadding)
    scrollBar:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -scrollBarPadding, tooltipContentPadding)

    local scroll = CreateFrame("ScrollFrame", nil, inset)
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", tooltipContentPadding, -tooltipContentPadding)
    scroll:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -scrollBarPadding, 0)
    local body = CreateScrollBody(scroll, scrollBar)
    local noMatches = AddText(body, "No matching settings", "GameFontHighlight",
        settingsRowLeft + settingsSectionInset, -settingsListPadding)
    local checkboxes, sections = {}, {}
    for _, group in ipairs(addon.tooltipIDGroups) do
        local _, heading = CreateSectionHeading(body, group.title, 0)
        local section = { heading = heading, rows = {} }
        sections[#sections + 1] = section
        for _, category in ipairs(group) do
            local key, name = unpack(category)
            local row, label = CreateSettingRow(body, name, 0)
            local checkbox = CreateCheckbox(row, name, nil, function(value)
                categories[key] = value
            end)
            checkbox:ClearAllPoints()
            checkbox:SetPoint("RIGHT", row, "RIGHT", -tooltipCheckboxInset, 0)
            label:SetPoint("RIGHT", checkbox, "LEFT", -settingsButtonGap, 0)
            checkboxes[key] = checkbox
            section.rows[#section.rows + 1] = { frame = row, name = name:lower() }
        end
    end

    local function Filter()
        local query = search:GetText():lower():match("^%s*(.-)%s*$")
        local y = -settingsListPadding
        for _, section in ipairs(sections) do
            local firstRowY = y - settingsSectionHeight - settingsRowSpacing
            local rowY = firstRowY
            for _, row in ipairs(section.rows) do
                local matches = row.name:find(query, 1, true) ~= nil
                row.frame:SetShown(matches)
                if matches then
                    PositionSettingRow(row.frame, body, rowY)
                    rowY = rowY - settingsRowStep
                end
            end
            local hasMatches = rowY ~= firstRowY
            section.heading:SetShown(hasMatches)
            if hasMatches then
                section.heading:SetPoint("TOPLEFT", body, "TOPLEFT", settingsRowLeft + settingsSectionInset,
                    y + settingsSectionTitleY)
                y = rowY
            end
        end
        local empty = y == -settingsListPadding
        noMatches:SetShown(empty)
        body:SetHeight(-y + settingsListPadding + (empty and settingsRowHeight or 0))
        scroll:SetVerticalScroll(0)
    end
    search:HookScript("OnTextChanged", Filter)

    local function Refresh()
        for key, checkbox in pairs(checkboxes) do
            checkbox:SetChecked(categories[key])
        end
    end

    local defaultsButton = CreateTooltipDialogButton(dialog, "BOTTOMLEFT", "Defaults")
    defaultsButton:SetScript("OnClick", function()
        addon.ApplyTooltipIDDefaults(categories, true)
        Refresh()
    end)

    local closeButton = CreateTooltipDialogButton(dialog, "BOTTOMRIGHT", CLOSE)
    closeButton:SetScript("OnClick", function() dialog:Hide() end)
    dialog.CloseButton:SetScript("OnClick", function() dialog:Hide() end)
    dialog:SetScript("OnShow", function()
        search:SetText("")
        Filter()
        Refresh()
    end)
    dialog:SetScript("OnHide", function() search:ClearFocus() end)
    return dialog, Refresh
end

local function CreateTooltipRows(body, panel, y, anchor, ids, refreshAnchor)
    local function AddDropdown(label, key, choices, default)
        local row = CreateSettingRow(body, label, y)
        y = y - settingsRowStep
        return CreateSettingsDropdown(row, function(_, menu)
            for _, choice in ipairs(choices) do
                menu:CreateRadio(choice, function(value) return anchor[key] == value end, function(value)
                    anchor[key] = value
                    refreshAnchor()
                end, choice)
            end
        end, nil, default)
    end

    local mode = AddDropdown("Mouse Anchor", "mode", mouseAnchorModes, mouseAnchorDefaults.mode)
    local align = AddDropdown("Align", "align", tooltipAlignments, mouseAnchorDefaults.align)
    local refreshHorizontal = CreateNumericRow(body, "Horizontal Offset (px)", y, anchor, "horizontalOffset", refreshAnchor)
    y = y - sliderRowStep
    local refreshVertical = CreateNumericRow(body, "Vertical Offset (px)", y, anchor, "verticalOffset", refreshAnchor)
    y = y - sliderRowStep
    local row = CreateSettingRow(body, "Show IDs", y)
    local checkbox = CreateCheckbox(row, "Show IDs", "Show selected identifiers in tooltips.", function(value)
        ids.enabled = value
    end)
    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetWidth(settingsButtonWidth)
    button:SetPoint("LEFT", checkbox, "RIGHT", settingsButtonGap, 0)
    button:SetText("Configure")
    local dialog, refreshDialog
    button:SetScript("OnClick", function()
        if not dialog then
            dialog, refreshDialog = CreateTooltipIDDialog(panel, ids.categories)
        end
        dialog:Show()
    end)

    local function RefreshOffsets()
        refreshHorizontal()
        refreshVertical()
    end
    local function RefreshControls()
        RefreshDropdown(mode)
        RefreshDropdown(align)
        checkbox:SetChecked(ids.enabled)
        if refreshDialog then
            refreshDialog()
        end
    end
    local function CloseDialog()
        if dialog then
            dialog:Hide()
        end
    end
    return y - settingsRowStep, RefreshOffsets, RefreshControls, CloseDialog
end

local function RegisterDebugOptions(parentCategory, settings, setSimpleNameplatesEnabled)
    local panel, defaultsButton = CreateOptionsPanel("Debug")
    local body = CreateSettingsBody(panel)
    local label = "Simple Nameplates"
    local row = CreateSettingRow(body, label, -settingsListPadding)
    local checkbox = CreateCheckbox(row, label, "Allow nearby simple plates when native and addon nameplates are off.", setSimpleNameplatesEnabled)
    body:SetHeight(settingsRowHeight + settingsListPadding * 2)

    local function RefreshOptions()
        checkbox:SetChecked(settings.enabled)
    end
    defaultsButton:SetScript("OnClick", function()
        setSimpleNameplatesEnabled(true)
        RefreshOptions()
    end)
    panel:SetScript("OnShow", RefreshOptions)
    RefreshOptions()
    Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, "Debug")
end

local function RegisterOptions(db, refreshTransport, refreshIndicators, preview, tracking, setSimpleNameplatesEnabled, refreshAnchor, refreshCraftTimer)
    local panel, defaultsButton = CreateOptionsPanel(title)
    local body = CreateSettingsBody(panel)
    local craftTimerTitle = "Craft Timer"
    local y = CreateSectionHeading(body, craftTimerTitle, -settingsListPadding)
    local craftTimerRow = CreateSettingRow(body, craftTimerTitle, y)
    local craftTimerCheckbox = CreateCheckbox(craftTimerRow, craftTimerTitle,
        "Show crafting time estimates and the remaining time for Create All.", function(value)
            db.craftTimerEnabled = value
            refreshCraftTimer()
        end)
    local indicators = db.friendlyIndicators
    local indicatorsTitle = "Friendly Indicators"
    y = CreateSectionHeading(body, indicatorsTitle, y - settingsRowStep)
    local indicatorsRow = CreateSettingRow(body, indicatorsTitle, y)
    local indicatorsCheckbox = CreateCheckbox(indicatorsRow, indicatorsTitle, "Show symbols above friendly player names. In the open world, simple names can appear when game and addon nameplates are off.", function(value)
        indicators.enabled = value
        refreshIndicators()
    end)
    y = y - settingsRowStep
    local refreshSymbolSizes
    local refreshSize = CreateNumericRow(body, "Size (px)", y, indicators, "size", function()
        refreshSymbolSizes()
        refreshIndicators()
    end, indicatorSizePixels)
    y = y - sliderRowStep
    local refreshIndicatorHorizontal = CreateNumericRow(body, "Horizontal Offset (px)", y, indicators, "horizontalOffset", refreshIndicators)
    y = y - sliderRowStep
    local refreshIndicatorVertical = CreateNumericRow(body, "Vertical Offset (px)", y, indicators, "verticalOffset", refreshIndicators)
    y = y - sliderRowStep
    local refreshIndicatorRows, cancelColourPreview
    refreshIndicatorRows, cancelColourPreview, refreshSymbolSizes = CreateIndicatorColourRows(body, y, indicators, preview, refreshIndicators)

    y = CreateSectionHeading(body, "Tooltips", y - #indicatorCategories * settingsRowStep)
    local nextTooltipY, refreshTooltipOffsets, refreshTooltipControls, closeTooltipDialog =
        CreateTooltipRows(body, panel, y, db.mouseAnchorTooltips, db.tooltipIDs, refreshAnchor)
    y = CreateSectionHeading(body, "Tracking Manager", nextTooltipY)
    local nextSectionY, refreshTracking = CreateTrackingRows(body, y, tracking)

    local transportTitle = "Transport Destinations"
    y = CreateSectionHeading(body, transportTitle, nextSectionY)
    local transportRow = CreateSettingRow(body, transportTitle, y)
    local transportCheckbox = CreateCheckbox(transportRow, transportTitle, "Show fixed destinations on transport NPC nameplates and in mouseover tooltips. In the open world, simple NPC names can appear when game and addon nameplates are off.", function(value)
        db.showTransportDestinations = value
        refreshTransport()
    end)
    y = y - settingsRowStep
    local refreshTransportHorizontal = CreateNumericRow(body, "Horizontal Offset (px)", y, db, "transportHorizontalOffset", refreshTransport)
    y = y - sliderRowStep
    local refreshTransportVertical = CreateNumericRow(body, "Vertical Offset (px)", y, db, "transportVerticalOffset", refreshTransport)

    y = CreateSectionHeading(body, "About", y - sliderRowStep)
    CreateSettingRow(body, "Version: " .. C_AddOns.GetAddOnMetadata(addonName, "Version"), y)
    y = y - settingsRowStep
    CreateSettingRow(body, "Author: " .. C_AddOns.GetAddOnMetadata(addonName, "Author"), y)
    body:SetHeight(-y + settingsRowHeight + settingsListPadding)

    local function RefreshMeasurementControls()
        refreshSize()
        refreshIndicatorHorizontal()
        refreshIndicatorVertical()
        refreshTooltipOffsets()
        refreshTransportHorizontal()
        refreshTransportVertical()
    end

    local function RefreshOptions()
        RefreshMeasurementControls()
        craftTimerCheckbox:SetChecked(db.craftTimerEnabled)
        indicatorsCheckbox:SetChecked(indicators.enabled)
        refreshIndicatorRows()
        refreshTooltipControls()
        refreshTracking()
        transportCheckbox:SetChecked(db.showTransportDestinations)
    end
    defaultsButton:SetScript("OnClick", function()
        cancelColourPreview()
        ApplyDefaults(db, defaults, true)
        ApplyIndicatorDefaults(indicators, true)
        ApplyDefaults(db.mouseAnchorTooltips, mouseAnchorDefaults, true)
        db.tooltipIDs.enabled = false
        addon.ApplyTooltipIDDefaults(db.tooltipIDs.categories, true)
        tracking.Reset()
        setSimpleNameplatesEnabled(true)
        RefreshOptions()
        refreshTransport()
        refreshIndicators()
        refreshAnchor()
        refreshCraftTimer()
    end)
    panel:SetScript("OnShow", RefreshOptions)
    panel:SetScript("OnHide", function()
        closeTooltipDialog()
        cancelColourPreview()
    end)
    panel:RegisterEvent("UI_SCALE_CHANGED")
    panel:RegisterEvent("DISPLAY_SIZE_CHANGED")
    panel:SetScript("OnEvent", RefreshMeasurementControls)
    RefreshOptions()

    local category = Settings.RegisterCanvasLayoutCategory(panel, title)
    Settings.RegisterAddOnCategory(category)
    RegisterDebugOptions(category, db.simpleNameplates, setSimpleNameplatesEnabled)
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
    MigrateTransportSettings(db)
    ApplyDefaults(db, defaults)
    if type(db.friendlyIndicators) ~= "table" then
        db.friendlyIndicators = {}
    end
    ApplyIndicatorDefaults(db.friendlyIndicators)
    if type(db.mouseAnchorTooltips) ~= "table" then
        db.mouseAnchorTooltips = {}
    end
    local anchor = db.mouseAnchorTooltips
    ApplyDefaults(anchor, mouseAnchorDefaults)
    if not tContains(mouseAnchorModes, anchor.mode) then
        anchor.mode = mouseAnchorDefaults.mode
    end
    if not tContains(tooltipAlignments, anchor.align) then
        anchor.align = mouseAnchorDefaults.align
    end
    if type(db.tooltipIDs) ~= "table" then
        db.tooltipIDs = {}
    end
    db.tooltipIDs.enabled = db.tooltipIDs.enabled == true
    if type(db.tooltipIDs.categories) ~= "table" then
        db.tooltipIDs.categories = {}
    end
    addon.ApplyTooltipIDDefaults(db.tooltipIDs.categories)

    local setSimpleNameplatesEnabled = addon.InitializeSimpleNameplates(db)
    local preview = {}
    local refreshTransport = addon.InitializeTransportDestinations(db, defaults.transportVerticalOffset)
    local refreshIndicators = addon.InitializeFriendlyIndicators(db.friendlyIndicators, preview)
    local tracking = addon.InitializeTrackingManager(db)
    local refreshAnchor = addon.InitializeTooltipsMouseAnchor(anchor)
    local refreshCraftTimer = addon.InitializeCraftTimer(db)
    addon.InitializeTooltipIDs(db.tooltipIDs)
    local category = RegisterOptions(db, refreshTransport, refreshIndicators, preview, tracking,
        setSimpleNameplatesEnabled, refreshAnchor, refreshCraftTimer)
    addon.CreateTrackingMinimapButton(tracking.PopulateMenu, function()
        Settings.OpenToCategory(category:GetID())
    end)

    local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
    ChatFrameUtil.DisplaySystemMessage(ChatFrame1, title .. ": v" .. version)
end)
