local _, addon = ...

local styles = {
    player = {
        isPlayer = true,
        visibilityCVar = "nameplateShowFriendlyPlayers",
        nameOnlyCVar = "nameplateShowOnlyNameForFriendlyPlayerUnits",
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

local function HasFriendlyPlates(isPlayer)
    local playerGUID = isPlayer and GetReadableGUID("player")
    for _, plate in pairs(C_NamePlate.GetNamePlates()) do
        if plate:IsForbidden() or not plate.GetUnit then
            return true
        end
        local unit = plate:GetUnit()
        if not IsReadable(unit, "string") then
            return true
        end
        local player = UnitIsPlayer(unit)
        if not IsReadable(player, "boolean") then
            return true
        end
        if player == isPlayer then
            local friendly = UnitIsFriend("player", unit)
            if not IsReadable(friendly, "boolean") then
                return true
            end
            if friendly and (not playerGUID or GetReadableGUID(unit) ~= playerGUID) then
                return true
            end
        end
    end
    return false
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

function addon.CreateSimpleNameplateMode(kind, saved, isEnabled, refreshPlates)
    local mode = {}
    local style = styles[kind]
    local visibilityCVar, nameOnlyCVar = style.visibilityCVar, style.nameOnlyCVar
    local managedCVars = { visibilityCVar, nameOnlyCVar }
    local managedKeys = {}
    for _, name in ipairs(managedCVars) do
        managedKeys[name:lower()] = true
    end
    local displays, displayedUnits = {}, {}
    local active, ready, stopping, writing, queued = false, false, false, false, false
    local waitingForPlates, takeoverFailed = false, false
    local enabled = isEnabled()

    local function ReleaseDisplay(display)
        if not display.unit then
            return
        end
        if not IsForbidden(display.hiddenRegion) then
            local alpha = display.hiddenRegion:GetAlpha()
            if IsReadable(alpha, "number") and alpha == 0 then
                display.hiddenRegion:SetAlpha(display.originalAlpha)
            end
        end
        display.name:Hide()
        if display.subtitle then
            display.subtitle:Hide()
        end
        displayedUnits[display.unit] = nil
        display.unit, display.guid, display.native, display.hiddenRegion = nil, nil, nil, nil
        display.originalAlpha = nil
    end

    local function ReleaseDisplays()
        for _, display in pairs(displayedUnits) do
            ReleaseDisplay(display)
        end
    end

    function mode:ReleaseUnit(unit)
        local display = displayedUnits[unit]
        if display then
            ReleaseDisplay(display)
        end
    end

    function mode:ReleasePlate(plate)
        local display = displays[plate]
        if display then
            ReleaseDisplay(display)
        end
    end

    function mode:UpdateName(plate, unit, nativeName, subtitle, x, y)
        if not active then
            return nativeName
        end
        local guid = GetReadableGUID(unit)
        local unitFrame = plate.UnitFrame
        local widgetsOnly = unitFrame.widgetsOnlyMode
        if not guid or IsForbidden(nativeName) or (not style.isPlayer and (issecretvalue(widgetsOnly) or widgetsOnly)) then
            self:ReleasePlate(plate)
            return nativeName
        end

        -- Forever's native name-only setting applies to players. Hide the NPC UnitFrame
        -- with alpha so the nameplate remains available as an anchor.
        local hiddenRegion = style.isPlayer and nativeName or unitFrame
        local display = displays[plate]
        if display and display.unit and (display.unit ~= unit or display.guid ~= guid or display.native ~= nativeName) then
            ReleaseDisplay(display)
        end
        local previous = displayedUnits[unit]
        if previous and previous ~= display then
            ReleaseDisplay(previous)
        end

        local text = nativeName:GetText()
        if not IsReadable(text, "string") or text == "" then
            text = GetUnitName(unit, false)
        end
        local alpha = hiddenRegion:GetAlpha()
        if not IsReadable(text, "string") or text == "" or not IsReadable(alpha, "number") then
            self:ReleasePlate(plate)
            return nativeName
        end
        -- Leave name regions being hidden or restyled by another addon alone.
        if (display and display.unit and alpha ~= 0) or ((not display or not display.unit) and alpha == 0) then
            self:ReleasePlate(plate)
            if display then
                display.externalGUID = guid
            end
            return nativeName
        end
        if display and display.externalGUID == guid then
            return nativeName
        end

        if not display then
            display = { name = plate:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlate") }
            displays[plate] = display
        end
        if not display.unit then
            display.unit, display.guid, display.native, display.hiddenRegion = unit, guid, nativeName, hiddenRegion
            display.originalAlpha = alpha
            display.externalGUID = nil
            displayedUnits[unit] = display
            display.name:ClearAllPoints()
            display.name:SetPoint("CENTER", nativeName, "CENTER")
            hiddenRegion:SetAlpha(0)
        end

        local font, size, flags = nativeName:GetFont()
        if not IsReadable(font, "string") or not IsReadable(size, "number") then
            font, size, flags = display.name:GetFont()
        end
        local hasFont = IsReadable(font, "string") and IsReadable(size, "number")
        if hasFont then
            flags = WithoutOutline(flags)
            display.name:SetFont(font, size, flags)
        end
        local r, g, b = GetOverheadColour(unit, style)
        display.name:SetText(text)
        display.name:SetTextColor(r, g, b)
        display.name:Show()

        if style.isPlayer then
            subtitle = GetGuildTitle(unit)
        end
        if subtitle then
            if not display.subtitle then
                display.subtitle = plate:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlate")
            end
            x, y = x or 0, y or 0
            if display.subtitleX ~= x or display.subtitleY ~= y then
                display.subtitleX, display.subtitleY = x, y
                display.subtitle:ClearAllPoints()
                display.subtitle:SetPoint("TOP", display.name, "BOTTOM", x, y)
            end
            if hasFont then
                display.subtitle:SetFont(font, size, flags)
            end
            display.subtitle:SetText(subtitle)
            display.subtitle:SetTextColor(r, g, b)
            display.subtitle:Show()
        elseif display.subtitle then
            display.subtitle:Hide()
        end
        return display.name
    end

    function mode:RefreshName(plate, nativeName)
        local display = displays[plate]
        if display and display.unit then
            return self:UpdateName(plate, display.unit, nativeName)
        end
        return nativeName
    end

    local function WriteSetting(name, value)
        if not GetWritableSetting(name) then
            return false
        end
        writing = true
        pcall(C_CVar.SetCVar, name, value)
        writing = false
        return C_CVar.GetCVar(name) == value
    end

    local function RestoreSettings()
        local pending = saved.nameplateRestore
        if type(pending) ~= "table" then
            saved.nameplateRestore = nil
            return true
        end
        local playerGUID = GetReadableGUID("player")
        for _, name in ipairs(managedCVars) do
            local entry = pending[name]
            if type(entry) == "table" and entry.value == "0" then
                if entry.player and entry.player ~= playerGUID then
                    return false
                end
                local current = C_CVar.GetCVar(name)
                if current ~= "0" and (current ~= "1" or not WriteSetting(name, entry.value)) then
                    return false
                end
            end
            pending[name] = nil
        end
        saved.nameplateRestore = nil
        return true
    end

    local function StillOwnsSettings()
        return C_CVar.GetCVar(visibilityCVar) == "1" and (not nameOnlyCVar or C_CVar.GetCVar(nameOnlyCVar) == "1")
    end

    local function Stop(restore)
        local wasActive = active
        if wasActive and not StillOwnsSettings() then
            restore = false
        end
        active = false
        ReleaseDisplays()
        if wasActive then
            for _, display in pairs(displays) do
                display.externalGUID = nil
            end
        end
        if restore then
            RestoreSettings()
        else
            saved.nameplateRestore = nil
            saved.yieldFriendlyNameplates = true
        end
        if wasActive and not stopping then
            refreshPlates()
        end
    end

    local function Reconcile()
        if stopping or not ready then
            return
        end
        local inInstance = IsInInstance()
        if active then
            if not isEnabled() or inInstance then
                Stop(true)
            elseif not StillOwnsSettings() then
                Stop(false)
            end
            return
        end
        if not RestoreSettings() or not isEnabled() or saved.yieldFriendlyNameplates
            or takeoverFailed or inInstance or InCombatLockdown() then
            return
        end

        local visibility, visibilityPlayer = GetWritableSetting(visibilityCVar)
        local nameOnly, nameOnlyPlayer
        if nameOnlyCVar then
            nameOnly, nameOnlyPlayer = GetWritableSetting(nameOnlyCVar)
        end
        if visibility ~= "0" or (nameOnlyCVar and not nameOnly) then
            waitingForPlates = false
            return
        end
        waitingForPlates = HasFriendlyPlates(style.isPlayer)
        if waitingForPlates then
            return
        end

        local pending = {}
        saved.nameplateRestore = pending
        if nameOnly == "0" then
            pending[nameOnlyCVar] = { value = nameOnly, player = nameOnlyPlayer }
            if not WriteSetting(nameOnlyCVar, "1") then
                takeoverFailed = true
                RestoreSettings()
                return
            end
        end
        pending[visibilityCVar] = { value = visibility, player = visibilityPlayer }
        if not WriteSetting(visibilityCVar, "1") then
            takeoverFailed = true
            RestoreSettings()
            return
        end
        active = true
        if StillOwnsSettings() then
            refreshPlates()
        else
            Stop(false)
        end
    end

    local function QueueReconcile()
        if ready and not queued and not stopping then
            queued = true
            C_Timer.After(0, function()
                queued = false
                Reconcile()
            end)
        end
    end

    function mode:UpdateSettings()
        local enabledNow = isEnabled()
        if enabled == enabledNow then
            return
        end
        enabled = enabledNow
        saved.yieldFriendlyNameplates = nil
        takeoverFailed = false
        if enabled then
            QueueReconcile()
        else
            Stop(true)
        end
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_LEAVING_WORLD")
    events:RegisterEvent("PLAYER_LOGOUT")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    events:RegisterEvent("CVAR_UPDATE")
    events:SetScript("OnEvent", function(_, event, name)
        if event == "PLAYER_LOGOUT" then
            stopping = true
            Stop(true)
        elseif event == "PLAYER_LEAVING_WORLD" then
            ready = false
            Stop(true)
        elseif event == "PLAYER_ENTERING_WORLD" then
            ready = true
            takeoverFailed = false
            QueueReconcile()
        elseif event == "PLAYER_REGEN_ENABLED" or (event == "NAME_PLATE_UNIT_REMOVED" and waitingForPlates) then
            QueueReconcile()
        elseif event == "CVAR_UPDATE" and not writing and IsReadable(name, "string") then
            if managedKeys[name:lower()] then
                if active then
                    Reconcile()
                else
                    QueueReconcile()
                end
            end
        end
    end)

    return mode
end
