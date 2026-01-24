NXMileageHUD = {}
NXMileageHUD.state = {}
local S = NXMileageHUD.state

-- Constants
local NETWORK_THRESHOLD = 10 -- Send updates every 10 meters
local SAVE_INTERVAL = 20000 -- Auto-save every 20 seconds (20000ms)
local HOLD_TIME_RESET = 1000 

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
                    if v.getIsEntered and v:getIsEntered() then return v end
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
    
    -- Use configFileName as primary identifier (stable across sessions)
    if root.configFileName then 
        local uniqueId = root.configFileName
        
        -- Add property state for uniqueness if available
        if root.propertyState then
            uniqueId = uniqueId .. "_" .. tostring(root.propertyState)
        end
        
        -- Fallback: add currentSavegameId if available for additional uniqueness
        if root.currentSavegameId then
            uniqueId = uniqueId .. "_" .. tostring(root.currentSavegameId)
        end
        
        return uniqueId
    end
    
    -- Fallback to ID if configFileName not available
    if root.id then return "vehicle_" .. tostring(root.id) end
    
    -- Last resort
    return "unknown_" .. tostring(root)
end

local function saveMileage()
    -- Only server should save in multiplayer
    if g_currentMission.missionDynamicInfo.isMultiplayer and not g_server then 
        print("NXMileageHUD: Skipping save (not server in multiplayer)")
        return 
    end
    
    if not S.mileageData then 
        print("NXMileageHUD: No mileage data to save")
        return 
    end
    
    local savegameDir = g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory
    if not savegameDir then 
        print("NXMileageHUD: ERROR - No savegame directory available")
        return 
    end
    
    local filepath = savegameDir .. "/NXMileageData.xml"
    local xmlFile = createXMLFile("mileageXML", filepath, "mileage")
    
    if xmlFile and xmlFile ~= 0 then
        local i = 0
        for vehicleId, data in pairs(S.mileageData) do
            if vehicleId and data then
                local key = string.format("mileage.vehicle(%d)", i)
                setXMLString(xmlFile, key .. "#id", tostring(vehicleId))
                setXMLFloat(xmlFile, key .. "#odoMeter", data.odoMeter or 0.0)
                setXMLFloat(xmlFile, key .. "#tripMeter", data.tripMeter or 0.0)
                i = i + 1
            end
        end
        
        local success = saveXMLFile(xmlFile)
        delete(xmlFile)
        
        if success then
            print(string.format("NXMileageHUD: Successfully saved mileage data for %d vehicles to %s", i, filepath))
        else
            print("NXMileageHUD: ERROR - Failed to save XML file!")
        end
    else
        print("NXMileageHUD: ERROR - Failed to create XML file for saving")
    end
end

local function loadMileage()
    S.mileageData = {}
    
    local savegameDir = g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory
    if not savegameDir then 
        print("NXMileageHUD: No savegame directory available for loading")
        return 
    end
    
    local filepath = savegameDir .. "/NXMileageData.xml"
    if not fileExists(filepath) then 
        print("NXMileageHUD: No existing mileage data file found (this is normal for first load)")
        return 
    end
    
    local xmlFile = loadXMLFile("mileageXML", filepath)
    if xmlFile and xmlFile ~= 0 then
        local i = 0
        while true do
            local key = string.format("mileage.vehicle(%d)", i)
            if not hasXMLProperty(xmlFile, key) then break end
            
            local vehicleId = getXMLString(xmlFile, key .. "#id")
            local odoMeter = getXMLFloat(xmlFile, key .. "#odoMeter")
            local tripMeter = getXMLFloat(xmlFile, key .. "#tripMeter")
            
            if vehicleId and odoMeter then
                S.mileageData[vehicleId] = {
                    odoMeter = odoMeter,
                    tripMeter = tripMeter or 0.0,
                    odoDistanceSent = odoMeter,
                    tripDistanceSent = tripMeter or 0.0
                }
            end
            i = i + 1
        end
        delete(xmlFile)
        print(string.format("NXMileageHUD: Successfully loaded mileage data for %d vehicles from %s", i, filepath))
    else
        print("NXMileageHUD: ERROR - Failed to load XML file")
    end
end

function NXMileageHUD.saveToSavegame()
    print("NXMileageHUD: Game saving, persisting mileage data...")
    saveMileage()
end

function NXMileageHUD:loadMap()
    print("NXMileageHUD: Loading map...")
    loadMileage()
    S.saveTimer = 0
    S.displayMode = 0 
    S.keyPressStartTime = 0
    
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.speedMeter then
        self.speedMeter = g_currentMission.hud.speedMeter
    end
end

function NXMileageHUD:deleteMap()
    print("NXMileageHUD: Deleting map, saving final mileage data...")
    -- Save one last time before cleanup
    if g_server or not g_currentMission.missionDynamicInfo.isMultiplayer then
        saveMileage()
    end
    
    S.mileageData = nil
    S.visible = false
    S.text = nil
    S.lastVehicle = nil
    S.saveTimer = nil
    S.displayMode = nil
    S.keyPressStartTime = nil
    self.speedMeter = nil
end

function NXMileageHUD:update(dt)
    if not g_currentMission or not g_currentMission.missionInfo then
        S.visible = false
        return
    end

    -- Auto-save timer (SERVER ONLY in multiplayer, always in singleplayer)
    if g_server or not g_currentMission.missionDynamicInfo.isMultiplayer then
        S.saveTimer = (S.saveTimer or 0) + dt
        if S.saveTimer >= SAVE_INTERVAL then
            saveMileage()
            S.saveTimer = 0
        end
    end

    if not S.mileageData then S.mileageData = {} end

    -- Get vehicle list
    local vehicleList = nil
    
    if g_currentMission.vehicleSystem and g_currentMission.vehicleSystem.vehicles then
        vehicleList = g_currentMission.vehicleSystem.vehicles
    elseif g_currentMission.vehicles then
        vehicleList = g_currentMission.vehicles
    end
    
    if vehicleList then
        for vehicleKey, vehicle in pairs(vehicleList) do
            if vehicle and type(vehicle) == "table" then
                local root = vehicle.rootVehicle or vehicle
                local vehicleId = getVehicleId(root)
                
                if vehicleId then
                    -- Initialize mileage data if needed
                    if not S.mileageData[vehicleId] then
                        S.mileageData[vehicleId] = {
                            odoMeter = 0.0,
                            tripMeter = 0.0,
                            odoDistanceSent = 0.0,
                            tripDistanceSent = 0.0
                        }
                    end
                    
                    local data = S.mileageData[vehicleId]
                    local lastMoved = vehicle.lastMovedDistance or 0
                    
                    -- Track movement (server only to prevent duplicate tracking in multiplayer)
                    if (g_server or not g_currentMission.missionDynamicInfo.isMultiplayer) and lastMoved and lastMoved > 0.001 then
                        data.odoMeter = data.odoMeter + lastMoved
                        data.tripMeter = data.tripMeter + lastMoved
                        
                        if math.abs(data.odoMeter - data.odoDistanceSent) > NETWORK_THRESHOLD then
                            data.odoDistanceSent = data.odoMeter
                        end
                        if math.abs(data.tripMeter - data.tripDistanceSent) > NETWORK_THRESHOLD then
                            data.tripDistanceSent = data.tripMeter
                        end
                    end
                end
            end
        end
    end

    -- Display update (client side)
    if not g_client then
        S.visible = false
        return
    end

    -- Get current vehicle for display
    local veh = getCurrentVehicle()
    if not veh then
        S.visible = false
        S.lastVehicle = nil
        return
    end

    local root = veh.rootVehicle or veh
    local vehicleId = getVehicleId(root)
    
    if not vehicleId then
        S.visible = false
        return
    end

    if not S.mileageData[vehicleId] then
        S.mileageData[vehicleId] = {
            odoMeter = 0.0,
            tripMeter = 0.0,
            odoDistanceSent = 0.0,
            tripDistanceSent = 0.0
        }
    end

    local data = S.mileageData[vehicleId]
    
    -- Format display text
    local distanceInMeters = S.displayMode == 0 and data.odoMeter or data.tripMeter
    local distanceInKM = (distanceInMeters / 1000) % 999999.99
    local displayDistance = g_i18n:getDistance(distanceInKM)
    local unit = g_i18n:getMeasuringUnit()
    local modeLabel = S.displayMode == 0 and "MLG" or "Trip"
    
    S.text = string.format("%s  %08.2f %s", modeLabel, displayDistance, unit)
    
    S.visible = true
    S.lastVehicle = root
end

function NXMileageHUD:draw()
    if not g_client or not S.visible or not S.text then return end

    local size = getCorrectTextSize and getCorrectTextSize(0.009) or 0.009
    size = size * getUiScale()

    local uiScale = getUiScale()
    
    -- Position calculation
    local baseX = 0
    local baseY = 0
    
    if self.speedMeter and self.speedMeter.speedBg then
        baseX = self.speedMeter.speedBg.x + (self.speedMeter.speedBg.width / 2)
        baseY = self.speedMeter.speedBg.y + (self.speedMeter.speedBg.height / 2)
        
        local textX, textY = self.speedMeter:scalePixelToScreenVector({0, -40})
        baseX = baseX + textX
        baseY = baseY + textY
    else
        -- Fallback position
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
        
        -- Green text
        setTextColor(60/255, 118/255, 0/255, 1.0)
        renderText(baseX, baseY, size, S.text)
        
        -- Reset text settings
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
    if actionName == "NX_MILEAGE_TOGGLE_MODE" then
        local pressDuration = g_currentMission.time - (S.keyPressStartTime or 0)
        
        if pressDuration >= HOLD_TIME_RESET then
            -- Reset trip meter on long press
            local veh = getCurrentVehicle()
            if veh then
                local vehicleId = getVehicleId(veh.rootVehicle or veh)
                if vehicleId and S.mileageData and S.mileageData[vehicleId] then
                    S.mileageData[vehicleId].tripMeter = 0.0
                    S.mileageData[vehicleId].tripDistanceSent = 0.0
                    -- Immediate save after reset
                    if g_server or not g_currentMission.missionDynamicInfo.isMultiplayer then
                        saveMileage()
                    end
                    local resetText = g_i18n:getText("nx_mileage_trip_reset") or "Trip meter reset"
                    g_currentMission:showBlinkingWarning(resetText, 2000)
                end
            end
        else
            -- Toggle display mode on short press
            S.displayMode = (S.displayMode + 1) % 2
            local modeText = S.displayMode == 0 and 
                (g_i18n:getText("nx_mileage_mode_mileage") or "Mileage") or 
                (g_i18n:getText("nx_mileage_mode_trip") or "Trip Meter")
            g_currentMission:showBlinkingWarning(modeText, 2000)
        end
        
        S.keyPressStartTime = 0
    end
end

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, NXMileageHUD.saveToSavegame)

addModEventListener(NXMileageHUD)