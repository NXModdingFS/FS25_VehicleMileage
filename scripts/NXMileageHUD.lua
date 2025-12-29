NXMileageHUD = {}
local S = {}

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

local function getIsMetric()
    if g_gameSettings then
        if g_gameSettings.getValue then
            local ok, val = pcall(g_gameSettings.getValue, g_gameSettings, "isMetric")
            if ok and type(val) == "boolean" then return val end
        end
        if type(g_gameSettings.isMetric) == "boolean" then
            return g_gameSettings.isMetric
        end
        if g_gameSettings.useMiles ~= nil then
            return not g_gameSettings.useMiles
        end
    end
    return true
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
            for _, v in ipairs(g_currentMission.vehicles) do
                if v then
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

local function getSpeedKmh(veh)
    if veh and veh.getLastSpeed then
        local ok, val = pcall(veh.getLastSpeed, veh)
        if ok and val then return val end
    end
    return 0.0
end

local function getVehicleId(veh)
    if not veh then return nil end
    local root = veh.rootVehicle or veh
    if root.id then return tostring(root.id) end
    if root.configFileName then return root.configFileName end
    return tostring(root)
end

local function saveMileage()
    if not S.mileageData then return end
    
    local savegameDir = g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory
    if not savegameDir then return end
    
    local filepath = savegameDir .. "/NXMileageData.xml"
    local xmlFile = createXMLFile("mileageXML", filepath, "mileage")
    
    if xmlFile and xmlFile ~= 0 then
        local i = 0
        for vehicleId, data in pairs(S.mileageData) do
            local key = string.format("mileage.vehicle(%d)", i)
            setXMLString(xmlFile, key .. "#id", vehicleId)
            setXMLFloat(xmlFile, key .. "#distance", data.distance or 0.0)
            setXMLBool(xmlFile, key .. "#isMetric", data.isMetric or true)
            i = i + 1
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
            local distance = getXMLFloat(xmlFile, key .. "#distance")
            local isMetric = getXMLBool(xmlFile, key .. "#isMetric")
            
            if vehicleId and distance then
                S.mileageData[vehicleId] = {
                    distance = distance,
                    isMetric = isMetric ~= nil and isMetric or true
                }
            end
            i = i + 1
        end
        delete(xmlFile)
    end
end

function NXMileageHUD:loadMap()
    loadMileage()
    S.saveTimer = 0
end

function NXMileageHUD:deleteMap()
    saveMileage()
end

function NXMileageHUD:update(dt)
    if not g_client or not g_currentMission or not g_currentMission.missionInfo then
        S.visible = false
        return
    end

    S.saveTimer = (S.saveTimer or 0) + dt
    if S.saveTimer >= 60000 then
        saveMileage()
        S.saveTimer = 0
    end

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

    if not S.mileageData then S.mileageData = {} end
    if not S.mileageData[vehicleId] then
        S.mileageData[vehicleId] = { distance = 0.0, isMetric = getIsMetric() }
    end

    local isMetric = getIsMetric()
    
    if S.mileageData[vehicleId].isMetric ~= isMetric then
    
        if isMetric then
         
            S.mileageData[vehicleId].distance = S.mileageData[vehicleId].distance * 1.60934
        else
  
            S.mileageData[vehicleId].distance = S.mileageData[vehicleId].distance / 1.60934
        end
 
        S.mileageData[vehicleId].isMetric = isMetric
    end
    

    if veh.lastMovedDistance and veh.lastMovedDistance > 0.001 then
        if isMetric then
            -- Store in kilometers
            local distanceKm = veh.lastMovedDistance / 1000.0
            S.mileageData[vehicleId].distance = S.mileageData[vehicleId].distance + distanceKm
        else
            -- Store in miles
            local distanceMiles = veh.lastMovedDistance / 1609.34
            S.mileageData[vehicleId].distance = S.mileageData[vehicleId].distance + distanceMiles
        end
    end


    local totalDistance = S.mileageData[vehicleId].distance
    
    if isMetric then
        S.text = string.format("%07d km", math.floor(totalDistance))
    else
        S.text = string.format("%07d mi", math.floor(totalDistance))
    end
    
    S.visible = true
    S.lastVehicle = root
end

function NXMileageHUD:draw()
    if not g_client or not S.visible or not S.text then return end

    local size = getCorrectTextSize and getCorrectTextSize(0.013) or 0.013
    size = size * getUiScale()

    local uiScale = getUiScale()
    
    local dx, dy = 0.0, 0.0
    if getNormalizedScreenValues then
        local ok, nx, ny = pcall(getNormalizedScreenValues, 216 * uiScale, 80 * uiScale)
        if ok and nx and ny then dx, dy = nx, ny end
    end

    local x = 1.0 - (_G.g_safeFrameOffsetX or 0.0) - dx
    local y = (_G.g_safeFrameOffsetY or 0.0) + dy

    if setTextAlignment and setTextVerticalAlignment and renderText then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
        
        setTextColor(1.0, 1.0, 1.0, 1.0)
        renderText(x, y, size, S.text)
        
        setTextColor(1, 1, 1, 1)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
    end
end

addModEventListener(NXMileageHUD)