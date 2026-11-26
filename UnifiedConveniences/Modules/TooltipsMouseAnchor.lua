local _, addon = ...

local screenMarginPixels = 8
local cursorGapPixels = 8
local cursorSizes = { [0] = 32, 48, 64, 96, 128 }
local automaticCursorSize = 128
local cursorAnchor = "ANCHOR_CURSOR_RIGHT"
local preferredSides = {
    Left = { "left", "right", "above", "below" },
    Centre = { "above", "below", "right", "left" },
    Right = { "right", "left", "above", "below" },
}

local function IsNumber(value)
    return not issecretvalue(value) and type(value) == "number"
        and value > -math.huge and value < math.huge
end

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function PlaceTooltip(mouseX, mouseY, width, height, screenWidth, screenHeight, margin, cursorGap, cursorSize, settings)
    local minX, minY = margin, margin
    local maxX, maxY = screenWidth - margin - width, screenHeight - margin - height
    local cursorLeft, cursorRight = mouseX - cursorGap, mouseX + cursorSize + cursorGap
    local cursorBottom, cursorTop = mouseY - cursorSize - cursorGap, mouseY + cursorGap
    local centreX, centreY = mouseX - width / 2, mouseY - height / 2
    local dx, dy = settings.horizontalOffset, settings.verticalOffset

    if maxX >= minX and maxY >= minY then
        for _, side in ipairs(preferredSides[settings.align]) do
            if side == "right" and cursorRight <= maxX then
                return Clamp(cursorRight + dx, math.max(minX, cursorRight), maxX), Clamp(centreY + dy, minY, maxY)
            elseif side == "left" and cursorLeft - width >= minX then
                return Clamp(cursorLeft - width + dx, minX, math.min(maxX, cursorLeft - width)), Clamp(centreY + dy, minY, maxY)
            elseif side == "above" and cursorTop <= maxY then
                return Clamp(centreX + dx, minX, maxX), Clamp(cursorTop + dy, math.max(minY, cursorTop), maxY)
            elseif side == "below" and cursorBottom - height >= minY then
                return Clamp(centreX + dx, minX, maxX), Clamp(cursorBottom - height + dy, minY, math.min(maxY, cursorBottom - height))
            end
        end
    end

    -- For an oversized tooltip keep its top-left content readable.
    return Clamp(centreX + dx, minX, math.max(minX, maxX)), Clamp(centreY + dy, math.min(minY, maxY), maxY)
end

local function ReadDefaultAnchor(tooltip)
    local anchor = tooltip:GetAnchorType()
    local count = tooltip:GetNumPoints()
    if issecretvalue(anchor) or anchor ~= "ANCHOR_NONE" or not IsNumber(count) or count == 0 then
        return
    end
    local points = {}
    for index = 1, count do
        local point, relative, relativePoint, x, y = tooltip:GetPoint(index)
        if issecretvalue(point) or issecretvalue(relative) or issecretvalue(relativePoint)
            or not IsNumber(x) or not IsNumber(y) then
            return
        end
        if relative and relative.IsForbidden and relative:IsForbidden() then
            return
        end
        points[index] = { point, relative, relativePoint, x, y }
    end
    return points
end

function addon.InitializeTooltipsMouseAnchor(settings)
    local tooltip = GameTooltip
    local updates = CreateFrame("Frame")
    local defaultPoints, appliedX, appliedY
    local screenWidth, screenHeight, rootScale, anchorScale, pixelsToUI, cursorSize
    local width, height

    local function ForgetAnchor()
        updates:SetScript("OnUpdate", nil)
        defaultPoints, appliedX, appliedY = nil, nil, nil
    end

    local function CanPosition()
        if tooltip:IsForbidden() then
            return false
        end
        if InCombatLockdown() then
            local protected = tooltip:IsProtected()
            return not issecretvalue(protected) and protected == false
        end
        return true
    end

    local function RestoreAnchor()
        updates:SetScript("OnUpdate", nil)
        if not appliedX or not CanPosition() then
            return
        end
        local anchor = tooltip:GetAnchorType()
        if issecretvalue(anchor) then
            return
        end
        appliedX, appliedY = nil, nil
        if anchor == cursorAnchor then
            tooltip:SetAnchorType("ANCHOR_NONE")
            tooltip:ClearAllPoints()
            for _, point in ipairs(defaultPoints) do
                tooltip:SetPoint(unpack(point, 1, 5))
            end
        else
            defaultPoints = nil
        end
    end

    local function ShouldFollow()
        if not defaultPoints or settings.mode == "Off" or not CanPosition() then
            return false
        end
        if EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() then
            return false
        end
        if settings.mode == "Out of Combat" then
            local combat = UnitAffectingCombat("player")
            return not InCombatLockdown() and not issecretvalue(combat) and combat == false
        end
        return true
    end

    local function Reposition()
        if tooltip:IsForbidden() then
            ForgetAnchor()
            return
        end
        local mouseX, mouseY = GetCursorPosition()
        if not IsNumber(mouseX) or not IsNumber(mouseY) then
            RestoreAnchor()
            return
        end
        mouseX, mouseY = mouseX / rootScale, mouseY / rootScale
        local x, y = PlaceTooltip(mouseX, mouseY, width, height, screenWidth, screenHeight,
            screenMarginPixels * pixelsToUI, cursorGapPixels * pixelsToUI, cursorSize, settings)
        local offsetX, offsetY = (x - mouseX) / anchorScale, (y + height - mouseY) / anchorScale
        if offsetX == appliedX and offsetY == appliedY then
            return
        end
        if not CanPosition() then
            updates:SetScript("OnUpdate", nil)
            return
        end
        local anchor = tooltip:GetAnchorType()
        if issecretvalue(anchor) then
            RestoreAnchor()
            return
        end
        if anchor ~= (appliedX and cursorAnchor or "ANCHOR_NONE") then
            ForgetAnchor()
            return
        end
        -- Native cursor anchors use the tooltip's top edge as their vertical reference.
        appliedX, appliedY = offsetX, offsetY
        tooltip:SetAnchorType(cursorAnchor, offsetX, offsetY)
    end

    local function Refresh()
        if not ShouldFollow() then
            RestoreAnchor()
            return
        end
        local visible = tooltip:IsVisible()
        if issecretvalue(visible) or visible ~= true then
            RestoreAnchor()
            return
        end
        local tooltipWidth, tooltipHeight = tooltip:GetSize()
        local tooltipScale = tooltip:GetEffectiveScale()
        rootScale = UIParent:GetEffectiveScale()
        screenWidth, screenHeight = UIParent:GetSize()
        if not IsNumber(tooltipWidth) or not IsNumber(tooltipHeight) or not IsNumber(tooltipScale)
            or not IsNumber(screenWidth) or not IsNumber(screenHeight) or not IsNumber(rootScale)
            or tooltipWidth <= 0 or tooltipHeight <= 0 or tooltipScale <= 0 or rootScale <= 0 then
            RestoreAnchor()
            return
        end
        anchorScale = tooltipScale / rootScale
        width, height = tooltipWidth * anchorScale, tooltipHeight * anchorScale
        pixelsToUI = PixelUtil.GetPixelToUIUnitFactor() / rootScale
        local size = C_CVar.GetCVar("cursorSizePreferred")
        size = not issecretvalue(size) and tonumber(size) or nil
        cursorSize = (cursorSizes[size] or automaticCursorSize) * pixelsToUI
        Reposition()
        if defaultPoints and appliedX then
            updates:SetScript("OnUpdate", Reposition)
        end
    end

    hooksecurefunc(tooltip, "SetOwner", ForgetAnchor)
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(frame)
        if frame ~= tooltip or frame:IsForbidden() then
            return
        end
        defaultPoints = ReadDefaultAnchor(frame)
        Refresh()
    end)
    tooltip:HookScript("OnShow", Refresh)
    tooltip:HookScript("OnHide", ForgetAnchor)
    tooltip:HookScript("OnSizeChanged", Refresh)

    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "CVAR_UPDATE" }) do
        updates:RegisterEvent(event)
    end
    updates:SetScript("OnEvent", function(_, event, cvar)
        if event ~= "CVAR_UPDATE" or (not issecretvalue(cvar) and cvar == "cursorSizePreferred") then
            Refresh()
        end
    end)
    return Refresh
end
