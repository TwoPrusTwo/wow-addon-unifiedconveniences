local _, addon = ...

local targetPlateRetryDelay = .1
local destinations = {
    [9564] = "Undercity",           -- Frezza
    [12136] = "Grom'gol Base Camp", -- Snurk Bucksquick
    [9566] = "Orgrimmar",           -- Zapetta
    [3150] = "Grom'gol Base Camp",  -- Hin Denburg
    [3149] = "Orgrimmar",           -- Nez'raz
    [12137] = "Undercity",          -- Squibby Overspeck
}

local function GetDestination(guid)
    if type(guid) ~= "string" or issecretvalue(guid) then
        return
    end

    -- A creature GUID ends with the NPC ID followed by the spawn ID.
    local npcID = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    if npcID then
        return destinations[tonumber(npcID)]
    end
end

local function GetDestinationTitle(guid)
    local destination = GetDestination(guid)
    if destination then
        return "<" .. destination .. " Zeppelin Master>"
    end
end

local function ReplaceTooltipTitle(tooltip, data)
    if tooltip ~= GameTooltip or tooltip:IsForbidden() or type(data) ~= "table" or issecretvalue(data) then
        return
    end

    local title = GetDestinationTitle(data.guid)
    if not title then
        return
    end

    -- Change only the rendered title so Blizzard can rebuild the original tooltip.
    for lineIndex = 2, tooltip:NumLines() do
        local line = _G["GameTooltipTextLeft" .. lineIndex]
        if line then
            local text = line:GetText()
            if not issecretvalue(text) and (text == "Zeppelin Master" or text == "<Zeppelin Master>") then
                line:SetText(title)
                return
            end
        end
    end
end

function addon.InitializeZeppelinDestinations(db, defaultVerticalOffset)
    if type(db.zeppelinNameplateMode) ~= "table" then
        db.zeppelinNameplateMode = {}
    end
    local labelsByPlate, activeLabelsByUnit = {}, {}
    local nameplateMode

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
        if db.showZeppelinDestination then
            ReplaceTooltipTitle(tooltip, data)
        end
    end)

    local function ClearNameplateTitle(unit)
        local label = activeLabelsByUnit[unit]
        if label then
            label:Hide()
            label.unit = nil
            activeLabelsByUnit[unit] = nil
        end
    end

    local function UpdateNameplateTitle(plate)
        if not plate then
            return
        end
        local label = labelsByPlate[plate]
        if label and label.unit then
            ClearNameplateTitle(label.unit)
        end
        if plate:IsForbidden() or not plate.GetUnit then
            nameplateMode:ReleasePlate(plate)
            return
        end

        local unit = plate:GetUnit()
        if issecretvalue(unit) or type(unit) ~= "string" then
            nameplateMode:ReleasePlate(plate)
            return
        end
        ClearNameplateTitle(unit)
        local title = GetDestinationTitle(UnitGUID(unit))
        if not title then
            nameplateMode:ReleasePlate(plate)
            return
        end
        local isFriendly = UnitIsFriend("player", unit)
        local isPlayer = UnitIsPlayer(unit)
        if issecretvalue(isFriendly) or isFriendly ~= true or issecretvalue(isPlayer) or isPlayer ~= false then
            nameplateMode:ReleasePlate(plate)
            return
        end

        local scale = addon.GetUIToRegionScale(plate)
        local x, y = db.zeppelinHorizontalOffset * scale, db.zeppelinVerticalOffset * scale
        local unitFrame = plate.UnitFrame
        if unitFrame and not unitFrame:IsForbidden() and unitFrame.name then
            local name = unitFrame.name
            -- The default offset places the title just below the name on a simple plate.
            if nameplateMode:UpdateName(plate, unit, name, title, x, y - defaultVerticalOffset * scale) ~= name then
                return
            end
        else
            nameplateMode:ReleasePlate(plate)
        end

        if not label then
            label = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            labelsByPlate[plate] = label
        end
        label:ClearAllPoints()
        label:SetPoint("TOP", plate, "BOTTOM", x, y)
        label.unit = unit
        activeLabelsByUnit[unit] = label
        label:SetText(title)
        label:Show()
    end

    local function RefreshNameplates()
        for unit in pairs(activeLabelsByUnit) do
            ClearNameplateTitle(unit)
        end
        if db.showZeppelinDestination then
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                UpdateNameplateTitle(plate)
            end
        end
    end

    nameplateMode = addon.CreateSimpleNameplateMode("npc", db.zeppelinNameplateMode, function()
        return db.showZeppelinDestination
    end, RefreshNameplates, function(unit)
        return GetDestination(UnitGUID(unit)) ~= nil
    end)

    local events = CreateFrame("Frame")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    events:RegisterEvent("UNIT_NAME_UPDATE")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("UI_SCALE_CHANGED")
    events:RegisterEvent("DISPLAY_SIZE_CHANGED")
    local targetRefreshQueued = false
    local function RefreshTargetTitle(retry)
        targetRefreshQueued = false
        if not db.showZeppelinDestination then
            return
        end
        local plate = C_NamePlate.GetNamePlateForUnit("target")
        if plate then
            UpdateNameplateTitle(plate)
        elseif retry then
            local exists = UnitExists("target")
            if not issecretvalue(exists) and exists then
                targetRefreshQueued = true
                C_Timer.After(targetPlateRetryDelay, function() RefreshTargetTitle(false) end)
            end
        end
    end

    events:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            if db.showZeppelinDestination and not targetRefreshQueued then
                targetRefreshQueued = true
                -- The native frame can finish binding after the target event.
                C_Timer.After(0, function() RefreshTargetTitle(true) end)
            end
            return
        end
        if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
            if db.showZeppelinDestination then
                RefreshNameplates()
            end
            return
        end
        if issecretvalue(unit) or type(unit) ~= "string" then
            return
        end
        if event == "NAME_PLATE_UNIT_REMOVED" then
            ClearNameplateTitle(unit)
            nameplateMode:ReleaseUnit(unit)
        elseif db.showZeppelinDestination then
            UpdateNameplateTitle(C_NamePlate.GetNamePlateForUnit(unit))
        end
    end)

    local function RefreshSettings()
        nameplateMode:UpdateSettings()
        RefreshNameplates()
    end
    RefreshSettings()
    return RefreshSettings
end
