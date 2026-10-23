-- Util/Click
-- Small helper that makes every interaction work on both desktop and mobile.

local Click = {}

-- True when `input` is a "press" coming from a mouse or a finger.
function Click.isPointer(input)
    local inputType = input.UserInputType
    return inputType == Enum.UserInputType.MouseButton1
        or inputType == Enum.UserInputType.Touch
end

--[[
    Click.bind(guiObject, callback)

    Fires `callback` when the object is activated by a mouse click,
    a touch tap, or gamepad selection. Works on GuiButtons (via
    Activated) and plain GuiObjects (via InputBegan), unlike the old
    MouseButton1Down-only approach that did nothing on phones.
]]
function Click.bind(guiObject, callback)
    if (guiObject:IsA("GuiButton")) then
        guiObject.Activated:Connect(callback)
        return
    end

    guiObject.InputBegan:Connect(function(input)
        if (Click.isPointer(input)) then
            callback()
        end
    end)
end

return Click
