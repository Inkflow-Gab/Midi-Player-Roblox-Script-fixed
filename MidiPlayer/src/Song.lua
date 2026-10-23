-- Song
-- 0866
-- November 03, 2020
-- (cursor-based playback, safer file loading, config folder support)


local Song = {}
Song.__index = Song
Song.Speed = 1
Song.MissPercent = 0

local MIDI = require(script.Parent.MIDI)
local Input = require(script.Parent.Input)
local Config = require(script.Parent.Config)
local Signal = require(script.Parent.Util.Signal)

-- Fired once (Song itself, static signal) whenever a song reaches its
-- TimeLength and pauses. Drives playlist auto-advance/repeat behavior.
Song.Ended = Signal.new()

local RunService = game:GetService("RunService")

getgenv().rightNotePitches = {}
getgenv().leftNotePitches = {}

local function GetTimeLength(score)
    local length = 0
    for i, track in ipairs(score) do
        if (i == 1) then continue end
        local last = track[#track]
        if (last) then
            length = math.max(length, last[2])
        end
    end
    return length
end

local function chance(x)
    if math.random(1,100) <= x then
        return true
    else
        return false
    end
end

function Song.new(file)

    local ok, contents = pcall(readfile, file)
    if (not ok or type(contents) ~= "string") then
        error(("MidiPlayer: cannot read MIDI file: %s (%s)"):format(
            tostring(file), tostring(contents)
        ), 0)
    end

    local score = MIDI.midi2score(contents)

    local fullname = (file:match("[^/\\]+$") or file)
    local name = fullname:match("^([^%.]+)") or ""

    -- Events inside each track are indexed by play position, so sort them
    -- once by absolute tick. This lets playback walk each track with a
    -- cursor instead of rescanning every event every frame.
    for i = 1, #score do
        local track = score[i]
        if (type(track) == "table" and #track > 1) then
            table.sort(track, function(a, b)
                return a[2] < b[2]
            end)
        end
    end

    local self = setmetatable({

        Name = name;
        Path = file;
        TimePosition = 0;
        TimeLength = 0;
        Timebase = score[1];
        IsPlaying = false;

        _score = score;
        _usPerBeat = 0;
        _lastTimePosition = 0;
        _length = GetTimeLength(score);
        _eventStatus = {};
        _updateConnection = nil;
        _cursor = {};

    }, Song)

    -- Malformed files can carry 0 ticks-per-quarter; keep time math finite
    if (not self.Timebase or self.Timebase <= 0) then
        self.Timebase = 480
    end

    self:_resetCursors()
    self.TimeLength = (self._length / self.Timebase)

    return self

end


--[[
    Repositions every track cursor at the current TimePosition so playback
    continues (or restarts) from exactly the right event. Used on jumps,
    seeks and song-position markers.
]]
function Song:_resetCursors()
    local ticks = self.TimePosition * self.Timebase
    self._lastTimePosition = self.TimePosition
    self._resetToken = (self._resetToken or 0) + 1

    for i = 2, #self._score do
        local track = self._score[i]
        local cursor = 1
        while (cursor <= #track and track[cursor][2] < ticks) do
            cursor += 1
        end
        self._cursor[i] = cursor
    end

    -- Track 1 (tempo/meta track) is walked too
    local first = self._score[1]
    if (first) then
        local cursor = 1
        while (cursor <= #first and first[cursor][2] < ticks) do
            cursor += 1
        end
        self._cursor[1] = cursor
    end
end


function Song:Update(timePosition, lastTimePosition)

    local ticksUpper = timePosition * self.Timebase
    local ticksLower = lastTimePosition * self.Timebase
    local clearedRight = false
    local clearedLeft = false

    -- Incremented by _resetCursors; if it changes mid-frame, playback was
    -- re-anchored (song_position) and the rest of this frame must be skipped.
    local resetToken = self._resetToken

    for i, track in ipairs(self._score) do
        local cursor = self._cursor[i] or 1
        local count = #track

        while (cursor <= count) do
            local event = track[cursor]
            local eventTicks = event[2]

            if (eventTicks > ticksUpper) then
                break
            end
            cursor += 1

            -- Only fire events that entered the window this frame
            if (eventTicks >= ticksLower) then

                local pos = (i % 4)
                if (event[1] == "note") then
                    local pitch = event[5]
                    if pos == 2 then
                        local tableRight = getgenv().rightNotePitches
                        if (not clearedRight) then
                            table.clear(tableRight)
                            clearedRight = true
                        end
                        tableRight[pitch] = true
                    elseif pos == 3 then
                        local tableLeft = getgenv().leftNotePitches
                        if (not clearedLeft) then
                            table.clear(tableLeft)
                            clearedLeft = true
                        end
                        tableLeft[pitch] = true
                    end
                end

                self:_parse(event)

                if (self._resetToken ~= resetToken) then
                    return
                end
            end
        end

        self._cursor[i] = cursor
    end
end


function Song:Step(deltaTime)
    self._lastTimePosition = self.TimePosition
    if (self._usPerBeat ~= 0) then
        self.TimePosition += (deltaTime / (self._usPerBeat / 1000000))  * self.Speed
    else
        self.TimePosition += deltaTime * self.Speed
    end
end


function Song:JumpTo(timePosition)
    self.TimePosition = timePosition
    self:_resetCursors()
end


function Song:Play()

    -- Restart automatically once the song has finished
    if (self.TimeLength > 0 and self.TimePosition >= self.TimeLength) then
        self:JumpTo(0)
    end

    -- Guard against duplicate render connections when Play is re-invoked
    self:Pause()

    self._updateConnection = RunService.RenderStepped:Connect(function(dt)
        self:Update(self.TimePosition, self._lastTimePosition)
        self:Step(dt)
        if (self.TimePosition >= self.TimeLength) then
            self:Pause()
            if (self.TimeLength > 0) then
                -- Reached the end naturally; playlist can react to this
                Song.Ended:Fire(self)
            end
        end
    end)
    self.IsPlaying = true
end


function Song:Stop()
    if (self._updateConnection) then
        self._updateConnection:Disconnect()
        self._updateConnection = nil
        self.IsPlaying = false
    end
    self._lastTimePosition = 0
end


function Song:Pause()
    if (self._updateConnection) then
        self._updateConnection:Disconnect()
        self._updateConnection = nil
        self.IsPlaying = false
    end
end


function Song:_parse(event)
   --[[

        Event:
            Event name  [String]
            Start time  [Number]
            ...

        Note:
            Event name  [String]
            Start time  [Number]
            Duration    [Number]
            Channel     [Number]
            Pitch       [Number]
            Velocity    [Number]

    ]]
    local eventName = event[1]

    if (eventName == "set_tempo") then
        self._usPerBeat = event[3]
    elseif (eventName == "song_position") then
        self.TimePosition = (event[3] / self.Timebase)
        -- Keep playback moving from the new position without replaying events
        self:_resetCursors()
    elseif (eventName == "note") then
        if self.MissPercent > 0 then
            task.spawn(function()
                local random1 = chance(self.MissPercent)
                local random2 = chance(self.MissPercent)
                local random3 = chance(self.MissPercent)
                if random1 then wait(math.random(0.1, 0.5)) end
                if not random3 then Input.Hold(not random2 and event[5] or event[5] - 1, event[3] / self.Timebase) end
            end)
        else
            Input.Hold(event[5], event[3] / self.Timebase)
        end
    end
end


function Song.FromTitle(midiTitle)
    local filePath = Config:FindFile(midiTitle)
    if (not filePath) then
        error("MidiPlayer: no MIDI file named '" .. tostring(midiTitle) .. "' was found in the configured folders.", 0)
    end
    return Song.new(filePath)
end


Song.Destroy = Song.Stop

return Song
