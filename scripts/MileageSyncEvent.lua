-- MileageSyncEvent.lua
-- Sent by clients to the server to persist mileage data

MileageSyncEvent = {}
MileageSyncEvent.__index = MileageSyncEvent

local MileageSyncEvent_mt = Class(MileageSyncEvent, Event)

InitEventClass(MileageSyncEvent, "MileageSyncEvent")

function MileageSyncEvent.emptyNew()
    local self = Event.new(MileageSyncEvent_mt)
    return self
end

function MileageSyncEvent.new(vehicleId, odoMeter, tripMeter)
    local self = MileageSyncEvent.emptyNew()
    self.vehicleId = vehicleId
    self.odoMeter  = odoMeter
    self.tripMeter = tripMeter
    return self
end

function MileageSyncEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.vehicleId or "")
    streamWriteFloat32(streamId, self.odoMeter  or 0)
    streamWriteFloat32(streamId, self.tripMeter  or 0)
end

function MileageSyncEvent:readStream(streamId, connection)
    self.vehicleId = streamReadString(streamId)
    self.odoMeter  = streamReadFloat32(streamId)
    self.tripMeter  = streamReadFloat32(streamId)
end

-- Called on the server when the event arrives
function MileageSyncEvent:run(connection)
    if not g_server then return end
    if not self.vehicleId or self.vehicleId == "" then return end

    local S = NXMileageHUD.state
    if not S.mileageData then S.mileageData = {} end

    local existing = S.mileageData[self.vehicleId]
    if existing then
        -- Only update if the client value is higher (prevents rollbacks)
        if self.odoMeter > existing.odoMeter then
            existing.odoMeter = self.odoMeter
            existing.odoDistanceSent = self.odoMeter
        end
        if self.tripMeter > existing.tripMeter then
            existing.tripMeter = self.tripMeter
            existing.tripDistanceSent = self.tripMeter
        end
    else
        S.mileageData[self.vehicleId] = {
            odoMeter         = self.odoMeter,
            tripMeter        = self.tripMeter,
            odoDistanceSent  = self.odoMeter,
            tripDistanceSent = self.tripMeter
        }
    end
end