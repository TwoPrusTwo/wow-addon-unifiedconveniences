local _, addon = ...

local millisecondsPerSecond = 1000
local secondsPerMinute = 60
local updateInterval = 0.2
local castStartTimeout = 3
local betweenCastsTimeout = 2
local buttonSidePadding = 6
local quantityArrowGap = 4
local castBarLayers = { "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY", "HIGHLIGHT" }

local function IsNumber(value)
    return not issecretvalue(value) and type(value) == "number"
        and value > -math.huge and value < math.huge
end

local function CanAccess(frame)
    return not issecretvalue(frame) and frame and not frame:IsForbidden()
end

local function IsVisible(frame)
    if CanAccess(frame) then
        local visible = frame:IsVisible()
        return not issecretvalue(visible) and visible == true
    end
end

local function IsReadableTable(value)
    return not issecretvalue(value) and type(value) == "table" and not (issecrettable and issecrettable(value))
end

local function GetRecipeID(page)
    local info = page.SchematicForm:GetRecipeInfo()
    if IsReadableTable(info) and IsNumber(info.recipeID) and info.recipeID > 0 then
        return info.recipeID
    end
end

local function FormatDuration(seconds)
    seconds = math.ceil(seconds)
    return ("%d:%02d"):format(math.floor(seconds / secondsPerMinute), seconds % secondsPerMinute)
end

local function GetButtonText(button, textState)
    local text = button:GetText()
    if not issecretvalue(text) and type(text) == "string" then
        return text, text == textState.estimate and textState.native or text
    end
end

local function SetCompactButtonText(button, text, currentText, quantityArrow)
    local font = button:GetFontString()
    if not issecretvalue(font) and not font then
        font = button.Text
    end
    if not CanAccess(font) then
        return
    end
    local textWidth = font:GetUnboundedStringWidthForText(text)
    if not IsNumber(textWidth) or textWidth <= 0 then
        return
    end
    local width = math.ceil(textWidth + buttonSidePadding * 2)
    if IsVisible(quantityArrow) then
        local arrowLeft, buttonLeft = quantityArrow:GetLeft(), button:GetLeft()
        local arrowScale, buttonScale = quantityArrow:GetEffectiveScale(), button:GetEffectiveScale()
        if IsNumber(arrowLeft) and IsNumber(buttonLeft) and IsNumber(arrowScale)
            and IsNumber(buttonScale) and buttonScale > 0 then
            local available = (arrowLeft * arrowScale - buttonLeft * buttonScale) / buttonScale - quantityArrowGap
            if available < textWidth then
                return
            end
            width = math.min(width, available)
        end
    end
    if text ~= currentText then
        button:SetTextToFit(text)
    end
    local currentWidth = button:GetWidth()
    if IsNumber(currentWidth) and currentWidth ~= width then
        button:SetWidth(width)
    end
    return true
end

local function UpdateEstimate(button, textState, quantity, duration, quantityArrow)
    if not (duration or textState.estimate) or not IsVisible(button) then
        return
    end
    local currentText, nativeText = GetButtonText(button, textState)
    if not nativeText or nativeText == "" then
        return
    end
    local label = nativeText
    local enabled = button:IsEnabled()
    if not issecretvalue(enabled) and enabled and duration and IsNumber(quantity) and quantity > 0 then
        local space = nativeText:match("%[%d+%]$") and "" or " "
        label = ("%s%s[%s]"):format(nativeText, space, FormatDuration(quantity * duration))
    end
    if CanAccess(quantityArrow) and label ~= nativeText then
        if SetCompactButtonText(button, label, currentText, quantityArrow) then
            currentText = label
        else
            label = nativeText
        end
    end
    textState.native = nativeText
    textState.estimate = label ~= nativeText and label or nil
    if label ~= currentText then
        button:SetTextToFit(label)
    end
end

local function CreateBatchDisplay()
    local fill = CreateFrame("StatusBar", nil, UIParent)
    fill:SetMinMaxValues(0, 1)
    fill:Hide()

    local function AddBarTexture(layer, atlas, padding)
        local texture = fill:CreateTexture(nil, layer)
        texture:SetAtlas(atlas)
        texture:SetPoint("TOPLEFT", fill, "TOPLEFT", -padding, padding)
        texture:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", padding, -padding)
    end

    -- Match the native cast bar's background and frame extents.
    AddBarTexture("BACKGROUND", "ui-castingbar-background", 1)
    AddBarTexture("OVERLAY", "ui-castingbar-frame", 2)
    local glow = fill:CreateTexture(nil, "OVERLAY", nil, 1)
    glow:SetAtlas("cast_crafting_pipglow", true)
    glow:SetBlendMode("ADD")
    local spark = fill:CreateTexture(nil, "OVERLAY", nil, 2)
    spark:SetAtlas("ui-castingbar-pip", true)
    glow:SetPoint("RIGHT", spark, "LEFT", 2, 0)

    -- Clip the tip horizontally while preserving the native glow above and below the bar.
    local tipMask = fill:CreateMaskTexture()
    tipMask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    tipMask:SetPoint("LEFT", fill, "LEFT")
    tipMask:SetPoint("RIGHT", fill, "RIGHT")
    spark:AddMaskTexture(tipMask)
    glow:AddMaskTexture(tipMask)

    local label = fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", fill)
    return { fill = fill, label = label, spark = spark, glow = glow, tipMask = tipMask }
end

local function MatchTextureSize(texture, source)
    if CanAccess(source) then
        local width, height = source:GetSize()
        if IsNumber(width) and IsNumber(height) and width > 0 and height > 0 then
            texture:SetSize(width, height)
        end
    end
end

local function PrepareBatchDisplay(display, bar, anchor)
    local nativeFill = bar:GetStatusBarTexture()
    if not CanAccess(nativeFill) then
        return false
    end
    local asset = nativeFill:GetAtlas()
    if issecretvalue(asset) then
        return false
    end
    asset = asset or nativeFill:GetTexture()
    local width, height = bar:GetSize()
    local scale, rootScale = bar:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if issecretvalue(asset) or not asset or not IsNumber(width) or not IsNumber(height)
        or width <= 0 or height <= 0 or not IsNumber(scale) or not IsNumber(rootScale)
        or scale <= 0 or rootScale <= 0 then
        return false
    end
    local fill = display.fill
    if not fill:SetStatusBarTexture(asset) then
        return false
    end
    local r, g, b, a = bar:GetStatusBarColor()
    if IsNumber(r) and IsNumber(g) and IsNumber(b) and IsNumber(a) then
        fill:SetStatusBarColor(r, g, b, a)
    end
    fill:SetFrameStrata("HIGH")
    fill:SetScale(scale / rootScale)
    fill:SetSize(width, height)
    fill:ClearAllPoints()
    fill:SetPoint("CENTER", anchor or bar)
    MatchTextureSize(display.spark, bar.Spark)
    MatchTextureSize(display.glow, bar.CraftGlow)
    display.tipMask:SetHeight(math.max(height, display.spark:GetHeight(), display.glow:GetHeight()))
    display.spark:ClearAllPoints()
    display.spark:SetPoint("CENTER", fill:GetStatusBarTexture(), "RIGHT")
    return true
end

local function SuppressBar(bar, suppressedBars)
    if not CanAccess(bar) or suppressedBars[bar] then
        return
    end
    local layers = {}
    suppressedBars[bar] = layers
    -- Native fades and fill changes run normally while their drawing is suspended.
    for _, layer in ipairs(castBarLayers) do
        local enabled = bar:IsDrawLayerEnabled(layer)
        if not issecretvalue(enabled) and enabled == true then
            layers[#layers + 1] = layer
            bar:SetDrawLayerEnabled(layer, false)
        end
    end
end

local function InstallCraftTimer(page, events, settings)
    local create, createAll, input = page.CreateButton, page.CreateAllButton, page.CreateMultipleInputBox
    local createText, createAllText = {}, {}
    local suppressedBars = {}
    local display
    local lastRecipeID, lastBatchText, craftable
    local ticker, batch

    local function UpdateButtons()
        if InCombatLockdown() or not IsVisible(page) then
            return
        end
        local duration, selectedQuantity
        local recipeID = settings.craftTimerEnabled and GetRecipeID(page)
        if recipeID then
            local spell = C_Spell.GetSpellInfo(recipeID)
            if IsReadableTable(spell) and IsNumber(spell.castTime) and spell.castTime > 0 then
                duration = spell.castTime / millisecondsPerSecond
            end
        end
        if duration then
            if CanAccess(input) then
                selectedQuantity = input:GetValue()
            end
            if IsVisible(createAll) then
                local _, text = GetButtonText(createAll, createAllText)
                -- The native label includes the maximum craftable quantity.
                if text ~= lastBatchText or recipeID ~= lastRecipeID then
                    craftable = page:GetCraftableCount()
                    lastBatchText, lastRecipeID = text, recipeID
                end
            elseif IsNumber(selectedQuantity) and selectedQuantity == 0 then
                selectedQuantity = 1
            end
        end
        UpdateEstimate(create, createText, selectedQuantity, duration)
        UpdateEstimate(createAll, createAllText, craftable, duration, CanAccess(input) and input.DecrementButton)
    end

    local function RestoreBar(bar)
        local layers = suppressedBars[bar]
        if layers and CanAccess(bar) then
            for _, layer in ipairs(layers) do
                bar:SetDrawLayerEnabled(layer, true)
            end
            suppressedBars[bar] = nil
        end
    end

    local function RestoreBars(waitForHide)
        for bar in pairs(suppressedBars) do
            if not waitForHide or not IsVisible(bar) then
                RestoreBar(bar)
            end
        end
    end

    local function Stop(finished)
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        batch = nil
        if display then
            display.fill:Hide()
        end
        RestoreBars(finished == true)
    end

    local function GetOverlayAnchor()
        local overlay = OverlayPlayerCastingBarFrame
        if CanAccess(overlay) then
            local parent = overlay:GetParent()
            if not issecretvalue(parent) and parent == page.OverlayCastBarAnchor then
                return parent
            end
        end
    end

    local function ShowProgress(progress, remaining)
        if not batch.displayReady then
            local anchor = IsVisible(OverlayPlayerCastingBarFrame) and GetOverlayAnchor()
            local bar = anchor and OverlayPlayerCastingBarFrame or PlayerCastingBarFrame
            if not IsVisible(bar) then
                return
            end
            display = display or CreateBatchDisplay()
            if not PrepareBatchDisplay(display, bar, anchor) then
                return
            end
            batch.displayReady = true
            SuppressBar(bar, suppressedBars)
            -- Blizzard can hand the cast back to the HUD bar while the batch is active.
            SuppressBar(PlayerCastingBarFrame, suppressedBars)
        end
        local interpolate = progress < 1 and display.fill:IsShown() and Enum.StatusBarInterpolation
        display.fill:SetValue(progress, interpolate and interpolate.ExponentialEaseOut or nil)
        display.spark:SetShown(progress < 1)
        display.glow:SetShown(progress < 1)
        local text = FormatDuration(remaining)
        if display.label:GetText() ~= text then
            display.label:SetText(text)
        end
        display.fill:Show()
    end

    local function UpdateBatch()
        if not batch or not settings.craftTimerEnabled or InCombatLockdown() or not IsVisible(page) then
            Stop()
            return
        end
        local now = GetTime()
        local _, _, _, startMS, endMS, isTradeSkill, _, _, spellID = UnitCastingInfo("player")
        if issecretvalue(spellID) or issecretvalue(startMS) or issecretvalue(endMS) then
            Stop()
            return
        end
        if isTradeSkill == true and spellID == batch.recipeID and IsNumber(startMS) and IsNumber(endMS)
            and endMS > startMS then
            local remaining = C_TradeSkillUI.GetRemainingRecasts()
            if not IsNumber(remaining) or remaining < 0 then
                Stop()
                return
            end
            batch.endTime = endMS / millisecondsPerSecond
            batch.duration = (endMS - startMS) / millisecondsPerSecond
            batch.remaining = remaining
            batch.total = math.max(batch.total or 0, remaining + 1)
        elseif spellID or (not batch.endTime and now >= batch.startDeadline)
            or (batch.endTime and (batch.remaining == 0 or now >= batch.endTime + betweenCastsTimeout)) then
            Stop(batch.finished and not spellID)
            return
        elseif not batch.endTime then
            return
        end

        -- Keep the fill at the completed-craft boundary if there is a short gap before the next cast.
        local currentRemaining = math.max(0, math.min(batch.duration, batch.endTime - now))
        local remaining = currentRemaining + batch.remaining * batch.duration
        if remaining > 0 then
            local progress = 1 - (batch.remaining + currentRemaining / batch.duration) / batch.total
            ShowProgress(progress, remaining)
        elseif now >= batch.endTime + betweenCastsTimeout then
            Stop(batch.finished)
        end
    end

    hooksecurefunc(page, "ValidateControls", UpdateButtons)
    input:HookScript("OnTextChanged", UpdateButtons)
    create:HookScript("OnClick", function() Stop() end)
    createAll:HookScript("OnClick", function()
        Stop()
        if not settings.craftTimerEnabled or InCombatLockdown() or not IsVisible(page) then
            return
        end
        local recipeID = GetRecipeID(page)
        if recipeID then
            batch = { recipeID = recipeID, startDeadline = GetTime() + castStartTimeout }
            UpdateBatch()
            if batch then
                ticker = C_Timer.NewTicker(updateInterval, UpdateBatch)
            end
        end
    end)
    page:HookScript("OnHide", function() Stop() end)

    local function WatchNativeBar(bar)
        if CanAccess(bar) then
            bar:HookScript("OnShow", function()
                if batch and batch.displayReady and not InCombatLockdown()
                    and (bar == PlayerCastingBarFrame or GetOverlayAnchor()) then
                    SuppressBar(bar, suppressedBars)
                else
                    RestoreBar(bar)
                end
            end)
            bar:HookScript("OnHide", function()
                if not batch then
                    RestoreBar(bar)
                end
            end)
        end
    end
    WatchNativeBar(PlayerCastingBarFrame)
    WatchNativeBar(OverlayPlayerCastingBarFrame)

    events:SetScript("OnEvent", function(_frame, event, arg, _castGUID, spellID)
        if event == "PLAYER_REGEN_ENABLED" then
            RestoreBars()
            UpdateButtons()
        elseif not batch then
            if event == "UNIT_SPELLCAST_START" or event == "PLAYER_LEAVING_WORLD" then
                RestoreBars()
            end
            return
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
            UpdateBatch()
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if not InCombatLockdown() and not issecretvalue(spellID)
                and spellID == batch.recipeID and batch.remaining == 0 then
                batch.finished = true
                ShowProgress(1, 0)
            end
        elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
            if issecretvalue(spellID) or spellID == batch.recipeID then
                Stop()
            end
        elseif event == "UPDATE_TRADESKILL_CAST_STOPPED" then
            if not issecretvalue(arg) and arg == false then
                Stop(batch.finished)
            end
        else
            Stop()
        end
    end)
    for _, event in ipairs({ "TRADE_SKILL_CLOSE", "TRADE_SKILL_DATA_SOURCE_CHANGING",
        "UPDATE_TRADESKILL_CAST_STOPPED", "PLAYER_LEAVING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED" }) do
        events:RegisterUnitEvent(event, "player")
    end
    UpdateButtons()
    return function()
        if not settings.craftTimerEnabled then
            Stop()
        end
        UpdateButtons()
    end
end

function addon.InitializeCraftTimer(settings)
    local events = CreateFrame("Frame")
    local refresh
    local function TryInstall()
        local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
        if CanAccess(page) and CanAccess(page.CreateAllButton) and CanAccess(page.CreateButton)
            and CanAccess(page.CreateMultipleInputBox) then
            events:UnregisterEvent("ADDON_LOADED")
            refresh = InstallCraftTimer(page, events, settings)
        end
    end

    TryInstall()
    if not refresh then
        events:RegisterEvent("ADDON_LOADED")
        events:SetScript("OnEvent", function(_, _, name)
            if name == "Blizzard_Professions" then
                TryInstall()
            end
        end)
    end
    return function()
        if refresh then
            refresh()
        end
    end
end
