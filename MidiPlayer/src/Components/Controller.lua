-- Controller
-- 0866
-- November 03, 2020
-- (mobile/touch support updates)


local midiPlayer = script:FindFirstAncestor("MidiPlayer")
local Signal = require(midiPlayer.Util.Signal)
local Thread = require(midiPlayer.Util.Thread)
local Song = require(midiPlayer.Song)
local Click = require(midiPlayer.Util.Click)
local FastTween = require(midiPlayer.FastTween)
local Preview = require(midiPlayer.Components.Preview)

local Controller = {
    CurrentSong = nil;
    CurrentFile = nil;
    FileLoaded = Signal.new();
}

getgenv().LeftHand = true;
getgenv().RightHand = true;

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local main, controller


function Controller:Select(filePath)
    if (self.CurrentSong) then
        self.CurrentSong:Destroy()
    end
    getgenv().LeftHand = true;
    getgenv().RightHand = true;
    controller.RightHand.ImageTransparency = 0
    controller.LeftHand.ImageTransparency = 0
    self.CurrentFile = filePath
    self.CurrentSong = Song.new(filePath)

    -- Picking a song immediately begins playback (mobile-friendly)
    self.CurrentSong:Play()

    self.FileLoaded:Fire(self.CurrentSong)
    self:Update()
    Preview:Draw(self.CurrentSong)
end


function Controller:Update()
    local song = self.CurrentSong

    if (song) then
        main.Title.Text = song.Name

        -- Elapsed / total playback time as M:SS / M:SS
        local total = math.floor(math.max(song.TimeLength, 0))
        local elapsed = math.floor(math.clamp(song.TimePosition, 0, math.max(song.TimeLength, 0)))
        controller.Time.Text = ("%i:%02i / %i:%02i"):format(
            math.floor(elapsed / 60), elapsed % 60,
            math.floor(total / 60), total % 60
        )

        controller.Speed.Text = tostring(math.floor(song.Speed * 10) / 10).. "x"
        controller.SpeedScrubber.Progress.Size = UDim2.fromScale(math.min(1, song.Speed / 2), 1)
        controller.Miss.Text = tostring(math.round(song.MissPercent)).. "%"
        controller.MissScrubber.Progress.Size = UDim2.fromScale(math.min(1, song.MissPercent / 100), 1)
        if (song.TimeLength > 0) then
            controller.Scrubber.Progress.Size = UDim2.fromScale(math.min(1, song.TimePosition / song.TimeLength), 1)
        else
            controller.Scrubber.Progress.Size = UDim2.fromScale(0, 1)
        end
        controller.Scrubber.Fill.Size = UDim2.fromScale(1 - controller.Scrubber.Progress.Size.X.Scale, 1)
        controller.Resume.Image = (song.IsPlaying and "rbxassetid://5915789609") or "rbxassetid://5915551861"

    else
        main.Title.Text = "No song selected"
        controller.Time.Text = "0:00 / 0:00"
        controller.Speed.Text = "1x"
        controller.Miss.Text = "0%"
        controller.Scrubber.Progress.Size = UDim2.fromScale(0, 1)
        controller.Scrubber.Fill.Size = UDim2.fromScale(1, 1)
        controller.Resume.Image = "rbxassetid://5915551861"
        controller.RightHand.ImageTransparency = 0
        controller.LeftHand.ImageTransparency = 0
    end
end


function Controller:Init(frame)

    main = frame.Main
    controller = main.Controller

    self:_startHandButtons()

    self:_startScrubber()
    self:_startSpeedScrubber()
    self:_startMissScrubber()

    self:_startPlaybackButton()

    self:_startHidePreviewButton()

    Thread.DelayRepeat(1/60, function()
        if (self.CurrentSong) then
            Preview:Update(self.CurrentSong.TimePosition * self.CurrentSong.Timebase)
        end
    end)

    RunService.Heartbeat:Connect(function()
        self:Update()
    end)

end


function Controller:_startHidePreviewButton()
    local togglePreview = main.TogglePreview
    Click.bind(togglePreview, function()
        getgenv()._hideSongPreview = (not getgenv()._hideSongPreview)
        if (getgenv()._hideSongPreview) then
            FastTween(togglePreview.Fill, { 0.1 }, { Size = UDim2.new() })
        else
            FastTween(togglePreview.Fill, { 0.1 }, { Size = UDim2.new(1, -12, 1, -12) })
        end
    end)
end


function Controller:_startPlaybackButton()
    local playback = controller.Resume
    Click.bind(playback, function()
        if (not self.CurrentSong) then return end
        if (self.CurrentSong.IsPlaying) then
            self.CurrentSong:Pause()
        else
            self.CurrentSong:Play()
        end
        self:Update()
    end)
end

function Controller:_startHandButtons()
    local right = controller.RightHand
    local left = controller.LeftHand

    Click.bind(left, function()
        if (getgenv().LeftHand) then
            Preview:hideHand("left")
            FastTween(left, { 0.1 }, { ImageTransparency = 0.5 })
        else
            Preview:showHand("left")
            FastTween(left, { 0.1 }, { ImageTransparency = 0 })
        end
        getgenv().LeftHand = not getgenv().LeftHand
    end)

    Click.bind(right, function()
        if (getgenv().RightHand) then
            Preview:hideHand("right")
            FastTween(right, { 0.1 }, { ImageTransparency = 0.5 })
        else
            Preview:showHand("right")
            FastTween(right, { 0.1 }, { ImageTransparency = 0 })
        end
        getgenv().RightHand = not getgenv().RightHand
    end)
end



--[[
    Uniform slider helper used by the time, speed and miss scrubbers.
    Works with both mouse and touch: taps jump straight to the position and
    dragging updates continuously.

    `callback(ratio, song)` receives a clamped 0-1 progress.
    Set `pauseWhileDragging` for the time scrubber.
]]
function Controller:_addSlider(hitbox, callback, pauseWhileDragging)
    if (not hitbox) then return end

    local dragging = false
    local dragInput = nil

    local function update(input)
        local song = self.CurrentSong
        if (song) then
            -- Read the size at event time; UI scaling may change it at runtime
            local absPos = hitbox.AbsolutePosition
            local absSize = hitbox.AbsoluteSize
            if (absSize.X > 0) then
                callback(math.clamp((input.Position.X - absPos.X) / absSize.X, 0, 1), song)
            end
        end
        self:Update()
    end

    hitbox.InputBegan:Connect(function(input)
        if (Click.isPointer(input)) then
            dragging = true
            dragInput = input
            input.Changed:Connect(function()
                if (input.UserInputState == Enum.UserInputState.End) then
                    dragging = false
                end
            end)
            if (pauseWhileDragging and self.CurrentSong and self.CurrentSong.IsPlaying) then
                self.CurrentSong:Pause()
            end
            update(input)
        end
    end)

    hitbox.InputChanged:Connect(function(input)
        if (Click.isPointer(input)) then
            dragInput = input
        end
    end)

    -- Keeps receiving moves while the finger/pointer slides off the hitbox
    UserInputService.InputChanged:Connect(function(input)
        if (input == dragInput and dragging) then
            update(input)
        end
    end)
end


function Controller:_startScrubber()
    self:_addSlider(controller.Scrubber.Hitbox, function(ratio, song)
        song:JumpTo(ratio * song.TimeLength)
    end, true)
end


function Controller:_startSpeedScrubber()
    self:_addSlider(controller.SpeedScrubber.Hitbox, function(ratio, song)
        song.Speed = (ratio * 2)
    end, false)
end


function Controller:_startMissScrubber()
    self:_addSlider(controller.MissScrubber.Hitbox, function(ratio, song)
        song.MissPercent = math.round(ratio * 100)
    end, false)
end

return Controller
