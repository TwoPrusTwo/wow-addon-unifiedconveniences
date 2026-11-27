local _, addon = ...

local millisecondsPerSecond = 1000
local secondsPerMinute = 60
local updateInterval = 0.2
local castStartTimeout = 3
local betweenCastsTimeout = 2
local maxRunningProgress = 0.999
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
    local display = CreateFrame("StatusBar", nil, UIParent, "CastingBarFrameTemplate")
    display:Hide()
    display.Countdown = display:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    display.Countdown:SetPoint("CENTER", display)
    return display
end

local function PrepareBatchDisplay(display, bar, anchor)
    local width, height = bar:GetSize()
    local scale, rootScale = bar:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local look, strata, level = bar.look, bar:GetFrameStrata(), bar:GetFrameLevel()
    if issecretvalue(look) or issecretvalue(strata) or not IsNumber(level)
        or not IsNumber(width) or not IsNumber(height) or width <= 0 or height <= 0
        or not IsNumber(scale) or not IsNumber(rootScale)
        or scale <= 0 or rootScale <= 0 then
        return false
    end
    display.playCastFX = true
    display:SetLook(look)
    display:SetFrameStrata(strata)
    display:SetFrameLevel(level)
    display:SetScale(scale / rootScale)
    display:SetSize(width, height)
    display:ClearAllPoints()
    display:SetPoint("CENTER", anchor or bar)
    display:SetNameTextShown(IsVisible(bar.Text) == true)
    display.TextBorder:SetShown(IsVisible(bar.TextBorder) == true)
    display:SetIconShown(IsVisible(bar.Icon) == true)
    return true
end

local function SuppressBar(bar, suppressedBars)
    if not CanAccess(bar) then
        return false
    end
    if suppressedBars[bar] then
        return true
    end
    local layers = {}
    for _, layer in ipairs(castBarLayers) do
        local enabled = bar:IsDrawLayerEnabled(layer)
        if issecretvalue(enabled) then
            return false
        end
        if enabled then
            layers[#layers + 1] = layer
        end
    end
    -- Native fades and fill changes run normally while their drawing is suspended.
    suppressedBars[bar] = layers
    for _, layer in ipairs(layers) do
        bar:SetDrawLayerEnabled(layer, false)
    end
    return true
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
        if display and not finished then
            display:StopAnims()
            display:HideSpark()
            display:Hide()
        end
        RestoreBars(finished == true)
    end

    local function GetOverlayAnchor()
        local overlay = OverlayPlayerCastingBarFrame
        if CanAccess(overlay) then
            local parent = overlay:GetParent()
            if CanAccess(parent) and parent == page.OverlayCastBarAnchor then
                return parent
            end
        end
    end

    local function DrawProgress()
        if not batch then
            return
        end
        -- Between casts, the fill holds at the last completed craft.
        local currentRemaining = math.max(0, math.min(batch.duration, batch.endTime - GetTime()))
        local progress = 1 - (batch.remaining + currentRemaining / batch.duration) / batch.total
        local seconds = math.ceil(currentRemaining + batch.remaining * batch.duration)
        if seconds ~= batch.displayedSeconds then
            display.Countdown:SetText(FormatDuration(seconds))
            batch.displayedSeconds = seconds
        end
        -- Use the native spark positioning without letting its clock finish the cast.
        display.value = math.min(progress, maxRunningProgress)
        display:OnUpdate(0)
    end

    local function StartDisplay(spellText, icon)
        local anchor = IsVisible(OverlayPlayerCastingBarFrame) and GetOverlayAnchor()
        local bar = anchor and OverlayPlayerCastingBarFrame or PlayerCastingBarFrame
        if not IsVisible(bar) then
            return
        end
        if not display then
            display = CreateBatchDisplay()
            display:SetScript("OnUpdate", DrawProgress)
        end
        if not PrepareBatchDisplay(display, bar, anchor) or not SuppressBar(bar, suppressedBars) then
            return
        end
        -- Blizzard can hand the cast back to the HUD while the batch is active.
        if bar ~= PlayerCastingBarFrame and not SuppressBar(PlayerCastingBarFrame, suppressedBars)
            and IsVisible(PlayerCastingBarFrame) then
            RestoreBar(bar)
            return
        end
        batch.displayReady = true
        display:SimulateCast({
            barType = CastingBarType.ApplyingCrafting,
            castTime = 1,
            spellName = not issecretvalue(spellText) and spellText or "",
            iconTexture = not issecretvalue(icon) and icon or nil,
        })
        DrawProgress()
    end

    local function FinishBatch()
        if batch.displayReady then
            display.Countdown:SetText(FormatDuration(0))
            display:FinishSpell()
            Stop(true)
        else
            Stop()
        end
    end

    local function UpdateBatch()
        if not batch or not settings.craftTimerEnabled or InCombatLockdown() or not IsVisible(page) then
            Stop()
            return
        end
        local now = GetTime()
        if batch.stopDeadline and now >= batch.stopDeadline then
            Stop()
            return
        end
        local _, spellText, icon, startMS, endMS, isTradeSkill, castID, _, spellID = UnitCastingInfo("player")
        if issecretvalue(spellID) or issecretvalue(castID) or issecretvalue(startMS) or issecretvalue(endMS) then
            Stop()
            return
        end
        if isTradeSkill == true and spellID == batch.recipeID and IsNumber(startMS) and IsNumber(endMS)
            and endMS > startMS then
            local remaining = C_TradeSkillUI.GetRemainingRecasts()
            if not IsNumber(remaining) or remaining < 0
                or (batch.remaining == 0 and batch.castID ~= castID) then
                Stop()
                return
            end
            batch.castID = castID
            batch.endTime = endMS / millisecondsPerSecond
            batch.duration = (endMS - startMS) / millisecondsPerSecond
            batch.remaining = remaining
            batch.total = math.max(batch.total or 0, remaining + 1)
            if not batch.displayReady then
                StartDisplay(spellText, icon)
            end
        elseif spellID or now >= (batch.endTime and batch.endTime + betweenCastsTimeout or batch.startDeadline) then
            Stop()
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
                    if not SuppressBar(bar, suppressedBars) then
                        Stop()
                    end
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

    events:SetScript("OnEvent", function(_frame, event, arg, castID, spellID)
        if event == "PLAYER_REGEN_ENABLED" then
            RestoreBars()
            UpdateButtons()
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
            if batch then
                UpdateBatch()
            elseif event == "UNIT_SPELLCAST_START" then
                Stop()
            end
        elseif event == "TRADE_SKILL_CLOSE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGING"
            or event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_REGEN_DISABLED"
            or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
            Stop()
        elseif batch then
            if event == "UPDATE_TRADESKILL_CAST_STOPPED" then
                if not issecretvalue(arg) and arg == false then
                    if batch.remaining == 0 then
                        -- The stop notification can arrive before the final cast result.
                        batch.stopDeadline = GetTime() + updateInterval
                    else
                        Stop()
                    end
                end
            elseif issecretvalue(castID) or issecretvalue(spellID) then
                Stop()
            elseif spellID == batch.recipeID and (not batch.castID or castID == batch.castID) then
                if event == "UNIT_SPELLCAST_SUCCEEDED" then
                    if not InCombatLockdown() and batch.remaining == 0 then
                        FinishBatch()
                    end
                else
                    Stop()
                end
            end
        end
    end)
    for _, event in ipairs({ "TRADE_SKILL_CLOSE", "TRADE_SKILL_DATA_SOURCE_CHANGING",
        "UPDATE_TRADESKILL_CAST_STOPPED", "PLAYER_LEAVING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
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
