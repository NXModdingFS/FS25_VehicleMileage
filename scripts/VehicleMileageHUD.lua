NXMileageHUD = {}
NXMileageHUD.state = {}
local S = NXMileageHUD.state

local NETWORK_THRESHOLD = 10
local SAVE_INTERVAL     = 20000  
local HOLD_TIME_RESET   = 1000     
local SYNC_INTERVAL     = 5000     


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
    return type(_G.g_uiScale) == "number" and _G.g_uiScale > 0 and _G.g_uiScale or 1.0
end

local function getCurrentVehicle()
    local hud = g_currentMission and g_currentMission.hud
    if hud then
        local speedo = hud.speedMeter
        if speedo and speedo.vehicle then return speedo.vehicle end
        if hud.activeDisplayVehicle then return hud.activeDisplayVehicle end
    end
    if g_currentMission then
        if g_currentMission.controlledVehicle then return g_currentMission.controlledVehicle end
        if g_currentMission.vehicles then
            for _, v in pairs(g_currentMission.vehicles) do
                if v and type(v) == "table" then
                    if v.getIsControlled and v:getIsControlled() then return v end
                    if v.getIsEntered   and v:getIsEntered()    then return v end
                    local spec = v.spec_enterable
                    if spec and (spec.isControlled or spec.entered or (spec.numPassengers or 0) > 0) then
                        return v
                    end
                end
            end
        end
    end
end

local function getVehicleId(veh)
    if not veh then return nil end
    local root = veh.rootVehicle or veh

    if root.configFileName then
        local uniqueId = root.configFileName
        if root.propertyState     then uniqueId = uniqueId .. "_" .. tostring(root.propertyState)     end
        if root.currentSavegameId then uniqueId = uniqueId .. "_" .. tostring(root.currentSavegameId) end
        return uniqueId
    end

    if root.id then return "vehicle_" .. tostring(root.id) end
    return "unknown_" .. tostring(root)
end


local function saveMileage()
    if g_currentMission.missionDynamicInfo.isMultiplayer and not g_server then return end
    if not S.mileageData then return end

    local savegameDir = g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory
    if not savegameDir then return end

    local filepath = savegameDir .. "/NXMileageData.xml"          -- ← fixed filename
    local xmlFile  = createXMLFile("mileageXML", filepath, "mileage")

    if xmlFile and xmlFile ~= 0 then
        local i = 0
        for vehicleId, data in pairs(S.mileageData) do
            if vehicleId and data then
                local key = string.format("mileage.vehicle(%d)", i)
                setXMLString(xmlFile, key .. "#id",        tostring(vehicleId))
                setXMLFloat (xmlFile, key .. "#odoMeter",  data.odoMeter  or 0.0)
                setXMLFloat (xmlFile, key .. "#tripMeter", data.tripMeter or 0.0)
                i = i + 1
            end
        end
        saveXMLFile(xmlFile)
        delete(xmlFile)
    end
end

local function loadMileage()
    S.mileageData = {}

    local savegameDir = g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory
    if not savegameDir then return end

    local filepath = savegameDir .. "/NXMileageData.xml"         
    if not fileExists(filepath) then return end

    local xmlFile = loadXMLFile("mileageXML", filepath)
    if xmlFile and xmlFile ~= 0 then
        local i = 0
        while true do
            local key = string.format("mileage.vehicle(%d)", i)
            if not hasXMLProperty(xmlFile, key) then break end

            local vehicleId = getXMLString(xmlFile, key .. "#id")
            local odoMeter  = getXMLFloat (xmlFile, key .. "#odoMeter")
            local tripMeter = getXMLFloat (xmlFile, key .. "#tripMeter")

            if vehicleId and odoMeter then
                S.mileageData[vehicleId] = {
                    odoMeter         = odoMeter,
                    tripMeter        = tripMeter or 0.0,
                    odoDistanceSent  = odoMeter,
                    tripDistanceSent = tripMeter or 0.0
                }
            end
            i = i + 1
        end
        delete(xmlFile)
    end
end

local function updateActionEventVisibility()
    if not NXMileageHUD.actionEventIds then return end
    local isInVehicle = g_currentMission and g_currentMission.controlledVehicle ~= nil
    for _, actionEventId in ipairs(NXMileageHUD.actionEventIds) do
        if actionEventId then
            g_inputBinding:setActionEventTextVisibility(actionEventId, isInVehicle)
        end
    end
end

function NXMileageHUD.saveToSavegame()
    saveMileage()
end

function NXMileageHUD:loadMap()
    loadMileage()
    S.saveTimer        = 0
    S.syncTimer        = 0
    S.displayMode      = 0
    S.keyPressStartTime = 0
    S.wasInVehicle     = false

    if g_currentMission and g_currentMission.hud and g_currentMission.hud.speedMeter then
        self.speedMeter = g_currentMission.hud.speedMeter
    end
end

function NXMileageHUD:deleteMap()
    if g_server or not g_currentMission.missionDynamicInfo.isMultiplayer then
        saveMileage()
    end

    S.mileageData       = nil
    S.visible           = false
    S.text              = nil
    S.lastVehicle       = nil
    S.saveTimer         = nil
    S.syncTimer         = nil
    S.displayMode       = nil
    S.keyPressStartTime = nil
    S.wasInVehicle      = nil
    self.speedMeter     = nil
end

function NXMileageHUD:update(dt)
    if not g_currentMission or not g_currentMission.missionInfo then
        S.visible = false
        return
    end

    -- Keep action-help text in sync with whether we're in a vehicle
    local isInVehicle = g_currentMission.controlledVehicle ~= nil
    if S.wasInVehicle ~= isInVehicle then
        updateActionEventVisibility()
        S.wasInVehicle = isInVehicle
    end

    -- Server-side periodic save
    if g_server or not g_currentMission.missionDynamicInfo.isMultiplayer then
        S.saveTimer = (S.saveTimer or 0) + dt
        if S.saveTimer >= SAVE_INTERVAL then
            saveMileage()
            S.saveTimer = 0
        end
    end

    if not S.mileageData then S.mileageData = {} end

    local isMP = g_currentMission.missionDynamicInfo.isMultiplayer

    local vehicleList =
        (g_currentMission.vehicleSystem and g_currentMission.vehicleSystem.vehicles) or
        g_currentMission.vehicles

    if vehicleList then
        for _, vehicle in pairs(vehicleList) do
            if vehicle and type(vehicle) == "table" then
                local root      = vehicle.rootVehicle or vehicle
                local vehicleId = getVehicleId(root)

                if vehicleId then
                    if not S.mileageData[vehicleId] then
                        S.mileageData[vehicleId] = {
                            odoMeter         = 0.0,
                            tripMeter        = 0.0,
                            odoDistanceSent  = 0.0,
                            tripDistanceSent = 0.0
                        }
                    end

                    local data      = S.mileageData[vehicleId]
                    local lastMoved = vehicle.lastMovedDistance or 0

                    local isControlled = root.getIsControlled and root:getIsControlled()
                    local shouldTrack  = (not isMP) or g_server or isControlled

                    if shouldTrack and lastMoved > 0.001 then
                        data.odoMeter  = data.odoMeter  + lastMoved
                        data.tripMeter = data.tripMeter + lastMoved
                    end
                end
            end
        end
    end

    if isMP and not g_server and g_client then
        S.syncTimer = (S.syncTimer or 0) + dt
        if S.syncTimer >= SYNC_INTERVAL then
            S.syncTimer = 0

            local veh = getCurrentVehicle()
            if veh then
                local root      = veh.rootVehicle or veh
                local vehicleId = getVehicleId(root)
                local data      = vehicleId and S.mileageData[vehicleId]

                if data then
                    local odoDiff  = data.odoMeter  - (data.odoDistanceSent  or 0)
                    local tripDiff = data.tripMeter - (data.tripDistanceSent or 0)

                    if math.abs(odoDiff) >= NETWORK_THRESHOLD or math.abs(tripDiff) >= NETWORK_THRESHOLD then
                        g_client:getServerConnection():sendEvent(
                            MileageSyncEvent.new(vehicleId, data.odoMeter, data.tripMeter)
                        )
                        data.odoDistanceSent  = data.odoMeter
                        data.tripDistanceSent = data.tripMeter
                    end
                end
            end
        end
    end

    if not g_client then
        S.visible = false
        return
    end

    if g_currentMission.hud and not g_currentMission.hud:getIsVisible() then
        S.visible = false
        return
    end

    local veh = getCurrentVehicle()
    if not veh then
        S.visible   = false
        S.lastVehicle = nil
        return
    end

    local root      = veh.rootVehicle or veh
    local vehicleId = getVehicleId(root)

    if not vehicleId then
        S.visible = false
        return
    end

    if not S.mileageData[vehicleId] then
        S.mileageData[vehicleId] = {
            odoMeter         = 0.0,
            tripMeter        = 0.0,
            odoDistanceSent  = 0.0,
            tripDistanceSent = 0.0
        }
    end

    local data           = S.mileageData[vehicleId]
    local distanceInMeters = S.displayMode == 0 and data.odoMeter or data.tripMeter
    local distanceInKM   = (distanceInMeters / 1000) % 999999.99
    local displayDistance = g_i18n:getDistance(distanceInKM)
    local unit            = g_i18n:getMeasuringUnit()
    local modeLabel       = S.displayMode == 0 and "MLG" or "Trip"

    S.text      = string.format("%s  %08.2f %s", modeLabel, displayDistance, unit)
    S.visible   = true
    S.lastVehicle = root
end

function NXMileageHUD:draw()
    if not g_client or not S.visible or not S.text then return end

    if g_currentMission.hud and not g_currentMission.hud:getIsVisible() then return end

    local uiScale = getUiScale()
    local size    = (getCorrectTextSize and getCorrectTextSize(0.009) or 0.009) * uiScale

    local baseX, baseY = 0, 0

    if self.speedMeter and self.speedMeter.speedBg then
        baseX = self.speedMeter.speedBg.x + (self.speedMeter.speedBg.width  / 2)
        baseY = self.speedMeter.speedBg.y + (self.speedMeter.speedBg.height / 2)
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

    if setTextAlignment and setTextVerticalAlignment and renderText then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
        setTextBold(true)

        setTextColor(60/255, 118/255, 0/255, 1.0)
        renderText(baseX, baseY, size, S.text)

        setTextColor(1, 1, 1, 1)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
        setTextBold(false)
    end
end

function NXMileageHUD:onActionCallDown(actionName, keyStatus, arg4, arg5, arg6)
    if actionName == "NX_MILEAGE_TOGGLE_MODE" then
        S.keyPressStartTime = g_currentMission.time
    end
end

function NXMileageHUD:onActionCallUp(actionName, keyStatus, arg4, arg5, arg6)
    if actionName ~= "NX_MILEAGE_TOGGLE_MODE" then return end

    local pressDuration = g_currentMission.time - (S.keyPressStartTime or 0)

    if pressDuration >= HOLD_TIME_RESET then
        -- Long press → reset trip meter
        local veh = getCurrentVehicle()
        if veh then
            local vehicleId = getVehicleId(veh.rootVehicle or veh)
            if vehicleId and S.mileageData and S.mileageData[vehicleId] then
                local data = S.mileageData[vehicleId]
                data.tripMeter        = 0.0
                data.tripDistanceSent = 0.0

                -- In MP, immediately tell the server the trip was reset
                if g_currentMission.missionDynamicInfo.isMultiplayer and g_client and not g_server then
                    g_client:getServerConnection():sendEvent(
                        MileageSyncEvent.new(vehicleId, data.odoMeter, 0.0)
                    )
                end

                if g_server or not g_currentMission.missionDynamicInfo.isMultiplayer then
                    saveMileage()
                end

                local resetText = g_i18n:getText("nx_mileage_trip_reset") or "Trip meter reset"
                g_currentMission:showBlinkingWarning(resetText, 2000)
            end
        end
    else
        -- Short press → toggle ODO / Trip display
        S.displayMode = (S.displayMode + 1) % 2
        local modeText = S.displayMode == 0
            and (g_i18n:getText("nx_mileage_mode_mileage") or "Mileage")
            or  (g_i18n:getText("nx_mileage_mode_trip")    or "Trip Meter")
        g_currentMission:showBlinkingWarning(modeText, 2000)
    end

    S.keyPressStartTime = 0
end

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, NXMileageHUD.saveToSavegame)

addModEventListener(NXMileageHUD)