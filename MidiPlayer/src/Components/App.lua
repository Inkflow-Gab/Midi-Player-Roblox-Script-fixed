-- App
-- 0866
-- November 03, 2020
-- (mobile scaling + centering updates)


local App = {}

local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local midiPlayer = script:FindFirstAncestor("MidiPlayer")
assert(midiPlayer, "MidiPlayer folder not found. Ensure the script is within the proper hierarchy.")

-- Module requirements
local FastDraggable = require(midiPlayer:WaitForChild("FastDraggable"))
local Components = midiPlayer:WaitForChild("Components")
local Controller = require(Components:WaitForChild("Controller"))
local Sidebar = require(Components:WaitForChild("Sidebar"))
local Preview = require(Components:WaitForChild("Preview"))
local Extras = require(Components:WaitForChild("Extras"))

-- GUI asset
local gui = midiPlayer:WaitForChild("Assets"):WaitForChild("ScreenGui")
assert(gui:IsA("ScreenGui"), "Expected ScreenGui in Assets folder.")

-- Mobile layout state
local frame = nil
local uiScale = nil


-- Function to retrieve GUI
function App:GetGUI()
    return gui
end


--[[
    Mobile detection: a device whose primary pointing device is the
    touchscreen. Desktops with touchscreens still count as desktop here.
]]
function App:IsTouchPrimary()
    if (UserInputService.TouchEnabled) then
        return not (UserInputService.MouseEnabled or UserInputService.KeyboardEnabled)
    end
    return false
end


--[[
    Shrinks the window to fit small phone screens. Recomputed automatically
    when the screen is rotated or resized.
]]
function App:_fitWindowToDevice()
    if (not frame or not uiScale) then
        return
    end

    local viewport = gui.AbsoluteSize
    local absolute = frame.AbsoluteSize
    if (viewport.X <= 0 or viewport.Y <= 0 or absolute.X <= 0 or absolute.Y <= 0) then
        return
    end

    -- Undo the current scale so we always work with the unscaled window size
    local unscaledX = absolute.X / math.max(uiScale.Scale, 0.001)
    local unscaledY = absolute.Y / math.max(uiScale.Scale, 0.001)

    local padding = 24
    local scale = math.min(
        1,
        (viewport.X - padding) / unscaledX,
        (viewport.Y - padding) / unscaledY
    )

    uiScale.Scale = math.clamp(scale, 0.5, 1)
end


function App:_setupMobileLayout()
    local options = {}
    do
        local ok, overrides = pcall(function()
            return getgenv().MidiPlayerConfig
        end)
        if (ok and type(overrides) == "table" and type(overrides.Options) == "table") then
            options = overrides.Options
        end
    end

    if (options.DisableMobileScale) then
        return
    end

    if (not self:IsTouchPrimary()) then
        return
    end

    -- Start slightly smaller so a large window doesn't flash at full size
    uiScale = Instance.new("UIScale")
    uiScale.Scale = 0.5
    uiScale.Parent = frame

    -- Center the window once at startup (anchor-based, so it survives
    -- scaling and still plays nicely with FastDraggable afterwards)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)

    local function scheduleFit()
        task.delay(0.05, function()
            self:_fitWindowToDevice()
        end)
    end

    gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(scheduleFit)
    task.delay(0.15, function()
        self:_fitWindowToDevice()
    end)
end


-- Initialize the app
function App:Init()
    -- Ensure FastDraggable is initialized correctly
    if not gui.Frame or not gui.Frame:FindFirstChild("Handle") then
        error("GUI Frame or its Handle is missing. Ensure the structure matches expectations.")
    end

    frame = gui.Frame

    FastDraggable(frame, frame.Handle)

    -- Protect the GUI for exploits if Synapse is available
    if syn and syn.protect_gui then
        syn.protect_gui(gui)
    end

    -- Parent the GUI to CoreGui for visibility
    local parented = pcall(function()
        gui.Parent = CoreGui
    end)
    if (not parented) then
        -- Fallback for environments where CoreGui access is blocked
        local Players = game:GetService("Players")
        local player = Players.LocalPlayer
        gui.Parent = player:WaitForChild("PlayerGui")
    end

    -- Mobile: adapt the window to the device screen
    self:_setupMobileLayout()

    -- Initialize individual components
    Controller:Init(frame)
    Sidebar:Init(frame)
    Preview:Init(frame)

    -- Extras initializes last: it repositions existing elements (time label,
    -- song list) and listens to Sidebar/Controller/Song state
    Extras:Init(frame)
end


return App
