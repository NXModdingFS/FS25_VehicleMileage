NXMileageTripResetEvent = {}
NXMileageTripResetEvent.__index = NXMileageTripResetEvent

local NXMileageTripResetEvent_mt = Class(NXMileageTripResetEvent, Event)
InitEventClass(NXMileageTripResetEvent, "NXMileageTripResetEvent")

function NXMileageTripResetEvent.emptyNew()
    return Event.new(NXMileageTripResetEvent_mt)
end

function NXMileageTripResetEvent.new(vehicle)
    local self   = NXMileageTripResetEvent.emptyNew()
    self.vehicle = vehicle
    return self
end

function NXMileageTripResetEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
end

function NXMileageTripResetEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

function NXMileageTripResetEvent:run(connection)
    if not g_server then return end
    if not self.vehicle then return end

    NXMileageSpec.ensureData(self.vehicle)

    self.vehicle.nxMileage.tripMeter        = 0.0
    self.vehicle.nxMileage.tripDistanceSent = 0.0
    self.vehicle:raiseDirtyFlags(self.vehicle.nxMileage.dirtyFlag)
end