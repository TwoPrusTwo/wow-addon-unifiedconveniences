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

local labelsByPlate = {}
local activeLabelsByUnit = {}

local function ClearNameplateTitle(unit)
    local label = activeLabelsByUnit[unit]
    if label then
        label:Hide()
        label.unit = nil
        activeLabelsByUnit[unit] = nil
    end
end

local function UpdateNameplateTitle(plate, unit, horizontalOffset, verticalOffset)
    ClearNameplateTitle(unit)
    if not plate or plate:IsForbidden() then
        return
    end

    local label = labelsByPlate[plate]
    if label and label.unit then
        ClearNameplateTitle(label.unit)
    end

    local title = GetDestinationTitle(UnitGUID(unit))
    if not title then
        return
    end
    local isFriendly = UnitIsFriend("player", unit)
    if issecretvalue(isFriendly) or not isFriendly then
        return
    end

    if not label then
        label = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelsByPlate[plate] = label
    end
    label:ClearAllPoints()
    label:SetPoint("TOP", plate, "BOTTOM", horizontalOffset, verticalOffset)
    label.unit = unit
    activeLabelsByUnit[unit] = label
    label:SetText(title)
    label:Show()
end

function addon.InitializeZeppelinDestinations(db)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
        if db.showZeppelinDestination then
            ReplaceTooltipTitle(tooltip, data)
        end
    end)

    local function RefreshNameplates()
        for unit in pairs(activeLabelsByUnit) do
            ClearNameplateTitle(unit)
        end
        if db.showZeppelinDestination then
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                if not plate:IsForbidden() and plate.GetUnit then
                    local unit = plate:GetUnit()
                    if type(unit) == "string" and not issecretvalue(unit) then
                        UpdateNameplateTitle(plate, unit, db.zeppelinHorizontalOffset, db.zeppelinVerticalOffset)
                    end
                end
            end
        end
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    events:SetScript("OnEvent", function(_, event, unit)
        if type(unit) ~= "string" or issecretvalue(unit) then
            return
        end
        if event == "NAME_PLATE_UNIT_REMOVED" then
            ClearNameplateTitle(unit)
        elseif db.showZeppelinDestination then
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            UpdateNameplateTitle(plate, unit, db.zeppelinHorizontalOffset, db.zeppelinVerticalOffset)
        end
    end)

    RefreshNameplates()
    return RefreshNameplates
end
