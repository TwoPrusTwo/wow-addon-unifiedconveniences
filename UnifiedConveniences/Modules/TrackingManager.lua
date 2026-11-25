local addonName, addon = ...

local off, smart = "Off", "Smart"
local treasureSpell = 2481
local treasurePrompt = "UC_ENABLE_FIND_TREASURE"
local defaultInterval = 15
local globalCooldownSpell = 61304
local trackingCooldownDelay = 1.6
local minimapButtonSize = 31
local minimapBorderSize = 54
local minimapIconSize = 18
local minimapButtonAngle = math.rad(225)
local trackingSpells = {
    [2383] = { profession = 182 }, -- Find Herbs
    [8387] = { profession = 182 },
    [2580] = { profession = 186 }, -- Find Minerals
    [8388] = { profession = 186 },
    [1494] = { creatureType = 1 }, -- Beast
    [19879] = { creatureType = 2 }, -- Dragonkin
    [19878] = { creatureType = 3 }, -- Demon
    [5500] = { creatureType = 3 },
    [19880] = { creatureType = 4 }, -- Elemental
    [19882] = { creatureType = 5 }, -- Giant
    [19884] = { creatureType = 6 }, -- Undead
    [5502] = { creatureType = 6 },
    [19883] = { creatureType = 7 }, -- Humanoid
    [5225] = { creatureType = 7 },
    [treasureSpell] = {},
}

local function IsPositiveInteger(value)
    return type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value)
end

local function GetTrackingEntries()
    local entries = {}
    for index = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(index)
        if info and not issecretvalue(info.type) and info.type == "spell"
            and not issecretvalue(info.name) and type(info.name) == "string" then
            local spellID = info.spellID
            if issecretvalue(spellID) or not IsPositiveInteger(spellID) then
                spellID = nil
            end
            entries[#entries + 1] = { index = index, key = spellID or "name:" .. info.name, info = info }
        end
    end
    return entries
end

local spellIDsByName
local function GetEntrySpellID(entry)
    if type(entry.key) == "number" then
        return entry.key
    end
    -- Some native spell entries omit their ID. Use localized names for classification.
    if not spellIDsByName then
        spellIDsByName = {}
        for spellID in pairs(trackingSpells) do
            local name = C_Spell.GetSpellName(spellID)
            if name then
                spellIDsByName[name] = spellID
            end
        end
    end
    return spellIDsByName[entry.info.name]
end

local function FindTrackingEntry(entries, key)
    for _, entry in ipairs(entries) do
        if entry.key == key or GetEntrySpellID(entry) == key then
            return entry
        end
    end
end

local function GetProfessionSkill(slot)
    if slot then
        return select(7, GetProfessionInfo(slot))
    end
end

local function GetSmartTracker(entries)
    local firstSkill, secondSkill
    if GetProfessions and GetProfessionInfo then
        local first, second = GetProfessions()
        firstSkill, secondSkill = GetProfessionSkill(first), GetProfessionSkill(second)
    end

    local firstGathering, secondProfession
    for _, entry in ipairs(entries) do
        local spell = trackingSpells[GetEntrySpellID(entry)]
        local skill = spell and spell.profession
        if skill then
            if skill == firstSkill then
                return entry
            end
            if skill == secondSkill then
                secondProfession = secondProfession or entry
            end
            firstGathering = firstGathering or entry
        end
    end
    if firstGathering then
        return secondProfession or firstGathering
    end

    local _, creatureType = UnitCreatureType("target")
    if issecretvalue(creatureType) or type(creatureType) ~= "number" then
        return
    end
    for _, entry in ipairs(entries) do
        local spell = trackingSpells[GetEntrySpellID(entry)]
        if spell and spell.creatureType == creatureType then
            return entry
        end
    end
end

local function CanCheckTracking()
    if InCombatLockdown() or UnitIsDeadOrGhost("player") then
        return false
    end
    local inCombat = UnitAffectingCombat("player")
    return not issecretvalue(inCombat) and not inCombat
end

local function IsInactive(entry)
    if entry then
        local active = entry.info.active
        return not issecretvalue(active) and active == false
    end
end

local function IsGlobalCooldownActive()
    local cooldown = C_Spell.GetSpellCooldown(globalCooldownSpell)
    if cooldown then
        local start, duration = cooldown.startTime, cooldown.duration
        if not issecretvalue(start) and not issecretvalue(duration) and type(start) == "number" and type(duration) == "number" then
            return start + duration > GetTime()
        end
    end
end

function addon.CreateTrackingMinimapButton(populateMenu, openOptions)
    local title = C_AddOns.GetAddOnMetadata(addonName, "Title")
    local buttonName = "UCTrackingMinimapButton"
    local button = CreateFrame("Button", buttonName, Minimap, "MiniMapButtonTemplate")
    button:SetSize(minimapButtonSize, minimapButtonSize)
    local function PositionButton(_, width, height)
        button:SetPoint("CENTER", Minimap, "CENTER",
            math.cos(minimapButtonAngle) * width / 2, math.sin(minimapButtonAngle) * height / 2)
    end
    PositionButton(Minimap, Minimap:GetSize())
    Minimap:HookScript("OnSizeChanged", PositionButton)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    -- MiniMapButtonTemplate moves the named icon when pressed.
    local icon = button:CreateTexture(buttonName .. "Icon", "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(minimapIconSize, minimapIconSize)
    local iconTexture = C_AddOns.GetAddOnMetadata(addonName, "IconTexture")
    icon:SetTexture(tonumber(iconTexture) or iconTexture)
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    border:SetSize(minimapBorderSize, minimapBorderSize)

    button:SetScript("OnClick", function(self, mouseButton)
        GameTooltip:Hide()
        if mouseButton == "LeftButton" then
            MenuUtil.CreateContextMenu(self, populateMenu)
        elseif mouseButton == "RightButton" then
            openOptions()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(title)
        GameTooltip_AddNormalLine(GameTooltip, "Left-click: " .. HIGHLIGHT_FONT_COLOR:WrapTextInColorCode("Quick settings."))
        GameTooltip_AddNormalLine(GameTooltip, "Right-click: " .. HIGHLIGHT_FONT_COLOR:WrapTextInColorCode("Open options."))
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
end

function addon.InitializeTrackingManager(db)
    if type(db.trackingManager) ~= "table" then
        db.trackingManager = {}
    end
    local settings = db.trackingManager
    local selection = settings.selection
    if selection ~= smart and not IsPositiveInteger(selection) and not (type(selection) == "string" and selection:match("^name:.")) then
        settings.selection = off
    end
    settings.findTreasure = settings.findTreasure == true
    if not IsPositiveInteger(settings.interval) then
        settings.interval = defaultInterval
    end

    local _, race = UnitRace("player")
    local manager = { settings = settings, isDwarf = race == "Dwarf" }
    local ticker, treasureTimer, tickerInterval

    local function WantsTreasure()
        return manager.isDwarf and settings.findTreasure
    end

    local function CheckTracking()
        if treasureTimer or not CanCheckTracking() then
            return
        end
        local entries = GetTrackingEntries()
        local selected
        if settings.selection == smart then
            selected = GetSmartTracker(entries)
        elseif settings.selection ~= off then
            selected = FindTrackingEntry(entries, settings.selection)
        end
        local treasure = WantsTreasure() and FindTrackingEntry(entries, treasureSpell)
        local missingMain = IsInactive(selected)
        local missingTreasure = IsInactive(treasure)
        if not (missingMain or missingTreasure) or IsGlobalCooldownActive() then
            return
        end
        if missingMain then
            C_Minimap.SetTracking(selected.index, true)
            if missingTreasure and treasure ~= selected then
                treasureTimer = C_Timer.NewTimer(trackingCooldownDelay, function()
                    treasureTimer = nil
                    if WantsTreasure() and CanCheckTracking() and not IsGlobalCooldownActive() then
                        local current = FindTrackingEntry(GetTrackingEntries(), treasureSpell)
                        if IsInactive(current) then
                            C_Minimap.SetTracking(current.index, true)
                        end
                    end
                end)
            end
        else
            C_Minimap.SetTracking(treasure.index, true)
        end
    end

    local function UpdateSchedule(checkNow)
        local interval = (settings.selection ~= off or WantsTreasure()) and settings.interval or nil
        if treasureTimer and (checkNow or not interval) then
            treasureTimer:Cancel()
            treasureTimer = nil
        end
        if ticker and (checkNow or tickerInterval ~= interval) then
            ticker:Cancel()
            ticker = nil
        end
        if interval and not ticker then
            tickerInterval = interval
            ticker = C_Timer.NewTicker(interval, CheckTracking)
        end
        if checkNow and interval then
            CheckTracking()
        end
    end

    local function RefreshOptions()
        if manager.RefreshOptions then
            manager.RefreshOptions()
        end
    end

    function manager.SetTreasure(enabled)
        if manager.isDwarf and settings.findTreasure ~= enabled then
            settings.findTreasure = enabled
            UpdateSchedule(true)
            RefreshOptions()
        end
    end

    function manager.SetInterval(value)
        if IsPositiveInteger(value) and settings.interval ~= value then
            settings.interval = value
            UpdateSchedule()
        end
    end

    function manager.Reset()
        settings.selection = off
        settings.findTreasure = false
        settings.interval = defaultInterval
        StaticPopup_Hide(treasurePrompt)
        UpdateSchedule()
    end

    StaticPopupDialogs[treasurePrompt] = {
        text = "Enable Find Treasure?",
        button1 = ACCEPT,
        button2 = DECLINE,
        OnAccept = function()
            if settings.selection == smart then
                manager.SetTreasure(true)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    local function SetSelection(value)
        if settings.selection == value then
            return
        end
        settings.selection = value
        if value == smart and manager.isDwarf and not settings.findTreasure then
            StaticPopup_Show(treasurePrompt)
        else
            StaticPopup_Hide(treasurePrompt)
        end
        UpdateSchedule(true)
        RefreshOptions()
    end

    local function IsSelected(value)
        return settings.selection == value
    end

    function manager.PopulateMenu(_, menu)
        menu:CreateRadio(off, IsSelected, SetSelection, off)
        menu:CreateRadio(smart, IsSelected, SetSelection, smart)
        for _, entry in ipairs(GetTrackingEntries()) do
            menu:CreateRadio(entry.info.name, IsSelected, SetSelection, entry.key)
        end
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("MINIMAP_UPDATE_TRACKING")
    events:SetScript("OnEvent", RefreshOptions)
    UpdateSchedule()
    return manager
end
