local _, addon = ...

local targetPlateRetryDelay = .1
local neutralReaction = 4
local zeppelinMaster = "Zeppelin Master"
local shipmaster = "Shipmaster"
local destinations = {
    [9564] = { destination = "Undercity", title = zeppelinMaster },           -- Frezza
    [12136] = { destination = "Grom'gol Base Camp", title = zeppelinMaster }, -- Snurk Bucksquick
    [9566] = { destination = "Orgrimmar", title = zeppelinMaster },           -- Zapetta
    [3150] = { destination = "Grom'gol Base Camp", title = zeppelinMaster },  -- Hin Denburg
    [3149] = { destination = "Orgrimmar", title = zeppelinMaster },           -- Nez'raz
    [12137] = { destination = "Undercity", title = zeppelinMaster },          -- Squibby Overspeck

    [9558] = { destination = "Booty Bay", title = shipmaster },               -- Grimble
    [9559] = { destination = "Ratchet", title = shipmaster },                 -- Grizzlowe
    [12658] = { destination = "Theramore Isle" },                            -- Adam Lind
    [12716] = { destination = "Menethil Harbor" },                           -- Decedra Willham
    [12657] = { destination = "Southshore" },                                 -- Don Pompa
    [276316] = { destination = "Auberdine", title = "Dockmaster" },           -- Raul Sweete
    [260405] = { destination = "Powderfuse Port" },                           -- Wharfmaster Steamfizzle
    [259961] = { destination = "Steamwheedle Port" },                         -- Wharfmaster Whizzbuzz

    [275269] = { destination = "Dalaran" },                                   -- High Order Dockmaster
    [275270] = { destination = "Skywatcher Plateau, Mulgore" },               -- Windshapers Dockmaster
    [11800] = { destination = "Rut'theran Village" },                         -- Silva Fil'naveth
    [11798] = { destination = "Thunder Bluff" },                             -- Bunthen Plainswind
    [8395] = { destination = "Archmage Xylem's tower" },                      -- Sanath Lim-yo
}

local function GetRoute(guid)
    if issecretvalue(guid) or type(guid) ~= "string" then
        return
    end

    -- A creature GUID ends with the NPC ID followed by the spawn ID.
    local npcID = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    if npcID then
        return destinations[tonumber(npcID)]
    end
end

local function GetDestinationLabel(route)
    return "<To " .. route.destination .. ">"
end

local function GetDestinationTitle(route)
    if route.title then
        return "<" .. route.destination .. " " .. route.title .. ">"
    end
    return GetDestinationLabel(route)
end

local function UpdateTooltip(tooltip, data)
    if tooltip ~= GameTooltip or tooltip:IsForbidden() or issecretvalue(data) or type(data) ~= "table" then
        return
    end

    local route = GetRoute(data.guid)
    if not route then
        return
    end

    local label = GetDestinationLabel(route)
    local originalTitle = route.title and "<" .. route.title .. ">"
    local title = GetDestinationTitle(route)
    for lineIndex = 2, tooltip:NumLines() do
        local line = _G["GameTooltipTextLeft" .. lineIndex]
        if line and (not line.IsForbidden or not line:IsForbidden()) then
            local text = line:GetText()
            if not issecretvalue(text) then
                if text == label or text == title then
                    return
                end
                if route.title and (text == route.title or text == originalTitle) then
                    line:SetText(title)
                    return
                end
            end
        end
    end

    GameTooltip_AddNormalLine(tooltip, label)
end

function addon.InitializeTransportDestinations(db, defaultVerticalOffset)
    local labelsByPlate, activeLabelsByUnit = {}, {}
    local nameplateMode

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
        if db.showTransportDestinations then
            UpdateTooltip(tooltip, data)
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

        local visible = plate:IsVisible()
        if issecretvalue(visible) or visible ~= true then
            nameplateMode:ReleasePlate(plate)
            return
        end
        local unit = plate:GetUnit()
        if issecretvalue(unit) or type(unit) ~= "string" then
            nameplateMode:ReleasePlate(plate)
            return
        end
        ClearNameplateTitle(unit)
        local route = GetRoute(UnitGUID(unit))
        if not route then
            nameplateMode:ReleasePlate(plate)
            return
        end
        local isFriendly = UnitIsFriend("player", unit)
        local isPlayer = UnitIsPlayer(unit)
        if issecretvalue(isFriendly) or type(isFriendly) ~= "boolean" or issecretvalue(isPlayer) or isPlayer ~= false then
            nameplateMode:ReleasePlate(plate)
            return
        end
        if not isFriendly then
            local reaction = UnitReaction("player", unit)
            if issecretvalue(reaction) or reaction ~= neutralReaction then
                nameplateMode:ReleasePlate(plate)
                return
            end
        end

        local unitFrame = plate.UnitFrame
        if not unitFrame or unitFrame:IsForbidden() then
            nameplateMode:ReleasePlate(plate)
            return
        end
        local name = unitFrame.name
        if name and name.IsForbidden and name:IsForbidden() then
            nameplateMode:ReleasePlate(plate)
            return
        end
        local title = GetDestinationTitle(route)
        local scale = addon.GetUIToRegionScale(plate)
        local x, y = db.transportHorizontalOffset * scale, db.transportVerticalOffset * scale
        if isFriendly and name then
            -- The default offset places the title just below the name on a simple plate.
            if nameplateMode:UpdateName(plate, unit, name, title, x, y - defaultVerticalOffset * scale) ~= name then
                return
            end
        else
            nameplateMode:ReleasePlate(plate)
        end
        -- Simple Nameplates can hide an NPC's native frame while its outer plate remains visible.
        local frameVisible, frameAlpha = unitFrame:IsVisible(), unitFrame:GetAlpha()
        if issecretvalue(frameVisible) or frameVisible ~= true
            or issecretvalue(frameAlpha) or type(frameAlpha) ~= "number" or frameAlpha <= 0 then
            return
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
        if db.showTransportDestinations then
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                UpdateNameplateTitle(plate)
            end
        end
    end

    nameplateMode = addon.CreateSimpleNameplateMode("npc", db.transportNameplateMode, function()
        return db.showTransportDestinations
    end, RefreshNameplates, function(unit)
        return GetRoute(UnitGUID(unit)) ~= nil
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
        if not db.showTransportDestinations then
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
            if db.showTransportDestinations and not targetRefreshQueued then
                targetRefreshQueued = true
                -- The native frame can finish binding after the target event.
                C_Timer.After(0, function() RefreshTargetTitle(true) end)
            end
            return
        end
        if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
            if db.showTransportDestinations then
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
        elseif db.showTransportDestinations then
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
