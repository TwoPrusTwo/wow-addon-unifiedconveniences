local _, addon = ...

local styles = {
    player = {
        isPlayer = true,
        visibilityCVar = "nameplateShowFriendlyPlayers",
        fallbackColour = CreateColorFromHexString("FF8686FF"),
    },
    npc = {
        isPlayer = false,
        visibilityCVar = "nameplateShowFriendlyNpcs",
        fallbackColour = FACTION_GREEN_COLOR,
    },
}

local function IsReadable(value, valueType)
    return not issecretvalue(value) and type(value) == valueType
end

local function WithoutOutline(flags)
    if not IsReadable(flags, "string") or flags == "OUTLINE" or flags == "THICKOUTLINE" then
        return ""
    end
    if not flags:find("OUTLINE", 1, true) then
        return flags
    end

    local remaining = {}
    for flag in flags:gmatch("[^,%s]+") do
        if flag ~= "OUTLINE" and flag ~= "THICKOUTLINE" then
            remaining[#remaining + 1] = flag
        end
    end
    return table.concat(remaining, ", ")
end

local function IsForbidden(region)
    if region.IsForbidden and region:IsForbidden() then
        return true
    end
    local parent = region:GetParent()
    return parent and parent:IsForbidden()
end

local function GetReadableGUID(unit)
    local guid = UnitGUID(unit)
    if IsReadable(guid, "string") then
        return guid
    end
end

local function GetWritableSetting(name)
    local value, _, _, perCharacter, locked, secure, readOnly = C_CVar.GetCVarInfo(name)
    if locked or secure or readOnly or not IsReadable(value, "string") or (value ~= "0" and value ~= "1") then
        return
    end
    if perCharacter then
        local guid = GetReadableGUID("player")
        if not guid then
            return
        end
        return value, guid
    end
    return value
end

local function GetOverheadColour(unit, style)
    local r, g, b = UnitSelectionColor(unit, style.isPlayer)
    if IsReadable(r, "number") and IsReadable(g, "number") and IsReadable(b, "number") then
        return r, g, b
    end
    return style.fallbackColour:GetRGB()
end

local function GetGuildTitle(unit)
    local guild = GetGuildInfo and GetGuildInfo(unit)
    if IsReadable(guild, "string") and guild ~= "" then
        return "<" .. guild .. ">"
    end
end

local alwaysShow = "nameplateShowAll"
local enemyVisibilityCVar = "nameplateShowEnemies"
local visibilityKeys = {
    alwaysShow,
    enemyVisibilityCVar,
    styles.player.visibilityCVar,
    styles.npc.visibilityCVar,
    "nameplateShowSelf",
}
local nameOnly = "nameplateShowOnlyNameForFriendlyPlayerUnits"
local watchedKeys = { [nameOnly:lower()] = true }
for _, name in ipairs(visibilityKeys) do
    watchedKeys[name:lower()] = true
end
local colourblindMode = "colorblindmode"
local npcNameSettings = {
    [colourblindMode] = true,
    unitnamenpc = true,
    unitnamefriendlyspecialnpcname = true,
    unitnamehostlenpc = true,
    unitnameinteractivenpc = true,
    unitnamenoncombatcreaturename = true,
    unitnamefriendlyminionname = true,
}

-- A loaded nameplate replacement can control visibility without writing a CVar.
local nameplateAddons = {
    "BetterBlizzPlates", "DenoNameplate", "EllesmereUINameplates", "ElvUI",
    "Kui_Nameplates", "NeatPlates", "Platynator", "Plater", "SmartFriendlyNameplates",
    "ThreatPlates", "TidyPlates", "TidyPlates_ThreatPlates", "Tukui",
}

local baseFontSize = 14
local minimumFontSize, maximumFontSize = 2.5, 52
local halfSizeDepth = 9.5
local fallbackCameraZoom = 15
local scaleResponseTime = .06
local settledScaleDelta = .001
local rangeCheckInterval = .1
local closeRangeIndex, followRangeIndex = 3, 4
local closeUnitDistance, middleUnitDistance, farUnitDistance = 0, 14, 32
local plateRetryDelay = .1

local function IsDistance(value)
    return IsReadable(value, "number") and value >= 0 and value < math.huge
end

local function GetReadableCameraZoom()
    local zoom = GetCameraZoom()
    if IsDistance(zoom) then
        return zoom
    end
end

local function IsPlayerOutOfCombat()
    local combat = UnitAffectingCombat("player")
    return IsReadable(combat, "boolean") and not combat and not InCombatLockdown()
end

local function GetUnitDistance(unit, canCheckInteractionRange)
    local squared, checked = UnitDistanceSquared(unit)
    if IsReadable(checked, "boolean") and checked and IsDistance(squared) then
        return math.sqrt(squared)
    end
    if canCheckInteractionRange then
        -- Exact distance is normally available only for group members.
        local close = CheckInteractDistance(unit, closeRangeIndex)
        if not issecretvalue(close) and close then
            return closeUnitDistance
        end
        local withinFollowRange = CheckInteractDistance(unit, followRangeIndex)
        if not issecretvalue(close) and not issecretvalue(withinFollowRange) then
            return withinFollowRange and middleUnitDistance or farUnitDistance
        end
    end
end

local function GetTextScale(zoom, distance)
    -- Camera zoom and unit range are both measured from the player.
    local depth = zoom + (distance or middleUnitDistance)
    local fontSize = maximumFontSize * .5 ^ (depth / halfSizeDepth)
    return math.max(minimumFontSize, fontSize) / baseFontSize
end

local function CreateOverheadText(plate)
    local label = plate:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlate")
    label:SetWordWrap(false)
    label:SetSmoothScaling(true)
    return label
end

local function AnchorSubtitle(display)
    -- Keep configured offsets in plate units while the subtitle region scales.
    local scale = display.textScale
    display.subtitle:SetPoint("TOP", display.name, "BOTTOM", display.subtitleX / scale, display.subtitleY / scale)
end

local function HasNameplateAddon()
    for _, name in ipairs(nameplateAddons) do
        if C_AddOns.IsAddOnLoaded(name) then
            return true
        end
    end
    return false
end

local function GetUnitForPlate(plate)
    if not plate or plate:IsForbidden() or not plate.GetUnit then
        return
    end
    local unit = plate:GetUnit()
    if IsReadable(unit, "string") then
        return unit
    end
end

local function IsNativePlateVisible(plate)
    if plate:IsForbidden() then
        return true
    end
    local frame = plate.UnitFrame
    local visible = plate:IsVisible()
    if not frame or (IsReadable(visible, "boolean") and not visible) then
        return false
    end
    if frame:IsForbidden() then
        return true
    end
    local alpha = frame:GetEffectiveAlpha()
    visible = frame:IsVisible()
    return (not IsReadable(visible, "boolean") or visible) and (not IsReadable(alpha, "number") or alpha > 0)
end

local function GetPlateName(unit, nativeName)
    local text = nativeName:GetText()
    if not IsReadable(text, "string") or text == "" then
        text = GetUnitName(unit, false)
    end
    if IsReadable(text, "string") and text ~= "" then
        return text
    end
end

local function HasTooltipLineType(line, expectedType)
    return IsReadable(line, "table") and IsReadable(line.type, "number") and line.type == expectedType
end

local function ReadNPCTitle(unit, guid)
    local lineTypes = Enum.TooltipDataLineType
    if not lineTypes or not C_TooltipInfo or not C_TooltipInfo.GetUnit or not guid:match("^Creature%-") then
        return
    end
    local minion = UnitIsMinion(unit)
    if not IsReadable(minion, "boolean") or minion then
        return
    end
    local colourblind = C_CVar.GetCVar(colourblindMode)
    if not IsReadable(colourblind, "string") or (colourblind ~= "0" and colourblind ~= "1") then
        return
    end

    local data = C_TooltipInfo.GetUnit(unit)
    if not IsReadable(data, "table") or not IsReadable(data.lines, "table") then
        return
    end
    if issecretvalue(data.guid) or (data.guid and data.guid ~= guid) then
        return
    end
    -- Forever returns untyped NPC titles after the name and any colourblind reaction line.
    local line = data.lines[colourblind == "1" and 3 or 2]
    if not HasTooltipLineType(data.lines[1], lineTypes.UnitName) or not HasTooltipLineType(line, lineTypes.None) then
        return
    end
    local text, right = line.leftText, line.rightText
    if not IsReadable(text, "string") or issecretvalue(right) or (right and right ~= "") or text:find("[\r\n]") then
        return
    end
    local title = text:match("^%s*(.-)%s*$")
    title = title:match("^<%s*(.-)%s*>$") or title
    -- Level text can occupy the same untyped slot on an NPC without a title.
    if title ~= "" and not (IsReadable(LEVEL, "string") and LEVEL ~= "" and title:lower():find(LEVEL:lower(), 1, true)) then
        return "<" .. title .. ">"
    end
end

local function CanRenderName(unitFrame)
    if unitFrame:IsForbidden() or IsForbidden(unitFrame.name) then
        return false
    end
    local widgetsOnly = unitFrame.widgetsOnlyMode
    return not issecretvalue(widgetsOnly) and not widgetsOnly
end

local function IsTarget(unit)
    local exists = UnitExists("target")
    if not IsReadable(exists, "boolean") then
        return
    end
    if not exists then
        return false
    end
    local matches = UnitIsUnit(unit, "target")
    if IsReadable(matches, "boolean") then
        return matches
    end
end

local function GetFriendlyKind(unit)
    local friendly = UnitIsFriend("player", unit)
    local player = UnitIsPlayer(unit)
    if not IsReadable(friendly, "boolean") or not IsReadable(player, "boolean") then
        return nil, false
    end
    if not friendly then
        return nil, true
    end
    if not player then
        return "npc", true
    end
    local guid, ownGUID = GetReadableGUID(unit), GetReadableGUID("player")
    if not guid or not ownGUID then
        return nil, false
    end
    return guid ~= ownGUID and "player" or nil, true
end

function addon.InitializeSimpleNameplates(db)
    local modes, displays, displayedUnits = {}, {}, {}
    local saved = type(db.simpleNameplates) == "table" and db.simpleNameplates or {}
    db.simpleNameplates = saved
    if type(saved.enabled) ~= "boolean" then
        saved.enabled = true
    end
    local active, transitioning, yielded
    local outdoors = false
    local settingsPanel
    local expectedVisibility, pauseInCombat
    local pendingUnits, plateRetry, reconcileTimer = {}, nil, nil
    local waitingForReadyPlate = false
    local visibleSimpleCount = 0
    local cameraZoom, rangeElapsed, scaling = fallbackCameraZoom, 0, false
    local events = CreateFrame("Frame")

    local function WriteSetting(name, value)
        if not GetWritableSetting(name) then
            return false
        end
        pcall(C_CVar.SetCVar, name, value)
        return C_CVar.GetCVar(name) == value
    end

    local function RestoreSettings(store)
        local pending = store.nameplateRestore
        if type(pending) ~= "table" then
            store.nameplateRestore = nil
            return true
        end
        local playerGUID = GetReadableGUID("player")
        for name, entry in pairs(pending) do
            if type(entry) == "table" and entry.value == "0" then
                if entry.player and entry.player ~= playerGUID then
                    return false
                end
                local current = C_CVar.GetCVar(name)
                if not IsReadable(current, "string") or (current == "1" and not WriteSetting(name, "0")) then
                    return false
                end
            end
            pending[name] = nil
        end
        store.nameplateRestore = nil
        return true
    end

    local function RefreshTextScale(_, elapsed)
        if not outdoors or not active then
            return
        end
        rangeElapsed = rangeElapsed + elapsed
        local checkDistances = rangeElapsed >= rangeCheckInterval
        local zoom = GetReadableCameraZoom() or cameraZoom
        if not checkDistances and not scaling and zoom == cameraZoom then
            return
        end
        cameraZoom = zoom
        scaling = false
        if checkDistances then
            rangeElapsed = 0
        end
        local canCheckInteractionRange = checkDistances and IsPlayerOutOfCombat()
        local blend = 1 - math.exp(-elapsed / scaleResponseTime)
        for _, display in pairs(displayedUnits) do
            if display.textScale then
                if checkDistances then
                    display.distance = GetUnitDistance(display.unit, canCheckInteractionRange) or display.distance
                end
                local targetScale = GetTextScale(cameraZoom, display.distance)
                local delta = targetScale - display.textScale
                if delta ~= 0 then
                    local scale = targetScale
                    if math.abs(delta) > settledScaleDelta then
                        scale = display.textScale + delta * blend
                        scaling = true
                    end
                    display.textScale = scale
                    display.name:SetScale(scale)
                    if display.subtitle and display.subtitle:IsShown() then
                        display.subtitle:SetScale(scale)
                        if display.subtitleX ~= 0 or display.subtitleY ~= 0 then
                            AnchorSubtitle(display)
                        end
                    end
                end
            end
        end
    end

    local function ReleaseDisplay(display, skipNativeRestore)
        if not display or not display.unit then
            return
        end
        local region = display.hiddenRegion
        if not skipNativeRestore and not IsForbidden(region) then
            local alpha = region:GetAlpha()
            if IsReadable(alpha, "number") and alpha == 0 then
                pcall(region.SetAlpha, region, display.originalAlpha)
            end
        end
        if display.name then
            display.name:Hide()
        end
        if display.subtitle then
            display.subtitle:Hide()
        end
        if display.kind then
            visibleSimpleCount = visibleSimpleCount - 1
            if visibleSimpleCount == 0 then
                events:SetScript("OnUpdate", nil)
                rangeElapsed, scaling = 0, false
            end
        end
        displayedUnits[display.unit] = nil
        display.unit, display.guid, display.kind, display.hiddenRegion = nil, nil, nil, nil
        display.distance, display.textScale = nil, nil
        display.npcTitle = nil
    end

    local function RefreshOverlays()
        for _, mode in pairs(modes) do
            mode.refreshPlates()
        end
    end

    local function Stop(deferRestoration)
        local wasActive = active
        active = false
        expectedVisibility, pauseInCombat = nil, nil
        if plateRetry then
            plateRetry:Cancel()
            plateRetry = nil
        end
        if reconcileTimer then
            reconcileTimer:Cancel()
            reconcileTimer = nil
        end
        pendingUnits = {}
        transitioning = true
        for _, display in pairs(displayedUnits) do
            ReleaseDisplay(display, deferRestoration)
        end
        local restored = not deferRestoration and RestoreSettings(saved)
        transitioning = false
        if wasActive and outdoors then
            RefreshOverlays()
        end
        return restored
    end

    local function Suspend(insideInstance)
        if outdoors then
            outdoors = false
            Stop(insideInstance or IsInInstance())
        end
    end

    local function Yield()
        yielded = true
        Stop()
    end

    local function HideNative(plate, unit, kind)
        local region = plate.UnitFrame
        local guid = GetReadableGUID(unit)
        if not guid or not region or region:IsForbidden() then
            return
        end
        local display = displays[plate]
        if display and display.unit
            and (display.unit ~= unit or display.guid ~= guid or display.kind ~= kind or display.hiddenRegion ~= region) then
            ReleaseDisplay(display)
        end
        local previous = displayedUnits[unit]
        if previous and previous ~= display then
            ReleaseDisplay(previous)
        end
        local alpha = region:GetAlpha()
        if not IsReadable(alpha, "number") or (display and display.unit and alpha ~= 0)
            or ((not display or not display.unit) and alpha <= 0) then
            return
        end
        if not display then
            display = {}
            displays[plate] = display
        end
        if not display.unit then
            local ok = pcall(region.SetAlpha, region, 0)
            if not ok or region:GetAlpha() ~= 0 then
                return
            end
            display.unit, display.guid, display.kind = unit, guid, kind
            display.hiddenRegion, display.originalAlpha = region, alpha
            displayedUnits[unit] = display
            if kind then
                visibleSimpleCount = visibleSimpleCount + 1
            end
        end
        return display
    end

    local function RenderName(plate, unit, kind, nativeName, text, subtitle, x, y)
        local style = kind == "npcName" and styles.npc or styles[kind]
        local display = HideNative(plate, unit, kind)
        if not display then
            return
        end
        if not display.name then
            display.name = CreateOverheadText(plate)
        end
        display.name:ClearAllPoints()
        display.name:SetPoint("CENTER", nativeName, "CENTER")

        if not display.textScale then
            local zoom = GetReadableCameraZoom() or cameraZoom
            display.distance = GetUnitDistance(unit, IsPlayerOutOfCombat())
            display.textScale = GetTextScale(zoom, display.distance)
            if visibleSimpleCount == 1 then
                cameraZoom = zoom
                events:SetScript("OnUpdate", RefreshTextScale)
            end
        end
        local font, _, flags = nativeName:GetFont()
        if not IsReadable(font, "string") then
            font, _, flags = display.name:GetFont()
        end
        font = IsReadable(font, "string") and font or nil
        flags = WithoutOutline(flags)
        if font then
            display.name:SetFont(font, baseFontSize, flags)
        end
        display.name:SetScale(display.textScale)
        local r, g, b = GetOverheadColour(unit, style)
        display.name:SetText(text)
        display.name:SetTextColor(r, g, b)
        display.name:Show()

        if style.isPlayer then
            subtitle = GetGuildTitle(unit)
        elseif kind == "npcName" then
            if display.npcTitle == nil and IsPlayerOutOfCombat() then
                local ok, title = pcall(ReadNPCTitle, unit, display.guid)
                display.npcTitle = ok and title or false
            end
            subtitle = display.npcTitle
        end
        if subtitle then
            if not display.subtitle then
                display.subtitle = CreateOverheadText(plate)
            end
            if font then
                display.subtitle:SetFont(font, baseFontSize, flags)
            end
            display.subtitleX, display.subtitleY = x or 0, y or 0
            display.subtitle:SetScale(display.textScale)
            display.subtitle:ClearAllPoints()
            AnchorSubtitle(display)
            display.subtitle:SetText(subtitle)
            display.subtitle:SetTextColor(r, g, b)
            display.subtitle:Show()
        elseif display.subtitle then
            display.subtitle:Hide()
        end
        return display.name
    end

    local function FilterPlate(plate)
        if plate and plate:IsForbidden() then
            return false
        end
        local unit = GetUnitForPlate(plate)
        if not unit then
            return nil
        end
        local target = IsTarget(unit)
        if target ~= false then
            ReleaseDisplay(displays[plate])
            return target == true
        end
        local kind, readable = GetFriendlyKind(unit)
        if not readable then
            return false
        end
        local display = displays[plate]
        if (not display or not display.unit) and not IsNativePlateVisible(plate) then
            return nil
        end
        local mode = modes[kind]
        local featureName = mode and mode:IncludesUnit(unit)
        local preserveNPCName = false
        if kind == "npc" and not featureName then
            -- The temporary plate displaces the world name. Follow WoW's name rules
            -- when replacing that text without a feature-specific subtitle.
            local showName = UnitShouldDisplayName(unit)
            preserveNPCName = IsReadable(showName, "boolean") and showName
        end
        if featureName or preserveNPCName then
            local unitFrame = plate.UnitFrame
            if not unitFrame or not unitFrame.name then
                return nil
            end
            if not CanRenderName(unitFrame) then
                return false
            end
            local text = GetPlateName(unit, unitFrame.name)
            if not text then
                return nil
            end
            if preserveNPCName then
                return RenderName(plate, unit, "npcName", unitFrame.name, text) ~= nil
            end
            return true
        end
        local inCombat = UnitAffectingCombat("player")
        if not IsReadable(inCombat, "boolean") then
            return false
        end
        if inCombat then
            ReleaseDisplay(displays[plate])
            return true
        end
        if not plate.UnitFrame then
            return nil
        end
        return HideNative(plate, unit, nil) ~= nil
    end

    local RefreshPlates

    local function QueuePlateRetry(attempt)
        if not plateRetry then
            local delay = attempt == 1 and 0 or plateRetryDelay
            local timer
            timer = C_Timer.NewTimer(delay, function()
                if plateRetry ~= timer then
                    return
                end
                plateRetry = nil
                if outdoors and active then
                    RefreshPlates(attempt)
                end
            end)
            plateRetry = timer
        end
    end

    function RefreshPlates(attempt)
        if not outdoors then
            return
        end
        if active then
            local pending, unsafe = false, false
            for unit in pairs(pendingUnits) do
                if C_NamePlate.GetNamePlateForUnit(unit) then
                    pendingUnits[unit] = nil
                else
                    pending = true
                end
            end
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                local result = FilterPlate(plate)
                if result == false then
                    Yield()
                    return
                elseif result == nil then
                    pending = true
                    unsafe = unsafe or IsNativePlateVisible(plate)
                end
            end
            if pending then
                if attempt == 2 then
                    -- A later native event can recover an incomplete plate. Do
                    -- not leave an extra visible frame up while waiting for it.
                    if unsafe then
                        waitingForReadyPlate = true
                        Stop()
                        return
                    end
                else
                    QueuePlateRetry(attempt and 2 or 1)
                end
            end
        end
        RefreshOverlays()
    end

    local function RestoreLegacySettings()
        for _, mode in pairs(modes) do
            if not RestoreSettings(mode.legacy) then
                return false
            end
        end
        return true
    end

    local function HasVisibilityChanged(expected)
        for name, value in pairs(expected) do
            local current = C_CVar.GetCVar(name)
            if not IsReadable(current, "string") or current ~= value then
                return true
            end
        end
        return false
    end

    local function CanAcquire()
        local inCombat = UnitAffectingCombat("player")
        if not saved.enabled or yielded or not settingsPanel or settingsPanel:IsShown() or InCombatLockdown()
            or not IsReadable(inCombat, "boolean") or inCombat or HasNameplateAddon() then
            return false
        end
        -- Existing untargeted plates may already be styled by WoW or an addon.
        for _, plate in pairs(C_NamePlate.GetNamePlates()) do
            if IsNativePlateVisible(plate) then
                local unit = GetUnitForPlate(plate)
                if not unit or IsTarget(unit) ~= true then
                    return false
                end
            end
        end
        return true
    end

    local function Acquire()
        local matchingCategories = {}
        for kind, mode in pairs(modes) do
            if mode.isEnabled() then
                matchingCategories[styles[kind].visibilityCVar] = true
            end
        end
        if not next(matchingCategories) or not CanAcquire() then
            return
        end

        local expected, toEnable = {}, {}
        local nativeCombatPlatesEnabled = false
        for _, name in ipairs(visibilityKeys) do
            local current = C_CVar.GetCVar(name)
            if not IsReadable(current, "string") then
                return
            end
            if current == "0" then
                if name == alwaysShow or matchingCategories[name] then
                    toEnable[#toEnable + 1] = name
                    expected[name] = "1"
                else
                    expected[name] = "0"
                end
            elseif current == "1" and (matchingCategories[name] or name == enemyVisibilityCVar) then
                -- WoW will use this category in combat even with Always Show off.
                expected[name] = "1"
                nativeCombatPlatesEnabled = true
            else
                return
            end
        end

        local pending = {}
        transitioning = true
        saved.nameplateRestore = pending
        for _, name in ipairs(toEnable) do
            local current, player = GetWritableSetting(name)
            if current ~= "0" then
                Yield()
                return
            end
            pending[name] = { value = current, player = player }
            if not WriteSetting(name, "1") then
                Yield()
                return
            end
        end
        if HasVisibilityChanged(expected) then
            Yield()
            return
        end
        expectedVisibility, pauseInCombat = expected, nativeCombatPlatesEnabled
        active = true
        transitioning = false
        RefreshPlates()
    end

    local function QueueReconcile()
        if reconcileTimer or not outdoors or waitingForReadyPlate then
            return
        end
        local timer
        timer = C_Timer.NewTimer(0, function()
            if reconcileTimer ~= timer then
                return
            end
            reconcileTimer = nil
            if outdoors and not active and not waitingForReadyPlate and not IsInInstance() and Stop() then
                transitioning = true
                local restored = RestoreLegacySettings()
                transitioning = false
                if restored then
                    Acquire()
                end
            end
        end)
        reconcileTimer = timer
    end

    local function RefreshControlSettings()
        yielded = false
        waitingForReadyPlate = false
        if outdoors then
            Stop()
            QueueReconcile()
        end
    end

    function addon.CreateSimpleNameplateMode(kind, legacy, isEnabled, refreshPlates, includesUnit)
        local mode = { legacy = legacy, isEnabled = isEnabled, refreshPlates = refreshPlates }
        local enabled = isEnabled()
        modes[kind] = mode

        function mode:ReleaseUnit(unit)
            local display = displayedUnits[unit]
            if display and display.kind == kind then
                ReleaseDisplay(display)
            end
        end

        function mode:ReleasePlate(plate)
            local display = displays[plate]
            if display and display.kind == kind then
                ReleaseDisplay(display)
            end
        end

        function mode:IncludesUnit(unit)
            return enabled and (not includesUnit or includesUnit(unit))
        end

        function mode:UpdateName(plate, unit, nativeName, subtitle, x, y)
            if not outdoors then
                return nativeName
            end
            if not active or not self:IncludesUnit(unit) or IsTarget(unit) ~= false then
                self:ReleasePlate(plate)
                return nativeName
            end
            if not CanRenderName(plate.UnitFrame) then
                Yield()
                return nativeName
            end
            local text = GetPlateName(unit, nativeName)
            if not text then
                self:ReleasePlate(plate)
                return nativeName
            end

            local current = displays[plate]
            if (not current or not current.unit) and not IsNativePlateVisible(plate) then
                return nativeName
            end

            local name = RenderName(plate, unit, kind, nativeName, text, subtitle, x, y)
            if not name then
                Yield()
                return nativeName
            end
            return name
        end

        function mode:RefreshName(plate, nativeName)
            local display = displays[plate]
            if display and display.unit and display.kind == kind then
                return self:UpdateName(plate, display.unit, nativeName)
            end
            return nativeName
        end

        function mode:UpdateSettings()
            local enabledNow = isEnabled()
            if enabled == enabledNow then
                return
            end
            enabled = enabledNow
            RefreshControlSettings()
        end

        return mode
    end

    local function HookSettingsPanel()
        if not settingsPanel and SettingsPanel then
            settingsPanel = SettingsPanel
            -- Restore the actual CVars before the native settings panel is drawn.
            settingsPanel:HookScript("OnShow", function()
                if outdoors then
                    Stop()
                end
            end)
            settingsPanel:HookScript("OnHide", QueueReconcile)
        end
    end
    HookSettingsPanel()

    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_NAME_UPDATE", "FORBIDDEN_NAME_PLATE_UNIT_ADDED",
        "CVAR_UPDATE", "ADDON_LOADED",
    }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, unit)
        if transitioning then
            return
        end
        if event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
            Suspend()
        elseif event == "PLAYER_ENTERING_WORLD" then
            if IsInInstance() then
                -- A reload can leave an outdoor restoration pending until the next exit.
                Suspend(true)
            else
                outdoors = true
                waitingForReadyPlate = false
                QueueReconcile()
            end
        elseif event == "ADDON_LOADED" then
            HookSettingsPanel()
            if active and HasNameplateAddon() then
                Yield()
            end
        elseif not outdoors then
            return
        elseif event == "CVAR_UPDATE" and IsReadable(unit, "string") and watchedKeys[unit:lower()] then
            if active then
                if unit:lower() == nameOnly:lower() or HasVisibilityChanged(expectedVisibility) then
                    Yield()
                end
            else
                QueueReconcile()
            end
        elseif event == "CVAR_UPDATE" and active and IsReadable(unit, "string") and npcNameSettings[unit:lower()] then
            if unit:lower() == colourblindMode then
                for _, display in pairs(displayedUnits) do
                    display.npcTitle = nil
                end
            end
            RefreshPlates()
        elseif event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" and active then
            Suspend()
        elseif event == "NAME_PLATE_UNIT_REMOVED" and IsReadable(unit, "string") then
            pendingUnits[unit] = nil
            ReleaseDisplay(displayedUnits[unit])
            if not active then
                QueueReconcile()
            end
        elseif (active or waitingForReadyPlate) and (event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_NAME_UPDATE")
            and IsReadable(unit, "string") then
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            if event == "UNIT_NAME_UPDATE" and displays[plate] then
                displays[plate].npcTitle = nil
            end
            if active and (event == "NAME_PLATE_UNIT_ADDED" or plate) then
                local result = FilterPlate(plate)
                pendingUnits[unit] = not plate and true or nil
                if result == false then
                    Yield()
                elseif result == nil then
                    QueuePlateRetry(1)
                end
            elseif waitingForReadyPlate then
                local frame = plate and not plate:IsForbidden() and plate.UnitFrame
                if frame and not frame:IsForbidden() and frame.name and not IsForbidden(frame.name)
                    and GetPlateName(unit, frame.name) then
                    waitingForReadyPlate = false
                    QueueReconcile()
                end
            end
        elseif event == "PLAYER_REGEN_DISABLED" and active and pauseInCombat then
            Stop()
        elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            RefreshPlates()
            if not active then
                QueueReconcile()
            end
        end
    end)

    return function(enabled)
        if saved.enabled ~= enabled then
            saved.enabled = enabled
            RefreshControlSettings()
        end
    end
end
