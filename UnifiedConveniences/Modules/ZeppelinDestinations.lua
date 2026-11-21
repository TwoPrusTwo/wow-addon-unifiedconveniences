local _, addon = ...

local destinations = {
    [9564] = "Undercity",           -- Frezza
    [12136] = "Grom'gol Base Camp", -- Snurk Bucksquick
    [9566] = "Orgrimmar",           -- Zapetta
    [3150] = "Grom'gol Base Camp",  -- Hin Denburg
    [3149] = "Orgrimmar",           -- Nez'raz
    [12137] = "Undercity",          -- Squibby Overspeck
}

local function GetDestinationTitle(guid)
    if type(guid) ~= "string" or issecretvalue(guid) then
        return
    end

    -- A creature GUID ends with the NPC ID followed by the spawn ID.
    local npcID = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    if npcID then
        local destination = destinations[tonumber(npcID)]
        if destination then
            return "<" .. destination .. " Zeppelin Master>"
        end
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
        local isFriendly = title and UnitIsFriend("player", unit)
        if not title or issecretvalue(isFriendly) or isFriendly ~= true then
            nameplateMode:ReleasePlate(plate)
            return
        end

        local x, y = db.zeppelinHorizontalOffset, db.zeppelinVerticalOffset
        local unitFrame = plate.UnitFrame
        if unitFrame and not unitFrame:IsForbidden() and unitFrame.name then
            local name = unitFrame.name
            -- The default offset places the title just below the name on a simple plate.
            if nameplateMode:UpdateName(plate, unit, name, title, x, y - defaultVerticalOffset) ~= name then
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
    end, RefreshNameplates)

    local events = CreateFrame("Frame")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    events:RegisterEvent("UNIT_NAME_UPDATE")
    events:SetScript("OnEvent", function(_, event, unit)
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
