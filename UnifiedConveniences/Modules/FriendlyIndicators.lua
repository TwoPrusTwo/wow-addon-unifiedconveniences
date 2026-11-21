local addonName, addon = ...

local indicatorTexture = "Interface\\AddOns\\" .. addonName .. "\\Textures\\FriendlyIndicators.tga"
-- Cells are ordered left to right in the texture atlas.
local categories = {
    { key = "party", label = "Party", cell = 1 },
    { key = "favourite", label = "Favourite", cell = 2 },
    { key = "friends", label = "Friends", cell = 3 },
    { key = "guild", label = "Guild", cell = 4 },
}
addon.friendlyIndicatorCategories = categories

function addon.SetFriendlyIndicatorTexture(texture, category)
    local cell = category.cell
    texture:SetTexture(indicatorTexture)
    texture:SetTexCoord((cell - 1) / #categories, cell / #categories, 0, 1)
end

local friendEvents = {
    FRIENDLIST_UPDATE = true,
    BN_FRIEND_LIST_SIZE_CHANGED = true,
    BN_FRIEND_INFO_CHANGED = true,
    BN_CONNECTED = true,
    BN_DISCONNECTED = true,
}

local chatColourFallbacks = {
    GUILD = CreateColorFromHexString("FF40FF40"),
    PARTY = CreateColorFromHexString("FFAAAAFF"),
    PARTY_LEADER = CreateColorFromHexString("FF76C8FF"),
}
local defaultChatTypes = {
    guild = "GUILD",
    party = "PARTY",
    partyLeader = "PARTY_LEADER",
}
local fixedDefaultColours = {
    friends = CreateColorFromHexString("FF727EFF"),
    favourite = CreateColorFromHexString("FFFFFF00"),
}

local function IsReadable(value, valueType)
    return not issecretvalue(value) and type(value) == valueType
end

local function IsTrue(value)
    return not issecretvalue(value) and value == true
end

function addon.IsFriendlyIndicatorChatColour(chatType)
    return IsReadable(chatType, "string") and chatColourFallbacks[chatType:upper()] ~= nil
end

local function GetDefaultColour(key)
    local chatType = defaultChatTypes[key]
    if not chatType then
        return fixedDefaultColours[key]
    end
    local colour = ChatTypeInfo and ChatTypeInfo[chatType]
    if IsReadable(colour, "table") and IsReadable(colour.r, "number")
        and IsReadable(colour.g, "number") and IsReadable(colour.b, "number") then
        return colour
    end
    return chatColourFallbacks[chatType]
end

local function GetPlayerGUID(unit)
    local guid = UnitGUID(unit)
    if IsReadable(guid, "string") and guid:match("^Player%-") then
        return guid
    end
end

local function GetPartyMembers()
    local members = {}
    local inRaid = IsInRaid()
    if not IsReadable(inRaid, "boolean") then
        return members
    end
    if inRaid then
        local playerIndex = UnitInRaid("player")
        if not IsReadable(playerIndex, "number") then
            return members
        end

        local _, _, playerSubgroup = GetRaidRosterInfo(playerIndex)
        if not IsReadable(playerSubgroup, "number") then
            return members
        end

        local memberCount = GetNumGroupMembers()
        if not IsReadable(memberCount, "number") then
            return members
        end
        for index = 1, memberCount do
            local _, _, subgroup = GetRaidRosterInfo(index)
            if index ~= playerIndex and IsReadable(subgroup, "number") and subgroup == playerSubgroup then
                local unit = "raid" .. index
                local guid = GetPlayerGUID(unit)
                if guid then
                    members[guid] = IsTrue(UnitIsGroupLeader(unit)) and "partyLeader" or "party"
                end
            end
        end
    else
        local memberCount = GetNumSubgroupMembers()
        if not IsReadable(memberCount, "number") then
            return members
        end
        for index = 1, memberCount do
            local unit = "party" .. index
            local guid = GetPlayerGUID(unit)
            if guid then
                members[guid] = IsTrue(UnitIsGroupLeader(unit)) and "partyLeader" or "party"
            end
        end
    end
    return members
end

local function GetBattleNetFriends()
    local friends, favourites = {}, {}
    local friendCount = BNGetNumFriends()
    if not IsReadable(friendCount, "number") then
        return friends, favourites
    end
    for index = 1, friendCount do
        local account = C_BattleNet.GetFriendAccountInfo(index)
        if IsReadable(account, "table") then
            local favourite = IsTrue(account.isFavorite)
            local numGames = C_BattleNet.GetFriendNumGameAccounts(index)
            if IsReadable(numGames, "number") then
                for gameIndex = 1, numGames do
                    local game = C_BattleNet.GetFriendGameAccountInfo(index, gameIndex)
                    if IsReadable(game, "table") and IsTrue(game.isOnline) then
                        local guid = game.playerGuid
                        if IsReadable(guid, "string") and guid:match("^Player%-") then
                            friends[guid] = true
                            if favourite then
                                favourites[guid] = true
                            end
                        end
                    end
                end
            end
        end
    end
    return friends, favourites
end

local function GetNameColour(name)
    local r, g, b = name:GetVertexColor()
    if IsReadable(r, "number") and IsReadable(g, "number") and IsReadable(b, "number") then
        return r, g, b
    end
    return WHITE_FONT_COLOR:GetRGB()
end

local function GetClassColour(unit)
    local _, class = UnitClass(unit)
    if IsReadable(class, "string") then
        return RAID_CLASS_COLORS[class]
    end
end

local function GetConfiguredColour(style, previewColour, unit, defaultKey)
    if previewColour then
        return previewColour
    end
    if style.colourMode == "Custom" then
        return style.colour
    end
    if style.colourMode == "Class" then
        return GetClassColour(unit)
    end
    return GetDefaultColour(defaultKey)
end

function addon.GetFriendlyIndicatorPreviewColour(key, style, previewColour)
    return GetConfiguredColour(style, previewColour, "player", key) or WHITE_FONT_COLOR
end

function addon.InitializeFriendlyIndicators(settings, preview)
    local partyMembers, battleNetFriends, favourites = {}, {}, {}
    local markersByPlate, activeByUnit = {}, {}
    local wasEnabled = false
    local nameplateMode

    local function GetCategory(unit, guid)
        if settings.party.enabled and partyMembers[guid] then
            return categories[1]
        end
        if settings.favourite.enabled and favourites[guid] then
            return categories[2]
        end
        if settings.friends.enabled and (battleNetFriends[guid] or IsTrue(C_FriendList.IsFriend(guid))) then
            return categories[3]
        end
        if settings.guild.enabled and IsTrue(UnitIsInMyGuild(unit)) then
            return categories[4]
        end
    end

    local function HideMarker(record)
        if record.unit then
            activeByUnit[record.unit] = nil
            record.unit = nil
            record.marker:Hide()
        end
    end

    local function UpdateAppearance(record, name)
        local style = settings[record.category.key]
        local previewColour = preview.key == record.category.key and preview.colour
        local colour = GetConfiguredColour(style, previewColour, record.unit, record.defaultColourKey)
        if colour then
            record.marker:SetVertexColor(colour.r, colour.g, colour.b)
        else
            record.marker:SetVertexColor(GetNameColour(name))
        end
        record.marker:SetShown(record.anchor:IsShown())
    end

    local function AnchorMarker(record, anchor)
        record.anchor = anchor
        record.marker:ClearAllPoints()
        record.marker:SetPoint("BOTTOM", anchor, "TOP", settings.horizontalOffset, settings.verticalOffset)
    end

    local function UpdatePlate(plate, unit)
        local readableUnit = IsReadable(unit, "string")
        local oldRecord = readableUnit and activeByUnit[unit]
        if oldRecord then
            HideMarker(oldRecord)
        end
        if not plate then
            return
        end
        if plate:IsForbidden() then
            nameplateMode:ReleasePlate(plate)
            return
        end

        local record = markersByPlate[plate]
        if record then
            HideMarker(record)
        end
        local unitFrame = plate.UnitFrame
        if not readableUnit or not unitFrame or unitFrame:IsForbidden() or not unitFrame.name then
            nameplateMode:ReleasePlate(plate)
            return
        end

        local guid = GetPlayerGUID(unit)
        if not guid or not IsTrue(UnitIsFriend("player", unit)) or guid == GetPlayerGUID("player") then
            nameplateMode:ReleasePlate(plate)
            return
        end
        local name = unitFrame.name
        local anchor = nameplateMode:UpdateName(plate, unit, name)
        local category = GetCategory(unit, guid)
        if not category then
            return
        end

        if not record then
            local marker = plate:CreateTexture(nil, "OVERLAY")
            marker:SetIgnoreParentAlpha(true)
            record = { marker = marker }
            markersByPlate[plate] = record
        end
        if record.category ~= category then
            addon.SetFriendlyIndicatorTexture(record.marker, category)
        end
        record.unit = unit
        record.category = category
        record.defaultColourKey = category.key == "party" and partyMembers[guid] or category.key
        activeByUnit[unit] = record

        local marker = record.marker
        AnchorMarker(record, anchor)
        local size = settings.size / plate:GetEffectiveScale() * PixelUtil.GetPixelToUIUnitFactor()
        if size > 0 and size < math.huge then
            marker:SetSize(size, size)
        end
        UpdateAppearance(record, name)
    end

    local function RefreshMarkers()
        for _, record in pairs(activeByUnit) do
            HideMarker(record)
        end
        if settings.enabled then
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                if not plate:IsForbidden() and plate.GetUnit then
                    UpdatePlate(plate, plate:GetUnit())
                else
                    nameplateMode:ReleasePlate(plate)
                end
            end
        end
    end

    local function RefreshSettings()
        if settings.enabled and not wasEnabled then
            partyMembers = GetPartyMembers()
            battleNetFriends, favourites = GetBattleNetFriends()
        end
        wasEnabled = settings.enabled
        nameplateMode:UpdateSettings()
        RefreshMarkers()
    end

    local events = CreateFrame("Frame")
    for event in pairs(friendEvents) do
        events:RegisterEvent(event)
    end
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("PARTY_LEADER_CHANGED")
    events:RegisterEvent("PLAYER_GUILD_UPDATE")
    events:RegisterEvent("GUILD_ROSTER_UPDATE")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    events:RegisterEvent("UNIT_NAME_UPDATE")
    events:RegisterEvent("UI_SCALE_CHANGED")
    events:RegisterEvent("DISPLAY_SIZE_CHANGED")
    events:SetScript("OnEvent", function(_, event, unit)
        if not settings.enabled then
            return
        end
        if event == "NAME_PLATE_UNIT_REMOVED" then
            if IsReadable(unit, "string") then
                local record = activeByUnit[unit]
                if record then
                    HideMarker(record)
                end
                nameplateMode:ReleaseUnit(unit)
            end
            return
        end
        if event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_NAME_UPDATE" then
            if IsReadable(unit, "string") then
                local plate = C_NamePlate.GetNamePlateForUnit(unit)
                if plate and not plate:IsForbidden() then
                    UpdatePlate(plate, plate:GetUnit())
                end
            end
            return
        end
        if event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            partyMembers = GetPartyMembers()
        end
        if friendEvents[event] or event == "PLAYER_ENTERING_WORLD" then
            battleNetFriends, favourites = GetBattleNetFriends()
        end
        RefreshMarkers()
    end)

    hooksecurefunc("CompactUnitFrame_UpdateName", function(unitFrame)
        if settings.enabled and not unitFrame:IsForbidden() then
            local plate = unitFrame:GetParent()
            if plate and not plate:IsForbidden() and plate.UnitFrame == unitFrame and unitFrame.name then
                local name = unitFrame.name
                local anchor = nameplateMode:RefreshName(plate, name)
                local record = markersByPlate[plate]
                if record and record.unit then
                    if record.anchor ~= anchor then
                        AnchorMarker(record, anchor)
                    end
                    UpdateAppearance(record, name)
                end
            end
        end
    end)

    nameplateMode = addon.CreateSimpleNameplateMode("player", settings, function()
        return settings.enabled
    end, RefreshMarkers)
    RefreshSettings()
    return RefreshSettings
end
