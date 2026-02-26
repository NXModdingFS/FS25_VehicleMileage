
local NX_MOD_DIR  = g_currentModDirectory
local NX_MOD_NAME = g_currentModName

NXMileageHUD = {}
NXMileageHUD.actionEventIds = NXMileageHUD.actionEventIds or {}

local HOLD_TIME_RESET = 1000

TypeManager.validateTypes = Utils.prependedFunction(
    TypeManager.validateTypes,
    function(types)
        if types.typeName == "vehicle" then
            NXMileageSpec.installSpecializations(
                g_vehicleTypeManager,
                g_specializationManager
            )
        end
    end
)

local function getUiScale()
    if g_gameSettings then
        if g_gameSettings.getValue then
            local ok, val = pcall(g_gameSettings.getValue, g_gameSettings, "uiScale")
            if ok and type(val) == "number" and val > 0 then return val end
        end
        if type(g_gameSettings.uiScale) == "number" and g_gameSettings.uiScale > 0 then
            return g_gameSettings.uiScale
        end
    end
    return (type(_G.g_uiScale) == "number" and _G.g_uiScale > 0) and _G.g_uiScale or 1.0
end

local function getCurrentVehicle()
    if not g_currentMission then return nil end

    local hud = g_currentMission.hud
    if hud then
        if hud.speedMeter and hud.speedMeter.vehicle then
            return hud.speedMeter.vehicle
        end
        if hud.activeDisplayVehicle then
            return hud.activeDisplayVehicle
        end
    end

    if g_currentMission.controlledVehicle then
        return g_currentMission.controlledVehicle
    end

    local vehicles = g_currentMission.vehicles
    if vehicles then
        for _, v in pairs(vehicles) do
            if v and type(v) == "table" then
                if v.getIsControlled and v:getIsControlled() then return v end
                if v.getIsEntered   and v:getIsEntered()    then return v end
            end
        end
    end
end

local function updateActionEventVisibility()
    if not NXMileageHUD.actionEventIds then return end
    local inVehicle = g_currentMission and g_currentMission.controlledVehicle ~= nil
    for _, id in ipairs(NXMileageHUD.actionEventIds) do
        if id then g_inputBinding:setActionEventTextVisibility(id, inVehicle) end
    end
end

function NXMileageHUD:loadMap()
    self.keyPressStartTime = 0
    self.wasInVehicle      = false
    self.visible           = false
    self.text              = nil

    if g_currentMission and g_currentMission.hud and g_currentMission.hud.speedMeter then
        self.speedMeter = g_currentMission.hud.speedMeter
    end
end

function NXMileageHUD:deleteMap()
    self.visible           = false
    self.text              = nil
    self.keyPressStartTime = nil
    self.wasInVehicle      = nil
    self.speedMeter        = nil
end

function NXMileageHUD:update(dt)
    if not g_currentMission or not g_currentMission.missionInfo then
        self.visible = false
        return
    end

    local inVehicle = g_currentMission.controlledVehicle ~= nil
    if self.wasInVehicle ~= inVehicle then
        updateActionEventVisibility()
        self.wasInVehicle = inVehicle
    end

    if not g_client then
        self.visible = false
        return
    end

    if g_currentMission.hud and not g_currentMission.hud:getIsVisible() then
        self.visible = false
        return
    end

    local veh = getCurrentVehicle()
    if not veh then
        self.visible = false
        return
    end

    local root = veh.rootVehicle or veh

    if root.nxMileage == nil then
        NXMileageSpec.ensureData(root)
    end

    local data   = root.nxMileage
    local mode   = data.odoMode or 0
    local meters = mode == 0 and data.odoMeter or data.tripMeter
    local km     = (meters / 1000) % 999999.99
    local dist   = g_i18n:getDistance(km)
    local unit   = g_i18n:getMeasuringUnit()
    local label  = mode == 0 and "MLG" or "Trip"

    self.text    = string.format("%s  %08.2f %s", label, dist, unit)
    self.visible = true
end

function NXMileageHUD:draw()
    if not g_client or not self.visible or not self.text then return end
    if g_currentMission.hud and not g_currentMission.hud:getIsVisible() then return end

    local uiScale = getUiScale()
    local size    = (getCorrectTextSize and getCorrectTextSize(0.009) or 0.009) * uiScale
    local baseX, baseY = 0, 0

    if self.speedMeter and self.speedMeter.speedBg then
        local bg = self.speedMeter.speedBg
        baseX = bg.x + bg.width  / 2
        baseY = bg.y + bg.height / 2
        local tx, ty = self.speedMeter:scalePixelToScreenVector({0, -40})
        baseX = baseX + tx
        baseY = baseY + ty
    else
        local dx, dy = 0.0, 0.0
        if getNormalizedScreenValues then
            local ok, nx, ny = pcall(getNormalizedScreenValues, 216 * uiScale, 90 * uiScale)
            if ok and nx and ny then dx, dy = nx, ny end
        end
        baseX = 1.0 - (_G.g_safeFrameOffsetX or 0.0) - dx
        baseY = (_G.g_safeFrameOffsetY or 0.0) + dy
    end

    if setTextAlignment and renderText then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
        setTextBold(true)
        setTextColor(60/255, 118/255, 0/255, 1.0)
        renderText(baseX, baseY, size, self.text)
        setTextColor(1, 1, 1, 1)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
        setTextBold(false)
    end
end

function NXMileageHUD:onActionCallDown(actionName, keyStatus, arg4, arg5, arg6)
    if actionName == "NX_MILEAGE_TOGGLE_MODE" then
        self.keyPressStartTime = g_currentMission.time
    end
end

function NXMileageHUD:onActionCallUp(actionName, keyStatus, arg4, arg5, arg6)
    if actionName ~= "NX_MILEAGE_TOGGLE_MODE" then return end

    local held = g_currentMission.time - (self.keyPressStartTime or 0)
    local veh  = getCurrentVehicle()
    local root = veh and (veh.rootVehicle or veh)

    if held >= HOLD_TIME_RESET then
        if root then
            if root.nxMileage == nil then NXMileageSpec.ensureData(root) end

            root.nxMileage.tripMeter        = 0.0
            root.nxMileage.tripDistanceSent = 0.0

            if g_server then
                root:raiseDirtyFlags(root.nxMileage.dirtyFlag)
            elseif g_client then
                g_client:getServerConnection():sendEvent(NXMileageTripResetEvent.new(root))
            end

            local txt = g_i18n:getText("nx_mileage_trip_reset") or "Trip meter reset"
            g_currentMission:showBlinkingWarning(txt, 2000)
        end
    else
        if root then
            if root.nxMileage == nil then NXMileageSpec.ensureData(root) end
            root.nxMileage.odoMode = (root.nxMileage.odoMode + 1) % 2
            local txt = root.nxMileage.odoMode == 0
                and (g_i18n:getText("nx_mileage_mode_mileage") or "Mileage")
                or  (g_i18n:getText("nx_mileage_mode_trip")    or "Trip Meter")
            g_currentMission:showBlinkingWarning(txt, 2000)
        end
    end

    self.keyPressStartTime = 0
end

-- ---------------------------------------------------------------------------
-- Register mod listener
-- ---------------------------------------------------------------------------

addModEventListener(NXMileageHUD)