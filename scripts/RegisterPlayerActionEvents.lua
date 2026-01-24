local isDbPrintfOn = true

local function dbPrintf(...)
    if isDbPrintfOn then
        print(string.format(...))
    end
end

dbPrintf("NXMileageHUD: Registering global player action events")

PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
    PlayerInputComponent.registerGlobalPlayerActionEvents,
    function(self, controlling)
        local triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings = 
            false, true, false, true, nil, true

        -- Register key DOWN event
        local success, actionEventId = g_inputBinding:registerActionEvent(
            InputAction.NX_MILEAGE_TOGGLE_MODE,
            NXMileageHUD,
            NXMileageHUD.onActionCallDown,
            triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings
        )

        if success then
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
            g_inputBinding:setActionEventTextVisibility(actionEventId, true)
            dbPrintf("NXMileageHUD - Register DOWN key (controlling=%s, action=%s, actionId=%s)", 
                controlling or "nil", "NX_MILEAGE_TOGGLE_MODE", actionEventId or "nil")
        else
            dbPrintf("NXMileageHUD - Failed to register DOWN key (controlling=%s, action=%s)", 
                controlling or "nil", "NX_MILEAGE_TOGGLE_MODE")
        end

        -- Register key UP event
        triggerUp, triggerDown = true, false
        success, actionEventId = g_inputBinding:registerActionEvent(
            InputAction.NX_MILEAGE_TOGGLE_MODE,
            NXMileageHUD,
            NXMileageHUD.onActionCallUp,
            triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings
        )

        if success then
            g_inputBinding:setActionEventTextVisibility(actionEventId, false)
            dbPrintf("NXMileageHUD - Register UP key (actionId=%s)", actionEventId or "nil")
        else
            dbPrintf("NXMileageHUD - Failed to register UP key")
        end
    end
)