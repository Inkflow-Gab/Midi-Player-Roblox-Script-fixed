-- Sidebar
-- 0866
-- November 03, 2020
-- (mobile/touch support + multi-folder scanning updates)


local midiPlayer = script:FindFirstAncestor("MidiPlayer")
local Thread = require(midiPlayer.Util.Thread)
local Controller = require(midiPlayer.Components.Controller)
local Click = require(midiPlayer.Util.Click)
local Config = require(midiPlayer.Config)
local FastTween = require(midiPlayer.FastTween)

local Sidebar = {}

-- Elements keyed by full file path (paths are unique, display names are not)
local Elements = {}

local tweenInfo = { 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out }

local sidebar, template


local function getBasename(filePath)
    return (filePath:match("[^/\\]+$"))
end

local function getDisplayName(filePath)
    return ((getBasename(filePath) or ""):match("^([^%.]+)") or "")
end


function Sidebar:CreateElement(filePath)

    local fullname = getBasename(filePath)
    local name = getDisplayName(filePath)

    local element = template:Clone()
    element.Name = filePath
    element.Title.Text = name

    Elements[filePath] = element

    if (Controller.CurrentFile == filePath) then
        element.Selection.Size = UDim2.fromOffset(3, 16)
    else
        element.Selection.Size = UDim2.fromOffset(3, 0)
    end

    element.InputBegan:Connect(function(input)
        if (Click.isPointer(input)) then
            FastTween(element, tweenInfo, { BackgroundTransparency = 0.5 })
            Controller:Select(filePath)
        end
    end)

    element.InputEnded:Connect(function(input)
        if (Click.isPointer(input)) then
            FastTween(element, tweenInfo, { BackgroundTransparency = 0.75 })
        end
    end)

    element.MouseEnter:Connect(function()
        FastTween(element, tweenInfo, { BackgroundTransparency = 0.75 })
    end)

    element.MouseLeave:Connect(function()
        FastTween(element, tweenInfo, { BackgroundTransparency = 1 })
    end)

    element.Parent = sidebar.Songs
    self:_refreshCanvas()
end


function Sidebar:_refreshCanvas()
    -- Let the UIListLayout drive the canvas when available; otherwise
    -- compute the height from the visible song frames.
    if (sidebar.Songs:FindFirstChildOfClass("UIListLayout")) then
        return
    end
    -- AbsoluteSize isn't valid until the next layout pass
    task.defer(function()
        local total = 0
        for _,element in ipairs(sidebar.Songs:GetChildren()) do
            if (element:IsA("Frame") and element.Visible) then
                total += math.max(element.AbsoluteSize.Y, 1)
            end
        end
        sidebar.Songs.CanvasSize = UDim2.new(0, 0, 0, total)
    end)
end


function Sidebar:Update()

    -- Rebuild the lookup table from live children so it never drifts
    Elements = {}

    -- GetMidiFiles() already walks every configured folder (deduplicated)
    local files = Config:GetMidiFiles()

    local seen = {}
    for _,filePath in ipairs(files) do
        seen[filePath] = true
    end

    for _,element in ipairs(sidebar.Songs:GetChildren()) do
        if (element:IsA("Frame") and not seen[element.Name]) then
            element:Destroy()
        end
    end

    for _,filePath in ipairs(files) do
        if (not sidebar.Songs:FindFirstChild(filePath)) then
            self:CreateElement(filePath)
        end
    end

    -- Sorted display order (case-insensitive by song name)
    local sortable = {}
    for _,element in ipairs(sidebar.Songs:GetChildren()) do
        if (element:IsA("Frame")) then
            table.insert(sortable, element)
            Elements[element.Name] = element
        end
    end
    table.sort(sortable, function(a, b)
        return (getDisplayName(a.Name):lower() < getDisplayName(b.Name):lower())
    end)

    -- Playback order used by the playlist (previous/next, auto-advance)
    local order = {}
    for index,element in ipairs(sortable) do
        table.insert(order, element.Name)
        element.LayoutOrder = index
    end
    self._order = order

    self:Filter(sidebar.Search.Text)
    self:_refreshCanvas()
end


function Sidebar:Filter(text)
    text = (text or ""):lower()

    if (text ~= '') then
        for path,element in pairs(Elements) do
            local name = getDisplayName(path)
            if (name:lower():find(text, 1, true)) then
                element.Visible = true
                element.Size = UDim2.new(1, 0, 0, 32)
            else
                element.Visible = false
                element.Size = UDim2.new(1, 0, 0, 0)
            end
        end
    else
        for _,element in pairs(Elements) do
            element.Visible = true
            element.Size = UDim2.new(1, 0, 0, 32)
        end
    end

    self:_refreshCanvas()
end


--[[
    Sidebar:GetOrder() -> { filePath, ... }

    Current display order of every loaded song (sorted by name, refreshed
    by Update()). Used by the playlist controls to move between songs.
]]
function Sidebar:GetOrder()
    return self._order or {}
end


function Sidebar:Init(frame)

    sidebar = frame.Sidebar

    template = sidebar.Songs.Song
    template.Parent = nil

    sidebar.Search:GetPropertyChangedSignal('Text'):Connect(function()
        self:Update()
    end)

    Controller.FileLoaded:Connect(function(song)
        for _,element in ipairs(sidebar.Songs:GetChildren()) do
            if (element:IsA("Frame")) then
                if (element.Name == song.Path) then
                    FastTween(element.Selection, tweenInfo, { Size = UDim2.fromOffset(3, 16) })
                else
                    FastTween(element.Selection, tweenInfo, { Size = UDim2.fromOffset(3, 0) })
                end
            end
        end
    end)

    Thread.DelayRepeat(1, self.Update, self)
    self:Update()
end


return Sidebar
