local _, addon = ...

local millisecondsPerSecond = 1000
local secondsPerMinute = 60
local updateInterval = 0.2
local castStartTimeout = 3
local betweenCastsTimeout = 2

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

local function UpdateEstimate(button, textState, quantity, duration)
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
        label = ("%s · %s"):format(nativeText, FormatDuration(quantity * duration))
    end
    textState.native = nativeText
    textState.estimate = label ~= nativeText and label or nil
    if label ~= currentText then
        button:SetTextToFit(label)
    end
end

local function InstallCraftTimer(page, events, settings)
    local create, createAll, input = page.CreateButton, page.CreateAllButton, page.CreateMultipleInputBox
    local createText, createAllText = {}, {}
    local overlays = {}
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
        UpdateEstimate(createAll, createAllText, craftable, duration)
    end

    local function HideLabels()
        for _, label in pairs(overlays) do
            label:Hide()
        end
    end

    local function Stop()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        batch = nil
        HideLabels()
    end

    local function ShowRemaining(remaining)
        local overlay = OverlayPlayerCastingBarFrame
        local bar = PlayerCastingBarFrame
        if IsVisible(overlay) and overlay:GetParent() == page.OverlayCastBarAnchor then
            bar = overlay
        end

        for parent, label in pairs(overlays) do
            if parent ~= bar then
                label:Hide()
            end
        end
        if not IsVisible(bar) then
            HideLabels()
            return
        end
        local label = overlays[bar]
        if not label then
            label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("CENTER", bar)
            overlays[bar] = label
        end
        local text = FormatDuration(remaining)
        if label:GetText() ~= text then
            label:SetText(text)
        end
        label:Show()
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
        elseif spellID or (not batch.endTime and now >= batch.startDeadline)
            or (batch.endTime and (batch.remaining == 0 or now >= batch.endTime + betweenCastsTimeout)) then
            Stop()
            return
        else
            -- Blizzard can briefly report no cast between two queued crafts.
            HideLabels()
            return
        end

        local remaining = math.max(0, batch.endTime - now) + batch.remaining * batch.duration
        if remaining > 0 then
            ShowRemaining(remaining)
        else
            Stop()
        end
    end

    hooksecurefunc(page, "ValidateControls", UpdateButtons)
    input:HookScript("OnTextChanged", UpdateButtons)
    create:HookScript("OnClick", Stop)
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
    page:HookScript("OnHide", Stop)

    events:SetScript("OnEvent", function(_frame, event, arg, _castGUID, spellID)
        if event == "PLAYER_REGEN_ENABLED" then
            UpdateButtons()
        elseif not batch then
            return
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
            UpdateBatch()
        elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
            if issecretvalue(spellID) or spellID == batch.recipeID then
                Stop()
            end
        elseif event ~= "UPDATE_TRADESKILL_CAST_STOPPED" or (not issecretvalue(arg) and arg == false) then
            Stop()
        end
    end)
    for _, event in ipairs({ "TRADE_SKILL_CLOSE", "TRADE_SKILL_DATA_SOURCE_CHANGING",
        "UPDATE_TRADESKILL_CAST_STOPPED", "PLAYER_LEAVING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
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
