local _, addon = ...

local screenMarginPixels = 8
local alignmentFractions = { Left = 1, Centre = 0.5, Right = 0 }
local fadingTooltips = setmetatable({}, { __mode = "k" })

function addon.TrackTooltipFade(tooltip)
    if fadingTooltips[tooltip] ~= nil or not tooltip.FadeOut or not tooltip.SetOwner then
        return
    end
    fadingTooltips[tooltip] = false
    hooksecurefunc(tooltip, "FadeOut", function() fadingTooltips[tooltip] = true end)
    hooksecurefunc(tooltip, "SetOwner", function() fadingTooltips[tooltip] = false end)
    tooltip:HookScript("OnShow", function() fadingTooltips[tooltip] = false end)
end

function addon.IsTooltipFading(tooltip)
    return fadingTooltips[tooltip] == true
end

function addon.MarkTooltipActive(tooltip)
    if fadingTooltips[tooltip] then
        fadingTooltips[tooltip] = false
    end
end

local function IsNumber(value)
    return not issecretvalue(value) and type(value) == "number"
        and value > -math.huge and value < math.huge
end

local function ReadDefaultPoints(tooltip)
    local count = tooltip:GetNumPoints()
    if not IsNumber(count) or count == 0 then
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

local function ReadClamp(tooltip)
    local enabled = tooltip:IsClampedToScreen()
    local left, right, top, bottom = tooltip:GetClampRectInsets()
    if not issecretvalue(enabled) and IsNumber(left) and IsNumber(right) and IsNumber(top) and IsNumber(bottom) then
        return { enabled = enabled, left, right, top, bottom }
    end
end

function addon.InitializeTooltipsMouseAnchor(settings)
    local tooltip = GameTooltip
    local events = CreateFrame("Frame")
    local defaultPoints, appliedAnchor, appliedX, appliedY
    local originalClamp, appliedMargin
    local restoreMouseMotion

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

    local function RestoreFrameSettings()
        if not (originalClamp or restoreMouseMotion) or not CanPosition() then
            return
        end
        if originalClamp then
            local saved = originalClamp
            originalClamp, appliedMargin = nil, nil
            tooltip:SetClampRectInsets(unpack(saved, 1, 4))
            tooltip:SetClampedToScreen(saved.enabled)
        end
        if restoreMouseMotion then
            restoreMouseMotion = nil
            tooltip:EnableMouseMotion(true)
        end
    end

    local function ForgetAnchor()
        defaultPoints, appliedAnchor, appliedX, appliedY = nil, nil, nil, nil
        RestoreFrameSettings()
    end

    local function RestoreAnchor(anchor)
        if appliedAnchor and anchor == appliedAnchor then
            appliedAnchor, appliedX, appliedY = nil, nil, nil
            tooltip:SetAnchorType("ANCHOR_NONE")
            tooltip:ClearAllPoints()
            for _, point in ipairs(defaultPoints) do
                tooltip:SetPoint(unpack(point, 1, 5))
            end
        end
        RestoreFrameSettings()
    end

    local function ShouldFollow()
        if settings.mode == "Off" or (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then
            return false
        end
        if settings.mode == "Out of Combat" then
            local combat = UnitAffectingCombat("player")
            return not InCombatLockdown() and not issecretvalue(combat) and combat == false
        end
        return true
    end

    local function Refresh()
        if not CanPosition() or addon.IsTooltipFading(tooltip) then
            return
        end
        if not defaultPoints then
            RestoreFrameSettings()
            return
        end
        local anchor = tooltip:GetAnchorType()
        if issecretvalue(anchor) or anchor ~= (appliedAnchor or "ANCHOR_NONE") then
            ForgetAnchor()
            return
        end
        if not ShouldFollow() then
            RestoreAnchor(anchor)
            return
        end
        local visible = tooltip:IsVisible()
        if issecretvalue(visible) or visible ~= true then
            return
        end
        local width, height = tooltip:GetSize()
        local scale, parentScale = tooltip:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local screenWidth, screenHeight = UIParent:GetSize()
        if not IsNumber(width) or not IsNumber(height) or not IsNumber(scale) or not IsNumber(parentScale)
            or not IsNumber(screenWidth) or not IsNumber(screenHeight)
            or width <= 0 or height <= 0 or scale <= 0 or parentScale <= 0 then
            RestoreAnchor(anchor)
            return
        end

        local unitScale = parentScale / scale
        local dx = math.max(-screenWidth, math.min(screenWidth, settings.horizontalOffset)) * unitScale
        local x = dx - width * alignmentFractions[settings.align]
        local y = math.max(-screenHeight, math.min(screenHeight, settings.verticalOffset)) * unitScale
        local cursorAnchor = "ANCHOR_CURSOR_RIGHT"
        if settings.align == "Centre" and settings.horizontalOffset == 0 and settings.verticalOffset == 0 then
            cursorAnchor, x, y = "ANCHOR_CURSOR", nil, nil
        end

        if not originalClamp then
            originalClamp = ReadClamp(tooltip)
        end
        local margin = screenMarginPixels * PixelUtil.GetPixelToUIUnitFactor() / scale
        if originalClamp and appliedMargin ~= margin then
            appliedMargin = margin
            tooltip:SetClampRectInsets(-margin, margin, margin, -margin)
            tooltip:SetClampedToScreen(true)
        end
        local mouseMotion = tooltip:IsMouseMotionEnabled()
        if not issecretvalue(mouseMotion) and mouseMotion == true then
            -- A tooltip following the pointer should not become its new hover target.
            restoreMouseMotion = true
            tooltip:EnableMouseMotion(false)
        end
        if cursorAnchor ~= appliedAnchor or x ~= appliedX or y ~= appliedY then
            appliedAnchor, appliedX, appliedY = cursorAnchor, x, y
            tooltip:SetAnchorType(cursorAnchor, x, y)
        end
    end

    addon.TrackTooltipFade(tooltip)
    hooksecurefunc(tooltip, "SetOwner", ForgetAnchor)
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(frame)
        if frame ~= tooltip or frame:IsForbidden() then
            return
        end
        local anchor = frame:GetAnchorType()
        if not issecretvalue(anchor) and anchor == "ANCHOR_NONE" then
            defaultPoints = ReadDefaultPoints(frame)
            Refresh()
        end
    end)
    tooltip:HookScript("OnShow", Refresh)
    tooltip:HookScript("OnHide", ForgetAnchor)
    tooltip:HookScript("OnSizeChanged", Refresh)

    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", Refresh)
    return Refresh
end
