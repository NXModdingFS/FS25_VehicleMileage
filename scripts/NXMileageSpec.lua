local NX_MOD_DIR  = g_currentModDirectory
local NX_MOD_NAME = g_currentModName

NXMileageSpec = {}

local NETWORK_THRESHOLD = 10

function NXMileageSpec.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Drivable,  specializations)
       and SpecializationUtil.hasSpecialization(Enterable, specializations)
       and SpecializationUtil.hasSpecialization(Motorized, specializations)
end

function NXMileageSpec.registerEventListeners(vehicleType)
    for _, n in pairs({
        "onPostLoad",
        "saveToXMLFile",
        "onUpdate",
        "onReadStream",
        "onWriteStream",
        "onReadUpdateStream",
        "onWriteUpdateStream",
    }) do
        SpecializationUtil.registerEventListener(vehicleType, n, NXMileageSpec)
    end
end

local NXMileageSpecInstalled = false

function NXMileageSpec.installSpecializations(vehicleTypeManager, specializationManager)
    if NXMileageSpecInstalled then return end
    NXMileageSpecInstalled = true


    local specFilePath = NX_MOD_DIR .. "scripts/NXMileageSpec.lua"

    specializationManager:addSpecialization(
        "NXMileage",
        "NXMileageSpec",
        specFilePath,
        nil
    )

    if specializationManager:getSpecializationByName("NXMileage") == nil then
        print("NXMileage ERROR: could not register specialization")
        return
    end

    local added = 0
    for typeName, typeDef in pairs(vehicleTypeManager.types) do
        if  SpecializationUtil.hasSpecialization(Drivable,  typeDef.specializations)
        and SpecializationUtil.hasSpecialization(Enterable, typeDef.specializations)
        and SpecializationUtil.hasSpecialization(Motorized, typeDef.specializations)
        and not SpecializationUtil.hasSpecialization(Locomotive,     typeDef.specializations)
        and not SpecializationUtil.hasSpecialization(ConveyorBelt,   typeDef.specializations)
        and not SpecializationUtil.hasSpecialization(AIConveyorBelt, typeDef.specializations)
        then
            vehicleTypeManager:addSpecialization(typeName, NX_MOD_NAME .. ".NXMileage")
            added = added + 1
        end
    end

    print(string.format("NXMileage: attached to %d vehicle types", added))
end

function NXMileageSpec.ensureData(vehicle)
    if vehicle.nxMileage ~= nil then return end
    vehicle.nxMileage = {
        odoMeter         = 0.0,
        tripMeter        = 0.0,
        odoMode          = 0,
        dirtyFlag        = vehicle:getNextDirtyFlag(),
        odoDistanceSent  = 0.0,
        tripDistanceSent = 0.0,
    }
end

function NXMileageSpec:onPostLoad(savegame)
    NXMileageSpec.ensureData(self)

    if savegame ~= nil then
        -- NX_MOD_NAME captured at load time so the key is always correct
        local key  = savegame.key .. "." .. NX_MOD_NAME .. ".NXMileage"
        local odo  = getXMLFloat(savegame.xmlFile.handle, key .. "#odoMeter")
        local trip = getXMLFloat(savegame.xmlFile.handle, key .. "#tripMeter")
        local mode = getXMLInt(  savegame.xmlFile.handle, key .. "#odoMode")

        if odo  ~= nil then self.nxMileage.odoMeter  = odo  end
        if trip ~= nil then self.nxMileage.tripMeter = trip end
        if mode ~= nil then self.nxMileage.odoMode   = mode end

        self.nxMileage.odoDistanceSent  = self.nxMileage.odoMeter
        self.nxMileage.tripDistanceSent = self.nxMileage.tripMeter
    end
end

function NXMileageSpec:saveToXMLFile(xmlFile, key)
    if self.nxMileage == nil then return end
    setXMLFloat(xmlFile.handle, key .. "#odoMeter",  self.nxMileage.odoMeter  or 0.0)
    setXMLFloat(xmlFile.handle, key .. "#tripMeter", self.nxMileage.tripMeter or 0.0)
    setXMLInt(  xmlFile.handle, key .. "#odoMode",   self.nxMileage.odoMode   or 0)
end

function NXMileageSpec:onUpdate(dt)
    if not self.isServer then return end
    if self.nxMileage == nil then return end
    if not self:getIsMotorStarted() then return end

    local moved = self.lastMovedDistance or 0
    if moved > 0.001 then
        self.nxMileage.odoMeter  = self.nxMileage.odoMeter  + moved
        self.nxMileage.tripMeter = self.nxMileage.tripMeter + moved

        if math.abs(self.nxMileage.odoMeter - self.nxMileage.odoDistanceSent) > NETWORK_THRESHOLD then
            self:raiseDirtyFlags(self.nxMileage.dirtyFlag)
            self.nxMileage.odoDistanceSent = self.nxMileage.odoMeter
        end
        if math.abs(self.nxMileage.tripMeter - self.nxMileage.tripDistanceSent) > NETWORK_THRESHOLD then
            self:raiseDirtyFlags(self.nxMileage.dirtyFlag)
            self.nxMileage.tripDistanceSent = self.nxMileage.tripMeter
        end
    end
end

function NXMileageSpec:onWriteStream(streamId, connection)
    NXMileageSpec.ensureData(self)
    streamWriteFloat32(streamId, self.nxMileage.odoMeter  or 0)
    streamWriteFloat32(streamId, self.nxMileage.tripMeter or 0)
    streamWriteInt8(   streamId, self.nxMileage.odoMode   or 0)
end

function NXMileageSpec:onReadStream(streamId, connection)
    NXMileageSpec.ensureData(self)
    self.nxMileage.odoMeter  = streamReadFloat32(streamId)
    self.nxMileage.tripMeter = streamReadFloat32(streamId)
    self.nxMileage.odoMode   = streamReadInt8(   streamId)
end

function NXMileageSpec:onWriteUpdateStream(streamId, connection, dirtyMask)
    if self.nxMileage == nil then return end
    if not connection:getIsServer() then
        if streamWriteBool(streamId, bitAND(dirtyMask, self.nxMileage.dirtyFlag) ~= 0) then
            streamWriteFloat32(streamId, self.nxMileage.odoMeter  or 0)
            streamWriteFloat32(streamId, self.nxMileage.tripMeter or 0)
        end
    end
end

function NXMileageSpec:onReadUpdateStream(streamId, timestamp, connection)
    if self.nxMileage == nil then return end
    if connection:getIsServer() then
        if streamReadBool(streamId) then
            self.nxMileage.odoMeter  = streamReadFloat32(streamId)
            self.nxMileage.tripMeter = streamReadFloat32(streamId)
        end
    end
end