NXMileageHUD.actionEventIds = NXMileageHUD.actionEventIds or {}

local function updateActionEventVisibility()
    local isInVehicle = g_currentMission and g_currentMission.controlledVehicle ~= nil
    
    for _, actionEventId in ipairs(NXMileageHUD.actionEventIds) do
        if actionEventId then
            g_inputBinding:setActionEventTextVisibility(actionEventId, isInVehicle)
        end
    end
end

PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
    PlayerInputComponent.registerGlobalPlayerActionEvents,
    function(self, controlling)
        local triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings = 
            false, true, false, true, nil, true

        NXMileageHUD.actionEventIds = {}

        local success, actionEventId = g_inputBinding:registerActionEvent(
            InputAction.NX_MILEAGE_TOGGLE_MODE,
            NXMileageHUD,
            NXMileageHUD.onActionCallDown,
            triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings
        )

        if success then
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
            table.insert(NXMileageHUD.actionEventIds, actionEventId)
        end

        triggerUp, triggerDown = true, false
        success, actionEventId = g_inputBinding:registerActionEvent(
            InputAction.NX_MILEAGE_TOGGLE_MODE,
            NXMileageHUD,
            NXMileageHUD.onActionCallUp,
            triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings
        )

        if success then
            g_inputBinding:setActionEventTextVisibility(actionEventId, false)
        end

        updateActionEventVisibility()
    end
)