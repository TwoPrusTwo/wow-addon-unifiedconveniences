local _, addon = ...

local groups = {
    { title = "Collections and assets",
        { "appearanceSources", "Appearance Sources" },
        { "appearances", "Appearances" },
        { "pets", "Companion Pet Species" },
        { "icons", "Icon File IDs" },
        { "mounts", "Mounts", true },
        { "outfits", "Outfits" },
        { "toys", "Toys" },
    },
    { title = "Common",
        { "currencies", "Currencies" },
        { "items", "Items", true },
        { "npcs", "NPCs", true },
        { "quests", "Quests" },
        { "spells", "Spells", true },
        { "objects", "World Objects" },
    },
    { title = "Equipment",
        { "bagSlots", "Bag Slot IDs" },
        { "enchants", "Enchants" },
        { "equipmentSets", "Equipment Sets" },
        { "equipmentSlots", "Equipment Slot IDs" },
        { "gems", "Gems" },
        { "bonuses", "Item Bonuses" },
        { "expansions", "Item Expansions" },
        { "itemSets", "Item Sets" },
    },
    { title = "Map",
        { "maps", "Maps" },
        { "pointsOfInterest", "Points of Interest" },
        { "vignettes", "Vignettes" },
    },
    { title = "Progression and actions",
        { "criteria", "Achievement Criteria" },
        { "achievements", "Achievements and Legacy Challenges" },
        { "actionSlots", "Action Bar Slot IDs" },
        { "factions", "Factions" },
        { "macros", "Macros" },
        { "talentDefinitions", "Talent Definitions" },
        { "talentEntries", "Talent Entries" },
        { "talentNodes", "Talent Nodes" },
    },
}
addon.tooltipIDGroups = groups

local names = {
    items = "Item ID", spells = "Spell ID", npcs = "NPC ID", quests = "Quest ID",
    objects = "Object ID", currencies = "Currency ID", equipmentSets = "Equipment Set ID",
    enchants = "Enchant ID", gems = "Gem Item ID", bonuses = "Item Bonus ID",
    itemSets = "Item Set ID", expansions = "Item Expansion ID", talentNodes = "Talent Node ID",
    talentEntries = "Talent Entry ID", talentDefinitions = "Talent Definition ID",
    achievements = "Achievement ID", criteria = "Achievement Criteria ID", factions = "Faction ID",
    macros = "Macro ID", mounts = "Mount ID", pets = "Pet Species ID", toys = "Toy Item ID",
    appearances = "Appearance ID", appearanceSources = "Appearance Source ID", outfits = "Outfit ID",
    icons = "Icon File ID", maps = "Map ID", pointsOfInterest = "Point of Interest ID",
    vignettes = "Vignette ID",
}
local tooltipNames = {
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "WorldMapTooltip", "EmbeddedItemTooltip",
}
local slotSources = {
    GetInventoryItem = { category = "equipmentSlots", { "Equipment Slot ID", 2 } },
    GetBagItem = { category = "bagSlots", { "Bag ID", 1, true }, { "Bag Slot", 2 } },
    GetAction = { category = "actionSlots", { "Action Slot", 1 } },
}
local guidPattern = "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$"
local supportedTypes = {
    Spell = "spells", UnitAura = "spells", PetAction = "spells", Totem = "spells",
    RecipeRankInfo = "spells", Currency = "currencies", CompanionPet = "pets",
    Mount = "mounts", Achievement = "achievements", EquipmentSet = "equipmentSets",
    Quest = "quests", QuestPartyProgress = "quests", Macro = "macros", Outfit = "outfits",
}

function addon.ApplyTooltipIDDefaults(settings, reset)
    for _, group in ipairs(groups) do
        for _, category in ipairs(group) do
            local key, _, checked = unpack(category)
            if reset or type(settings[key]) ~= "boolean" then
                settings[key] = checked == true
            end
        end
    end
end

local function IsReadable(value, kind)
    return not issecretvalue(value) and type(value) == kind
        and (kind ~= "table" or not (issecrettable and issecrettable(value)))
end

local function Field(data, key)
    if IsReadable(data, "table") then
        local value = data[key]
        if not issecretvalue(value) then
            return value
        end
    end
end

local function ValidID(value, allowZero, allowNegative)
    if not IsReadable(value, "number") or value <= -math.huge or value >= math.huge or value % 1 ~= 0 then
        return
    end
    if value > 0 or (allowZero and value == 0) or (allowNegative and value < 0) then
        return value
    end
end

local function Call(api, key, ...)
    if api and api[key] then
        return api[key](...)
    end
end

local function IsAccessible(tooltip)
    if issecretvalue(tooltip) or not tooltip or tooltip:IsForbidden() then
        return false
    end
    if InCombatLockdown() then
        local protected = tooltip:IsProtected()
        return not issecretvalue(protected) and protected == false
    end
    return true
end

local function AppendID(tooltip, label, id)
    local text = label .. ": " .. id
    local name, lines = tooltip:GetName(), tooltip:NumLines()
    if not IsReadable(name, "string") or not IsReadable(lines, "number") then
        return false
    end
    for index = 1, lines do
        local line = _G[name .. "TextLeft" .. index]
        if line and (not line.IsForbidden or not line:IsForbidden()) then
            local existing = line:GetText()
            if not issecretvalue(existing) and existing == text then
                return false
            end
        end
    end
    GameTooltip_AddColoredLine(tooltip, text, GRAY_FONT_COLOR)
    return true
end

local function ResolveItemLink(data, getter, args)
    local link = Field(data, "hyperlink")
    if IsReadable(link, "string") and link:find("item:", 1, true) then
        return link
    end
    local guid = Field(data, "guid")
    if IsReadable(guid, "string") and guid:match("^Item%-") then
        link = Call(C_Item, "GetItemLinkByGUID", guid)
        if IsReadable(link, "string") then
            return link
        end
    end
    if getter == "GetBagItem" then
        local bag, slot = ValidID(Field(args, 1), true, true), ValidID(Field(args, 2))
        if bag and slot then
            link = Call(C_Container, "GetContainerItemLink", bag, slot)
        end
    elseif getter == "GetInventoryItem" and GetInventoryItemLink then
        local unit, slot = Field(args, 1), ValidID(Field(args, 2))
        if IsReadable(unit, "string") and slot then
            link = GetInventoryItemLink(unit, slot)
        end
    elseif getter == "GetHyperlink" then
        link = Field(args, 1)
    end
    if IsReadable(link, "string") then
        return link
    end
end

function addon.InitializeTooltipIDs(settings)
    local categories = settings.categories
    local dataTypes = Enum.TooltipDataType
    local questTitle = Enum.TooltipDataLineType.QuestTitle
    local kinds = {}
    for dataType, category in pairs(supportedTypes) do
        if dataTypes[dataType] then
            kinds[dataTypes[dataType]] = category
        end
    end

    local function Add(tooltip, category, id, label, allowZero, allowNegative)
        if categories[category] and ValidID(id, allowZero, allowNegative) then
            return AppendID(tooltip, label or names[category], id)
        end
    end

    local function AddAchievement(tooltip, id)
        if not ValidID(id) then
            return
        end
        local changed = Add(tooltip, "achievements", id)
        if categories.criteria and GetAchievementNumCriteria and GetAchievementCriteriaInfo then
            local count = GetAchievementNumCriteria(id)
            if ValidID(count) then
                for index = 1, count do
                    local criteriaID = select(10, GetAchievementCriteriaInfo(id, index))
                    changed = Add(tooltip, "criteria", criteriaID) or changed
                end
            end
        end
        return changed
    end

    local function AddItem(tooltip, data, getter, args)
        local id = ValidID(Field(data, "id"))
        local link, itemString
        if not id or categories.enchants or categories.bonuses or categories.gems
            or categories.appearances or categories.appearanceSources then
            link = ResolveItemLink(data, getter, args)
            itemString = link and link:match("item:([%d:%-?]+)")
            id = id or (itemString and tonumber(itemString:match("^%d+")))
        end
        if not ValidID(id) then
            return
        end
        Add(tooltip, "items", id)
        if categories.enchants or categories.bonuses then
            if itemString then
                local fields = { strsplit(":", itemString) }
                Add(tooltip, "enchants", tonumber(fields[2]))
                local count = tonumber(fields[13]) or 0
                for index = 14, math.min(13 + count, #fields) do
                    Add(tooltip, "bonuses", tonumber(fields[index]))
                end
            end
        end
        if categories.gems and link then
            for socket = 1, 4 do
                Add(tooltip, "gems", Call(C_Item, "GetItemGemID", link, socket))
            end
        end
        if categories.itemSets or categories.expansions then
            local expansion, itemSet = select(15, Call(C_Item, "GetItemInfo", id))
            Add(tooltip, "expansions", expansion, nil, true)
            Add(tooltip, "itemSets", itemSet)
        end
        if categories.appearances or categories.appearanceSources then
            local appearance, source = Call(C_TransmogCollection, "GetItemInfo", link or id)
            Add(tooltip, "appearances", appearance)
            Add(tooltip, "appearanceSources", source)
        end
        if categories.icons then
            Add(tooltip, "icons", Call(C_Item, "GetItemIconByID", id))
        end
        if categories.mounts then
            Add(tooltip, "mounts", Call(C_MountJournal, "GetMountFromItem", id))
        end
        if categories.toys then
            Add(tooltip, "toys", Call(C_ToyBox, "GetToyInfo", id))
        end
    end

    local function AddFromData(tooltip, data)
        if not issecretvalue(tooltip) then
            addon.MarkTooltipActive(tooltip)
        end
        if not settings.enabled or not IsAccessible(tooltip) then
            return
        end
        local name = tooltip:GetName()
        if not IsReadable(name, "string") or not tContains(tooltipNames, name) or _G[name] ~= tooltip then
            return
        end
        local kind = Field(data, "type")
        if not IsReadable(kind, "number") then
            return
        end
        local id = Field(data, "id")
        local info = tooltip.GetProcessingTooltipInfo and tooltip:GetProcessingTooltipInfo()
        local getter, args = Field(info, "getterName"), Field(info, "getterArgs")
        local slots = slotSources[getter]
        if slots and categories[slots.category] then
            for _, slot in ipairs(slots) do
                local label, arg, signed = unpack(slot)
                Add(tooltip, slots.category, Field(args, arg), label, signed, signed)
            end
        end
        if getter == "GetTraitEntry" then
            local entry = ValidID(Field(args, 1))
            if entry then
                Add(tooltip, "talentEntries", entry)
                Add(tooltip, "talentDefinitions", Field(data, "definitionID"))
            end
        elseif getter == "GetRecipeResultItem" then
            Add(tooltip, "spells", Field(args, 1))
        elseif getter == "GetAction" and categories.macros and GetActionInfo then
            local slot = ValidID(Field(args, 1))
            if slot then
                local actionType, macroID = GetActionInfo(slot)
                if not issecretvalue(actionType) and actionType == "macro" then
                    Add(tooltip, "macros", macroID)
                end
            end
        end
        if kind == dataTypes.Item or kind == dataTypes.Toy then
            AddItem(tooltip, data, getter, args)
            if kind == dataTypes.Toy then
            Add(tooltip, "toys", id or (getter == "GetToyByItemID" and Field(args, 1)))
            end
        elseif kind == dataTypes.Unit or kind == dataTypes.Corpse or kind == dataTypes.Object then
            if categories.npcs or categories.objects then
                local guid = Field(data, "guid")
                if IsReadable(guid, "string") then
                    local guidKind, record = guid:match(guidPattern)
                    if guidKind == "Creature" or guidKind == "Vehicle" then
                        Add(tooltip, "npcs", tonumber(record))
                    elseif guidKind == "GameObject" then
                        Add(tooltip, "objects", tonumber(record))
                    end
                end
            end
            if categories.quests and questTitle then
                local lines = Field(data, "lines")
                if IsReadable(lines, "table") then
                    for _, line in ipairs(lines) do
                        if Field(line, "type") == questTitle then
                            Add(tooltip, "quests", Field(line, "id"))
                        end
                    end
                end
            end
        elseif kind == dataTypes.Achievement then
            AddAchievement(tooltip, id)
        else
            local category = kinds[kind]
            if category == "spells" then
                id = ValidID(Field(data, "spellID")) or id
                if ValidID(id) then
                    if categories.mounts then
                        Add(tooltip, "mounts", Call(C_MountJournal, "GetMountFromSpell", id))
                    end
                    if categories.icons then
                        Add(tooltip, "icons", Call(C_Spell, "GetSpellTexture", id))
                    end
                end
            end
            if category then
                Add(tooltip, category, id, nil, category == "equipmentSets")
            end
        end
    end

    local function AddToOwnedTooltips(owner, append)
        if not settings.enabled or not IsAccessible(owner) then
            return
        end
        for _, name in ipairs(tooltipNames) do
            local tooltip = _G[name]
            if IsAccessible(tooltip) and not addon.IsTooltipFading(tooltip) and tooltip.GetOwner and tooltip.NumLines then
                local visible, currentOwner = tooltip:IsVisible(), tooltip:GetOwner()
                if not issecretvalue(visible) and visible and not issecretvalue(currentOwner) and currentOwner == owner
                    and append(tooltip) then
                    tooltip:Show()
                end
            end
        end
    end

    local registeredHooks = {}
    local function Hook(target, method, callback)
        local owner = target or _G
        if owner[method] and registeredHooks[method] ~= owner[method] then
            hooksecurefunc(owner, method, callback)
            registeredHooks[method] = owner[method]
        end
    end

    local function InstallPanelHooks()
        for _, name in ipairs(tooltipNames) do
            local tooltip = _G[name]
            if IsAccessible(tooltip) then
                addon.TrackTooltipFade(tooltip)
            end
        end
        if TalentDisplayMixin then
            Hook(TalentDisplayMixin, "SetTooltipInternal", function(button)
                if not (categories.talentNodes or categories.talentEntries or categories.talentDefinitions) then
                    return
                end
                AddToOwnedTooltips(button, function(tooltip)
                    local changed = Add(tooltip, "talentEntries", Field(button, "entryID"))
                    changed = Add(tooltip, "talentDefinitions", Field(button, "definitionID")) or changed
                    if categories.talentNodes and button.GetNodeInfo then
                        changed = Add(tooltip, "talentNodes", Field(button:GetNodeInfo(), "ID")) or changed
                    end
                    return changed
                end)
            end)
        end
        if ReputationEntryMixin then
            Hook(ReputationEntryMixin, "ShowTooltipForReputationType", function(row)
                if categories.factions then
                    AddToOwnedTooltips(row, function(tooltip)
                        return Add(tooltip, "factions", Field(Field(row, "elementData"), "factionID"))
                    end)
                end
            end)
        end
        Hook(nil, "AchievementShield_OnEnter", function(shield)
            if categories.achievements or categories.criteria then
                AddToOwnedTooltips(shield, function(tooltip)
                    local parent = shield:GetParent()
                    if IsAccessible(parent) and parent.GetElementData then
                        return AddAchievement(tooltip, Field(parent:GetElementData(), "id"))
                    end
                end)
            end
        end)
        Hook(nil, "PaperDollItemSlotButton_OnEnter", function(button)
            if categories.equipmentSlots then
                AddToOwnedTooltips(button, function(tooltip)
                    return Add(tooltip, "equipmentSlots", button:GetID(), "Equipment Slot ID")
                end)
            end
        end)
        Hook(nil, "QuestMapLogTitleButton_OnEnter", function(button)
            if categories.quests then
                AddToOwnedTooltips(button, function(tooltip)
                    local index = ValidID(Field(button, "questLogIndex"))
                    local id = Field(button, "questID")
                    if not ValidID(id) and index then
                        id = Call(C_QuestLog, "GetQuestIDForLogIndex", index)
                    end
                    return Add(tooltip, "quests", id)
                end)
            end
        end)
        local function AddPin(tooltip, pin, category, id)
            local changed = Add(tooltip, category, id)
            if categories.maps and pin.GetMap then
                local map = pin:GetMap()
                if IsAccessible(map) then
                    changed = Add(tooltip, "maps", map:GetMapID()) or changed
                end
            end
            return changed
        end
        if AreaPOIPinMixin then
            Hook(AreaPOIPinMixin, "TryShowTooltip", function(pin)
                if categories.pointsOfInterest or categories.maps then
                    AddToOwnedTooltips(pin, function(tooltip)
                        return AddPin(tooltip, pin, "pointsOfInterest", Field(Field(pin, "poiInfo"), "areaPoiID"))
                    end)
                end
            end)
        end
        if VignettePinBaseMixin then
            Hook(VignettePinBaseMixin, "OnMouseEnter", function(pin)
                if categories.vignettes or categories.maps then
                    AddToOwnedTooltips(pin, function(tooltip)
                        return AddPin(tooltip, pin, "vignettes", pin:GetVignetteID())
                    end)
                end
            end)
        end
    end

    TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, AddFromData)
    local events = CreateFrame("Frame")
    events:RegisterEvent("ADDON_LOADED")
    events:SetScript("OnEvent", InstallPanelHooks)
    InstallPanelHooks()
end
